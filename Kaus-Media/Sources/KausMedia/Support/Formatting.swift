import Foundation

/// Formatação pt-BR fixa: o extrato é em reais independentemente do locale do
/// aparelho, e o servidor (Linux, locale C) precisa produzir o mesmo texto.
///
/// Única fonte da formatação de dinheiro para o app e o servidor; datas são
/// apresentação e ficam no app.
extension Money {
    /// "R$ 1.234,56" / "-R$ 80,00".
    public var brl: String {
        Formatters.currency.string(from: NSDecimalNumber(decimal: decimalValue)) ?? "R$ 0,00"
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
}
