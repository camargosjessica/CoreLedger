import Fluent

/// Comentário livre nos lançamentos e o mês da fatura no lote de importação,
/// que permite substituir a fatura anterior do mesmo cartão e mês.
struct AddNoteAndStatementMonthMigration: AsyncMigration {
    func prepare(on database: any Database) async throws {
        try await database.schema("transactions")
            .field("note", .string)
            .update()
        try await database.schema("import_batches")
            .field("statement_month", .string)
            .update()
    }

    func revert(on database: any Database) async throws {
        try await database.schema("import_batches")
            .deleteField("statement_month")
            .update()
        try await database.schema("transactions")
            .deleteField("note")
            .update()
    }
}
