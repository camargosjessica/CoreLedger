import XCTest
import ZIPFoundation
@testable import KausMedia

final class SpreadsheetReaderTests: XCTestCase {

    /// Monta um `.xlsx` mínimo em memória no formato exportado pelos bancos:
    /// cabeçalho do banco antes da tabela, data com formato personalizado e
    /// parcela numa coluna própria.
    private func makeXLSX(sheetRows: String, sharedStrings: [String], sheetPath: String = "worksheets/sheet1.xml") throws -> Data {
        let strings = sharedStrings.map { "<si><t>\($0)</t></si>" }.joined()
        let files: [String: String] = [
            "[Content_Types].xml": "<?xml version=\"1.0\"?><Types xmlns=\"http://schemas.openxmlformats.org/package/2006/content-types\"/>",
            "xl/workbook.xml": """
            <?xml version="1.0"?><workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" \
            xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">\
            <sheets><sheet name="Fatura" sheetId="1" r:id="rId1"/></sheets></workbook>
            """,
            "xl/_rels/workbook.xml.rels": """
            <?xml version="1.0"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">\
            <Relationship Id="rId1" Type="worksheet" Target="\(sheetPath)"/></Relationships>
            """,
            "xl/styles.xml": """
            <?xml version="1.0"?><styleSheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">\
            <numFmts count="2"><numFmt numFmtId="100" formatCode="[$R$-416] * #,##0.00"/>\
            <numFmt numFmtId="101" formatCode="dd/mm/yyyy"/></numFmts>\
            <cellXfs count="4"><xf numFmtId="0"/><xf numFmtId="101"/><xf numFmtId="100"/><xf numFmtId="14"/></cellXfs></styleSheet>
            """,
            "xl/sharedStrings.xml": "<?xml version=\"1.0\"?><sst xmlns=\"http://schemas.openxmlformats.org/spreadsheetml/2006/main\">\(strings)</sst>",
            "xl/\(sheetPath)": """
            <?xml version="1.0"?><worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">\
            <sheetData>\(sheetRows)</sheetData></worksheet>
            """,
        ]

        let archive = try Archive(data: Data(), accessMode: .create)
        for (path, content) in files.sorted(by: { $0.key < $1.key }) {
            let data = Data(content.utf8)
            try archive.addEntry(with: path, type: .file, uncompressedSize: Int64(data.count), compressionMethod: .deflate) { position, size in
                data.subdata(in: Int(position)..<Int(position) + size)
            }
        }
        return try XCTUnwrap(archive.data)
    }

    private func s(_ ref: String, _ index: Int) -> String { "<c r=\"\(ref)\" t=\"s\"><v>\(index)</v></c>" }
    private func n(_ ref: String, _ value: String, style: Int = 0) -> String { "<c r=\"\(ref)\" s=\"\(style)\"><v>\(value)</v></c>" }

    private func invoiceXLSX() throws -> Data {
        let strings = ["Nome", "Fulana", "Data", "Lançamento", "Parcelamento", "Valor",
                       "Pagamento Efetuado", "IFD*RESTAURANTE", "Shopee*loja", "Parcela 2 de 12",
                       "Subtotal", "Importante saber", "Aviso; com \"aspas\""]
        let rows = """
        <row r="1">\(s("B1", 0))\(s("C1", 1))</row>
        <row r="4">\(s("B4", 2))\(s("C4", 3))\(s("D4", 4))\(s("E4", 5))</row>
        <row r="5">\(n("B5", "46204", style: 1))\(s("C5", 6))\(n("E5", "-6873.37", style: 2))</row>
        <row r="6">\(n("B6", "46226", style: 1))\(s("C6", 7))\(n("E6", "44.32", style: 2))</row>
        <row r="7">\(n("B7", "46192", style: 3))\(s("C7", 8))\(s("D7", 9))\(n("E7", "115.14", style: 2))</row>
        <row r="9">\(s("D9", 10))<c r="E9" s="2"><f>SUBTOTAL(9,E5:E7)</f></c></row>
        <row r="11">\(s("B11", 11))</row>
        <row r="12">\(s("B12", 12))</row>
        """
        return try makeXLSX(sheetRows: rows, sharedStrings: strings)
    }

    func testReadsCellsInTheirColumnsWithDatesAndNumbers() throws {
        let rows = try SpreadsheetReader.rows(fromXLSX: invoiceXLSX())

        XCTAssertEqual(rows[1], ["", "Data", "Lançamento", "Parcelamento", "Valor"])
        XCTAssertEqual(rows[2], ["", "01/07/2026", "Pagamento Efetuado", "", "-6873.37"])
        XCTAssertEqual(rows[4], ["", "19/06/2026", "Shopee*loja", "Parcela 2 de 12", "115.14"], "Formato de data embutido (14)")
        XCTAssertEqual(rows[5], ["", "", "", "Subtotal", ""], "Fórmula sem valor calculado fica vazia")
    }

