import Foundation

/// Mês de uma fatura de cartão, usado para substituir a fatura anterior do
/// mesmo mês quando o arquivo é reenviado.
public enum StatementMonth {
    private static let names = ["jan", "fev", "mar", "abr", "mai", "jun", "jul", "ago", "set", "out", "nov", "dez"]
    private static let numericPattern = #"(20\d{2})[-_. ]?(0[1-9]|1[0-2])(?!\d)"#
    private static let namedPattern = #"(?:^|[^a-z])(jan|fev|mar|abr|mai|jun|jul|ago|set|out|nov|dez)[a-z]*[-_. ]?(?:de[-_. ]?)?(20\d{2})"#

    /// O nome do arquivo manda quando traz mês e ano ("fatura-agosto2026.xlsx",
    /// "fatura_2026-08.csv"). Sem isso, a fatura vence no mês seguinte à compra
    /// mais recente.
    public static func guess(filename: String?, latestDate: Date?) -> YearMonth? {
        if let filename, let month = parse(filename) { return month }
        return latestDate.map { YearMonth(date: $0).adding(months: 1) }
    }

    static func parse(_ filename: String) -> YearMonth? {
        let text = filename.lowercased().folding(options: .diacriticInsensitive, locale: nil)
        if let groups = firstMatch(namedPattern, in: text),
           let index = names.firstIndex(of: groups[0]), let year = Int(groups[1]) {
            return YearMonth(year: year, month: index + 1)
        }
        if let groups = firstMatch(numericPattern, in: text),
           let year = Int(groups[0]), let month = Int(groups[1]) {
            return YearMonth(year: year, month: month)
        }
        return nil
    }

    /// Grupos de captura da primeira ocorrência do padrão.
    private static func firstMatch(_ pattern: String, in text: String) -> [String]? {
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text))
        else { return nil }
        return (1..<match.numberOfRanges).compactMap { index in
            Range(match.range(at: index), in: text).map { String(text[$0]) }
        }
    }
}
