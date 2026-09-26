import Foundation

/// Leitor de CSV no estilo RFC 4180: suporta campos entre aspas, aspas escapadas
/// (`""`) e quebras de linha dentro de um campo. O separador é detectado entre
/// `;` (padrão dos bancos brasileiros), `,` e tabulação.
enum CSVReader {
    struct Row {
        /// Número da primeira linha física do registro, para reportar erros ao usuário.
        let line: Int
        let raw: String
        let fields: [String]
    }

    static func rows(from content: String) -> [Row] {
        let text = content.replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        guard !text.trimmed().isEmpty else { return [] }

        let separator = detectSeparator(in: text)

        var rows: [Row] = []
        var fields: [String] = []
        var field = ""
        var raw = ""
        var insideQuotes = false
        var line = 1
        var rowStartLine = 1

        var iterator = text.makeIterator()
        var pending: Character? = iterator.next()

        func finishRow() {
            fields.append(field)
            if fields.contains(where: { !$0.trimmed().isEmpty }) {
                rows.append(Row(line: rowStartLine, raw: raw, fields: fields))
            }
            fields = []
            field = ""
            raw = ""
            rowStartLine = line
        }

        while let character = pending {
            pending = iterator.next()

            if character != "\n" || insideQuotes { raw.append(character) }

            if insideQuotes {
                if character == "\"" {
                    if pending == "\"" {
                        field.append("\"")
                        raw.append("\"")
                        pending = iterator.next()
                    } else {
                        insideQuotes = false
                    }
                } else {
                    if character == "\n" { line += 1 }
                    field.append(character)
                }
                continue
            }

            switch character {
            case "\"":
                insideQuotes = true
            case separator:
                fields.append(field)
                field = ""
            case "\n":
                line += 1
                finishRow()
                rowStartLine = line
            default:
                field.append(character)
            }
        }

        if !field.isEmpty || !fields.isEmpty { finishRow() }
        return rows
    }

    /// Vírgulas e ponto e vírgulas dentro de aspas pertencem à descrição, não à
    /// estrutura: contá-los escolheria o separador errado em extratos com
    /// descrições longas entre aspas.
    private static func detectSeparator(in text: String) -> Character {
        let candidates: [Character] = [";", ",", "\t"]
        var counts: [Character: Int] = [:]
        var insideQuotes = false
        var lines = 0

        for character in text {
            if character == "\"" {
                insideQuotes.toggle()
                continue
            }
            if insideQuotes { continue }
            if character == "\n" {
                lines += 1
                if lines >= 5 { break }
                continue
            }
            if candidates.contains(character) { counts[character, default: 0] += 1 }
        }

        return candidates
            .map { ($0, counts[$0] ?? 0) }
            .max { $0.1 < $1.1 }
            .flatMap { $0.1 > 0 ? $0.0 : nil } ?? ";"
    }
}
