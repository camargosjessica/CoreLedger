import Foundation

/// Formatação pt-BR fixa: o extrato é em reais independentemente do locale do
/// aparelho, e o servidor (Linux, locale C) precisa produzir o mesmo texto.
extension Double {
    public var brl: String {
        Formatters.currency.string(from: NSNumber(value: self)) ?? "R$ 0,00"
    }
}

extension Date {
    /// "Janeiro 2025"
    public var monthYear: String {
        Formatters.monthYear.string(from: self).capitalized
    }

    /// "15/01/2025"
    public var shortDay: String {
        Formatters.shortDay.string(from: self)
    }
}

enum Formatters {
    static let ptBR = Locale(identifier: "pt_BR")

    static let currency: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.locale = ptBR
        formatter.currencyCode = "BRL"
        formatter.currencySymbol = "R$"
        formatter.groupingSeparator = "."
        formatter.decimalSeparator = ","
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 2
        return formatter
    }()

    static let monthYear: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = ptBR
        formatter.timeZone = LedgerCalendar.timeZone
        formatter.setLocalizedDateFormatFromTemplate("MMMM yyyy")
        return formatter
    }()

    static let shortDay: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = ptBR
        formatter.timeZone = LedgerCalendar.timeZone
        formatter.dateFormat = "dd/MM/yyyy"
        return formatter
    }()
}
