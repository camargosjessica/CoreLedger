import Fluent

/// Liga a contrapartida de uma transferência (ex.: a entrada na caixinha) ao
/// lançamento de origem. `onDelete: .cascade`: apagar a origem, inclusive ao
/// desfazer a importação que a criou, leva a contrapartida junto.
struct AddTransferSourceMigration: AsyncMigration {
    func prepare(on database: Database) async throws {
        try await database.schema("transactions")
            .field("transfer_source_id", .uuid, .references("transactions", "id", onDelete: .cascade))
            .update()
    }

    func revert(on database: Database) async throws {
        try await database.schema("transactions").deleteField("transfer_source_id").update()
    }
}
