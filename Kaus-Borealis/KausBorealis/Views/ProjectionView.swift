import Charts
import SwiftUI
import KausMedia

/// Meses passados e próximos lado a lado. O que já aconteceu aparece cheio;
/// o previsto aparece esmaecido e separa o que já está lançado (parcelas e
/// lançamentos futuros) da estimativa pela média dos últimos meses.
struct ProjectionView: View {
    @Bindable var store: LedgerStore

    private let columns = [GridItem(.adaptive(minimum: 340), spacing: 16, alignment: .top)]

    private var history: [MonthlySummary] { store.projection?.history ?? [] }
    private var forecast: [MonthlySummary] { store.projection?.forecast ?? [] }

    private var nextMonth: MonthlySummary? { forecast.first }

    private var committedAhead: Double {
        forecast.reduce(0) { $0 + $1.committedExpenses }
    }

    private var forecastBalance: Double {
        forecast.reduce(0) { $0 + $1.balance }
    }

    var body: some View {
        NavigationStack {
            CardScreen {
                if !forecast.isEmpty {
                    MetricGrid {
                        if let nextMonth {
                            MetricTile(
                                title: "Próximo mês",
                                value: nextMonth.balance,
                                symbol: "calendar",
                                color: Palette.star,
                                valueColor: nextMonth.balance < 0 ? Palette.expense : Palette.income,
                                caption: "Saldo previsto de \(nextMonth.month.monthYear)"
                            )
                        }
                        MetricTile(
                            title: "Já lançado à frente",
                            value: committedAhead,
                            symbol: "calendar.badge.clock",
                            color: Palette.expense,
                            caption: "Parcelas e lançamentos futuros dos próximos \(forecast.count) meses"
                        )
                        MetricTile(
                            title: "Saldo dos próximos meses",
                            value: forecastBalance,
                            symbol: "chart.line.uptrend.xyaxis",
                            color: Palette.income,
                            valueColor: forecastBalance < 0 ? Palette.expense : Palette.income,
                            caption: "Soma dos \(forecast.count) meses previstos"
                        )
                    }
                }

                if !history.isEmpty || !forecast.isEmpty {
                    IncomeExpenseCard(history: history, forecast: forecast)
                }

                LazyVGrid(columns: columns, spacing: 16) {
                    if !history.isEmpty {
                        TrendCard(title: "Receitas", months: history, value: \.income, color: Palette.income)
                        TrendCard(title: "Despesas", months: history, value: { abs($0.expenses) }, color: Palette.expense)
                    }
                    if let plan = store.plan, !plan.totals.isEmpty {
                        CashFlowCard(year: store.planYear, totals: plan.totals)
                    }
                    if !history.isEmpty || !forecast.isEmpty {
                        MonthsCard(history: history, forecast: forecast)
                    }
                }
            }
            .navigationTitle("Projeção")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    AccountFilter(store: store)
                }
            }
            .refreshable { await store.reload() }
            .overlay {
                if store.isLoading && store.projection == nil {
                    ProgressView()
                } else if history.isEmpty && forecast.isEmpty && !store.isLoading {
                    ContentUnavailableView(
                        "Sem meses para projetar",
                        systemImage: "chart.line.uptrend.xyaxis",
                        description: Text("Importe extratos ou lance compromissos futuros para ver a projeção.")
                    )
                }
            }
        }
    }
}

// MARK: - Entradas e saídas

/// Entradas e saídas de cada mês em barras lado a lado, com a linha do saldo.
/// Os meses previstos ficam esmaecidos e o mês atual é marcado com uma régua.
private struct IncomeExpenseCard: View {
    let history: [MonthlySummary]
    let forecast: [MonthlySummary]

    private struct Bar: Identifiable {
        var label: String
        var kind: String
        var value: Double
        var isForecast: Bool

        var id: String { label + kind }
    }

    private var months: [MonthlySummary] { Array(history.suffix(6)) + forecast }

