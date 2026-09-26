import Fluent

/// Lotes de importação e a referência em `transactions`.
///
/// `onDelete: .setNull` no lançamento: apagar o lote é uma operação de
/// histórico e não pode levar junto lançamentos que o usuário decidiu manter.
struct CreateImportBatchMigration: AsyncMigration {
    func prepare(on database: Database) async throws {
        try await database.schema("import_batches")
            .id()
            .field("account_id", .uuid, .required, .references("accounts", "id", onDelete: .cascade))
            .field("filename", .string)
            .field("confirmations", .json, .required)
            .field("created_at", .datetime)
            .create()

        try await database.schema("transactions")
            .field("import_batch_id", .uuid, .references("import_batches", "id", onDelete: .setNull))
            .update()
    }

    func revert(on database: Database) async throws {
        try await database.schema("transactions")
            .deleteField("import_batch_id")
            .update()
        try await database.schema("import_batches").delete()
    }
}
