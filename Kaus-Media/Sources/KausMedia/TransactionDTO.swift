import Foundation

public struct TransactionDTO: Codable, Equatable, Identifiable {
    public let id: UUID
    public let description: String
    public let amount: Double
    public let date: Date
    public let category: String?
    
    public init(id: UUID = UUID(), description: String, amount: Double, date: Date, category: String? = nil) {
        self.id = id
        self.description = description
        self.amount = amount
        self.date = date
        self.category = category
    }
}
