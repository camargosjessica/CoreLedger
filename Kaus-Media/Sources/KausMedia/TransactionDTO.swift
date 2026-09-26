import Foundation

public struct TransactionDTO: Codable, Sendable, Hashable, Identifiable {
    public var id: UUID?
    public var description: String
    public var amount: Double
    public var date: Date
    public var category: String?
    /// Conta à qual o lançamento pertence. `nil` mantém compatibilidade com os
    /// lançamentos criados antes da introdução de contas.
    public var accountID: UUID?
    /// Parcela futura já contratada, ainda não confirmada pela fatura.
    public var isProjected: Bool
    public var installment: Installment?
    /// Chave de deduplicação atribuída pelo servidor. Somente leitura para o cliente.
    public var dedupKey: String?

    public init(
        id: UUID? = nil,
        description: String,
        amount: Double,
        date: Date,
        category: String? = nil,
        accountID: UUID? = nil,
        isProjected: Bool = false,
        installment: Installment? = nil,
        dedupKey: String? = nil
    ) {
        self.id = id
        self.description = description
        self.amount = amount
        self.date = date
        self.category = category
        self.accountID = accountID
        self.isProjected = isProjected
        self.installment = installment
        self.dedupKey = dedupKey
    }

    // Campos novos são opcionais na decodificação para não quebrar clientes antigos.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id)
        description = try container.decode(String.self, forKey: .description)
        amount = try container.decode(Double.self, forKey: .amount)
        date = try container.decode(Date.self, forKey: .date)
        category = try container.decodeIfPresent(String.self, forKey: .category)
        accountID = try container.decodeIfPresent(UUID.self, forKey: .accountID)
        isProjected = try container.decodeIfPresent(Bool.self, forKey: .isProjected) ?? false
        installment = try container.decodeIfPresent(Installment.self, forKey: .installment)
        dedupKey = try container.decodeIfPresent(String.self, forKey: .dedupKey)
    }
}
