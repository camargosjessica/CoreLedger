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
    /// Marcadores livres. São preenchidos pela regra da categoria na importação
    /// e podem ser trocados depois — inclusive por tags que o usuário inventar.
    public var tags: [String]
    /// Comentário livre do usuário sobre o lançamento (o que foi a compra).
    public var note: String?
    /// Conta da contrapartida desta transferência (ex.: a caixinha que recebeu
    /// o dinheiro). Somente leitura: muda por `PUT /api/transactions/:id/transfer`.
    public var transferAccountID: UUID?
    /// Lançamento de origem, quando este é a contrapartida de uma transferência.
    /// Somente leitura.
    public var transferSourceID: UUID?

    public init(
        id: UUID? = nil,
        description: String,
        amount: Double,
        date: Date,
        category: String? = nil,
        accountID: UUID? = nil,
        isProjected: Bool = false,
        installment: Installment? = nil,
        dedupKey: String? = nil,
        tags: [String] = [],
        note: String? = nil,
        transferAccountID: UUID? = nil,
        transferSourceID: UUID? = nil
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
        self.tags = TagSet.normalize(tags)
        self.note = TransactionNote.normalize(note)
        self.transferAccountID = transferAccountID
        self.transferSourceID = transferSourceID
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
        tags = TagSet.normalize(try container.decodeIfPresent([String].self, forKey: .tags) ?? [])
        note = TransactionNote.normalize(try container.decodeIfPresent(String.self, forKey: .note))
        transferAccountID = try container.decodeIfPresent(UUID.self, forKey: .transferAccountID)
        transferSourceID = try container.decodeIfPresent(UUID.self, forKey: .transferSourceID)
    }
}

/// Corpo de `PUT /api/transactions/:id/transfer`. `accountID` é a conta que
/// recebe a contrapartida com o valor invertido; `nil` desfaz a ligação.
public struct TransferLinkRequest: Codable, Sendable {
    public var accountID: UUID?

    public init(accountID: UUID?) {
        self.accountID = accountID
    }
}

public enum TransactionNote {
    /// Comentário em branco é ausência de comentário.
    public static func normalize(_ note: String?) -> String? {
        guard let trimmed = note?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else { return nil }
        return trimmed
    }
}
