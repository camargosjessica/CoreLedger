import Foundation
import KausMedia

extension Double {
    /// Valor em reais. Despesas chegam negativas do servidor.
    var brl: String {
        Formatters.currency.string(from: NSNumber(value: self)) ?? String(format: "%.2f", self)
    }
}

extension Date {
    /// "setembro de 2025" — o servidor envia o mês como meia-noite UTC, então a
    /// formatação também é feita em UTC para não cair no mês anterior.
    var monthYear: String { Formatters.monthYear.string(from: self).capitalized }

    /// "25 de set."
    var shortDay: String { Formatters.shortDay.string(from: self) }
}

private enum Formatters {
    static let currency: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.locale = Locale(identifier: "pt_BR")
        return formatter
    }()

    static let monthYear = dateFormatter("MMMM 'de' yyyy")
    static let shortDay = dateFormatter("d 'de' MMM")

    private static func dateFormatter(_ format: String) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "pt_BR")
        formatter.timeZone = LedgerCalendar.timeZone
        formatter.dateFormat = format
        return formatter
    }
}
