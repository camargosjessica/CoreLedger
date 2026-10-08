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
        guard let named = try? Regex(namedPattern), let numeric = try? Regex(numericPattern) else { return nil }
        if let match = text.firstMatch(of: named),
           let name = match.output[1].substring, let yearText = match.output[2].substring,
           let index = names.firstIndex(of: String(name)), let year = Int(yearText) {
            return YearMonth(year: year, month: index + 1)
        }
        if let match = text.firstMatch(of: numeric),
           let yearText = match.output[1].substring, let monthText = match.output[2].substring,
           let year = Int(yearText), let month = Int(monthText) {
            return YearMonth(year: year, month: month)
        }
        return nil
    }
}
