import Fluent

struct CreateTransactionMigration: AsyncMigration {
    func prepare(on database: Database) async throws {
        try await database.schema("transactions")
            .id()
            .field("description", .string, .required)
            .field("amount", .double, .required)
            .field("category", .string, .required)
            .field("date", .datetime, .required)
            .create()
    }

    func revert(on database: Database) async throws {
        try await database.schema("transactions").delete()
    }
}
