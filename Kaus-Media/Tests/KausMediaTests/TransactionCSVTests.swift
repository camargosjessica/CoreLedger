import XCTest
@testable import KausMedia

final class TransactionCSVTests: XCTestCase {
    func testExportIsSortedAndReimportable() throws {
        let december = try XCTUnwrap(DateParser.parse("10/12/2026"))
        let november = try XCTUnwrap(DateParser.parse("05/11/2026"))
        let transactions = [
            TransactionDTO(description: "Shopee; colchões", amount: -115.14, date: december,
                           category: "Casa", isProjected: true, tags: ["moveis", "essencial"]),
            TransactionDTO(description: "Mercado", amount: -1234.5, date: november),
        ]

        let csv = TransactionCSV.export(transactions)

        XCTAssertEqual(csv, """
        Data;Descrição;Categoria;Tags;Valor;Situação
        05/11/2026;Mercado;;;-1234,50;Realizado
        10/12/2026;"Shopee; colchões";Casa;moveis, essencial;-115,14;Previsto

        """)
        let parsed = StatementParser.parse(content: csv, format: .csv)
        XCTAssertTrue(parsed.failures.isEmpty)
        XCTAssertEqual(parsed.transactions.map(\.amount), [-1234.5, -115.14])
        XCTAssertEqual(parsed.transactions.map(\.description), ["Mercado", "Shopee; colchões"])
    }
}
