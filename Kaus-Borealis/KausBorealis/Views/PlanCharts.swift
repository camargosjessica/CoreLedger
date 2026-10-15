import Charts
import SwiftUI
import KausMedia

/// Gráficos do ano no Plano. Vêm da grade anual: o mês que já aconteceu usa o
/// extrato e o que ainda vai acontecer usa os compromissos cadastrados.
struct PlanCharts: View {
    let year: Int
    let totals: [PlanMonthTotals]

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .top, spacing: 16) {
                IncomeExpenseCard(year: year, totals: totals)
                    .frame(minWidth: 340)
                CashFlowCard(year: year, totals: totals)
                    .frame(minWidth: 340)
            }
            VStack(spacing: 16) {
                IncomeExpenseCard(year: year, totals: totals)
                CashFlowCard(year: year, totals: totals)
            }
        }
    }
}

private func forecastNote(_ totals: [PlanMonthTotals]) -> some View {
    HStack(spacing: 12) {
        if totals.contains(where: \.isForecast) {
            Label("Esmaecido: compromissos cadastrados", systemImage: "circle.lefthalf.filled")
        }
    }
    .font(.caption2)
    .foregroundStyle(.secondary)
}

/// Entradas e saídas de cada mês em barras lado a lado, com a linha do saldo
/// (entradas − saídas) e uma régua no mês atual.
private struct IncomeExpenseCard: View {
    let year: Int
    let totals: [PlanMonthTotals]

    private struct Bar: Identifiable {
        var label: String
        var kind: String
        var value: Double
        var isForecast: Bool

        var id: String { label + kind }
    }

    private var bars: [Bar] {
        totals.flatMap { month in
            [
                Bar(label: month.month.startDate.shortMonth, kind: "Entradas", value: month.income, isForecast: month.isForecast),
                Bar(label: month.month.startDate.shortMonth, kind: "Saídas", value: abs(month.expenses), isForecast: month.isForecast),
            ]
        }
    }

    private var currentMonth: PlanMonthTotals? {
        totals.first { $0.month == YearMonth(date: Date()) }
    }

    var body: some View {
        let net = totals.reduce(0) { $0 + $1.net }
        VStack(alignment: .leading, spacing: 12) {
            CardHeader(title: "Entradas e saídas \(String(year))") {
                DeltaPill(text: net.signedBRL, color: net < 0 ? Palette.expense : Palette.income)
            }
            Chart {
                ForEach(bars) { bar in
                    BarMark(x: .value("Mês", bar.label), y: .value("Valor", bar.value))
                        .position(by: .value("Tipo", bar.kind))
                        .foregroundStyle(by: .value("Tipo", bar.kind))
                        .opacity(bar.isForecast ? 0.4 : 1)
                        .cornerRadius(3)
                }
                ForEach(totals) { month in
                    LineMark(x: .value("Mês", month.month.startDate.shortMonth), y: .value("Saldo", month.net))
                        .foregroundStyle(Palette.star)
                        .interpolationMethod(.catmullRom)
                        .lineStyle(StrokeStyle(lineWidth: 2))
                        .symbol(.circle)
                        .symbolSize(24)
                }
                if let currentMonth {
                    RuleMark(x: .value("Mês", currentMonth.month.startDate.shortMonth))
                        .foregroundStyle(.secondary.opacity(0.4))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [2, 3]))
                        .annotation(position: .overlay, alignment: .top) {
                            Text("hoje")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                }
            }
            .chartForegroundStyleScale(["Entradas": Palette.income, "Saídas": Palette.expense])
            .chartLegend(.hidden)
            .chartYAxis { AxisMarks(position: .leading) }
            .frame(height: 220)
            HStack(spacing: 12) {
                Label("Entradas", systemImage: "square.fill").foregroundStyle(Palette.income)
                Label("Saídas", systemImage: "square.fill").foregroundStyle(Palette.expense)
                Label("Saldo", systemImage: "circle").foregroundStyle(Palette.star)
            }
            .font(.caption2)
            forecastNote(totals)
        }
        .card()
    }
}

/// O que de fato entrou ou saiu da conta em cada mês (barras, já descontando o
/// que foi guardado) e o acumulado do ano (linha).
private struct CashFlowCard: View {
    let year: Int
    let totals: [PlanMonthTotals]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            CardHeader(title: "Fluxo de caixa \(String(year))") {
                if let last = totals.last {
                    DeltaPill(text: last.cumulative.signedBRL, color: last.cumulative < 0 ? Palette.expense : Palette.income)
                }
            }
            Chart(totals) { month in
                BarMark(x: .value("Mês", month.month.startDate.shortMonth), y: .value("Fluxo", month.cashFlow))
                    .foregroundStyle(month.cashFlow < 0 ? Palette.expense.gradient : Palette.income.gradient)
                    .opacity(month.isForecast ? 0.4 : 1)
                    .cornerRadius(3)
                LineMark(x: .value("Mês", month.month.startDate.shortMonth), y: .value("Acumulado", month.cumulative))
                    .foregroundStyle(Palette.star)
                    .interpolationMethod(.catmullRom)
                    .lineStyle(StrokeStyle(lineWidth: 2))
            }
            .chartYAxis { AxisMarks(position: .leading) }
            .frame(height: 220)
            HStack(spacing: 12) {
                Label("Fluxo do mês", systemImage: "square.fill").foregroundStyle(Palette.income)
                Label("Acumulado", systemImage: "line.diagonal").foregroundStyle(Palette.star)
            }
            .font(.caption2)
            forecastNote(totals)
        }
        .card()
    }
}
