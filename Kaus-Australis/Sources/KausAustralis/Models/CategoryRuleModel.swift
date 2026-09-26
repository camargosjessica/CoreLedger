import Fluent
import Vapor
import KausMedia

/// As regras de categorização vivem no banco: o usuário adiciona, edita e
/// desativa regras em tempo de execução, sem release.
final class CategoryRuleModel: Model, @unchecked Sendable {
    static let schema = "category_rules"

    @ID(key: .id)
    var id: UUID?

    @Field(key: "term")
    var term: String

    @Field(key: "category")
    var category: String

    @Field(key: "match_kind")
    var matchKind: String

    @Field(key: "amount_scope")
    var amountScope: String

    @Field(key: "priority")
    var priority: Int

    @Field(key: "is_enabled")
    var isEnabled: Bool

    @Field(key: "is_transfer")
    var isTransfer: Bool

    @Timestamp(key: "created_at", on: .create)
    var createdAt: Date?

    init() { }

    init(id: UUID? = nil, rule: CategoryRule) {
        self.id = id
        apply(rule)
    }

    func apply(_ rule: CategoryRule) {
        self.term = rule.term
        self.category = rule.category
        self.matchKind = rule.matchKind.rawValue
        self.amountScope = rule.amountScope.rawValue
        self.priority = rule.priority
        self.isEnabled = rule.isEnabled
        self.isTransfer = rule.isTransfer
    }

    func toDTO() -> CategoryRule {
        CategoryRule(
            id: id,
            term: term,
            category: category,
            matchKind: CategoryRule.MatchKind(rawValue: matchKind) ?? .word,
            amountScope: CategoryRule.AmountScope(rawValue: amountScope) ?? .any,
            priority: priority,
            isEnabled: isEnabled,
            isTransfer: isTransfer
        )
    }
}
