import Foundation

/// Novo nome de uma categoria ou tag.
public struct RenameLabelRequest: Codable, Sendable {
    public var name: String

    public init(name: String) {
        self.name = name
    }
}

/// Quantos registros mudaram ao renomear ou apagar uma categoria ou tag.
public struct LabelChangeResponse: Codable, Sendable, Hashable {
    public var transactions: Int
    public var rules: Int
    public var commitments: Int

    public init(transactions: Int = 0, rules: Int = 0, commitments: Int = 0) {
        self.transactions = transactions
        self.rules = rules
        self.commitments = commitments
    }
}

extension TagSet {
    /// Troca `tag` por `replacement` (ou a remove, com `nil`). Devolve `nil` quando
    /// a lista não tem a tag, para quem chama saber que não precisa gravar nada.
    public static func replacing(_ tag: String, with replacement: String?, in tags: [String]) -> [String]? {
        guard let target = normalize([tag]).first else { return nil }
        let current = normalize(tags)
        guard current.contains(target) else { return nil }
        let renamed = current.flatMap { $0 == target ? (replacement.map { [$0] } ?? []) : [$0] }
        return normalize(renamed)
    }
}
