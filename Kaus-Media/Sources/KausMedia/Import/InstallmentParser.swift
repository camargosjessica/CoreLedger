import Foundation

/// Reconhece parcelamentos na descrição da fatura ("PARC 03/10", "3 DE 10", "NETSHOES 3/10")
/// e projeta as parcelas que ainda vão cair nas próximas faturas.
public enum InstallmentParser {
    /// Maior número de parcelas aceito. Acima disso é quase certo que o "x/y"
    /// encontrado na descrição significa outra coisa.
    public static let maxInstallments = 72

    public struct Detection: Sendable, Equatable {
        /// Descrição sem o marcador de parcela, para que todas as parcelas da
        /// mesma compra compartilhem o mesmo texto base.
        public let baseDescription: String
        public let installment: Installment
    }

    private static let explicitPattern = try? NSRegularExpression(
        pattern: "\\bparc(?:ela)?[a-z]*\\.?\\s*(\\d{1,2})\\s*(?:/|de|-)\\s*(\\d{1,2})\\b",
        options: [.caseInsensitive]
    )

    /// `3/10` solto na descrição. O lookahead evita capturar datas (`03/10/2024`).
    private static let barePattern = try? NSRegularExpression(
        pattern: "(?<![\\d/])(\\d{1,2})\\s*/\\s*(\\d{1,2})(?![\\d/])",
        options: []
    )

    public static func detect(in description: String) -> Detection? {
        let normalized = TextNormalizer.normalize(description)
        for regex in [explicitPattern, barePattern].compactMap({ $0 }) {
            let range = NSRange(normalized.startIndex..., in: normalized)
            guard let match = regex.firstMatch(in: normalized, range: range),
                  let numberRange = Range(match.range(at: 1), in: normalized),
                  let totalRange = Range(match.range(at: 2), in: normalized),
                  let number = Int(normalized[numberRange]),
                  let total = Int(normalized[totalRange])
            else { continue }

            guard total >= 2, total <= maxInstallments, number >= 1, number <= total else { continue }

            guard let fullRange = Range(match.range, in: normalized) else { continue }
            var base = normalized
            base.removeSubrange(fullRange)
            let cleaned = TextNormalizer.normalize(base).trimmingCharacters(in: CharacterSet(charactersIn: " -–—·|"))

            return Detection(
                baseDescription: cleaned.isEmpty ? normalized : cleaned,
                installment: Installment(number: number, total: total)
            )
        }
        return nil
    }
}

public enum InstallmentExpander {
    /// Para cada lançamento parcelado, devolve a parcela original seguida das
    /// parcelas futuras (uma por mês, mesmo valor), marcadas como projetadas.
    ///
    /// As parcelas futuras usam a descrição base, de modo que, quando a fatura do
    /// mês seguinte for importada, a parcela real gere a mesma chave de
    /// deduplicação da projeção e apenas a confirme, em vez de duplicá-la.
    public static func expand(_ transactions: [ImportedTransaction]) -> [ImportedTransaction] {
        transactions.flatMap(expand)
    }

    public static func expand(_ transaction: ImportedTransaction) -> [ImportedTransaction] {
        guard let detection = InstallmentParser.detect(in: transaction.description) else {
            return [transaction]
        }

        var current = transaction
        current.description = detection.baseDescription
        current.installment = detection.installment

        guard detection.installment.remaining > 0 else { return [current] }

        let future = (1...detection.installment.remaining).map { offset -> ImportedTransaction in
            ImportedTransaction(
                date: LedgerCalendar.addingMonths(offset, to: transaction.date),
                description: detection.baseDescription,
                amount: transaction.amount,
                externalID: nil,
                installment: Installment(
                    number: detection.installment.number + offset,
                    total: detection.installment.total
                ),
                isProjected: true
            )
        }

        return [current] + future
    }
}
