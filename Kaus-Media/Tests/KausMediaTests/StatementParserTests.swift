import XCTest
@testable import KausMedia

final class StatementParserTests: XCTestCase {

    private func day(_ text: String) -> Date {
        DateParser.parse(text)!
    }

    func testCSVWithHeaderAndBrazilianValues() {
        let csv = """
        Data;Histórico;Valor
        15/01/2025;SUPERMERCADO BOM PRECO;-1.234,56
        16/01/2025;SALARIO JANEIRO;4.200,00
        """

        let result = StatementParser.parse(content: csv, filename: "extrato.csv")

        XCTAssertTrue(result.failures.isEmpty)
        XCTAssertEqual(result.transactions.count, 2)
        XCTAssertEqual(result.transactions[0].date, day("15/01/2025"))
        XCTAssertEqual(result.transactions[0].description, "SUPERMERCADO BOM PRECO")
        XCTAssertEqual(result.transactions[0].amount, -1234.56, accuracy: 0.001)
        XCTAssertEqual(result.transactions[1].amount, 4200, accuracy: 0.001)
    }

    func testCSVQuotedFieldWithSeparatorAndEmbeddedNewline() {
        let csv = "Data;Descrição;Valor\n"
            + "15/01/2025;\"PADARIA; FILIAL\nCENTRO\";-18,90\n"

        let result = StatementParser.parse(content: csv)

        XCTAssertEqual(result.transactions.count, 1)
        XCTAssertEqual(result.transactions[0].description, "PADARIA; FILIAL\nCENTRO")
        XCTAssertEqual(result.transactions[0].amount, -18.90, accuracy: 0.001)
    }

    func testCSVEscapedQuotes() {
        let csv = "Data;Descrição;Valor\n15/01/2025;\"LOJA \"\"A\"\"\";-10,00\n"

        let result = StatementParser.parse(content: csv)

        XCTAssertEqual(result.transactions.first?.description, "LOJA \"A\"")
    }

    func testCSVSeparateDebitAndCreditColumns() {
        let csv = """
        Data,Descricao,Debito,Credito
        15/01/2025,COMPRA CARTAO,80.00,
        16/01/2025,DEPOSITO,,500.00
        """

        let result = StatementParser.parse(content: csv)

        XCTAssertEqual(result.transactions.count, 2)
        XCTAssertEqual(result.transactions[0].amount, -80, accuracy: 0.001)
        XCTAssertEqual(result.transactions[1].amount, 500, accuracy: 0.001)
    }

    func testCSVWithoutHeader_FallsBackToPositionalColumns() {
        let csv = "15/01/2025;PADARIA;-18,90\n16/01/2025;POSTO SHELL;-200,00"

        let result = StatementParser.parse(content: csv)

        XCTAssertEqual(result.transactions.count, 2)
        XCTAssertEqual(result.transactions[1].description, "POSTO SHELL")
    }

    func testInvalidLinesAreReportedInsteadOfSilentlyDropped() {
        let csv = """
        Data;Histórico;Valor
        15/01/2025;OK;-10,00
        data-invalida;RUIM;-10,00
        16/01/2025;SEM VALOR;
        """

        let result = StatementParser.parse(content: csv)

        XCTAssertEqual(result.transactions.count, 1)
        XCTAssertEqual(result.failures.count, 2)
        XCTAssertEqual(result.failures[0].line, 3)
        XCTAssertTrue(result.failures[0].reason.contains("Data"))
        XCTAssertTrue(result.failures[1].reason.contains("Valor"))
    }

    func testOFXParsingWithFITID() {
        let ofx = """
        OFXHEADER:100
        <OFX><BANKMSGSRSV1><STMTTRNRS><STMTRS><BANKTRANLIST>
        <STMTTRN>
        <TRNTYPE>DEBIT
        <DTPOSTED>20250115120000[-3:BRT]
        <TRNAMT>-1234.56
        <FITID>202501150001
        <MEMO>SUPERMERCADO BOM PRECO
        </STMTTRN>
        <STMTTRN>
        <TRNTYPE>CREDIT
        <DTPOSTED>20250116
        <TRNAMT>4200.00
        <FITID>202501160002
        <NAME>SALARIO
        </STMTTRN>
        </BANKTRANLIST></STMTRS></STMTTRNRS></BANKMSGSRSV1></OFX>
        """

        let result = StatementParser.parse(content: ofx, filename: "extrato.ofx")

        XCTAssertTrue(result.failures.isEmpty)
        XCTAssertEqual(result.transactions.count, 2)
        XCTAssertEqual(result.transactions[0].externalID, "202501150001")
        XCTAssertEqual(result.transactions[0].amount, -1234.56, accuracy: 0.001)
        XCTAssertEqual(result.transactions[0].date, day("15/01/2025"))
        XCTAssertEqual(result.transactions[1].description, "SALARIO")
    }

    func testFormatDetectionWithoutFilename() {
        XCTAssertEqual(StatementParser.detectFormat(filename: nil, content: "<OFX><STMTTRN>"), .ofx)
        XCTAssertEqual(StatementParser.detectFormat(filename: nil, content: "Data;Valor"), .csv)
    }

    func testDatesAreNormalizedToMidnightUTC() {
        let result = StatementParser.parse(content: "15/01/2025;PADARIA;-10,00")
        let date = try! XCTUnwrap(result.transactions.first).date

        XCTAssertEqual(date, LedgerCalendar.startOfDay(date))
        XCTAssertEqual(LedgerCalendar.isoDay(date), "2025-01-15")
    }
}

final class ValueParserTests: XCTestCase {
    func testBrazilianAndEnglishFormats() {
        XCTAssertEqual(ValueParser.parse("1.234,56")!, 1234.56, accuracy: 0.001)
        XCTAssertEqual(ValueParser.parse("1,234.56")!, 1234.56, accuracy: 0.001)
        XCTAssertEqual(ValueParser.parse("R$ -80,00")!, -80, accuracy: 0.001)
        XCTAssertEqual(ValueParser.parse("(80,00)")!, -80, accuracy: 0.001)
        XCTAssertEqual(ValueParser.parse("80,00 D")!, -80, accuracy: 0.001)
        XCTAssertEqual(ValueParser.parse("80,00 C")!, 80, accuracy: 0.001)
        XCTAssertEqual(ValueParser.parse("-0.5")!, -0.5, accuracy: 0.001)
    }

    func testRejectsNonNumericText() {
        XCTAssertNil(ValueParser.parse(""))
        XCTAssertNil(ValueParser.parse("saldo"))
        XCTAssertNil(ValueParser.parse("R$"))
    }
}
