import Fluent
import Vapor
import KausMedia

struct TransactionController: RouteCollection {
    func boot(routes: any RoutesBuilder) throws {
        let transactions = routes.grouped("api", "transactions")
        transactions.get(use: index)
        transactions.post(use: create)
        transactions.delete(":transactionID", use: delete)

        routes.post("api", "imports", use: importStatement)
        routes.get("api", "summary", use: summary)
    }

    func index(req: Request) async throws -> [TransactionDTO] {
        let query = try req.query.decode(TransactionQuery.self)

        var builder = TransactionModel.query(on: req.db).sort(\.$date, .descending)
        if let accountID = query.accountID {
            builder = builder.filter(\.$account.$id == accountID)
        }
        if let from = query.from {
            builder = builder.filter(\.$date >= LedgerCalendar.startOfDay(from))
        }
        if let to = query.to {
            // O filtro é por dia: `to` na meia-noite ainda inclui o dia inteiro.
            builder = builder.filter(\.$date < LedgerCalendar.addingDays(1, to: LedgerCalendar.startOfDay(to)))
        }
        if query.includeProjected == false {
            builder = builder.filter(\.$isProjected == false)
        }
        if let search = query.search?.trimmingCharacters(in: .whitespacesAndNewlines), !search.isEmpty {
            builder = builder.group(.or) { group in
                group.filter(\.$description ~~ search).filter(\.$category ~~ search)
            }
        }

        let limit = min(max(query.limit ?? 500, 1), 1000)
        return try await builder
            .range(lower: query.offset ?? 0, upper: (query.offset ?? 0) + limit - 1)
            .all()
            .map { $0.toDTO() }
    }

    /// Criação manual. Idempotente: reenviar o mesmo lançamento devolve o existente
    /// em vez de duplicar.
    func create(req: Request) async throws -> Response {
        let dto = try req.content.decode(TransactionDTO.self)
        guard !dto.description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw Abort(.badRequest, reason: "A descrição é obrigatória")
        }
        if let accountID = dto.accountID, try await AccountModel.find(accountID, on: req.db) == nil {
            throw Abort(.notFound, reason: "Conta não encontrada")
        }

        let model = TransactionModel(newFrom: dto, categorizer: try await req.categoryRules.categorizer())

        if let key = model.dedupKey,
           let existing = try await TransactionModel.query(on: req.db).filter(\.$dedupKey == key).first() {
            return try await existing.toDTO().encodeResponse(status: .ok, for: req)
        }

        try await model.create(on: req.db)
        return try await model.toDTO().encodeResponse(status: .created, for: req)
    }

    func delete(req: Request) async throws -> HTTPStatus {
        guard let id = req.parameters.get("transactionID", as: UUID.self) else {
            throw Abort(.badRequest, reason: "Identificador inválido")
        }
        guard let model = try await TransactionModel.find(id, on: req.db) else {
            throw Abort(.notFound, reason: "Lançamento não encontrado")
        }
        try await model.delete(on: req.db)
        return .noContent
    }

    /// Importa um extrato ou fatura. Faturas de cartão geram também as parcelas futuras.
    func importStatement(req: Request) async throws -> ImportReportDTO {
        let request = try req.content.decode(ImportRequestDTO.self)
        guard let account = try await AccountModel.find(request.accountID, on: req.db) else {
            throw Abort(.notFound, reason: "Conta não encontrada")
        }
        guard !request.content.isEmpty else {
            throw Abort(.badRequest, reason: "Arquivo vazio")
        }
        return try await ImportService(database: req.db).run(request, account: account)
    }

    /// Resumo mensal + projeção dos próximos meses.
    func summary(req: Request) async throws -> LedgerProjection {
        let query = try req.query.decode(SummaryQuery.self)

        var builder = TransactionModel.query(on: req.db)
        if let accountID = query.accountID {
            builder = builder.filter(\.$account.$id == accountID)
        }
        let transactions = try await builder.all()

        let transferCategories = try await req.categoryRules.categorizer().transferCategories
        return Projection.project(
            transactions.map {
                Projection.Input(
                    date: $0.date,
                    amount: $0.amount,
                    category: $0.category,
                    isProjected: $0.isProjected
                )
            },
            transferCategories: query.includeTransfers == true ? [] : transferCategories,
            forecastMonths: min(max(query.forecastMonths ?? 6, 0), 24),
            baseMonths: min(max(query.baseMonths ?? 6, 1), 24)
        )
    }
}

struct TransactionQuery: Content {
    var accountID: UUID?
    var from: Date?
    var to: Date?
    var search: String?
    var includeProjected: Bool?
    var limit: Int?
    var offset: Int?
}

struct SummaryQuery: Content {
    var accountID: UUID?
    var forecastMonths: Int?
    var baseMonths: Int?
    var includeTransfers: Bool?
}