    func testFollowsWorkbookRelationshipToFindTheSheet() throws {
        let data = try makeXLSX(sheetRows: "<row r=\"1\">\(s("A1", 0))</row>", sharedStrings: ["ok"], sheetPath: "worksheets/aba.xml")

        XCTAssertEqual(try SpreadsheetReader.rows(fromXLSX: data), [["ok"]])
    }

    func testRejectsFilesThatAreNotXLSX() {
        XCTAssertThrowsError(try SpreadsheetReader.csv(fromXLSX: Data("Data;Valor".utf8))) { error in
            XCTAssertEqual(error as? SpreadsheetError, .notXLSX)
        }
    }

    func testCardInvoiceSpreadsheetParsesThroughTheStatementParser() throws {
        let csv = try SpreadsheetReader.csv(fromXLSX: invoiceXLSX())
        let parsed = StatementParser.parse(content: csv, filename: "fatura.xlsx")

        XCTAssertTrue(parsed.failures.isEmpty, "Cabeçalho do banco, subtotal e rodapé não viram erro: \(parsed.failures)")
        XCTAssertTrue(parsed.installmentsDatedByPurchase)
        XCTAssertEqual(parsed.transactions.map(\.description), [
            "Pagamento Efetuado", "IFD*RESTAURANTE", "Shopee*loja Parcela 2 de 12",
        ])
        XCTAssertEqual(parsed.transactions[0].amount, -6873.37, accuracy: 0.001)
        XCTAssertEqual(parsed.transactions[1].amount, 44.32, accuracy: 0.001)
    }

    func testNumberFormatting() {
        XCTAssertEqual(SpreadsheetReader.numberString("10"), "10")
        XCTAssertEqual(SpreadsheetReader.numberString("6.1300000000000003"), "6.13")
        XCTAssertEqual(SpreadsheetReader.numberString("1.234"), "1.23")
        XCTAssertEqual(SpreadsheetReader.dateString(fromSerial: 46237), "03/08/2026")
    }
}

final class CardStatementTests: XCTestCase {

    private func line(_ amount: Double) -> ImportedTransaction {
        ImportedTransaction(date: DateParser.parse("01/07/2026")!, description: "x", amount: amount)
    }

    func testFlipsInvoicesWherePurchasesArePositive() {
        let result = CardStatement.normalizeSigns([line(-6873.37), line(44.32), line(6.13)])

        XCTAssertEqual(result.map(\.amount), [6873.37, -44.32, -6.13])
    }

    func testKeepsInvoicesAlreadyInTheAppConvention() {
        let result = CardStatement.normalizeSigns([line(500), line(-44.32), line(-6.13)])

        XCTAssertEqual(result.map(\.amount), [500, -44.32, -6.13])
    }
}

final class PurchaseDatedInstallmentTests: XCTestCase {

    private func day(_ text: String) -> Date { DateParser.parse(text)! }

    private func month(_ date: Date) -> String { String(LedgerCalendar.isoDay(date).prefix(7)) }

    func testInstallmentMovesToItsBillingMonth() {
        let row = ImportedTransaction(date: day("26/07/2025"), description: "Shopee Formi Parcela 12 de 12", amount: -126.95)

        let expanded = InstallmentExpander.expand([row], datedByPurchase: true)

        XCTAssertEqual(expanded.count, 1)
        XCTAssertEqual(month(expanded[0].date), "2026-06")
    }

    /// O Itaú repete a data da compra em todas as faturas: a parcela 3/12 da
    /// fatura seguinte precisa gerar a mesma chave da projeção feita pela 2/12.
    func testNextInvoiceConfirmsTheProjectionInsteadOfDuplicating() {
        let accountID = UUID()
        let august = ImportedTransaction(date: day("19/06/2026"), description: "Shopee*zhihua Parcela 2 de 12", amount: -115.14)
        let september = ImportedTransaction(date: day("19/06/2026"), description: "Shopee*zhihua Parcela 3 de 12", amount: -115.14)

        let projected = InstallmentExpander.expand([august], datedByPurchase: true)
        let confirmed = InstallmentExpander.expand([september], datedByPurchase: true)

        let projectionKey = DedupKey.make(accountID: accountID, transaction: projected[1])
        let realKey = DedupKey.make(accountID: accountID, transaction: confirmed[0])
        XCTAssertTrue(projected[1].isProjected)
        XCTAssertEqual(projectionKey, realKey)
    }
}
