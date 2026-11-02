import Fluent
import SQLKit

/// Índices para os filtros mais usados da tabela de lançamentos: conta e
/// período (lista e saldos), lote de importação (desfazer, contagem) e
/// contrapartida de transferência (consultada a cada edição).
struct AddTransactionIndexesMigration: AsyncMigration {
    private let indexes: [(name: String, columns: String)] = [
        ("idx_transactions_account_date", "account_id, date"),
        ("idx_transactions_date", "date"),
        ("idx_transactions_import_batch", "import_batch_id"),
        ("idx_transactions_transfer_source", "transfer_source_id"),
    ]

    func prepare(on database: any Database) async throws {
        guard let sql = database as? any SQLDatabase else { return }
        for index in indexes {
            try await sql.raw("""
                CREATE INDEX IF NOT EXISTS \(ident: index.name) ON transactions (\(unsafeRaw: index.columns))
                """).run()
        }
    }

    func revert(on database: any Database) async throws {
        guard let sql = database as? any SQLDatabase else { return }
        for index in indexes {
            try await sql.raw("DROP INDEX IF EXISTS \(ident: index.name)").run()
        }
    }
}
