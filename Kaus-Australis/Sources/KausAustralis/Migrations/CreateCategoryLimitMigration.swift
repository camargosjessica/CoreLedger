import Fluent

/// Limites mensais por categoria.
struct CreateCategoryLimitMigration: AsyncMigration {
    func prepare(on database: Database) async throws {
        try await database.schema("category_limits")
            .id()
            .field("category", .string, .required)
            .field("monthly_limit", .double, .required)
            .unique(on: "category")
            .create()
    }

    func revert(on database: Database) async throws {
        try await database.schema("category_limits").delete()
    }
}
