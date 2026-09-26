import Fluent
import Vapor
import KausMedia

/// CRUD das regras de categorização: é o que torna a categorização configurável
/// em vez de uma lista fixa no código.
struct CategoryRuleController: RouteCollection {
    private static let regexLengthLimit = 200

    func boot(routes: any RoutesBuilder) throws {
        let rules = routes.grouped("api", "category-rules")
        rules.get(use: index)
        rules.post(use: create)
        rules.post("preview", use: preview)
        rules.group(":ruleID") { rule in
            rule.put(use: update)
            rule.delete(use: delete)
        }
        routes.post("api", "transactions", "recategorize", use: recategorize)
        routes.delete("api", "categories", ":category", use: deleteCategory)
    }

    func index(req: Request) async throws -> [CategoryRule] {
        try await req.categoryRules.rules()
    }

    func create(req: Request) async throws -> Response {
        let dto = try req.content.decode(CategoryRule.self)
        try validate(dto)
        let model = CategoryRuleModel(rule: dto)
        try await model.create(on: req.db)
        return try await model.toDTO().encodeResponse(status: .created, for: req)
    }

    func update(req: Request) async throws -> CategoryRule {
        let model = try await find(req)
        let dto = try req.content.decode(CategoryRule.self)
        try validate(dto)
        model.apply(dto)
        try await model.update(on: req.db)
        return model.toDTO()
    }

    func delete(req: Request) async throws -> HTTPStatus {
        let model = try await find(req)
        try await model.delete(on: req.db)
        return .noContent
    }

    /// Testa como uma descrição seria categorizada com as regras atuais,
    /// antes de salvar uma regra nova.
    func preview(req: Request) async throws -> CategoryPreviewResponse {
        let request = try req.content.decode(CategoryPreviewRequest.self)
        var rules = try await req.categoryRules.rules()
        if let candidate = request.rule {
            try validate(candidate)
            rules.append(candidate)
        }
        let categorizer = Categorizer(rules: rules)
        return CategoryPreviewResponse(
            category: categorizer.category(for: request.description, amount: request.amount),
            matchedTerm: categorizer.match(description: request.description, amount: request.amount)?.rule.term
        )
    }

    /// Reaplica as regras aos lançamentos existentes. Necessário depois de criar
    /// ou corrigir uma regra: sem isso, o histórico continuaria com a categoria antiga.
    func recategorize(req: Request) async throws -> RecategorizeResponse {
        let query = try req.query.decode(RecategorizeQuery.self)
        let categorizer = try await req.categoryRules.categorizer()

        var builder = TransactionModel.query(on: req.db)
        if let accountID = query.accountID {
            builder = builder.filter(\.$account.$id == accountID)
        }
        if query.onlyUncategorized == true {
            builder = builder.group(.or) { group in
                group.filter(\.$category == CategoryRule.uncategorizedDebit)
                    .filter(\.$category == CategoryRule.uncategorizedCredit)
            }
        }

        var changed = 0
        for model in try await builder.all() {
            let category = categorizer.category(for: model.description, amount: model.amount)
            guard category != model.category else { continue }
            model.category = category
            try await model.update(on: req.db)
            changed += 1
        }
        return RecategorizeResponse(updated: changed)
    }

    /// Apaga uma categoria: as regras que a produzem somem e os lançamentos que
    /// a usavam passam pelas regras restantes, em vez de ficarem com o nome de
    /// uma categoria que não existe mais.
    func deleteCategory(req: Request) async throws -> DeleteCategoryResponse {
        guard let name = req.parameters.get("category"), !name.isEmpty else {
            throw Abort(.badRequest, reason: "Categoria inválida")
        }

        return try await req.db.transaction { db in
            let rules = try await CategoryRuleModel.query(on: db)
                .filter(\.$category == name)
                .all()
            for rule in rules {
                try await rule.delete(on: db)
            }

            let categorizer = try await CategoryRuleService(database: db).categorizer()
            var recategorized = 0
            let affected = try await TransactionModel.query(on: db)
                .filter(\.$category == name)
                .all()
            for model in affected {
                model.category = categorizer.category(for: model.description, amount: model.amount)
                try await model.update(on: db)
                recategorized += 1
            }

            return DeleteCategoryResponse(removedRules: rules.count, recategorized: recategorized)
        }
    }

    private func validate(_ rule: CategoryRule) throws {
        guard !rule.term.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw Abort(.badRequest, reason: "O termo da regra é obrigatório")
        }
        guard !rule.category.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw Abort(.badRequest, reason: "A categoria da regra é obrigatória")
        }
        if rule.matchKind == .regex {
            // A regra é aplicada a cada lançamento em importações e recategorizações
            // em massa: um padrão longo e ambíguo custa caro multiplicado por milhares.
            guard rule.term.count <= Self.regexLengthLimit else {
                throw Abort(.badRequest, reason: "Expressão regular longa demais (máximo \(Self.regexLengthLimit) caracteres)")
            }
            guard (try? NSRegularExpression(pattern: rule.term)) != nil else {
                throw Abort(.badRequest, reason: "Expressão regular inválida: \(rule.term)")
            }
        }
    }

    private func find(_ req: Request) async throws -> CategoryRuleModel {
        guard let id = req.parameters.get("ruleID", as: UUID.self) else {
            throw Abort(.badRequest, reason: "Identificador de regra inválido")
        }
        guard let model = try await CategoryRuleModel.find(id, on: req.db) else {
            throw Abort(.notFound, reason: "Regra não encontrada")
        }
        return model
    }
}

struct RecategorizeQuery: Content {
    var accountID: UUID?
    var onlyUncategorized: Bool?
}
