import SwiftUI
import KausMedia

/// Resumo mensal realizado + previsão vinda de `GET /api/summary`.
struct SummaryView: View {
    @Bindable var store: LedgerStore

    var body: some View {
        NavigationStack {
            List {
                Section {
                    AccountFilter(store: store)
                }

                if let projection = store.projection {
                    if projection.history.isEmpty && projection.forecast.isEmpty {
                        Section {
                            Text("Importe um extrato para ver o resumo.")
                                .foregroundStyle(.secondary)
                        }
                    }
                    if let current = projection.history.last {
                        Section("Mês atual") {
                            MonthDetail(summary: current)
                        }
                    }
                    if !projection.history.isEmpty {
                        Section("Histórico") {
                            ForEach(projection.history.reversed()) { month in
                                MonthRow(summary: month)
                            }
                        }
                    }
                    if !projection.forecast.isEmpty {
                        Section("Previsão") {
                            ForEach(projection.forecast) { month in
                                MonthRow(summary: month)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Resumo")
            .refreshable { await store.reload() }
            .overlay { if store.isLoading && store.projection == nil { ProgressView() } }
        }
    }
}

private struct MonthRow: View {
    let summary: MonthlySummary

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(summary.month.monthYear)
                    .font(.headline)
                if summary.isForecast {
                    Text("previsto")
                        .font(.caption2)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(.quaternary, in: Capsule())
                }
                Spacer()
                Text(summary.balance.brl)
                    .font(.headline)
                    .foregroundStyle(summary.balance < 0 ? .red : .green)
            }
            HStack(spacing: 12) {
                Label(summary.income.brl, systemImage: "arrow.down.left")
                Label(summary.expenses.brl, systemImage: "arrow.up.right")
                if summary.committedExpenses < 0 {
                    Label(summary.committedExpenses.brl, systemImage: "calendar.badge.clock")
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }
}

private struct MonthDetail: View {
    let summary: MonthlySummary

    private var sortedCategories: [(category: String, total: Double)] {
        summary.byCategory
            .map { (category: $0.key, total: $0.value) }
            .sorted { $0.total < $1.total }
    }

    var body: some View {
        MonthRow(summary: summary)
        ForEach(sortedCategories, id: \.category) { entry in
            HStack {
                Text(entry.category)
                Spacer()
                Text(entry.total.brl)
                    .foregroundStyle(entry.total < 0 ? .primary : .green)
            }
            .font(.subheadline)
        }
    }
}
