import Foundation

public enum StatementFormat: String, Codable, Sendable, CaseIterable {
    case csv
    case ofx
}

/// Leitura de extratos bancários e faturas de cartão em CSV e OFX.
public enum StatementParser {
    /// Decodifica o arquivo tentando UTF-8 e, na sequência, os encodings usados
    /// pelos bancos brasileiros em arquivos antigos.
    public static func decode(_ data: Data) -> String? {
        for encoding: String.Encoding in [.utf8, .isoLatin1, .windowsCP1252] {
            if let text = String(data: data, encoding: encoding) { return text }
        }
        return nil
    }

    public static func detectFormat(filename: String?, content: String) -> StatementFormat {
        if let filename, filename.lowercased().hasSuffix(".ofx") { return .ofx }
        let head = content.prefix(4000).uppercased()
        if head.contains("<STMTTRN") || head.contains("<OFX") { return .ofx }
        return .csv
    }

    public static func parse(
        content: String,
        filename: String? = nil,
        format: StatementFormat? = nil
    ) -> ParsedStatement {
        switch format ?? detectFormat(filename: filename, content: content) {
        case .ofx: return parseOFX(content)
        case .csv: return parseCSV(content)
        }
    }

    // MARK: - OFX

    static func parseOFX(_ content: String) -> ParsedStatement {
        var transactions: [ImportedTransaction] = []
        var failures: [ImportFailure] = []

        let content = content.components(separatedBy: .newlines).joined(separator: "\n")
        let blocks = transactionBlocks(in: content)
        if blocks.isEmpty {
            return ParsedStatement(failures: [ImportFailure(line: 0, content: "", reason: "Nenhuma transação (<STMTTRN>) encontrada no arquivo OFX")])
        }

        for (index, block) in blocks.enumerated() {
            let rawDate = tag("DTPOSTED", in: block) ?? tag("DTUSER", in: block)
            let rawAmount = tag("TRNAMT", in: block)
            let description = tag("MEMO", in: block) ?? tag("NAME", in: block) ?? "Sem descrição"

            guard let rawDate, let date = parseOFXDate(rawDate) else {
                failures.append(ImportFailure(line: index + 1, content: block.trimmed(), reason: "Data (DTPOSTED) ausente ou inválida"))
                continue
            }
            guard let rawAmount, let amount = ValueParser.parse(rawAmount) else {
                failures.append(ImportFailure(line: index + 1, content: block.trimmed(), reason: "Valor (TRNAMT) ausente ou inválido"))
                continue
            }

            transactions.append(
                ImportedTransaction(
                    date: LedgerCalendar.startOfDay(date),
                    description: description.trimmed(),
                    amount: amount,
                    externalID: tag("FITID", in: block)?.trimmed()
                )
            )
        }

        return ParsedStatement(transactions: transactions, failures: failures)
    }

    /// OFX é SGML: `</STMTTRN>` é opcional. Quando não existe, cada transação vai
    /// da abertura de `<STMTTRN>` até a próxima abertura (ou o fim da lista).
    private static func transactionBlocks(in content: String) -> [String] {
        var starts: [String.Index] = []
        var cursor = content.startIndex
        while let range = content.range(of: "<STMTTRN>", options: .caseInsensitive, range: cursor..<content.endIndex) {
            starts.append(range.upperBound)
            cursor = range.upperBound
        }

        return starts.enumerated().compactMap { offset, start in
            let next = offset + 1 < starts.count ? starts[offset + 1] : content.endIndex
            var block = content[start..<next]
            for terminator in ["</STMTTRN>", "</BANKTRANLIST>"] {
                if let end = block.range(of: terminator, options: .caseInsensitive) {
                    block = block[block.startIndex..<end.lowerBound]
                    break
                }
            }
            let text = String(block)
            return text.trimmed().isEmpty ? nil : text
        }
    }

    /// OFX usa SGML: a tag de fechamento é opcional, o valor vai até a próxima tag ou fim de linha.
    private static func tag(_ name: String, in block: String) -> String? {
        let pattern = "<\(name)>([^<\r\n]*)"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
              let match = regex.firstMatch(in: block, range: NSRange(block.startIndex..., in: block)),
              let range = Range(match.range(at: 1), in: block)
        else { return nil }
        let value = String(block[range]).trimmed()
        return value.isEmpty ? nil : value
    }

