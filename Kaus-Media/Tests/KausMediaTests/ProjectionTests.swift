import XCTest
@testable import KausMedia

final class ProjectionTests: XCTestCase {

    private func input(_ date: String, _ amount: Double, _ category: String, projected: Bool = false) -> Projection.Input {
        Projection.Input(
            date: DateParser.parse(date)!,
            amount: amount,
            category: category,
            isProjected: projected
        )
    }

    private let reference = DateParser.parse("10/04/2025")!

    func testGroupsByMonthInUTC() {
        let result = Projection.project(
            [
                input("01/01/2025", -100, "Mercado"),
                input("31/01/2025", -50, "Mercado"),
                input("01/02/2025", 4000, "Salário")
            ],
            forecastMonths: 0,
            reference: reference
        )

        XCTAssertEqual(result.history.count, 2)
        XCTAssertEqual(result.history[0].expenses, -150, accuracy: 0.001)
        XCTAssertEqual(result.history[0].byCategory["Mercado"], -150)
        XCTAssertEqual(result.history[1].income, 4000, accuracy: 0.001)
        XCTAssertEqual(result.history[1].balance, 4000, accuracy: 0.001)
    }

    func testTransferCategoriesAreExcluded() {
        let result = Projection.project(
            [
                input("05/01/2025", -1000, "Transferências"),
                input("05/01/2025", 1000, "Transferências"),
                input("05/01/2025", -200, "Mercado")
            ],
            transferCategories: ["Transferências"],
            forecastMonths: 0,
            reference: reference
        )

        XCTAssertEqual(result.history.count, 1)
        XCTAssertEqual(result.history[0].expenses, -200, accuracy: 0.001)
        XCTAssertEqual(result.history[0].income, 0, accuracy: 0.001)
    }

    func testForecastUsesAverageOfClosedMonths() {
        let result = Projection.project(
            [
                input("05/01/2025", -300, "Mercado"),
                input("05/02/2025", -100, "Mercado"),
                input("05/03/2025", -200, "Mercado"),
                input("05/01/2025", 3000, "Salário"),
                input("05/02/2025", 3000, "Salário"),
                input("05/03/2025", 3000, "Salário")
            ],
            forecastMonths: 2,
            reference: reference
        )

        XCTAssertEqual(result.forecast.count, 2)
        XCTAssertTrue(result.forecast.allSatisfy(\.isForecast))
        XCTAssertEqual(result.forecast[0].byCategory["Mercado"]!, -200, accuracy: 0.001)
        XCTAssertEqual(result.forecast[0].income, 3000, accuracy: 0.001)
        XCTAssertEqual(result.forecast[0].month, LedgerCalendar.startOfMonth(DateParser.parse("01/05/2025")!))
    }

    func testCommittedInstallmentsAreAddedToTheForecast() {
        let result = Projection.project(
            [
                input("05/03/2025", -200, "Mercado"),
                input("10/05/2025", -199.90, "Compras", projected: true),
                input("10/06/2025", -199.90, "Compras", projected: true)
            ],
            forecastMonths: 2,
            reference: reference
        )

        XCTAssertEqual(result.forecast[0].committedExpenses, -199.90, accuracy: 0.001)
        XCTAssertEqual(result.forecast[0].byCategory["Compras"]!, -199.90, accuracy: 0.001)
        XCTAssertEqual(result.forecast[0].byCategory["Mercado"]!, -200, accuracy: 0.001)
        XCTAssertEqual(result.forecast[1].committedExpenses, -199.90, accuracy: 0.001)
    }

    func testProjectedTransactionsDoNotPolluteHistory() {
        let result = Projection.project(
            [
                input("05/03/2025", -200, "Mercado"),
                input("10/05/2025", -199.90, "Compras", projected: true)
            ],
            forecastMonths: 1,
            reference: reference
        )

        XCTAssertEqual(result.history.count, 1)
        XCTAssertFalse(result.history.contains { $0.isForecast })
    }

    func testEmptyHistoryStillForecastsCommittedInstallments() {
        let result = Projection.project(
            [input("10/05/2025", -199.90, "Compras", projected: true)],
            forecastMonths: 1,
            reference: reference
        )

        XCTAssertTrue(result.history.isEmpty)
        XCTAssertEqual(result.forecast[0].expenses, -199.90, accuracy: 0.001)
    }
    func testForecastKeepsIncomeAndExpensesSeparateWithinACategory() {
        let result = Projection.project(
            [
                input("05/01/2025", -500, "Compras"),
                input("20/01/2025", 500, "Compras"),
                input("05/02/2025", -500, "Compras"),
                input("20/02/2025", 500, "Compras")
            ],
            forecastMonths: 1,
            reference: reference
        )

        XCTAssertEqual(result.forecast[0].expenses, -500, accuracy: 0.001)
        XCTAssertEqual(result.forecast[0].income, 500, accuracy: 0.001)
        XCTAssertEqual(result.forecast[0].byCategory["Compras"], 0)
    }
}

final class FormattingTests: XCTestCase {
    func testCurrencyIsAlwaysBrazilian() {
        XCTAssertEqual((-1234.56).brl.replacingOccurrences(of: "\u{00A0}", with: " "), "-R$ 1.234,56")
    }

    func testMonthYearUsesUTC() {
        let date = DateParser.parse("01/01/2025")!
        XCTAssertTrue(date.monthYear.contains("2025"))
        XCTAssertEqual(date.shortDay, "01/01/2025")
    }
}
