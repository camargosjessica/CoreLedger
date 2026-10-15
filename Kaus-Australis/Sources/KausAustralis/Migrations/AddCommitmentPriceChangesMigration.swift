import Fluent

/// Reajustes permanentes dos compromissos. Entram vazios: o valor mensal
/// atual continua valendo para todos os meses até o primeiro reajuste.
struct AddCommitmentPriceChangesMigration: AsyncMigration {
    func prepare(on database: Database) async throws {
        try await database.schema("recurring_commitments")
            .field("price_changes", .dictionary(of: .double), .required, .sql(.default("{}")))
            .update()
    }

    func revert(on database: Database) async throws {
        try await database.schema("recurring_commitments").deleteField("price_changes").update()
    }
}
