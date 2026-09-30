import Fluent
import Vapor
import KausMedia

/// Contas fixas, receitas recorrentes, aportes — e a grade anual que sai deles.
struct PlanController: RouteCollection {
    private static let maxPlanMonths = 36

    func boot(routes: any RoutesBuilder) throws {
        let commitments = routes.grouped("api", "commitments")
        commitments.get(use: index)
        commitments.post(use: create)
        commitments.group(":commitmentID") { commitment in
            commitment.put(use: update)
            commitment.delete(use: delete)
        }
        routes.get("api", "plan", use: plan)
    }

    func index(req: Request) async throws -> [RecurringCommitment] {
        try await RecurringCommitmentModel.query(on: req.db)
            .sort(\.$name)
            .all()
            .map { $0.toDTO() }
    }

    func create(req: Request) async throws -> Response {
        let dto = try req.content.decode(RecurringCommitment.self)
        try await validate(dto, on: req)
        let model = RecurringCommitmentModel(commitment: dto)
        try await model.create(on: req.db)
        return try await model.toDTO().encodeResponse(status: .created, for: req)
    }

    func update(req: Request) async throws -> RecurringCommitment {
        let model = try await find(req)
        let dto = try req.content.decode(RecurringCommitment.self)
        try await validate(dto, on: req)
        model.apply(dto)
        try await model.update(on: req.db)
        return model.toDTO()
    }

    func delete(req: Request) async throws -> HTTPStatus {
        let model = try await find(req)
        try await model.delete(on: req.db)
        return .noContent
    }

    private static func month(_ text: String?, field: String) throws -> YearMonth? {
        guard let text else { return nil }
        guard let month = YearMonth(text) else {
            throw Abort(.badRequest, reason: "\(field) deve ser AAAA-MM com ano entre 1 e 9999")
        }
        return month
    }

    /// A grade anual: uma linha por categoria, uma coluna por mês, com o valor
    /// real quando o extrato já trouxe e o planejado quando o mês é futuro.
    func plan(req: Request) async throws -> PlanResponse {
        let query = try req.query.decode(PlanQuery.self)
        let reference = Date()
        let start = try Self.month(query.from, field: "from") ?? YearMonth(date: reference).adding(months: -2)
        let requestedEnd = try Self.month(query.to, field: "to") ?? start.adding(months: 11)
        let end = min(requestedEnd, start.adding(months: Self.maxPlanMonths - 1))

        let commitments = try await RecurringCommitmentModel.query(on: req.db).all().map { $0.toDTO() }
        let transactions = try await TransactionModel.query(on: req.db)
            .filter(\.$date >= start.startDate)
            .filter(\.$date < end.adding(months: 1).startDate)
            .all()

        let rules = try await req.categoryRules.rules()
        let categorizer = Categorizer(rules: rules)
        var tagsByCategory: [String: [String]] = [:]
        for rule in rules where !rule.tags.isEmpty {
            tagsByCategory[rule.category, default: []].append(contentsOf: rule.tags)
        }
        // O que o usuário declarou como aporte não pode ser tratado como
        // transferência descartável: é dinheiro dele, só mudou de lugar.
        let savingCategories = Set(commitments.filter { $0.kind == .saving }.map(\.category))
            .union(["Guardado"])

        let plan = AnnualPlan.build(
            from: start,
            to: end,
            transactions: transactions.map { $0.toDTO() },
            commitments: commitments,
            savingCategories: savingCategories,
            transferCategories: categorizer.transferCategories,
            tagsByCategory: tagsByCategory,
            openingBalance: query.openingBalance ?? 0,
            reference: reference
        )

        let knownTags = TagSet.normalize(
            commitments.flatMap(\.tags)
                + rules.flatMap(\.tags)
                + transactions.flatMap(\.tags)
                + [TagSet.essential]
        ).sorted()

        return PlanResponse(plan: plan, commitments: commitments, knownTags: knownTags)
    }

    private func validate(_ commitment: RecurringCommitment, on req: Request) async throws {
        guard !commitment.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw Abort(.badRequest, reason: "O nome é obrigatório")
        }
        guard !commitment.category.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw Abort(.badRequest, reason: "A categoria é obrigatória")
        }
        guard commitment.amount.isFinite, commitment.amount >= 0 else {
            throw Abort(.badRequest, reason: "Valor inválido")
        }
        if let end = commitment.end, end < commitment.start {
            throw Abort(.badRequest, reason: "O mês final é anterior ao inicial")
        }
        for (month, value) in commitment.overrides {
            guard YearMonth(month) != nil else {
                throw Abort(.badRequest, reason: "Mês inválido em valores por mês: \(month)")
            }
            guard value.isFinite, value >= 0 else {
                throw Abort(.badRequest, reason: "Valor inválido para \(month)")
            }
        }
        if let accountID = commitment.accountID,
           try await AccountModel.find(accountID, on: req.db) == nil {
            throw Abort(.notFound, reason: "Conta não encontrada")
        }
    }

    private func find(_ req: Request) async throws -> RecurringCommitmentModel {
        guard let id = req.parameters.get("commitmentID", as: UUID.self) else {
            throw Abort(.badRequest, reason: "Identificador inválido")
        }
        guard let model = try await RecurringCommitmentModel.find(id, on: req.db) else {
            throw Abort(.notFound, reason: "Compromisso não encontrado")
        }
        return model
    }
}

struct PlanQuery: Content {
    /// `YYYY-MM`.
    var from: String?
    var to: String?
    /// Saldo de partida do acumulado — por padrão a grade começa do zero.
    var openingBalance: Double?
}
