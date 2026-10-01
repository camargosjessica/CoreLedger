import Charts
import SwiftUI
import KausMedia

/// Painel principal: posição, plano do mês, tendências, categorias e
/// lançamentos, em cartões que se reorganizam conforme a largura da tela.
struct SummaryView: View {
    @Bindable var store: LedgerStore

    private let columns = [GridItem(.adaptive(minimum: 320), spacing: 16, alignment: .top)]

    private var currentPlan: PlanMonthTotals? {
        store.plan?.totals.first { $0.month == YearMonth(date: Date()) }
    }

    private var history: [MonthlySummary] { store.projection?.history ?? [] }
    private var forecast: [MonthlySummary] { store.projection?.forecast ?? [] }

    private var upcoming: [TransactionDTO] {
        let today = LedgerCalendar.startOfDay(Date())
        return store.transactions
            .filter { $0.isProjected && $0.date >= today }
            .sorted { $0.date < $1.date }
            .prefix(5)
            .map { $0 }
    }

    private var recent: [TransactionDTO] {
        Array(store.transactions.filter { !$0.isProjected }.prefix(6))
    }

    private var isEmpty: Bool {
        store.position == nil && history.isEmpty && forecast.isEmpty && store.transactions.isEmpty
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    if let position = store.position {
                        PositionHero(position: position)
                    }

                    if let current = history.last {
                        CategoryStrip(summary: current)
                    }

                    LazyVGrid(columns: columns, spacing: 16) {
                        if let currentPlan {
                            PlanMonthCard(totals: currentPlan)
                        }
                        if !history.isEmpty {
                            TrendCard(title: "Receitas", months: history, value: \.income, color: .green)
                            TrendCard(title: "Despesas", months: history, value: { abs($0.expenses) }, color: .red)
                        }
                        if let current = history.last {
                            CategoryBreakdownCard(summary: current)
                        }
                        if let plan = store.plan, !plan.totals.isEmpty {
                            CashFlowCard(year: store.planYear, totals: plan.totals)
                        }
                        if !upcoming.isEmpty {
                            TransactionListCard(title: "Próximas parcelas", transactions: upcoming, showsDate: true)
                        }
                        if !recent.isEmpty {
                            TransactionListCard(title: "Lançamentos recentes", transactions: recent, showsDate: false)
                        }
                        if !history.isEmpty || !forecast.isEmpty {
                            MonthsCard(history: history, forecast: forecast)
                        }
                    }
                }
                .padding()
            }
            .background(.background.secondary)
            .navigationTitle("Resumo")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    AccountFilter(store: store)
                }
            }
            .refreshable { await store.reload() }
            .overlay {
                if store.isLoading && store.projection == nil {
                    ProgressView()
                } else if isEmpty && !store.isLoading {
                    ContentUnavailableView(
                        "Nada por aqui ainda",
                        systemImage: "chart.bar.xaxis",
                        description: Text("Crie uma conta e importe um extrato para ver o painel.")
                    )
                }
            }
        }
    }
}

// MARK: - Posição

/// Cartão escuro de destaque: patrimônio líquido e o veredito
/// positiva/empatada/negativa, com guardado, disponível e cartão logo abaixo.
private struct PositionHero: View {
    let position: FinancialPosition

    private var statusColor: Color {
        switch position.status {
        case .positive: return .green
        case .even: return .orange
        case .negative: return .red
        }
    }

    private var savings: [AccountPosition] {
        position.accounts.filter { $0.kind.isSavings }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Patrimônio líquido")
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.7))
                    Text(position.net.brl)
                        .font(.system(size: 34, weight: .bold, design: .rounded).monospacedDigit())
                        .foregroundStyle(.white)
                        .minimumScaleFactor(0.6)
                        .lineLimit(1)
                }
                Spacer()
                DeltaPill(text: position.status.title, color: statusColor)
            }

            HStack(spacing: 12) {
                HeroMetric(title: "Disponível", value: position.available, symbol: "building.columns.fill", color: .blue)
                HeroMetric(title: "Guardado", value: position.saved, symbol: "lock.shield.fill", color: .teal)
                HeroMetric(title: "Cartão", value: -position.creditCardDebt, symbol: "creditcard.fill", color: .purple)
            }

            if !savings.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(savings) { account in
                            Label("\(account.name) · \(account.balance.brl)", systemImage: account.kind.symbol)
                                .font(.caption)
                                .foregroundStyle(.white.opacity(0.85))
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(.white.opacity(0.1), in: Capsule())
                        }
                    }
                }
            }

            if position.upcomingInstallments > 0 {
                Label(
                    "\(position.upcomingInstallments.brl) em parcelas ainda por vir",
                    systemImage: "calendar.badge.clock"
                )
                .font(.caption)
                .foregroundStyle(.white.opacity(0.7))
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            LinearGradient(
                colors: [Color(red: 0.10, green: 0.11, blue: 0.20), Color(red: 0.22, green: 0.18, blue: 0.40)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(cornerRadius: 22, style: .continuous)
        )
        .shadow(color: .black.opacity(0.15), radius: 12, y: 4)
    }
}

