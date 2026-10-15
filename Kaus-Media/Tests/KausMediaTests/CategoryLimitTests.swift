import XCTest
@testable import KausMedia

final class CategoryLimitTests: XCTestCase {
    func testStatusLevels() {
        let statuses = CategoryLimitStatus.evaluate(
            limits: [
                CategoryLimit(category: "Mercado", monthlyLimit: 1000),
                CategoryLimit(category: "Lazer", monthlyLimit: 200),
                CategoryLimit(category: "Saúde", monthlyLimit: 500)
            ],
            totalsByCategory: ["Mercado": -850, "Lazer": -250, "Saúde": -100]
        )

        XCTAssertEqual(statuses.map(\.category), ["Lazer", "Mercado", "Saúde"])
        XCTAssertEqual(statuses[0].level(), .over)
        XCTAssertEqual(statuses[0].remaining, -50, accuracy: 0.001)
        XCTAssertEqual(statuses[1].level(), .near)
        XCTAssertEqual(statuses[2].level(), .ok)
    }

    func testRefundsReduceSpendingButNeverBelowZero() {
        let statuses = CategoryLimitStatus.evaluate(
            limits: [
                CategoryLimit(category: "Compras", monthlyLimit: 300),
                CategoryLimit(category: "Viagem", monthlyLimit: 300)
            ],
            totalsByCategory: ["Compras": -120, "Viagem": 80]
        )

        XCTAssertEqual(statuses.first { $0.category == "Compras" }?.spent ?? -1, 120, accuracy: 0.001)
        XCTAssertEqual(statuses.first { $0.category == "Viagem" }?.spent, 0)
    }

    func testCategoryWithoutSpendingOrZeroLimit() {
        let statuses = CategoryLimitStatus.evaluate(
            limits: [
                CategoryLimit(category: "Pets", monthlyLimit: 150),
                CategoryLimit(category: "Nada", monthlyLimit: 0)
            ],
            totalsByCategory: [:]
        )

        XCTAssertEqual(statuses.map(\.category), ["Pets"])
        XCTAssertEqual(statuses[0].spent, 0)
        XCTAssertEqual(statuses[0].level(), .ok)
    }
}
