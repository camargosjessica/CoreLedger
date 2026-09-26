import Fluent
import Vapor
import KausMedia

final class TransactionModel: Model, @unchecked Sendable {
    static let schema = "transactions"
    
    @ID(key: .id)
    var id: UUID?
    
    @Field(key: "description")
    var description: String
    
    @Field(key: "amount")
    var amount: Double
    
    @Field(key: "category")
    var category: String
    
    @Field(key: "date")
    var date: Date

    @OptionalParent(key: "account_id")
    var account: AccountModel?

    /// Índice único no banco: a garantia contra reimportação do mesmo extrato.
    @OptionalField(key: "dedup_key")
    var dedupKey: String?

    /// Parcela futura já contratada, ainda não confirmada pela fatura.
    @Field(key: "is_projected")
    var isProjected: Bool

    @OptionalField(key: "installment_number")
    var installmentNumber: Int?

    @OptionalField(key: "installment_total")
    var installmentTotal: Int?

    /// `FITID` do OFX, quando o extrato de origem o fornece.
    @OptionalField(key: "external_id")
    var externalID: String?

    init() { }
    
    init(
        id: UUID? = nil,
        description: String,
        amount: Double,
        category: String,
        date: Date,
        accountID: UUID? = nil,
        dedupKey: String? = nil,
        isProjected: Bool = false,
        installment: Installment? = nil,
        externalID: String? = nil
    ) {
        self.id = id
        self.description = description
        self.amount = amount
        self.category = category
        self.date = date
        self.$account.id = accountID
        self.dedupKey = dedupKey
        self.isProjected = isProjected
        self.installmentNumber = installment?.number
        self.installmentTotal = installment?.total
        self.externalID = externalID
    }
}

extension TransactionModel {
    var installment: Installment? {
        guard let installmentNumber, let installmentTotal else { return nil }
        return Installment(number: installmentNumber, total: installmentTotal)
    }
}
