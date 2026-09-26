import Fluent
import Vapor
import KausMedia

final class AccountModel: Model, @unchecked Sendable {
    static let schema = "accounts"

    @ID(key: .id)
    var id: UUID?

    @Field(key: "name")
    var name: String

    @Field(key: "kind")
    var kind: String

    @Timestamp(key: "created_at", on: .create)
    var createdAt: Date?

    @Children(for: \.$account)
    var transactions: [TransactionModel]

    init() { }

    init(id: UUID? = nil, name: String, kind: AccountKind) {
        self.id = id
        self.name = name
        self.kind = kind.rawValue
    }
}

extension AccountModel {
    var accountKind: AccountKind {
        AccountKind(rawValue: kind) ?? .checking
    }

    func toDTO(transactionCount: Int? = nil, balance: Double? = nil) -> AccountDTO {
        AccountDTO(
            id: id,
            name: name,
            kind: accountKind,
            createdAt: createdAt,
            transactionCount: transactionCount,
            balance: balance
        )
    }
}
