import Foundation

/// Chave determinística que identifica um lançamento independentemente de quantas
/// vezes o mesmo extrato for importado. Vira índice único no Postgres — a garantia
/// fica no banco, não em um `Set` em memória.
public enum DedupKey {
    /// Descrição truncada para manter a chave em tamanho previsível no índice.
    private static let descriptionLimit = 120

    public static func make(
        accountID: UUID?,
        date: Date,
        description: String,
        amount: Double,
        installment: Installment? = nil,
        externalID: String? = nil
    ) -> String {
        let account = accountID?.uuidString.lowercased() ?? "-"
        let cents = amount.centsValue

        // Parcela: a chave ignora o dia, porque a mesma parcela pode ser projetada
        // para o dia 10 e cair de fato no dia 12. Mês, valor e posição da parcela
        // já identificam o lançamento com segurança.
        if let installment {
            let month = String(LedgerCalendar.isoDay(LedgerCalendar.startOfMonth(date)).prefix(7))
            return [
                "v1", account, "parc", month,
                normalizedDescription(description),
                String(cents),
                "\(installment.number)of\(installment.total)"
            ].joined(separator: "|")
        }

        // FITID é o identificador atribuído pelo próprio banco: quando existe,
        // é mais confiável do que qualquer combinação de campos.
        if let externalID, !externalID.trimmed().isEmpty {
            return ["v1", account, "fitid", TextNormalizer.normalize(externalID)].joined(separator: "|")
        }

        return [
            "v1", account, "tx",
            LedgerCalendar.isoDay(date),
            normalizedDescription(description),
            String(cents)
        ].joined(separator: "|")
    }

    public static func make(accountID: UUID?, transaction: ImportedTransaction) -> String {
        make(
            accountID: accountID,
            date: transaction.date,
            description: transaction.description,
            amount: transaction.amount,
            installment: transaction.installment,
            externalID: transaction.externalID
        )
    }

    private static func normalizedDescription(_ description: String) -> String {
        String(TextNormalizer.normalize(description).prefix(descriptionLimit))
    }
}