    private var bars: [Bar] {
        months.flatMap { month in
            [
                Bar(label: month.month.shortMonthYear, kind: "Entradas", value: month.income, isForecast: month.isForecast),
                Bar(label: month.month.shortMonthYear, kind: "Saídas", value: abs(month.expenses), isForecast: month.isForecast),
            ]
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            CardHeader(title: "Entradas e saídas")
            Chart {
                ForEach(bars) { bar in
                    BarMark(x: .value("Mês", bar.label), y: .value("Valor", bar.value))
                        .position(by: .value("Tipo", bar.kind))
                        .foregroundStyle(by: .value("Tipo", bar.kind))
                        .opacity(bar.isForecast ? 0.4 : 1)
                        .cornerRadius(4)
                }
                ForEach(months) { month in
                    LineMark(x: .value("Mês", month.month.shortMonthYear), y: .value("Saldo", month.balance))
                        .foregroundStyle(Palette.star)
                        .interpolationMethod(.catmullRom)
                        .lineStyle(StrokeStyle(lineWidth: 2, dash: month.isForecast ? [4, 3] : []))
                        .symbol(.circle)
                        .symbolSize(30)
                }
                if let current = history.last {
                    RuleMark(x: .value("Mês", current.month.shortMonthYear))
                        .foregroundStyle(.secondary.opacity(0.4))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [2, 3]))
                        .annotation(position: .top, alignment: .center) {
                            Text("hoje")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                }
            }
            .chartForegroundStyleScale(["Entradas": Palette.income, "Saídas": Palette.expense])
            .chartLegend(.hidden)
            .chartYAxis { AxisMarks(position: .leading) }
            .frame(height: 240)
            HStack(spacing: 14) {
                Label("Entradas", systemImage: "square.fill").foregroundStyle(Palette.income)
                Label("Saídas", systemImage: "square.fill").foregroundStyle(Palette.expense)
                Label("Saldo", systemImage: "circle").foregroundStyle(Palette.star)
                Label("Previsto esmaecido", systemImage: "circle.lefthalf.filled").foregroundStyle(.secondary)
            }
            .font(.caption2)
        }
        .card()
    }
}

// MARK: - Tendências

private struct ChartPoint: Identifiable {
    var month: Date
    var value: Double

    var id: Date { month }
    var label: String { month.shortMonthYear }
}

/// Valor do último mês, variação em relação ao anterior e a curva dos últimos seis.
private struct TrendCard: View {
    let title: String
    let months: [MonthlySummary]
    let value: (MonthlySummary) -> Double
    let color: Color

    private var points: [ChartPoint] {
        months.suffix(6).map { ChartPoint(month: $0.month, value: value($0)) }
    }

    var body: some View {
        let latest = months.last.map(value) ?? 0
        let previous = months.dropLast().last.map(value)
        VStack(alignment: .leading, spacing: 8) {
            CardHeader(title: title) {
                if let previous {
                    DeltaPill(text: (latest - previous).signedBRL, color: color)
                }
            }
            Text(latest.brl)
                .font(.system(.title2, design: .rounded).weight(.bold).monospacedDigit())
                .foregroundStyle(color)
            Chart(points) { point in
                AreaMark(x: .value("Mês", point.label), y: .value("Valor", point.value))
                    .foregroundStyle(
                        LinearGradient(colors: [color.opacity(0.35), color.opacity(0.02)], startPoint: .top, endPoint: .bottom)
                    )
                    .interpolationMethod(.catmullRom)
                LineMark(x: .value("Mês", point.label), y: .value("Valor", point.value))
                    .foregroundStyle(color)
                    .interpolationMethod(.catmullRom)
                    .lineStyle(StrokeStyle(lineWidth: 2.5))
            }
            .chartYAxis { AxisMarks(position: .leading) }
            .frame(height: 140)
        }
        .card()
    }
}

/// Fluxo de caixa de cada mês do ano (barras) e o acumulado (linha), vindos da grade anual.
private struct CashFlowCard: View {
    let year: Int
    let totals: [PlanMonthTotals]

