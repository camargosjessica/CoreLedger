import SwiftUI
import KausMedia

/// Mês e ano, sem dia — o compromisso vale para o mês inteiro.
struct MonthPicker: View {
    let title: String
    @Binding var month: YearMonth

    var body: some View {
        DatePicker(
            title,
            selection: Binding(
                get: { month.startDate },
                set: { month = YearMonth(date: $0) }
            ),
            displayedComponents: .date
        )
    }
}
