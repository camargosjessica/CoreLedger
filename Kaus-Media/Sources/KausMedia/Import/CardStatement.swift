import Foundation

public enum CardStatement {
    /// Faturas de cartão costumam trazer compras positivas e pagamentos negativos,
    /// o inverso do extrato da conta. Quando a maioria das linhas é positiva, os
    /// sinais são invertidos para seguir a convenção do app (negativo = saída).
    public static func normalizeSigns(_ transactions: [ImportedTransaction]) -> [ImportedTransaction] {
        let positives = transactions.filter { $0.amount > 0 }.count
        let negatives = transactions.filter { $0.amount < 0 }.count
        guard positives > negatives else { return transactions }
        return transactions.map { transaction in
            var flipped = transaction
            flipped.amount = -transaction.amount
            return flipped
        }
    }
}