    /// `20240115` ou `20240115120000[-3:BRT]` — só a parte da data importa.
    static func parseOFXDate(_ raw: String) -> Date? {
        let digits = raw.prefix { $0.isNumber }
        guard digits.count >= 8 else { return nil }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = LedgerCalendar.timeZone
        formatter.dateFormat = "yyyyMMdd"
        return formatter.date(from: String(digits.prefix(8)))
    }

    // MARK: - CSV

    static func parseCSV(_ content: String) -> ParsedStatement {
        let rows = CSVReader.rows(from: content)
        guard !rows.isEmpty else {
            return ParsedStatement(failures: [ImportFailure(line: 0, content: "", reason: "Arquivo vazio")])
        }

        var transactions: [ImportedTransaction] = []
        var failures: [ImportFailure] = []

        let layout = ColumnLayout(header: rows[0].fields)
        let body = layout.hasHeader ? Array(rows.dropFirst()) : rows

        for row in body {
            let fields = row.fields
            guard fields.contains(where: { !$0.isEmpty }) else { continue }

            guard let rawDate = layout.value(.date, in: fields), let date = DateParser.parse(rawDate) else {
                failures.append(ImportFailure(line: row.line, content: row.raw, reason: "Data ausente ou em formato desconhecido"))
                continue
            }
            guard let rawAmount = layout.amount(in: fields), let amount = ValueParser.parse(rawAmount) else {
                failures.append(ImportFailure(line: row.line, content: row.raw, reason: "Valor ausente ou em formato desconhecido"))
                continue
            }
            let description = layout.value(.description, in: fields)?.trimmed() ?? "Sem descrição"

            transactions.append(
                ImportedTransaction(
                    date: LedgerCalendar.startOfDay(date),
                    description: description.isEmpty ? "Sem descrição" : description,
                    amount: amount
                )
            )
        }

        return ParsedStatement(transactions: transactions, failures: failures)
    }
}

/// Descobre quais colunas do CSV contêm data, descrição e valor.
/// Sem cabeçalho reconhecível, assume a ordem `data, descrição, valor`.
struct ColumnLayout {
    enum Column { case date, description, amount }

    let hasHeader: Bool
    private let dateIndex: Int
    private let descriptionIndex: Int
    private let amountIndex: Int
    /// Extratos com colunas separadas de débito e crédito.
    private let debitIndex: Int?
    private let creditIndex: Int?

    init(header: [String]) {
        let normalized = header.map { TextNormalizer.normalize($0) }
        func index(matching terms: [String]) -> Int? {
            normalized.firstIndex { field in terms.contains { field.contains($0) } }
        }

        let date = index(matching: ["data", "date", "dt "])
        let description = index(matching: ["descri", "histor", "memo", "lancamento", "estabelecimento", "detalhe"])
        let amount = index(matching: ["valor", "amount", "montante", "quantia"])
        let debit = index(matching: ["debito", "saida", "despesa"])
        let credit = index(matching: ["credito", "entrada", "receita"])

        self.hasHeader = date != nil && (amount != nil || (debit != nil && credit != nil))
        self.dateIndex = date ?? 0
        self.descriptionIndex = description ?? 1
        self.amountIndex = amount ?? -1
        self.debitIndex = hasHeader ? debit : nil
        self.creditIndex = hasHeader ? credit : nil
    }

    func value(_ column: Column, in fields: [String]) -> String? {
        let index: Int
        switch column {
        case .date: index = dateIndex
        case .description: index = descriptionIndex
        case .amount: index = amountIndex
        }
        guard index >= 0, index < fields.count else { return nil }
        let value = fields[index].trimmed()
        return value.isEmpty ? nil : value
    }

    /// Valor da linha, seja em coluna única ou em colunas débito/crédito.
    func amount(in fields: [String]) -> String? {
        if let value = value(.amount, in: fields) { return value }

        if let creditIndex, creditIndex < fields.count {
            let credit = fields[creditIndex].trimmed()
            if !credit.isEmpty, let parsed = ValueParser.parse(credit), parsed != 0 {
                return String(abs(parsed))
            }
        }
        if let debitIndex, debitIndex < fields.count {
            let debit = fields[debitIndex].trimmed()
            if !debit.isEmpty, let parsed = ValueParser.parse(debit), parsed != 0 {
                return String(-abs(parsed))
            }
        }
        // Sem cabeçalho: último campo numérico da linha.
        if !hasHeader {
            return fields.reversed().first { ValueParser.parse($0.trimmed()) != nil }?.trimmed()
        }
        return nil
    }
}

extension String {
    func trimmed() -> String {
        trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
