import Fluent
import Vapor
import KausMedia

/// Teto mensal de gasto de uma categoria; no máximo um por categoria.
final class CategoryLimitModel: Model, @unchecked Sendable {
    static let schema = "category_limits"

    @ID(key: .id)
    var id: UUID?

    @Field(key: "category")
    var category: String

    @Field(key: "monthly_limit")
    var monthlyLimit: Double

    init() { }

    init(limit: CategoryLimit) {
        self.category = limit.category
        self.monthlyLimit = limit.monthlyLimit
    }

    func toDTO() -> CategoryLimit {
        CategoryLimit(category: category, monthlyLimit: monthlyLimit)
    }
}
