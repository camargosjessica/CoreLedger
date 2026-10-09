import XCTest
@testable import KausMedia

final class StatementMonthTests: XCTestCase {
    func testMonthComesFromFilename() {
        XCTAssertEqual(StatementMonth.guess(filename: "fatura-paga-final 3665-agosto2026.xlsx", latestDate: nil), YearMonth(year: 2026, month: 8))
        XCTAssertEqual(StatementMonth.guess(filename: "Fatura Março de 2027.csv", latestDate: nil), YearMonth(year: 2027, month: 3))
        XCTAssertEqual(StatementMonth.guess(filename: "fatura_2026-12.csv", latestDate: nil), YearMonth(year: 2026, month: 12))
    }

    func testWithoutMonthInNameTheStatementIsDueAfterTheLatestPurchase() throws {
        let latest = try XCTUnwrap(DateParser.parse("20/11/2026"))
        XCTAssertEqual(StatementMonth.guess(filename: "extrato.csv", latestDate: latest), YearMonth(year: 2026, month: 12))
        XCTAssertNil(StatementMonth.guess(filename: "extrato.csv", latestDate: nil))
    }
}

final class LabelSuggesterTests: XCTestCase {
    private let date = Date(timeIntervalSince1970: 1_790_000_000)

    func testSamePurchaseCarriesCategoryTagsAndNote() {
        let history = [
            LabeledTransaction(description: "shopee*shps tecnol", installment: Installment(number: 2, total: 10),
                               category: "Casa", tags: ["obra"], note: "piso do banheiro"),
        ]
        let row = ImportedTransaction(date: date, description: "shopee*shps tecnologia sao paulo bra", amount: -50,
                                      installment: Installment(number: 3, total: 10))

        let suggestion = LabelSuggester.suggestion(for: row, in: history)

        XCTAssertEqual(suggestion, .init(category: "Casa", tags: ["obra"], note: "piso do banheiro"))
    }

    func testDifferentInstallmentTotalIsAnotherPurchase() {
        let history = [
            LabeledTransaction(description: "shopee*shps tecnol", installment: Installment(number: 2, total: 10),
                               category: "Casa", tags: ["obra"], note: nil),
        ]
        let row = ImportedTransaction(date: date, description: "shopee*shps tecnol", amount: -50,
                                      installment: Installment(number: 1, total: 3))

        XCTAssertNil(LabelSuggester.suggestion(for: row, in: history))
    }

    func testSameDescriptionCarriesOnlyTags() {
        let history = [
            LabeledTransaction(description: "NETFLIX.COM", installment: nil, category: "Lazer", tags: ["assinatura"], note: "plano família"),
        ]
        let row = ImportedTransaction(date: date, description: "netflix.com", amount: -55.9)

        XCTAssertEqual(LabelSuggester.suggestion(for: row, in: history), .init(category: nil, tags: ["assinatura"], note: nil))
    }
}

final class InstallmentLabelTests: XCTestCase {
    func testLabelDoesNotCreateFutureInstallments() throws {
        let date = try XCTUnwrap(DateParser.parse("10/08/2026"))
        let row = ImportedTransaction(date: date, description: "IPTU 2/10", amount: -100)

        let labeled = InstallmentExpander.label([row])

        XCTAssertEqual(labeled.count, 1)
        XCTAssertEqual(labeled[0].installment, Installment(number: 2, total: 10))
        XCTAssertFalse(labeled[0].isProjected)
    }
}
