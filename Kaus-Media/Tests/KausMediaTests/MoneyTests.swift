import XCTest
@testable import KausMedia

final class MoneyTests: XCTestCase {
    func testSumIsExactWhereDoubleDrifts() {
        let tenCents: [Money] = Array(repeating: 0.1, count: 10)
        XCTAssertEqual(tenCents.sum(), 1)
        XCTAssertEqual(Money(0.1) + Money(0.2), Money(0.3))
    }

    func testRoundsHalfAwayFromZero() {
        XCTAssertEqual(Money(1.005).cents, 101)
        XCTAssertEqual(Money(-1.005).cents, -101)
        XCTAssertEqual(Money(Decimal(string: "2.345")!).cents, 235)
    }

    func testDecodesDecimalNumberFromJSON() throws {
        let data = Data(#"[-150.5, 0.1, 1234.56, 7]"#.utf8)
        let values = try JSONDecoder().decode([Money].self, from: data)
        XCTAssertEqual(values.map(\.cents), [-15050, 10, 123456, 700])
    }

    func testEncodesDecimalNumberWithoutFloatNoise() throws {
        let data = try JSONEncoder().encode([Money(cents: 10), Money(cents: -15050)])
        XCTAssertEqual(String(decoding: data, as: UTF8.self), "[0.1,-150.5]")
    }

    func testDescriptionIsLocaleIndependent() {
        XCTAssertEqual(Money(cents: -15050).description, "-150.50")
        XCTAssertEqual(Money(cents: 5).description, "0.05")
    }

    func testRatioAndMagnitude() {
        XCTAssertEqual(Money(80) / Money(100), 0.8)
        XCTAssertEqual(Money(80) / Money.zero, 0)
        XCTAssertEqual(abs(Money(-3.5)), Money(3.5))
    }

    func testValueParserReadsExactCents() {
        XCTAssertEqual(ValueParser.parse("1.234,56")?.cents, 123456)
        XCTAssertEqual(ValueParser.parse("(0,10)")?.cents, -10)
    }
}
