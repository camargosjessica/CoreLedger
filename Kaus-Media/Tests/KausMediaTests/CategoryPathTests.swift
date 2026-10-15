import XCTest
@testable import KausMedia

final class CategoryPathTests: XCTestCase {
    func testParentChildAndJoin() {
        XCTAssertEqual(CategoryPath.join("Moradia", "Energia"), "Moradia › Energia")
        XCTAssertEqual(CategoryPath.join("Moradia", " "), "Moradia")
        XCTAssertEqual(CategoryPath.parent(of: "Moradia › Energia"), "Moradia")
        XCTAssertEqual(CategoryPath.child(of: "Moradia › Energia"), "Energia")
        XCTAssertEqual(CategoryPath.parent(of: "Telefone/Internet"), "Telefone/Internet")
        XCTAssertNil(CategoryPath.child(of: "Telefone/Internet"))
    }

    func testWithinAndEssential() {
        XCTAssertTrue(CategoryPath.isWithin("Moradia › IPTU", "Moradia"))
        XCTAssertTrue(CategoryPath.isWithin("Moradia", "Moradia"))
        XCTAssertFalse(CategoryPath.isWithin("Moradias", "Moradia"))
        XCTAssertTrue(CategoryPath.isEssential("Moradia › IPTU", in: ["Moradia"]))
        XCTAssertFalse(CategoryPath.isEssential("Lazer", in: ["Moradia"]))
    }

    func testLimitOnParentCountsSubcategories() {
        let statuses = CategoryLimitStatus.evaluate(
            limits: [CategoryLimit(category: "Moradia", monthlyLimit: 1000)],
            totalsByCategory: ["Moradia › Energia": -300, "Moradia › Condomínio": -600, "Lazer": -50]
        )
        XCTAssertEqual(statuses[0].spent, 900, accuracy: 0.001)
    }

    func testSpendingGroupsByParentOrSubcategory() {
        let date = YearMonth(year: 2026, month: 3).date(day: 5)
        let inputs = [
            SpendingAnalysis.Input(date: date, amount: -100, category: "Moradia › Energia"),
            SpendingAnalysis.Input(date: date, amount: -200, category: "Moradia › IPTU")
        ]
        let byParent = SpendingAnalysis.make(inputs, year: 2026, grouping: .category)
        XCTAssertEqual(byParent.totals.map(\.group), ["Moradia"])
        let bySub = SpendingAnalysis.make(inputs, year: 2026, grouping: .subcategory)
        XCTAssertEqual(bySub.totals.count, 2)
    }

    func testPlanUsesCategorySwitchForEssentials() {
        let reference = YearMonth(year: 2026, month: 6).date(day: 15)
        let transactions = [
            TransactionDTO(description: "Luz", amount: -150, date: YearMonth(year: 2026, month: 3).date(day: 5), category: "Moradia › Energia"),
            TransactionDTO(description: "Cinema", amount: -40, date: YearMonth(year: 2026, month: 3).date(day: 6), category: "Lazer")
        ]
        let plan = AnnualPlan.build(
            from: YearMonth(year: 2026, month: 1),
            to: YearMonth(year: 2026, month: 12),
            transactions: transactions,
            commitments: [],
            essentialCategories: ["Moradia"],
            reference: reference
        )
        XCTAssertEqual(plan.totals[2].essentialExpenses, -150, accuracy: 0.001)
        XCTAssertTrue(plan.expenseRows.first { $0.category == "Moradia › Energia" }?.isEssential ?? false)
        XCTAssertFalse(plan.expenseRows.first { $0.category == "Lazer" }?.isEssential ?? true)
    }
}
