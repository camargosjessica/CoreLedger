import Fluent
import Vapor

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
    
    init() { }
    
    init(id: UUID? = nil, description: String, amount: Double, category: String, date: Date) {
        self.id = id
        self.description = description
        self.amount = amount
        self.category = category
        self.date = date
    }
}
