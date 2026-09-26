import Fluent

struct CreateAccountMigration: AsyncMigration {
    func prepare(on database: Database) async throws {
        try await database.schema("accounts")
            .id()
            .field("name", .string, .required)
            .field("kind", .string, .required)
            .field("created_at", .datetime)
            .unique(on: "name")
            .create()
    }

    func revert(on database: Database) async throws {
        try await database.schema("accounts").delete()
    }
}
