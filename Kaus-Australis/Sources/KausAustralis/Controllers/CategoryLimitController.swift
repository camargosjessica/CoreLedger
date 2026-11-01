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
        let dto = try Validation.limit(req.content.decode(CategoryLimit.self))

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
        let category = try req.parameters.label("category", invalid: .invalidCategory)
        try await CategoryLimitModel.query(on: req.db)
            .filter(\.$category == category)
            .delete()
        return .noContent
    }
}
