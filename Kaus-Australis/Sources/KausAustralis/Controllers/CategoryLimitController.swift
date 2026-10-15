import Fluent
import Vapor
import KausMedia

/// Limites mensais por categoria. `PUT` cria ou troca o limite da categoria.
struct CategoryLimitController: RouteCollection {
    func boot(routes: any RoutesBuilder) throws {
        let limits = routes.grouped("api", "limits")
        limits.get(use: index)
        limits.put(use: upsert)
        limits.delete(":category", use: delete)
    }

    func index(req: Request) async throws -> [CategoryLimit] {
        try await CategoryLimitModel.query(on: req.db)
            .sort(\.$category)
            .all()
            .map { $0.toDTO() }
    }

    func upsert(req: Request) async throws -> CategoryLimit {
        var dto = try req.content.decode(CategoryLimit.self)
        dto.category = dto.category.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !dto.category.isEmpty else {
            throw Abort(.badRequest, reason: "A categoria é obrigatória")
        }
        guard dto.monthlyLimit.isFinite, dto.monthlyLimit > 0 else {
            throw Abort(.badRequest, reason: "O limite deve ser maior que zero")
        }

        if let model = try await CategoryLimitModel.query(on: req.db)
            .filter(\.$category == dto.category)
            .first() {
            model.monthlyLimit = dto.monthlyLimit
            try await model.update(on: req.db)
            return model.toDTO()
        }
        let model = CategoryLimitModel(limit: dto)
        try await model.create(on: req.db)
        return model.toDTO()
    }

    func delete(req: Request) async throws -> HTTPStatus {
        guard let category = req.parameters.get("category"), !category.isEmpty else {
            throw Abort(.badRequest, reason: "Categoria inválida")
        }
        try await CategoryLimitModel.query(on: req.db)
            .filter(\.$category == category)
            .delete()
        return .noContent
    }
}
