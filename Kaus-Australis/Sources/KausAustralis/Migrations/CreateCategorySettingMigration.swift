import Fluent

/// Preferências por categoria (por enquanto, só "essencial").
struct CreateCategorySettingMigration: AsyncMigration {
    func prepare(on database: Database) async throws {
        try await database.schema("category_settings")
            .id()
            .field("category", .string, .required)
            .field("is_essential", .bool, .required, .sql(.default(false)))
            .unique(on: "category")
            .create()
    }

    func revert(on database: Database) async throws {
        try await database.schema("category_settings").delete()
    }
}
