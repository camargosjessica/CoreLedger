import Foundation
import Testing
import KausMedia
@testable import KausBorealis

@Suite("Formatação")
struct FormattingTests {
    /// Os formatos antigos, com DateFormatter, como referência.
    private func legacy(_ format: String, _ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "pt_BR")
        formatter.timeZone = LedgerCalendar.timeZone
        formatter.dateFormat = format
        return formatter.string(from: date)
    }

    @Test(arguments: 1...12)
    func dateStylesMatchThePreviousFormatters(month: Int) {
        let date = YearMonth(year: 2026, month: month).startDate
        let monthYear = legacy("MMMM 'de' yyyy", date)
        #expect(date.monthYear == monthYear.prefix(1).uppercased() + monthYear.dropFirst())
        #expect(date.shortDay == legacy("d 'de' MMM", date))
        #expect(date.shortMonth == legacy("MMM", date))
        #expect(date.shortMonthYear == legacy("MMM yy", date))
    }

    @Test func firstOfMonthStaysInItsMonth() {
        let date = YearMonth(year: 2025, month: 9).startDate
        #expect(date.monthYear == "Setembro de 2025")
        #expect(date.numericDay == "01/09/2025")
    }

    @Test func moneyIsAlwaysBrazilianReais() {
        #expect(Money(-1234.56).brl.replacingOccurrences(of: "\u{00A0}", with: " ") == "-R$ 1.234,56")
    }
}
