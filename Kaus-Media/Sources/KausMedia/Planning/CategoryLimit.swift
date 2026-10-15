import Foundation

/// Teto mensal de gasto para uma categoria.
public struct CategoryLimit: Codable, Sendable, Hashable, Identifiable {
    public var category: String
    /// Valor positivo: quanto se aceita gastar na categoria por mês.
    public var monthlyLimit: Double

    public var id: String { category }

    public init(category: String, monthlyLimit: Double) {
        self.category = category
        self.monthlyLimit = monthlyLimit
    }
}

/// Quanto de um limite já foi usado no mês.
public struct CategoryLimitStatus: Sendable, Hashable, Identifiable {
    public enum Level: Sendable, Hashable, Comparable {
        case ok
        case near
        case over
    }

    public var category: String
    public var limit: Double
    /// Gasto líquido do mês na categoria (estornos descontam), nunca negativo.
    public var spent: Double

    public var id: String { category }
    public var remaining: Double { limit - spent }
    public var ratio: Double { limit > 0 ? spent / limit : 0 }

    public func level(warningRatio: Double = CategoryLimitStatus.defaultWarningRatio) -> Level {
        if spent > limit { return .over }
        if ratio >= warningRatio { return .near }
        return .ok
    }

    public static let defaultWarningRatio = 0.8

    public init(category: String, limit: Double, spent: Double) {
        self.category = category
        self.limit = limit
        self.spent = spent
    }

    /// Cruza os limites com os totais do mês (`MonthlySummary.byCategory`,
    /// saídas negativas). Os mais apertados vêm primeiro.
    public static func evaluate(
        limits: [CategoryLimit],
        totalsByCategory: [String: Double]
    ) -> [CategoryLimitStatus] {
        limits
            .filter { $0.monthlyLimit > 0 }
            .map { limit in
                CategoryLimitStatus(
                    category: limit.category,
                    limit: limit.monthlyLimit,
                    spent: max(0, -(totalsByCategory[limit.category] ?? 0))
                )
            }
            .sorted { lhs, rhs in
                lhs.ratio != rhs.ratio ? lhs.ratio > rhs.ratio : lhs.category < rhs.category
            }
    }
}
