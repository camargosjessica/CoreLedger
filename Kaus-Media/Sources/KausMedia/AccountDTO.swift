import Foundation

/// Tipo da conta. Define como o extrato é interpretado na importação:
/// faturas de cartão passam pela expansão de parcelas.
public enum AccountKind: String, Codable, Sendable, CaseIterable {
    case checking
    /// Poupança ou caixinha: dinheiro guardado, com nome livre.
    case savings
    case creditCard
    case cash
    case investment

    public var expandsInstallments: Bool { self == .creditCard }

    /// Contas cujo saldo é dinheiro guardado, não disponível para o dia a dia.
    public var isSavings: Bool { self == .savings || self == .investment }

    public var displayName: String {
        switch self {
        case .checking: return "Conta corrente"
        case .savings: return "Caixinha ou poupança"
        case .creditCard: return "Cartão de crédito"
        case .cash: return "Dinheiro"
        case .investment: return "Investimento"
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