private struct HeroMetric: View {
    let title: String
    let value: Double
    let symbol: String
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            IconBadge(symbol: symbol, color: color, size: 28)
            Text(title)
                .font(.caption)
                .foregroundStyle(.white.opacity(0.7))
            Text(value.brl)
                .font(.subheadline.weight(.semibold).monospacedDigit())
                .foregroundStyle(.white)
                .minimumScaleFactor(0.7)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

// MARK: - Categorias

private struct CategoryTotal: Identifiable {
    var category: String
    var total: Double

    var id: String { category }
}

private func expenseTotals(_ summary: MonthlySummary) -> [CategoryTotal] {
    summary.byCategory
        .filter { $0.value < 0 }
        .map { CategoryTotal(category: $0.key, total: abs($0.value)) }
        .sorted { $0.total > $1.total }
}

/// Atalho visual do mês: um bloco colorido por categoria de despesa.
private struct CategoryStrip: View {
    let summary: MonthlySummary

    var body: some View {
        let totals = expenseTotals(summary)
        if !totals.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Text("Categorias · \(summary.month.monthYear)")
                    .font(.headline)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(totals) { entry in
                            CategoryTile(entry: entry)
                        }
                    }
                    .padding(.bottom, 4)
                }
            }
        }
    }
}

private struct CategoryTile: View {
    let entry: CategoryTotal

    var body: some View {
        let style = CategoryStyle.of(entry.category)
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: style.symbol)
                .font(.title2.weight(.semibold))
            Spacer(minLength: 0)
            Text(entry.category)
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)
            Text(entry.total.brl)
                .font(.caption.monospacedDigit())
                .opacity(0.9)
        }
        .foregroundStyle(.white)
        .padding(14)
        .frame(width: 140, height: 120, alignment: .leading)
        .background(style.color.gradient, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

/// Onde o dinheiro foi no mês, em barras horizontais com a cor de cada categoria.
private struct CategoryBreakdownCard: View {
    let summary: MonthlySummary

    var body: some View {
        let totals = Array(expenseTotals(summary).prefix(6))
        VStack(alignment: .leading, spacing: 12) {
            CardHeader(title: "Despesas por categoria")
            if totals.isEmpty {
                Text("Sem despesas neste mês.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Chart(totals) { entry in
                    BarMark(
                        x: .value("Total", entry.total),
                        y: .value("Categoria", entry.category)
                    )
                    .foregroundStyle(CategoryStyle.of(entry.category).color.gradient)
                    .cornerRadius(6)
                    .annotation(position: .trailing) {
                        Text(entry.total.brl)
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                }
                .chartXAxis(.hidden)
                .frame(height: CGFloat(totals.count) * 36)
            }
        }
        .card()
    }
}

// MARK: - Plano e tendências

/// O mês corrente da grade anual: quanto entrou, quanto saiu e quanto do
/// gasto é básico para sobreviver.
private struct PlanMonthCard: View {
    let totals: PlanMonthTotals

    /// Parte da receita já consumida pelas despesas.
    private var usage: Double {
        guard totals.income > 0 else { return totals.expenses < 0 ? 1 : 0 }
        return min(abs(totals.expenses) / totals.income, 1)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            CardHeader(title: "Plano do mês") {
                DeltaPill(text: totals.net.signedBRL, color: totals.net < 0 ? .red : .green)
            }
            ProgressView(value: usage)
                .tint(usage >= 1 ? Color.red : usage > 0.8 ? Color.orange : Color.green)
            Text("\(Int((usage * 100).rounded()))% da receita comprometida")
                .font(.caption)
                .foregroundStyle(.secondary)
            VStack(spacing: 6) {
                row("Receitas", totals.income, .green)
                row("Despesas", totals.expenses, .primary)
                row("Essenciais", totals.essentialExpenses, .orange)
                row("Guardado", totals.saved, .teal)
                Divider()
                row("Acumulado", totals.cumulative, totals.cumulative < 0 ? .red : .green)
            }
        }
        .card()
    }

    private func row(_ title: String, _ value: Double, _ color: Color) -> some View {
        HStack {
            Text(title)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value.brl)
                .monospacedDigit()
                .foregroundStyle(color)
        }
        .font(.subheadline)
    }
}

