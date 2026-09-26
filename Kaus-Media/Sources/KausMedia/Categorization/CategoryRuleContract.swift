import Foundation

/// Corpo de `POST /api/category-rules/preview`: simula a categorização de uma
/// descrição, opcionalmente com uma regra que ainda não foi salva.
public struct CategoryPreviewRequest: Codable, Sendable {
    public var description: String
    public var amount: Double
    public var rule: CategoryRule?

    public init(description: String, amount: Double, rule: CategoryRule? = nil) {
        self.description = description
        self.amount = amount
        self.rule = rule
    }
}

public struct CategoryPreviewResponse: Codable, Sendable {
    public var category: String
    /// Termo da regra que casou, quando alguma casou.
    public var matchedTerm: String?

    public init(category: String, matchedTerm: String? = nil) {
        self.category = category
        self.matchedTerm = matchedTerm
    }
}

/// Resultado de `POST /api/transactions/recategorize`.
public struct RecategorizeResponse: Codable, Sendable {
    public var updated: Int

    public init(updated: Int) {
        self.updated = updated
    }
}
