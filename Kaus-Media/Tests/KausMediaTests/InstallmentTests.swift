import XCTest
@testable import KausMedia

final class InstallmentParserTests: XCTestCase {

    func testDetectsExplicitInstallment() {
        let detection = InstallmentParser.detect(in: "NETSHOES PARC 03/10")

        XCTAssertEqual(detection?.installment, Installment(number: 3, total: 10))
        XCTAssertEqual(detection?.baseDescription, "netshoes")
    }

    func testDetectsWrittenForm() {
        let detection = InstallmentParser.detect(in: "MAGAZINE LUIZA PARCELA 2 DE 6")

        XCTAssertEqual(detection?.installment, Installment(number: 2, total: 6))
    }

    func testDetectsBareForm() {
        let detection = InstallmentParser.detect(in: "AMAZON BR 1/12")

        XCTAssertEqual(detection?.installment, Installment(number: 1, total: 12))
        XCTAssertEqual(detection?.baseDescription, "amazon br")
    }

    func testIgnoresDatesInDescription() {
        XCTAssertNil(InstallmentParser.detect(in: "PAGAMENTO REF 03/10/2024"))
    }

    func testIgnoresImpossibleInstallments() {
        XCTAssertNil(InstallmentParser.detect(in: "COMPRA 11/10"))
        XCTAssertNil(InstallmentParser.detect(in: "COMPRA 0/10"))
        XCTAssertNil(InstallmentParser.detect(in: "COMPRA 1/1"))
    }
}

final class InstallmentExpanderTests: XCTestCase {

    private let purchase = ImportedTransaction(
        date: DateParser.parse("15/01/2025")!,
        description: "NETSHOES PARC 03/10",
        amount: -199.90
    )

    func testExpandsRemainingInstallmentsAsProjected() {
        let result = InstallmentExpander.expand(purchase)

        XCTAssertEqual(result.count, 8, "parcela atual + 7 futuras")
        XCTAssertFalse(result[0].isProjected)
        XCTAssertEqual(result[0].installment, Installment(number: 3, total: 10))
        XCTAssertTrue(result.dropFirst().allSatisfy(\.isProjected))
        XCTAssertEqual(result.last?.installment, Installment(number: 10, total: 10))
        XCTAssertEqual(result.last?.date, DateParser.parse("15/08/2025"))
        XCTAssertTrue(result.allSatisfy { $0.amount == -199.90 })
    }

    func testFutureInstallmentsShareTheBaseDescription() {
        let result = InstallmentExpander.expand(purchase)

        XCTAssertEqual(Set(result.map(\.description)), ["netshoes"])
    }

    func testLastInstallmentGeneratesNoFutureRows() {
        let last = ImportedTransaction(
            date: DateParser.parse("15/01/2025")!,
            description: "NETSHOES PARC 10/10",
            amount: -199.90
        )

        XCTAssertEqual(InstallmentExpander.expand(last).count, 1)
    }

    func testTransactionWithoutInstallmentIsUntouched() {
        let simple = ImportedTransaction(
            date: DateParser.parse("15/01/2025")!,
            description: "PADARIA CENTRAL",
            amount: -18.90
        )

        XCTAssertEqual(InstallmentExpander.expand(simple), [simple])
    }

    func testNextInvoiceConfirmsTheProjectionInsteadOfDuplicatingIt() {
        let account = UUID()
        let projected = InstallmentExpander.expand(purchase)[1]

        // Fatura do mês seguinte: mesma compra, parcela 4/10, com data e FITID próprios.
        let realNextMonth = InstallmentExpander.expand(
            ImportedTransaction(
                date: DateParser.parse("17/02/2025")!,
                description: "NETSHOES PARC 04/10",
                amount: -199.90,
                externalID: "FITID-XYZ"
            )
        )[0]

        XCTAssertEqual(
            DedupKey.make(accountID: account, transaction: projected),
            DedupKey.make(accountID: account, transaction: realNextMonth)
        )
    }
}

final class DedupKeyTests: XCTestCase {

    func testSameTransactionProducesSameKeyRegardlessOfFormatting() {
        let account = UUID()
        let a = DedupKey.make(
            accountID: account,
            date: DateParser.parse("15/01/2025")!,
            description: "  Supermercado   Bom  Preço ",
            amount: -1234.56
        )
        let b = DedupKey.make(
            accountID: account,
            date: DateParser.parse("2025-01-15")!,
            description: "SUPERMERCADO BOM PRECO",
            amount: -1234.56
        )

        XCTAssertEqual(a, b)
    }

    func testDifferentAmountProducesDifferentKey() {
        let account = UUID()
        let date = DateParser.parse("15/01/2025")!

        XCTAssertNotEqual(
            DedupKey.make(accountID: account, date: date, description: "PADARIA", amount: -10),
            DedupKey.make(accountID: account, date: date, description: "PADARIA", amount: -10.01)
        )
    }

    func testDifferentAccountsDoNotCollide() {
        let date = DateParser.parse("15/01/2025")!

        XCTAssertNotEqual(
            DedupKey.make(accountID: UUID(), date: date, description: "PADARIA", amount: -10),
            DedupKey.make(accountID: UUID(), date: date, description: "PADARIA", amount: -10)
        )
    }

    func testExternalIDWins_WhenAvailable() {
        let account = UUID()
        let key = DedupKey.make(
            accountID: account,
            date: DateParser.parse("15/01/2025")!,
            description: "PADARIA",
            amount: -10,
            externalID: "FITID-1"
        )

        // O banco reemitiu o extrato com a descrição ajustada: mesmo FITID, mesma chave.
        let reissued = DedupKey.make(
            accountID: account,
            date: DateParser.parse("16/01/2025")!,
            description: "PADARIA CENTRAL LTDA",
            amount: -10,
            externalID: "FITID-1"
        )

        XCTAssertEqual(key, reissued)
    }
}