private struct ChartPoint: Identifiable {
    var label: String
    var value: Double

    var id: String { label }
}

/// Valor do último mês, variação em relação ao anterior e a curva dos últimos seis.
private struct TrendCard: View {
    let title: String
    let months: [MonthlySummary]
    let value: (MonthlySummary) -> Double
    let color: Color

    private var points: [ChartPoint] {
        months.suffix(6).map { ChartPoint(label: $0.month.shortMonth, value: value($0)) }
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
                .font(.title2.weight(.bold).monospacedDigit())
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

/// Saldo de cada mês do ano (barras) e o acumulado (linha), vindos da grade anual.
private struct CashFlowCard: View {
    let year: Int
    let totals: [PlanMonthTotals]

    private struct Point: Identifiable {
        var label: String
        var net: Double
        var cumulative: Double
        var isForecast: Bool

        var id: String { label }
    }

    private var points: [Point] {
        totals.map {
            Point(label: $0.month.startDate.shortMonth, net: $0.net, cumulative: $0.cumulative, isForecast: $0.isForecast)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            CardHeader(title: "Fluxo de caixa \(String(year))") {
                if let last = totals.last {
                    DeltaPill(text: last.cumulative.signedBRL, color: last.cumulative < 0 ? .red : .green)
                }
            }
            Chart(points) { point in
                BarMark(x: .value("Mês", point.label), y: .value("Saldo", point.net))
                    .foregroundStyle(point.net < 0 ? Color.red.gradient : Color.green.gradient)
                    .opacity(point.isForecast ? 0.45 : 1)
                    .cornerRadius(4)
                LineMark(x: .value("Mês", point.label), y: .value("Acumulado", point.cumulative))
                    .foregroundStyle(Color.indigo)
                    .interpolationMethod(.catmullRom)
                    .lineStyle(StrokeStyle(lineWidth: 2))
            }
            .chartYAxis { AxisMarks(position: .leading) }
            .frame(height: 180)
            HStack(spacing: 12) {
                Label("Saldo do mês", systemImage: "square.fill").foregroundStyle(.green)
                Label("Acumulado", systemImage: "line.diagonal").foregroundStyle(.indigo)
                Label("Previsto esmaecido", systemImage: "circle.lefthalf.filled").foregroundStyle(.secondary)
            }
            .font(.caption2)
        }
        .card()
    }
}

// MARK: - Listas

private struct TransactionListCard: View {
    let title: String
    let transactions: [TransactionDTO]
    let showsDate: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            CardHeader(title: title)
            ForEach(transactions) { transaction in
                HStack(spacing: 12) {
                    CategoryIcon(category: transaction.category, size: 32)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(transaction.description)
                            .font(.subheadline.weight(.medium))
                            .lineLimit(1)
                        Text(subtitle(for: transaction))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    Spacer()
                    Text(transaction.amount.brl)
                        .font(.subheadline.weight(.semibold).monospacedDigit())
                        .foregroundStyle(transaction.amount < 0 ? Color.red : Color.green)
                }
            }
        }
        .card()
    }

    private func subtitle(for transaction: TransactionDTO) -> String {
        var parts = [transaction.category ?? CategoryRule.uncategorizedDebit]
        if let installment = transaction.installment {
            parts.append("\(installment.number)/\(installment.total)")
        }
        if showsDate {
            parts.append(transaction.date.shortDay)
        }
        return parts.joined(separator: " · ")
    }
}

/// Histórico e previsão mês a mês, do mais recente para o mais antigo.
private struct MonthsCard: View {
    let history: [MonthlySummary]
    let forecast: [MonthlySummary]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            CardHeader(title: "Mês a mês")
            ForEach(Array(forecast.reversed()) + Array(history.reversed())) { month in
                MonthRow(summary: month)
                if month.id != history.first?.id {
                    Divider()
                }
            }
        }
        .card()
    }
}

private struct MonthRow: View {
    let summary: MonthlySummary

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(summary.month.monthYear)
                    .font(.subheadline.weight(.semibold))
                if summary.isForecast {
                    Text("previsto")
                        .font(.caption2)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(.quaternary, in: Capsule())
                }
                Spacer()
                Text(summary.balance.brl)
                    .font(.subheadline.weight(.semibold).monospacedDigit())
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
    }
}
