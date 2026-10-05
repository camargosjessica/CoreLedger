import XCTest
@testable import KausMedia

final class SpendingReportTests: XCTestCase {
    private func input(_ day: String, _ amount: Double, _ category: String, tags: [String] = [], projected: Bool = false) -> SpendingAnalysis.Input {
        SpendingAnalysis.Input(
            date: DateParser.parse(day)!,
            amount: amount,
            category: category,
            tags: tags,
            isProjected: projected
        )
    }

    func testGroupsExpensesByCategoryPerMonthAndYear() {
        let report = SpendingAnalysis.make([
            input("05/01/2026", -100, "Alimentação"),
            input("20/01/2026", -50, "Alimentação"),
            input("10/01/2026", -300, "Obra"),
            input("10/02/2026", -80, "Beleza", projected: true),
            input("10/02/2026", 5000, "Salário"),
            input("11/02/2026", -1000, "Guardado"),
            input("10/03/2025", -999, "Obra"),
        ], year: 2026, grouping: .category, excludedCategories: ["Guardado"])

        XCTAssertEqual(report.months.count, 12)
        XCTAssertEqual(report.months[0].slices, [
            SpendingSlice(group: "Obra", realized: 300),
            SpendingSlice(group: "Alimentação", realized: 150),
        ])
        XCTAssertEqual(report.months[1].total, 80)
        XCTAssertEqual(report.months[1].projected, 80)
        XCTAssertEqual(report.totals.map(\.group), ["Obra", "Alimentação", "Beleza"])
        XCTAssertEqual(report.total, 530)
    }

    func testTagGroupingCountsEveryTagButTotalOnce() {
        let report = SpendingAnalysis.make([
            input("05/04/2026", -200, "Cartão", tags: ["Casa", "essencial"]),
            input("06/04/2026", -40, "Cartão"),
        ], year: 2026, grouping: .tag)

        XCTAssertEqual(report.months[3].slices.map(\.group), ["casa", "essencial", SpendingReport.untagged])
        XCTAssertEqual(report.months[3].total, 240)
        XCTAssertEqual(report.total, 240)
    }

    func testReplacingTag() {
        XCTAssertEqual(TagSet.replacing("Casa", with: "obra", in: ["casa", "essencial"]), ["obra", "essencial"])
        XCTAssertEqual(TagSet.replacing("casa", with: "essencial", in: ["casa", "essencial"]), ["essencial"])
        XCTAssertEqual(TagSet.replacing("casa", with: nil, in: ["casa", "beleza"]), ["beleza"])
        XCTAssertNil(TagSet.replacing("casa", with: "obra", in: ["beleza"]))
    }
}
