import Charts
import SwiftUI
import KausMedia

/// Painel do mês: posição, plano do mês, categorias e lançamentos, em cartões
/// que se reorganizam conforme a largura da tela. Gráficos do ano e meses
/// futuros ficam em `PlanView`.
struct SummaryView: View {
    @Bindable var store: LedgerStore

    private let columns = [GridItem(.adaptive(minimum: 320), spacing: 16, alignment: .top)]

    private var currentPlan: PlanMonthTotals? {
        store.plan?.totals.first { $0.month == YearMonth(date: Date()) }
    }

    private var history: [MonthlySummary] { store.projection?.history ?? [] }
    private var forecast: [MonthlySummary] { store.projection?.forecast ?? [] }

    private var upcoming: [TransactionDTO] { Array(store.upcoming.prefix(5)) }

    private var recent: [TransactionDTO] {
        Array(store.transactions.filter { !$0.isProjected }.prefix(6))
    }

    private var isEmpty: Bool {
        store.position == nil && history.isEmpty && forecast.isEmpty && store.transactions.isEmpty && upcoming.isEmpty
    }

    var body: some View {
        NavigationStack {
            CardScreen {
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
                    if let current = history.last {
                        CategoryBreakdownCard(summary: current)
                    }
                    if !upcoming.isEmpty {
                        TransactionListCard(title: "Próximas parcelas", transactions: upcoming, showsDate: true)
                    }
                    if !recent.isEmpty {
                        TransactionListCard(title: "Lançamentos recentes", transactions: recent, showsDate: false)
                    }
                }
            }
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
        case .positive: return Palette.income
        case .even: return Palette.star
        case .negative: return Palette.expense
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
        .background {
            LinearGradient(
                colors: [Color(hex: 0x0E1430), Color(hex: 0x1F2B55)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .overlay(alignment: .topTrailing) {
                Circle()
                    .fill(Palette.star.opacity(0.22))
                    .frame(width: 220, height: 220)
                    .blur(radius: 70)
                    .offset(x: 60, y: -80)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(.white.opacity(0.08), lineWidth: 1)
        )
    }
}

private struct HeroMetric: View {
    let title: String
    let value: Double
    let symbol: String
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: symbol)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(color)
                    .frame(width: 24, height: 24)
                    .background(color.opacity(0.2), in: Circle())
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.7))
            }
            Text(value.brl)
                .font(.subheadline.weight(.semibold).monospacedDigit())
                .foregroundStyle(.white)
                .minimumScaleFactor(0.7)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
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
        VStack(alignment: .leading, spacing: 6) {
            Image(systemName: style.symbol)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(style.color)
                .frame(width: 32, height: 32)
                .background(style.color.opacity(0.16), in: Circle())
            Spacer(minLength: 0)
            Text(displayName(entry.category))
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)
            Text(entry.total.brl)
                .font(.system(.callout, design: .rounded).weight(.bold).monospacedDigit())
        }
        .padding(14)
        .frame(width: 150, height: 120, alignment: .leading)
        .background(Palette.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(alignment: .bottom) {
            Capsule()
                .fill(style.color)
                .frame(height: 3)
                .padding(.horizontal, 14)
        }
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(Palette.hairline, lineWidth: 1)
        )
    }
}

/// Onde o dinheiro foi no mês: rosca com o total no centro e a fatia de cada categoria.
private struct CategoryBreakdownCard: View {
    let summary: MonthlySummary

    var body: some View {
        let all = expenseTotals(summary)
        let total = all.reduce(0) { $0 + $1.total }
        let top = Array(all.prefix(6))
        VStack(alignment: .leading, spacing: 14) {
            CardHeader(title: "Despesas por categoria")
            if top.isEmpty {
                Text("Sem despesas neste mês.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Chart(top) { entry in
                    SectorMark(
                        angle: .value("Total", entry.total),
                        innerRadius: .ratio(0.64),
                        angularInset: 1.5
                    )
                    .cornerRadius(4)
                    .foregroundStyle(CategoryStyle.of(entry.category).color)
                }
                .chartBackground { _ in
                    VStack(spacing: 2) {
                        Text("Total")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(total.brl)
                            .font(.system(.headline, design: .rounded).weight(.bold).monospacedDigit())
                            .minimumScaleFactor(0.6)
                            .lineLimit(1)
                    }
                    .padding(.horizontal, 40)
                }
                .frame(height: 180)
                VStack(spacing: 8) {
                    ForEach(top) { entry in
                        HStack(spacing: 8) {
                            Circle()
                                .fill(CategoryStyle.of(entry.category).color)
                                .frame(width: 8, height: 8)
                            Text(displayName(entry.category))
                                .font(.subheadline)
                                .lineLimit(1)
                            Spacer()
                            Text(entry.total.brl)
                                .font(.subheadline.monospacedDigit())
                            Text(percent(entry.total, of: total))
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.secondary)
                                .frame(width: 38, alignment: .trailing)
                        }
                    }
                }
            }
        }
        .card()
    }

    private func percent(_ value: Double, of total: Double) -> String {
        guard total > 0 else { return "" }
        return "\(Int((value / total * 100).rounded()))%"
    }
}

/// Primeira letra maiúscula, sem mexer no restante ("cartão de crédito" → "Cartão de crédito").
private func displayName(_ category: String) -> String {
    category.prefix(1).uppercased() + category.dropFirst()
}

// MARK: - Plano e tendências

/// O mês corrente da grade anual: quanto entrou, quanto saiu e quanto do
/// gasto é básico para sobreviver.
private struct PlanMonthCard: View {
    let totals: PlanMonthTotals

    /// Despesas sobre receita; passa de 1 quando se gasta mais do que entra.
    private var usage: Double {
        guard totals.income > 0 else { return totals.expenses < 0 ? .infinity : 0 }
        return abs(totals.expenses) / totals.income
    }

    private var usageLabel: String {
        usage.isFinite
            ? "\(Int((usage * 100).rounded()))% da receita comprometida"
            : "Despesas sem receita no mês"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            CardHeader(title: "Plano do mês") {
                DeltaPill(text: totals.net.signedBRL, color: totals.net < 0 ? Palette.expense : Palette.income)
            }
            ProgressView(value: min(usage, 1))
                .tint(usage >= 1 ? Palette.expense : usage > 0.8 ? Palette.star : Palette.income)
            Text(usageLabel)
                .font(.caption)
                .foregroundStyle(.secondary)
            VStack(spacing: 6) {
                row("Receitas", totals.income, Palette.income)
                row("Despesas", totals.expenses, .primary)
                row("Essenciais", totals.essentialExpenses, Palette.star)
                row("Guardado", totals.saved, .teal)
                Divider()
                row("Acumulado", totals.cumulative, totals.cumulative < 0 ? Palette.expense : Palette.income)
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
                        .foregroundStyle(transaction.amount < 0 ? Palette.expense : Palette.income)
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
