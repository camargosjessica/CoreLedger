import Foundation
import KausMedia

/// Decide, sem tocar no banco, o que fazer com cada lançamento lido do extrato.
/// Fica separado do serviço para poder ser testado sem Postgres.
enum ImportPlanner {
    struct Plan {
        /// Lançamentos inéditos, a inserir.
        var inserts: [ImportedTransaction] = []
        /// Parcelas que já existiam como projeção e agora foram confirmadas pela fatura.
        var confirmations: [(key: String, transaction: ImportedTransaction)] = []
        /// Já existiam idênticos — ignorados.
        var duplicates: Int = 0
    }

    /// - Parameter existing: chaves já presentes no banco, e se o registro correspondente
    ///   é uma projeção (parcela futura ainda não confirmada).
    static func plan(
        transactions: [ImportedTransaction],
        accountID: UUID,
        existing: [String: Bool]
    ) -> Plan {
        // Deduplicação dentro do próprio lote: o mesmo arquivo pode trazer a
        // linha repetida, e a seleção pode conter o mesmo extrato duas vezes.
        // Entre duas linhas com a mesma chave, a real prevalece sobre a projetada.
        var batch: [String: ImportedTransaction] = [:]
        var order: [String] = []
        var duplicates = 0

        for transaction in transactions {
            let key = DedupKey.make(accountID: accountID, transaction: transaction)
            if let current = batch[key] {
                if current.isProjected && !transaction.isProjected {
                    batch[key] = transaction
                } else {
                    duplicates += 1
                }
                continue
            }
            batch[key] = transaction
            order.append(key)
        }

        var plan = Plan()
        plan.duplicates = duplicates

        for key in order {
            guard let transaction = batch[key] else { continue }
            switch existing[key] {
            case .none:
                plan.inserts.append(transaction)
            case .some(true) where !transaction.isProjected:
                // A projeção virou lançamento real.
                plan.confirmations.append((key: key, transaction: transaction))
            case .some:
                plan.duplicates += 1
            }
        }

        return plan
    }
}
