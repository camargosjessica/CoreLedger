import SwiftUI
import UniformTypeIdentifiers
import KausMedia

struct PeriodFilter: View {
    @Bindable var store: LedgerStore

    var body: some View {
        VStack(spacing: 8) {
            Picker("Período", selection: Bindable(store.transactions).period) {
                ForEach(TransactionsStore.Period.allCases) { period in
                    Text(period.title).tag(period)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            if store.transactions.period == .month {
                MonthStepper(month: Bindable(store.transactions).selectedMonth)
            }
        }
    }
}

struct CategoryFilter: View {
    @Bindable var store: LedgerStore

    var body: some View {
        Picker("Categoria", selection: Bindable(store.transactions).selectedCategory) {
            Text("Todas").tag(String?.none)
            ForEach(store.parentCategories, id: \.self) { parent in
                Text(parent).tag(String?.some(parent))
                ForEach(store.subcategories(of: parent), id: \.self) { sub in
                    Text("    \(CategoryPath.child(of: sub) ?? sub)").tag(String?.some(sub))
                }
            }
        }
    }
}
