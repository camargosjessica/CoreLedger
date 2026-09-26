import Foundation

/// Parcela de uma compra parcelada: `número` de `total` (ex.: 3/10).
public struct Installment: Codable, Sendable, Hashable {
    public var number: Int
    public var total: Int

    public init(number: Int, total: Int) {
        self.number = number
        self.total = total
    }

    public var remaining: Int { max(0, total - number) }
    public var label: String { "\(number)/\(total)" }
}

/// Lançamento lido de um extrato ou fatura, antes de virar registro no banco.
public struct ImportedTransaction: Sendable, Hashable {
    public var date: Date
    public var description: String
    /// Negativo = saída, positivo = entrada.
    public var amount: Double
    /// Identificador do lançamento no banco de origem (`FITID`, no OFX).
    /// Quando existe, é a base mais confiável para deduplicação.
    public var externalID: String?
    public var installment: Installment?
    /// `true` para as parcelas futuras geradas a partir de uma fatura de cartão:
    /// ainda não aconteceram, mas já estão comprometidas.
    public var isProjected: Bool

    public init(
        date: Date,
        description: String,
        amount: Double,
        externalID: String? = nil,
        installment: Installment? = nil,
        isProjected: Bool = false
    ) {
        self.date = date
        self.description = description
        self.amount = amount
        self.externalID = externalID
        self.installment = installment
        self.isProjected = isProjected
    }
}

/// Linha que não pôde ser interpretada. Importar em silêncio é pior do que falhar:
/// o usuário precisa saber que 12 de 300 linhas ficaram de fora e por quê.
public struct ImportFailure: Codable, Sendable, Hashable {
    public var line: Int
    public var content: String
    public var reason: String

    public init(line: Int, content: String, reason: String) {
        self.line = line
        self.content = content
        self.reason = reason
    }
}

public struct ParsedStatement: Sendable {
    public var transactions: [ImportedTransaction]
    public var failures: [ImportFailure]

    public init(transactions: [ImportedTransaction] = [], failures: [ImportFailure] = []) {
        self.transactions = transactions
        self.failures = failures
    }
}
