import Foundation

/// Tipo da conta. Define como o extrato é interpretado na importação:
/// faturas de cartão passam pela expansão de parcelas.
public enum AccountKind: String, Codable, Sendable, CaseIterable {
    case checking
    case savings
    case creditCard
    case cash

    public var expandsInstallments: Bool { self == .creditCard }

    public var displayName: String {
        switch self {
        case .checking: return "Conta corrente"
        case .savings: return "Poupança"
        case .creditCard: return "Cartão de crédito"
        case .cash: return "Dinheiro"
        }
    }
}

public struct AccountDTO: Codable, Sendable, Hashable, Identifiable {
    public var id: UUID?
    public var name: String
    public var kind: AccountKind
    public var createdAt: Date?
    /// Agregados calculados pelo servidor (não enviados na criação).
    public var transactionCount: Int?
    public var balance: Double?

    public init(
        id: UUID? = nil,
        name: String,
        kind: AccountKind = .checking,
        createdAt: Date? = nil,
        transactionCount: Int? = nil,
        balance: Double? = nil
    ) {
        self.id = id
        self.name = name
        self.kind = kind
        self.createdAt = createdAt
        self.transactionCount = transactionCount
        self.balance = balance
    }
}
