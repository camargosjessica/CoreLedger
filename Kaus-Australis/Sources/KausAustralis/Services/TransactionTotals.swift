import Fluent
import FluentSQL
import Foundation
import KausMedia
import Vapor

/// Somas e contagens de lançamentos calculadas pelo Postgres.
///
/// Trazer a tabela inteira para a memória só para somar faz o tempo de
/// resposta crescer junto com o histórico; `GROUP BY` devolve poucas linhas,
/// qualquer que seja o tamanho da tabela.
struct TransactionTotals {
    let database: any Database

    private var sql: any SQLDatabase {
        get throws {
            guard let sql = database as? any SQLDatabase else {
                throw Abort(.internalServerError, reason: "Banco sem suporte a SQL")
            }
            return sql
        }
    }

    // MARK: Por conta

    /// Totais de uma conta (`accountID == nil` reúne os lançamentos sem conta).
    struct AccountTotals: Sendable, Equatable {
        /// Todos os lançamentos, inclusive parcelas previstas.
        var transactionCount = 0
        /// Lançamentos já realizados (sem as parcelas previstas).
        var realizedCount = 0
        /// Só o que já aconteceu: parcelas futuras são previsão, não saldo.
        var balance: Money = .zero
        /// Parcelas previstas com saída de dinheiro.
        var upcomingExpenses: Money = .zero
    }

    private struct AccountRow: Decodable {
        var account_id: UUID?
        var is_projected: Bool
        var is_negative: Bool
        var count: Int
        var total: Int
    }

    func byAccount() async throws -> [UUID?: AccountTotals] {
        let rows = try await sql.raw("""
            SELECT account_id,
                   is_projected,
                   amount_cents < 0 AS is_negative,
                   COUNT(*)::bigint AS count,
                   COALESCE(SUM(amount_cents), 0)::bigint AS total
            FROM transactions
            GROUP BY account_id, is_projected, amount_cents < 0
            """).all(decoding: AccountRow.self)

        var result: [UUID?: AccountTotals] = [:]
        for row in rows {
            var totals = result[row.account_id] ?? AccountTotals()
            totals.transactionCount += row.count
            let amount = Money(cents: row.total)
            if row.is_projected {
                if row.is_negative { totals.upcomingExpenses += amount }
            } else {
                totals.realizedCount += row.count
                totals.balance += amount
            }
            result[row.account_id] = totals
        }
        return result
    }

    // MARK: Por mês e categoria

    private struct MonthlyRow: Decodable {
        var month: Date
        var category: String
        var is_projected: Bool
        var total: Int
    }

    /// Entradas da `Projection` já somadas por mês, categoria, previsão e sinal.
    ///
    /// Separar entradas e saídas no `GROUP BY` preserva o resultado da
    /// projeção, que classifica cada lançamento como receita ou despesa
    /// pelo sinal antes de somar.
    func monthlyInputs(accountID: UUID?, excludingCounterparts: Bool) async throws -> [Projection.Input] {
        let rows = try await sql.raw("""
            SELECT (date_trunc('month', date AT TIME ZONE 'UTC') AT TIME ZONE 'UTC') AS month,
                   category,
                   is_projected,
                   COALESCE(SUM(amount_cents), 0)::bigint AS total
            FROM transactions
            WHERE (\(bind: accountID)::uuid IS NULL OR account_id = \(bind: accountID)::uuid)
              AND (NOT \(bind: excludingCounterparts) OR transfer_source_id IS NULL)
            GROUP BY 1, category, is_projected, amount_cents > 0
            """).all(decoding: MonthlyRow.self)

        return rows.map {
            Projection.Input(
                date: $0.month,
                amount: Money(cents: $0.total),
                category: $0.category,
                isProjected: $0.is_projected
            )
        }
    }

    // MARK: Por importação

    private struct BatchRow: Decodable {
        var import_batch_id: UUID
        var count: Int
    }

    /// Quantidade de lançamentos de cada importação, numa única consulta.
    func countByBatch(_ batchIDs: [UUID]) async throws -> [UUID: Int] {
        guard !batchIDs.isEmpty else { return [:] }
        let rows = try await sql.raw("""
            SELECT import_batch_id, COUNT(*)::bigint AS count
            FROM transactions
            WHERE import_batch_id = ANY(\(bind: batchIDs))
            GROUP BY import_batch_id
            """).all(decoding: BatchRow.self)
        return Dictionary(uniqueKeysWithValues: rows.map { ($0.import_batch_id, $0.count) })
    }
}

extension Request {
    var transactionTotals: TransactionTotals { TransactionTotals(database: db) }
}
