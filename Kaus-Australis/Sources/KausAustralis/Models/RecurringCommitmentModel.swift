import Fluent
import Vapor
import KausMedia

/// Uma linha da grade anual: a conta fixa, a receita recorrente ou o aporte
/// planejado. O valor mensal pode ser sobrescrito mês a mês, como na planilha.
final class RecurringCommitmentModel: Model, @unchecked Sendable {
    static let schema = "recurring_commitments"

    @ID(key: .id)
    var id: UUID?

    @Field(key: "name")
    var name: String

    @Field(key: "category")
    var category: String

    @Field(key: "kind")
    var kind: String

    @Field(key: "amount")
    var amount: Double

    @Field(key: "day_of_month")
    var dayOfMonth: Int

    /// Guardados como `YYYY-MM`: o mês é um período, não um instante, e
    /// gravá-lo como data reintroduziria fuso horário na comparação.
    @Field(key: "start_month")
    var startMonth: String

    @OptionalField(key: "end_month")
    var endMonth: String?

    @Field(key: "tags")
    var tags: [String]

    @Field(key: "is_enabled")
    var isEnabled: Bool

    /// Valores que divergem do padrão, por mês (`YYYY-MM` -> valor).
    @Field(key: "overrides")
    var overrides: [String: Double]

    @OptionalParent(key: "account_id")
    var account: AccountModel?

    @OptionalField(key: "notes")
    var notes: String?

    @Timestamp(key: "created_at", on: .create)
    var createdAt: Date?

    init() { }

    init(id: UUID? = nil, commitment: RecurringCommitment) {
        self.id = id
        apply(commitment)
    }

    func apply(_ commitment: RecurringCommitment) {
        self.name = commitment.name
        self.category = commitment.category
        self.kind = commitment.kind.rawValue
        self.amount = abs(commitment.amount)
        self.dayOfMonth = min(max(commitment.dayOfMonth, 1), 31)
        self.startMonth = commitment.start.description
        self.endMonth = commitment.end?.description
        self.tags = TagSet.normalize(commitment.tags)
        self.isEnabled = commitment.isEnabled
        self.overrides = commitment.overrides.filter { YearMonth($0.key) != nil }
        self.$account.id = commitment.accountID
        self.notes = commitment.notes
    }

    func toDTO() -> RecurringCommitment {
        RecurringCommitment(
            id: id,
            name: name,
            category: category,
            kind: RecurringCommitment.Kind(rawValue: kind) ?? .expense,
            amount: amount,
            dayOfMonth: dayOfMonth,
            start: YearMonth(startMonth) ?? YearMonth(date: createdAt ?? Date()),
            end: endMonth.flatMap(YearMonth.init),
            tags: tags,
            isEnabled: isEnabled,
            overrides: overrides,
            accountID: $account.id,
            notes: notes
        )
    }
}
