import Foundation
import KausMedia

/// Decide, sem tocar no banco, o que fazer com cada lançamento lido do extrato.
/// Fica separado do serviço para poder ser testado sem Postgres.
enum ImportPlanner {
    struct Plan {
        /// Lançamentos inéditos, a inserir, com a chave que vai para o banco.
        var inserts: [(key: String, transaction: ImportedTransaction)] = []
        /// Parcelas que já existiam como projeção e agora foram confirmadas pela fatura.
        var confirmations: [(key: String, transaction: ImportedTransaction)] = []
        /// Já existiam idênticos — ignorados.
        var duplicates: Int = 0
    }

    /// Chave de cada lançamento do lote, na ordem do arquivo.
    ///
    /// Duas compras iguais no mesmo dia, pelo mesmo valor e no mesmo
    /// estabelecimento são compras distintas, não duplicata: a segunda recebe
    /// um sufixo de ocorrência. Como a numeração é determinística, reimportar o
    /// mesmo arquivo reproduz exatamente as mesmas chaves e nada é duplicado.
    /// Parcelas ficam de fora da numeração — mês e posição já as identificam,
    /// e é o que permite a projeção ser confirmada pela fatura real.
    static func keys(for transactions: [ImportedTransaction], accountID: UUID) -> [String] {
        var occurrences: [String: Int] = [:]
        return transactions.map { transaction in
            let base = DedupKey.make(accountID: accountID, transaction: transaction)
            guard transaction.installment == nil else { return base }
            let occurrence = (occurrences[base] ?? 0) + 1
            occurrences[base] = occurrence
            return occurrence == 1 ? base : "\(base)#\(occurrence)"
        }
    }

    /// - Parameter existing: chaves já presentes no banco, e se o registro correspondente
    ///   é uma projeção (parcela futura ainda não confirmada).
    /// - Parameter keys: chaves já resolvidas por `reconcilingInstallments`; sem elas,
    ///   usa `keys(for:accountID:)`.
    static func plan(
        transactions: [ImportedTransaction],
        accountID: UUID,
        existing: [String: Bool],
        keys: [String]? = nil
    ) -> Plan {
        let resolvedKeys = keys ?? Self.keys(for: transactions, accountID: accountID)
        // Entre duas parcelas com a mesma chave no lote, a real prevalece sobre
        // a projetada (a fatura seguinte confirma o que havia sido projetado).
        var batch: [String: ImportedTransaction] = [:]
        var order: [String] = []
        var duplicates = 0

        for (key, transaction) in zip(resolvedKeys, transactions) {
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
                plan.inserts.append((key: key, transaction: transaction))
            case .some(true) where !transaction.isProjected:
                // A projeção virou lançamento real.
                plan.confirmations.append((key: key, transaction: transaction))
            case .some:
                plan.duplicates += 1
            }
        }

        return plan
    }

    /// Parcela já gravada na conta, candidata a ser a mesma de uma linha da fatura.
    struct StoredInstallment {
        var key: String
        var description: String
        var amount: Double
        var date: Date
        var installment: Installment
    }

    /// Troca a chave das parcelas sem correspondência exata pela chave de uma parcela
    /// gravada da mesma compra: mesmo mês, mesma posição, valor a até 5 centavos e
    /// descrição compatível (`InstallmentDescription`). Sem isso, cada fatura que
    /// corta a descrição de outro jeito duplicaria a parcela e as projeções seguintes.
    static func reconcilingInstallments(
        keys: [String],
        transactions: [ImportedTransaction],
        existing: [String: Bool],
        stored: [StoredInstallment]
    ) -> [String] {
        let batchKeys = Set(keys)
        var aliases: [String: String] = [:]
        var claimed: Set<String> = []

        return zip(keys, transactions).map { key, transaction in
            guard let installment = transaction.installment, existing[key] == nil else { return key }
            if let alias = aliases[key] { return alias }

            let month = LedgerCalendar.startOfMonth(transaction.date)
            guard let match = stored.first(where: { candidate in
                !batchKeys.contains(candidate.key)
                    && !claimed.contains(candidate.key)
                    && candidate.installment == installment
                    && LedgerCalendar.startOfMonth(candidate.date) == month
                    && abs(candidate.amount.centsValue - transaction.amount.centsValue) <= 5
                    && InstallmentDescription.matches(candidate.description, transaction.description)
            }) else { return key }

            claimed.insert(match.key)
            aliases[key] = match.key
            return match.key
        }
    }
}
