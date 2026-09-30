import Charts
import SwiftUI
import KausMedia

/// Resumo mensal realizado + previsão vinda de `GET /api/summary`.
struct SummaryView: View {
    @Bindable var store: LedgerStore

    var body: some View {
        NavigationStack {
            List {
                if let position = store.position {
                    Section("Posição") {
                        PositionCard(position: position)
                    }
                }

                if let totals = store.plan?.totals.first(where: { $0.month == YearMonth(date: Date()) }) {
                    Section("Plano do mês") {
                        PlanSummaryCard(totals: totals)
                    }
                }

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

/// O rodapé da grade anual trazido para o Resumo: o quanto o mês já comprometeu
/// e o quanto dele é básico para sobreviver.
private struct PlanSummaryCard: View {
    let totals: PlanMonthTotals

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            row("Receitas", totals.income)
            row("Despesas", totals.expenses)
            row("Essenciais", totals.essentialExpenses)
            row("Guardado", totals.saved)
            Divider()
            row("Saldo do mês", totals.net)
            row("Acumulado", totals.cumulative)
        }
        .padding(.vertical, 4)
    }

    private func row(_ title: String, _ value: Double) -> some View {
        HStack {
            Text(title)
            Spacer()
            Text(value.brl)
                .foregroundStyle(value < 0 ? Color.primary : Color.green)
        }
        .font(.subheadline)
    }
}

/// Guardado, disponível e dívida do cartão lado a lado, com o veredito do
/// líquido: é a pergunta "estou empatada?" respondida em uma linha.
private struct PositionCard: View {
    let position: FinancialPosition

    private var statusColor: Color {
        switch position.status {
        case .positive: return .green
        case .even: return .orange
        case .negative: return .red
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(position.status.title)
                        .font(.headline)
                        .foregroundStyle(statusColor)
                    Text("guardado + disponível − cartão")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text(position.net.brl)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(statusColor)
            }

            HStack(alignment: .top) {
                PositionItem(title: "Guardado", value: position.saved, color: .blue)
                Spacer()
                PositionItem(title: "Disponível", value: position.available, color: .primary)
                Spacer()
                PositionItem(title: "Cartão", value: -position.creditCardDebt, color: .red)
            }

            if position.upcomingInstallments > 0 {
                Label(
                    "\(position.upcomingInstallments.brl) em parcelas ainda por vir",
                    systemImage: "calendar.badge.clock"
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            let savings = position.accounts.filter { $0.kind.isSavings }
            if !savings.isEmpty {
                Divider()
                ForEach(savings) { account in
                    HStack {
                        Text(account.name)
                        Spacer()
                        Text(account.balance.brl)
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 4)
    }
}

private struct PositionItem: View {
    let title: String
    let value: Double
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value.brl)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(color)
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
