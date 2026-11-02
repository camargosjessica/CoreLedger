import Fluent
import SQLKit

/// Troca as colunas de valor em ponto flutuante por centavos inteiros.
///
/// `double precision` não representa 0,10 com exatidão e acumula erro nas
/// somas de saldo. Os valores atuais são arredondados para o centavo mais
/// próximo; os campos JSON (exceções e reajustes dos compromissos, snapshots
/// das importações) continuam em reais decimais e não mudam.
struct ConvertAmountsToCentsMigration: AsyncMigration {
    private struct Column {
        let table: String
        let from: String
        let to: String
    }

    private let columns = [
        Column(table: "transactions", from: "amount", to: "amount_cents"),
        Column(table: "recurring_commitments", from: "amount", to: "amount_cents"),
        Column(table: "category_limits", from: "monthly_limit", to: "monthly_limit_cents"),
    ]

    func prepare(on database: any Database) async throws {
        guard let sql = database as? any SQLDatabase else { return }
        for column in columns {
            try await sql.raw("""
                ALTER TABLE \(ident: column.table) ADD COLUMN \(ident: column.to) bigint
                """).run()
            try await sql.raw("""
                UPDATE \(ident: column.table) SET \(ident: column.to) = round(\(ident: column.from)::numeric * 100)::bigint
                """).run()
            try await sql.raw("""
                ALTER TABLE \(ident: column.table) ALTER COLUMN \(ident: column.to) SET NOT NULL
                """).run()
            try await sql.raw("""
                ALTER TABLE \(ident: column.table) DROP COLUMN \(ident: column.from)
                """).run()
        }
    }

    func revert(on database: any Database) async throws {
        guard let sql = database as? any SQLDatabase else { return }
        for column in columns {
            try await sql.raw("""
                ALTER TABLE \(ident: column.table) ADD COLUMN \(ident: column.from) double precision
                """).run()
            try await sql.raw("""
                UPDATE \(ident: column.table) SET \(ident: column.from) = \(ident: column.to)::double precision / 100
                """).run()
            try await sql.raw("""
                ALTER TABLE \(ident: column.table) ALTER COLUMN \(ident: column.from) SET NOT NULL
                """).run()
            try await sql.raw("""
                ALTER TABLE \(ident: column.table) DROP COLUMN \(ident: column.to)
                """).run()
        }
    }
}
