import Fluent

/// Campos de importação em `transactions`.
///
/// `dedup_key` é opcional de propósito: os lançamentos criados antes desta
/// migração não têm chave, e no Postgres um índice único aceita múltiplos NULL —
/// então o histórico continua válido e os novos registros ficam protegidos.
struct AddTransactionImportFieldsMigration: AsyncMigration {
    func prepare(on database: Database) async throws {
        try await database.schema("transactions")
            .field("account_id", .uuid, .references("accounts", "id", onDelete: .cascade))
            .field("dedup_key", .string)
            .field("is_projected", .bool, .required, .sql(.default(false)))
            .field("installment_number", .int)
            .field("installment_total", .int)
            .field("external_id", .string)
            .unique(on: "dedup_key")
            .update()
    }

    func revert(on database: Database) async throws {
        try await database.schema("transactions")
            .deleteUnique(on: "dedup_key")
            .deleteField("account_id")
            .deleteField("dedup_key")
            .deleteField("is_projected")
            .deleteField("installment_number")
            .deleteField("installment_total")
            .deleteField("external_id")
            .update()
    }
}
