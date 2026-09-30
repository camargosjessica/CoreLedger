import Foundation

/// Mês do calendário, sem dia nem fuso.
///
/// A grade anual é indexada por mês e trafega em JSON; usar `Date` obrigaria
/// cliente e servidor a concordar sobre hora e fuso só para dizer "maio de 2026".
public struct YearMonth: Codable, Sendable, Hashable, Comparable, CustomStringConvertible {
    public var year: Int
    public var month: Int

    public init(year: Int, month: Int) {
        let normalized = YearMonth.normalize(year: year, month: month)
        self.year = normalized.year
        self.month = normalized.month
    }

    public init(date: Date) {
        let components = LedgerCalendar.calendar.dateComponents([.year, .month], from: date)
        self.init(year: components.year ?? 1970, month: components.month ?? 1)
    }

    /// `"2026-05"`. É também a forma serializada, para que a grade seja legível
    /// no JSON e utilizável como chave de dicionário.
    public var description: String { String(format: "%04d-%02d", year, month) }

    public init?(_ text: String) {
        let parts = text.split(separator: "-")
        guard parts.count == 2, let year = Int(parts[0]), let month = Int(parts[1]),
              (1...9999).contains(year), (1...12).contains(month) else { return nil }
        self.init(year: year, month: month)
    }

    public init(from decoder: any Decoder) throws {
        let text = try decoder.singleValueContainer().decode(String.self)
        guard let value = YearMonth(text) else {
            throw DecodingError.dataCorrupted(
                .init(codingPath: decoder.codingPath, debugDescription: "Mês inválido: \(text)")
            )
        }
        self = value
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(description)
    }

    public static func < (lhs: YearMonth, rhs: YearMonth) -> Bool {
        (lhs.year, lhs.month) < (rhs.year, rhs.month)
    }

    /// Primeiro instante do mês em UTC, para cruzar com datas de lançamentos.
    public var startDate: Date {
        LedgerCalendar.calendar.date(from: DateComponents(year: year, month: month, day: 1))
            ?? Date(timeIntervalSince1970: 0)
    }

    /// Data do dia pedido dentro do mês, limitada ao último dia existente —
    /// um compromisso do dia 31 cai em 28 de fevereiro, não em 3 de março.
    public func date(day: Int) -> Date {
        let range = LedgerCalendar.calendar.range(of: .day, in: .month, for: startDate)
        let lastDay = range?.count ?? 28
        let clamped = min(max(day, 1), lastDay)
        return LedgerCalendar.calendar
            .date(from: DateComponents(year: year, month: month, day: clamped)) ?? startDate
    }

    public func adding(months: Int) -> YearMonth {
        YearMonth(year: year, month: month + months)
    }

    public static func range(from start: YearMonth, to end: YearMonth) -> [YearMonth] {
        guard start <= end else { return [] }
        var months: [YearMonth] = []
        var current = start
        while current <= end {
            months.append(current)
            current = current.adding(months: 1)
        }
        return months
    }

    private static func normalize(year: Int, month: Int) -> (year: Int, month: Int) {
        let zeroBased = month - 1
        let yearOffset = Int(floor(Double(zeroBased) / 12))
        return (year + yearOffset, zeroBased - yearOffset * 12 + 1)
    }
}