    private struct Point: Identifiable {
        var label: String
        var cashFlow: Double
        var cumulative: Double
        var isForecast: Bool

        var id: String { label }
    }

    private var points: [Point] {
        totals.map {
            Point(label: $0.month.startDate.shortMonth, cashFlow: $0.cashFlow, cumulative: $0.cumulative, isForecast: $0.isForecast)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            CardHeader(title: "Fluxo de caixa \(String(year))") {
                if let last = totals.last {
                    DeltaPill(text: last.cumulative.signedBRL, color: last.cumulative < 0 ? Palette.expense : Palette.income)
                }
            }
            Chart(points) { point in
                BarMark(x: .value("Mês", point.label), y: .value("Fluxo", point.cashFlow))
                    .foregroundStyle(point.cashFlow < 0 ? Palette.expense.gradient : Palette.income.gradient)
                    .opacity(point.isForecast ? 0.4 : 1)
                    .cornerRadius(4)
                LineMark(x: .value("Mês", point.label), y: .value("Acumulado", point.cumulative))
                    .foregroundStyle(Palette.star)
                    .interpolationMethod(.catmullRom)
                    .lineStyle(StrokeStyle(lineWidth: 2))
            }
            .chartYAxis { AxisMarks(position: .leading) }
            .frame(height: 180)
            HStack(spacing: 12) {
                Label("Fluxo do mês", systemImage: "square.fill").foregroundStyle(Palette.income)
                Label("Acumulado", systemImage: "line.diagonal").foregroundStyle(Palette.star)
                Label("Previsto esmaecido", systemImage: "circle.lefthalf.filled").foregroundStyle(.secondary)
            }
            .font(.caption2)
        }
        .card()
    }
}

// MARK: - Mês a mês

/// Meses previstos primeiro (do mais distante ao próximo), depois os realizados.
private struct MonthsCard: View {
    let history: [MonthlySummary]
    let forecast: [MonthlySummary]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            CardHeader(title: "Mês a mês")
            if !forecast.isEmpty {
                sectionLabel("Previsto")
                ForEach(Array(forecast.reversed())) { month in
                    MonthRow(summary: month)
                    Divider()
                }
            }
            if !history.isEmpty {
                sectionLabel("Realizado")
                ForEach(Array(history.reversed())) { month in
                    MonthRow(summary: month)
                    if month.id != history.first?.id {
                        Divider()
                    }
                }
            }
        }
        .card()
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text.uppercased())
            .font(.caption2.weight(.semibold))
            .foregroundStyle(.secondary)
            .padding(.top, 4)
    }
}

private struct MonthRow: View {
    let summary: MonthlySummary

    /// Parte das saídas previstas que não vem de lançamentos futuros, e sim da média.
    private var estimatedExpenses: Double { summary.expenses - summary.committedExpenses }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(summary.month.monthYear)
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Text(summary.balance.brl)
                    .font(.subheadline.weight(.semibold).monospacedDigit())
                    .foregroundStyle(summary.balance < 0 ? Palette.expense : Palette.income)
            }
            .opacity(summary.isForecast ? 0.75 : 1)
            HStack(spacing: 12) {
                Label(summary.income.brl, systemImage: "arrow.down.left")
                Label(summary.expenses.brl, systemImage: "arrow.up.right")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            if summary.isForecast {
                HStack(spacing: 6) {
                    if summary.committedExpenses < 0 {
                        Tag(text: "já lançado \(summary.committedExpenses.brl)", color: Palette.expense)
                    }
                    if estimatedExpenses < 0 {
                        Tag(text: "média \(estimatedExpenses.brl)", color: .secondary)
                    }
                }
            }
        }
    }
}

private struct Tag: View {
    let text: String
    let color: Color

    var body: some View {
        Text(text)
            .font(.caption2.monospacedDigit())
            .foregroundStyle(color)
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .background(Palette.raised, in: Capsule())
    }
}
