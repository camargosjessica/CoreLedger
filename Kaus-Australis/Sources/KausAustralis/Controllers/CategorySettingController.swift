import Fluent
import Vapor
import KausMedia

/// Preferências por categoria. `PUT` grava; desligar tudo apaga a linha.
struct CategorySettingController: RouteCollection {
    func boot(routes: any RoutesBuilder) throws {
        let settings = routes.grouped("api", "category-settings")
        settings.get(use: index)
        settings.put(use: upsert)
    }

    func index(req: Request) async throws -> [CategorySetting] {
        try await CategorySettingModel.query(on: req.db)
            .sort(\.$category)
            .all()
            .map { $0.toDTO() }
    }

    func upsert(req: Request) async throws -> CategorySetting {
        let dto = try Validation.setting(req.content.decode(CategorySetting.self))

        let existing = try await CategorySettingModel.query(on: req.db)
            .filter(\.$category == dto.category)
            .first()
        if !dto.isEssential {
            try await existing?.delete(on: req.db)
            return dto
        }
        if let existing {
            existing.isEssential = true
            try await existing.update(on: req.db)
            return existing.toDTO()
        }
        let model = CategorySettingModel(setting: dto)
        try await model.create(on: req.db)
        return model.toDTO()
    }
}
