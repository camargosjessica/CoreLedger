import Foundation
import KausMedia

/// Datas da interface em pt-BR e em UTC: o servidor envia o mês como
/// meia-noite UTC, então formatar no fuso do aparelho faria o dia 1º cair
/// no mês anterior. Dinheiro usa `Money.brl`, do Kaus-Media.
extension Date {
    /// "Setembro de 2025": só a primeira letra em maiúscula.
    var monthYear: String {
        let text = formatted(DateStyles.monthYear)
        return text.prefix(1).uppercased() + text.dropFirst()
    }

    /// "25/09/2026"
    var numericDay: String { DateParser.format(self) }

    /// "25 de set."
    var shortDay: String { formatted(DateStyles.shortDay) }

    /// "set." — rótulo curto dos eixos dos gráficos.
    var shortMonth: String { formatted(DateStyles.shortMonth) }

    /// "set. 25" — para eixos que podem atravessar anos.
    var shortMonthYear: String { formatted(DateStyles.shortMonthYear) }
}

/// Formatos fixos (não dependem das preferências do aparelho). Os
/// `FormatStyle` são valores leves e fazem o cache internamente.
enum DateStyles {
    static let locale = Locale(identifier: "pt_BR")
    static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = LedgerCalendar.timeZone
        return calendar
    }()

    private static func style(_ format: Date.FormatString) -> Date.VerbatimFormatStyle {
        Date.VerbatimFormatStyle(format: format, locale: locale, timeZone: LedgerCalendar.timeZone, calendar: calendar)
    }

    static let monthYear = style("\(month: .wide) de \(year: .defaultDigits)")
    static let shortDay = style("\(day: .defaultDigits) de \(month: .abbreviated)")
    static let shortMonth = style("\(month: .abbreviated)")
    static let shortMonthYear = style("\(month: .abbreviated) \(year: .twoDigits)")
}
