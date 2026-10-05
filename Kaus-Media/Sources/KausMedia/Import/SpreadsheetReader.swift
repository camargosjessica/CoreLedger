import Foundation
#if canImport(FoundationXML)
import FoundationXML
#endif
import ZIPFoundation

public enum SpreadsheetError: Error, Equatable, LocalizedError {
    case notXLSX
    case missingSheet

    public var errorDescription: String? {
        switch self {
        case .notXLSX:
            return "O arquivo não é uma planilha .xlsx. Se for um .xls antigo, abra no Excel, Numbers ou Google Planilhas e salve como .xlsx ou .csv."
        case .missingSheet:
            return "A planilha não tem nenhuma aba com dados."
        }
    }
}

/// Leitura da primeira aba de uma planilha `.xlsx` (Excel ou Google Planilhas).
///
/// A planilha vira CSV para seguir pelo mesmo `StatementParser` dos extratos:
/// cabeçalho, colunas e parcelas são interpretados num lugar só.
public enum SpreadsheetReader {
    /// Todo `.xlsx` é um ZIP, e todo ZIP começa com `PK\u{3}\u{4}`.
    public static func isXLSX(_ data: Data) -> Bool {
        data.starts(with: [0x50, 0x4B, 0x03, 0x04])
    }

    public static func csv(fromXLSX data: Data) throws -> String {
        try rows(fromXLSX: data)
            .map { $0.map(quote).joined(separator: ";") }
            .joined(separator: "\n")
    }

    /// Linhas da primeira aba, com as células vazias preservadas para que cada
    /// coluna fique sempre na mesma posição.
    static func rows(fromXLSX data: Data) throws -> [[String]] {
        guard isXLSX(data), let archive = try? Archive(data: data, accessMode: .read, pathEncoding: nil) else {
            throw SpreadsheetError.notXLSX
        }

        func read(_ path: String) -> Data? {
            guard let entry = archive[path] else { return nil }
            var content = Data()
            guard (try? archive.extract(entry, consumer: { content.append($0) })) != nil else { return nil }
            return content
        }

        guard let sheetData = read(firstSheetPath(read: read)) else { throw SpreadsheetError.missingSheet }
        let sharedStrings = read("xl/sharedStrings.xml").map(SharedStringsParser.parse) ?? []
        let dateStyles = read("xl/styles.xml").map(StylesParser.dateStyles) ?? []

        return SheetParser.parse(sheetData, sharedStrings: sharedStrings, dateStyles: dateStyles)
    }

    /// Caminho da primeira aba declarada em `workbook.xml`, resolvido pelos
    /// relacionamentos — o Google Planilhas nem sempre usa `sheet1.xml`.
    private static func firstSheetPath(read: (String) -> Data?) -> String {
        let fallback = "xl/worksheets/sheet1.xml"
        guard let workbook = read("xl/workbook.xml"),
              let relationID = XMLAttributes.first(element: "sheet", attribute: "r:id", in: workbook),
              let relations = read("xl/_rels/workbook.xml.rels"),
              let target = XMLAttributes.target(ofRelationship: relationID, in: relations)
        else { return fallback }
        if target.hasPrefix("/") { return String(target.dropFirst()) }
        return "xl/" + target
    }

    private static func quote(_ field: String) -> String {
        guard field.contains(where: { $0 == ";" || $0 == "\"" || $0 == "\n" || $0 == "\r" }) else { return field }
        return "\"" + field.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }

    /// Datas no Excel são dias desde 30/12/1899 (sistema 1900, o padrão).
    static func dateString(fromSerial serial: Double) -> String {
        let epoch = DateComponents(calendar: LedgerCalendar.calendar, year: 1899, month: 12, day: 30).date ?? Date()
        let date = LedgerCalendar.addingDays(Int(serial.rounded(.down)), to: epoch)
        let parts = LedgerCalendar.calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%02d/%02d/%04d", parts.day ?? 1, parts.month ?? 1, parts.year ?? 1900)
    }

    /// Números fracionários saem com duas casas: em extrato são sempre valores
    /// em reais, e `1.234` com três casas seria lido como milhar pelo `ValueParser`.
    static func numberString(_ raw: String) -> String {
        guard let value = Double(raw) else { return raw }
        if value == value.rounded() && abs(value) < 1e15 { return String(Int64(value)) }
        return String(format: "%.2f", value)
    }
}

// MARK: - XML

private final class XMLAttributes: NSObject, XMLParserDelegate {
    private let element: String
    private let match: ([String: String]) -> String?
    private var result: String?

    private init(element: String, match: @escaping ([String: String]) -> String?) {
        self.element = element
        self.match = match
    }

    static func first(element: String, attribute: String, in data: Data) -> String? {
        run(data, element: element) { $0[attribute] }
    }

    static func target(ofRelationship id: String, in data: Data) -> String? {
        run(data, element: "Relationship") { $0["Id"] == id ? $0["Target"] : nil }
    }

    private static func run(_ data: Data, element: String, match: @escaping ([String: String]) -> String?) -> String? {
        let delegate = XMLAttributes(element: element, match: match)
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        _ = parser.parse()
        return delegate.result
    }

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?,
                qualifiedName: String?, attributes: [String: String] = [:]) {
        guard result == nil, elementName == element, let value = match(attributes) else { return }
        result = value
        parser.abortParsing()
    }
}

/// `sharedStrings.xml`: cada `<si>` é um texto, simples (`<t>`) ou formatado em
/// trechos (`<r><t>…</t></r>`). Textos fonéticos (`<rPh>`) não fazem parte do valor.
private final class SharedStringsParser: NSObject, XMLParserDelegate {
    private var strings: [String] = []
    private var current = ""
    private var insideText = false
    private var phoneticDepth = 0

