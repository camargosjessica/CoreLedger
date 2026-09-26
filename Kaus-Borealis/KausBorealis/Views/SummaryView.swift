import Charts
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
                    if !projection.history.isEmpty || !projection.forecast.isEmpty {
                        Section("Entradas e saídas") {
                            BalanceChart(
                                months: Array(projection.history.suffix(6)) + Array(projection.forecast.prefix(3))
                            )
                        }
                    }
                    if let current = projection.history.last {
                        Section("Mês atual") {
                            CategoryChart(summary: current)
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
                    .foregroundStyle(summary.balance < 0 ? Color.red : Color.green)
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

/// Receitas e despesas por mês; os meses previstos ficam esmaecidos para não
/// serem lidos como realizado.
private struct BalanceChart: View {
    let months: [MonthlySummary]

    private struct Bar: Identifiable {
        var label: String
        var kind: String
        var value: Double

        var id: String { "\(label)-\(kind)" }
    }

    private var bars: [Bar] {
        months.flatMap { month -> [Bar] in
            let label = month.isForecast ? "\(month.month.monthYear) (prev.)" : month.month.monthYear
            return [
                Bar(label: label, kind: "Receitas", value: month.income),
                Bar(label: label, kind: "Despesas", value: abs(month.expenses))
            ]
        }
    }

    var body: some View {
        Chart(bars) { bar in
            BarMark(
                x: .value("Mês", bar.label),
                y: .value("Valor", bar.value)
            )
            .foregroundStyle(by: .value("Tipo", bar.kind))
            .position(by: .value("Tipo", bar.kind))
        }
        .chartForegroundStyleScale(["Receitas": Color.green, "Despesas": Color.red])
        .frame(height: 200)
        .padding(.vertical, 4)
    }
}

/// Onde o dinheiro foi no mês: só despesas, porque misturar salário com gastos
/// numa rosca esconde o que interessa.
private struct CategoryChart: View {
    let summary: MonthlySummary

    private var slices: [CategoryTotal] {
        summary.byCategory
            .filter { $0.value < 0 }
            .map { CategoryTotal(category: $0.key, total: abs($0.value)) }
            .sorted { $0.total > $1.total }
    }

    var body: some View {
        if slices.isEmpty {
            Text("Sem despesas neste mês.")
                .font(.caption)
                .foregroundStyle(.secondary)
        } else {
            Chart(slices) { slice in
                SectorMark(
                    angle: .value("Total", slice.total),
                    innerRadius: .ratio(0.6),
                    angularInset: 1
                )
                .foregroundStyle(by: .value("Categoria", slice.category))
            }
            .frame(height: 220)
            .padding(.vertical, 4)
        }
    }
}

private struct CategoryTotal: Identifiable {
    var category: String
    var total: Double

    var id: String { category }
}

private struct MonthDetail: View {
    let summary: MonthlySummary

    private var sortedCategories: [CategoryTotal] {
        summary.byCategory
            .map { CategoryTotal(category: $0.key, total: $0.value) }
            .sorted { $0.total < $1.total }
    }

    var body: some View {
        MonthRow(summary: summary)
        ForEach(sortedCategories) { entry in
            HStack {
                Text(entry.category)
                Spacer()
                Text(entry.total.brl)
                    .foregroundStyle(entry.total < 0 ? Color.primary : Color.green)
            }
            .font(.subheadline)
        }
    }
}
