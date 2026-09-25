import Foundation

public struct TransactionDTO: Codable, Sendable {
    public var id: UUID?
    public var description: String
    public var amount: Double
    public var date: Date
    public var category: String?
    
    public init(id: UUID? = nil, description: String, amount: Double, date: Date, category: String? = nil) {
        self.id = id
        self.description = description
        self.amount = amount
        self.date = date
        self.category = category
    }
}