    static func parse(_ data: Data) -> [String] {
        let delegate = SharedStringsParser()
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        _ = parser.parse()
        return delegate.strings
    }

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?,
                qualifiedName: String?, attributes: [String: String] = [:]) {
        switch elementName {
        case "si": current = ""
        case "rPh": phoneticDepth += 1
        case "t": insideText = phoneticDepth == 0
        default: break
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        if insideText { current += string }
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName: String?) {
        switch elementName {
        case "si": strings.append(current)
        case "rPh": phoneticDepth -= 1
        case "t": insideText = false
        default: break
        }
    }
}

/// Descobre quais estilos de célula (`cellXfs`) formatam números como data.
private final class StylesParser: NSObject, XMLParserDelegate {
    /// Formatos de data embutidos no Excel (ECMA-376, 18.8.30).
    private static let builtInDateFormats: Set<Int> = [14, 15, 16, 17, 18, 19, 20, 21, 22, 45, 46, 47]

    private var customDateFormats: Set<Int> = []
    private var styleFormats: [Int] = []
    private var insideCellXfs = false

    static func dateStyles(_ data: Data) -> Set<Int> {
        let delegate = StylesParser()
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        _ = parser.parse()
        let dateFormats = builtInDateFormats.union(delegate.customDateFormats)
        return Set(delegate.styleFormats.indices.filter { dateFormats.contains(delegate.styleFormats[$0]) })
    }

    /// Formato personalizado é de data quando tem dia, mês ou ano fora de
    /// trechos literais (`"..."`) e de colchetes (`[$R$-416]`, `[Red]`).
    static func isDateFormat(_ code: String) -> Bool {
        var literal = false
        var bracket = false
        for character in code.lowercased() {
            switch character {
            case "\"": literal.toggle()
            case "[" where !literal: bracket = true
            case "]" where !literal: bracket = false
            case "d", "m", "y":
                if !literal && !bracket { return true }
            default: break
            }
        }
        return false
    }

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?,
                qualifiedName: String?, attributes: [String: String] = [:]) {
        switch elementName {
        case "numFmt":
            if let id = attributes["numFmtId"].flatMap(Int.init), let code = attributes["formatCode"],
               Self.isDateFormat(code) {
                customDateFormats.insert(id)
            }
        case "cellXfs":
            insideCellXfs = true
        case "xf" where insideCellXfs:
            styleFormats.append(attributes["numFmtId"].flatMap(Int.init) ?? 0)
        default:
            break
        }
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName: String?) {
        if elementName == "cellXfs" { insideCellXfs = false }
    }
}

/// Células de `sheetN.xml`. Fórmulas sem valor calculado ficam vazias.
private final class SheetParser: NSObject, XMLParserDelegate {
    private let sharedStrings: [String]
    private let dateStyles: Set<Int>

    private var rows: [[String]] = []
    private var row: [String] = []
    private var cellColumn = 0
    private var cellType: String?
    private var cellStyle = 0
    private var value = ""
    private var capturing = false

    private init(sharedStrings: [String], dateStyles: Set<Int>) {
        self.sharedStrings = sharedStrings
        self.dateStyles = dateStyles
    }

    static func parse(_ data: Data, sharedStrings: [String], dateStyles: Set<Int>) -> [[String]] {
        let delegate = SheetParser(sharedStrings: sharedStrings, dateStyles: dateStyles)
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        _ = parser.parse()
        let width = delegate.rows.map(\.count).max() ?? 0
        return delegate.rows.map { $0 + Array(repeating: "", count: width - $0.count) }
    }

    /// `C15` → 2. Sem referência, a célula ocupa a coluna seguinte.
    private static func columnIndex(of reference: String?) -> Int? {
        guard let reference else { return nil }
        let letters = reference.prefix { $0.isLetter }.uppercased()
        guard !letters.isEmpty else { return nil }
        return letters.unicodeScalars.reduce(0) { $0 * 26 + Int($1.value) - 64 } - 1
    }

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?,
                qualifiedName: String?, attributes: [String: String] = [:]) {
        switch elementName {
        case "row":
            row = []
        case "c":
            cellColumn = Self.columnIndex(of: attributes["r"]) ?? row.count
            cellType = attributes["t"]
            cellStyle = attributes["s"].flatMap(Int.init) ?? 0
            value = ""
        case "v", "t":
            capturing = true
        default:
            break
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        if capturing { value += string }
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName: String?) {
        switch elementName {
        case "v", "t":
            capturing = false
        case "c":
            guard cellColumn >= 0, cellColumn < 16_384 else { return }
            if row.count <= cellColumn { row += Array(repeating: "", count: cellColumn + 1 - row.count) }
            row[cellColumn] = resolvedValue().trimmingCharacters(in: .whitespacesAndNewlines)
        case "row":
            rows.append(row)
        default:
            break
        }
    }

    private func resolvedValue() -> String {
        switch cellType {
        case "s":
            guard let index = Int(value), sharedStrings.indices.contains(index) else { return "" }
            return sharedStrings[index]
        case "inlineStr", "str":
            return value
        case "b":
            return value == "1" ? "VERDADEIRO" : "FALSO"
        case "e":
            return ""
        default:
            guard !value.isEmpty else { return "" }
            if dateStyles.contains(cellStyle), let serial = Double(value) {
                return SpreadsheetReader.dateString(fromSerial: serial)
            }
            return SpreadsheetReader.numberString(value)
        }
    }
}
