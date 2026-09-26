import Foundation

/// Uma importação já realizada. Serve para desfazer o arquivo inteiro sem
/// precisar apagar lançamento por lançamento.
public struct ImportBatchDTO: Codable, Sendable, Hashable, Identifiable {
    public var id: UUID?
    public var accountID: UUID
    public var filename: String?
    public var createdAt: Date?
    /// Lançamentos criados por esta importação e ainda existentes.
    public var transactionCount: Int
    /// Projeções que esta importação confirmou; ao desfazer, voltam a ser projeções.
    public var confirmedCount: Int

    public init(
        id: UUID? = nil,
        accountID: UUID,
        filename: String? = nil,
        createdAt: Date? = nil,
        transactionCount: Int = 0,
        confirmedCount: Int = 0
    ) {
        self.id = id
        self.accountID = accountID
        self.filename = filename
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

public struct BulkDeleteResponse: Codable, Sendable {
    public var deleted: Int
    /// Projeções restauradas quando uma importação é desfeita.
    public var restored: Int

    public init(deleted: Int, restored: Int = 0) {
        self.deleted = deleted
        self.restored = restored
    }
}
