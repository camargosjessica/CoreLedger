import Foundation

/// Conversão de valores monetários vindos de extratos.
///
/// Cobre `1.234,56` (Brasil), `1,234.56` (inglês), `R$ -80,00`, `(80,00)`,
/// `80,00 D` / `80,00 C` e `-80.00`.
public enum ValueParser {
    public static func parse(_ raw: String) -> Double? {
        var text = raw.trimmed().uppercased()
        guard !text.isEmpty else { return nil }

        var isNegative = false

        if text.hasPrefix("(") && text.hasSuffix(")") {
            isNegative = true
            text = String(text.dropFirst().dropLast())
        }

        // Sufixo D (débito) / C (crédito) usado por alguns bancos.
        if let last = text.last, last == "D" || last == "C" {
            let body = String(text.dropLast()).trimmed()
            if !body.isEmpty, body.rangeOfCharacter(from: .decimalDigits) != nil {
                isNegative = isNegative || last == "D"
                text = body
            }
        }

        text = text.replacingOccurrences(of: "R$", with: "")
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "\u{00A0}", with: "")

        if text.hasPrefix("-") {
            isNegative = !isNegative
            text = String(text.dropFirst())
        } else if text.hasPrefix("+") {
            text = String(text.dropFirst())
        }

        guard text.rangeOfCharacter(from: .decimalDigits) != nil else { return nil }
        guard text.allSatisfy({ $0.isNumber || $0 == "." || $0 == "," }) else { return nil }

        let normalized = normalizeSeparators(text)
        guard let value = Double(normalized) else { return nil }
        return isNegative ? -value : value
    }

    /// Decide qual símbolo é decimal e qual é separador de milhar.
    private static func normalizeSeparators(_ text: String) -> String {
        let lastComma = text.lastIndex(of: ",")
        let lastDot = text.lastIndex(of: ".")

        switch (lastComma, lastDot) {
        case let (comma?, dot?):
            // O separador decimal é o que aparece por último.
            if comma > dot {
                return text.replacingOccurrences(of: ".", with: "").replacingOccurrences(of: ",", with: ".")
            }
            return text.replacingOccurrences(of: ",", with: "")
        case let (comma?, nil):
            // `1,234` é ambíguo: com exatamente 3 dígitos após a vírgula tratamos
            // como separador de milhar, que é o caso comum em extratos em inglês.
            let decimals = text.distance(from: text.index(after: comma), to: text.endIndex)
            return decimals == 3
                ? text.replacingOccurrences(of: ",", with: "")
                : text.replacingOccurrences(of: ",", with: ".")
        case let (nil, dot?):
            let decimals = text.distance(from: text.index(after: dot), to: text.endIndex)
            return decimals == 3 && text.filter({ $0 == "." }).count >= 1 && text.count > 4
                ? text.replacingOccurrences(of: ".", with: "")
                : text
        case (nil, nil):
            return text
        }
    }
}

/// Conversão das datas encontradas em extratos.
public enum DateParser {
    private static let formats = [
        "dd/MM/yyyy", "dd/MM/yy", "yyyy-MM-dd", "dd-MM-yyyy", "dd.MM.yyyy", "yyyy/MM/dd", "yyyyMMdd"
    ]

    private static let formatters: [DateFormatter] = formats.map { format in
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = LedgerCalendar.timeZone
        formatter.dateFormat = format
        formatter.isLenient = false
        return formatter
    }

    public static func parse(_ raw: String) -> Date? {
        let text = raw.trimmed()
        guard !text.isEmpty else { return nil }
        // Alguns extratos trazem data e hora na mesma coluna.
        let datePart = text.split(whereSeparator: { $0 == " " || $0 == "T" }).first.map(String.init) ?? text
        for formatter in formatters {
            if let date = formatter.date(from: datePart) { return date }
        }
        return nil
    }
}
