import Foundation

/// Uma importação já realizada. Serve para desfazer o arquivo inteiro sem
/// precisar apagar lançamento por lançamento.
public struct ImportBatchDTO: Codable, Sendable, Hashable, Identifiable {
    public var id: UUID?
    public var accountID: UUID
    public var filename: String?
    /// Mês da fatura, quando a importação foi de um cartão.
    public var statementMonth: YearMonth?
    public var createdAt: Date?
    /// Lançamentos criados por esta importação e ainda existentes.
    public var transactionCount: Int
    /// Projeções que esta importação confirmou; ao desfazer, voltam a ser projeções.
    public var confirmedCount: Int

    public init(
        id: UUID? = nil,
        accountID: UUID,
        filename: String? = nil,
        statementMonth: YearMonth? = nil,
        createdAt: Date? = nil,
        transactionCount: Int = 0,
        confirmedCount: Int = 0
    ) {
        self.id = id
        self.accountID = accountID
        self.filename = filename
        self.statementMonth = statementMonth
        self.createdAt = createdAt
        self.transactionCount = transactionCount
        self.confirmedCount = confirmedCount
    }
}

/// Corpo de `DELETE /api/transactions`: remoção em lote.
public struct BulkDeleteRequest: Codable, Sendable {
    public var ids: [UUID]

    public init(ids: [UUID]) {
        self.ids = ids
    }
}

/// Corpo de `PATCH /api/transactions`: mesma categoria e tags em vários lançamentos.
public struct BulkUpdateRequest: Codable, Sendable {
    public var ids: [UUID]
    /// `nil` mantém a categoria de cada lançamento.
    public var category: String?
    public var addTags: [String]
    public var removeTags: [String]

    public init(ids: [UUID], category: String? = nil, addTags: [String] = [], removeTags: [String] = []) {
        self.ids = ids
        self.category = category
        self.addTags = addTags
        self.removeTags = removeTags
    }

    /// Categoria a gravar, ou `nil` quando não muda.
    public var normalizedCategory: String? {
        guard let trimmed = category?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty else { return nil }
        return trimmed
    }

    /// Tags do lançamento depois de tirar `removeTags` e incluir `addTags`.
    public func applyTags(to tags: [String]) -> [String] {
        let removed = Set(TagSet.normalize(removeTags))
        return TagSet.normalize(TagSet.normalize(tags).filter { !removed.contains($0) } + addTags)
    }
}

public struct BulkUpdateResponse: Codable, Sendable {
    public var updated: Int

    public init(updated: Int) {
        self.updated = updated
    }
}

public struct BulkDeleteResponse: Codable, Sendable {
    public var deleted: Int
    /// Projeções restauradas quando uma importação é desfeita.
    public var restored: Int

    public init(deleted: Int, restored: Int = 0) {
        self.deleted = deleted
        self.restored = restored
    }
}
