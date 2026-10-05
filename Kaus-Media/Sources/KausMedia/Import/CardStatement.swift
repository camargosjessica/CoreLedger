import Foundation

public enum CardStatement {
    /// Faturas de cartão costumam trazer compras positivas e pagamentos negativos,
    /// o inverso do extrato da conta. Um pagamento de fatura negativo define a
    /// convenção; sem ele, vale a maioria das linhas. Nesses casos os sinais são
    /// invertidos para seguir a convenção do app (negativo = saída).
    public static func normalizeSigns(_ transactions: [ImportedTransaction]) -> [ImportedTransaction] {
        guard purchasesArePositive(transactions) else { return transactions }
        return transactions.map { transaction in
            var flipped = transaction
            flipped.amount = -transaction.amount
            return flipped
        }
    }

    private static func purchasesArePositive(_ transactions: [ImportedTransaction]) -> Bool {
        let payments = transactions.filter { isInvoicePayment($0.description) }
        if let payment = payments.first(where: { $0.amount != 0 }) {
            return payment.amount < 0
        }
        let positives = transactions.filter { $0.amount > 0 }.count
        let negatives = transactions.filter { $0.amount < 0 }.count
        return positives > negatives
    }

    private static func isInvoicePayment(_ description: String) -> Bool {
        let normalized = TextNormalizer.normalize(description)
        return normalized.hasPrefix("pagamento") || normalized.hasPrefix("pgto")
    }
}
