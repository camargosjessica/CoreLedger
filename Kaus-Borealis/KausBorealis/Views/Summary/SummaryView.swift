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
        store.plan.annual?.totals.first { $0.month == YearMonth(date: Date()) }
    }

    private var history: [MonthlySummary] { store.transactions.projection?.history ?? [] }
    private var forecast: [MonthlySummary] { store.transactions.projection?.forecast ?? [] }

    private var upcoming: [TransactionDTO] { Array(store.transactions.upcoming.prefix(5)) }

    private var limitStatuses: [CategoryLimitStatus] {
        let month = LedgerCalendar.startOfMonth(Date())
        let totals = history.first { $0.month == month }?.byCategory ?? [:]
        return CategoryLimitStatus.evaluate(limits: store.plan.limits, totalsByCategory: totals)
    }

    private var recent: [TransactionDTO] {
        Array(store.transactions.items.filter { !$0.isProjected }.prefix(6))
    }

    private var isEmpty: Bool {
        store.accounts.position == nil && history.isEmpty && forecast.isEmpty && store.transactions.items.isEmpty && upcoming.isEmpty
    }

    var body: some View {
        NavigationStack {
            CardScreen {
                if let position = store.accounts.position {
                    PositionHero(position: position)
                }

                if let current = history.last {
                    CategoryStrip(summary: current)
                }

                LazyVGrid(columns: columns, spacing: 16) {
                    if let currentPlan {
                        PlanMonthCard(totals: currentPlan)
                    }
                    if !limitStatuses.isEmpty {
                        LimitsCard(statuses: limitStatuses)
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
                if store.isLoading && store.transactions.projection == nil {
                    ProgressView()
                } else if isEmpty && !store.isLoading {
                    EmptyState(
                        symbol: "moon.stars",
                        title: "Nada por aqui ainda",
                        message: "Crie uma conta em Contas e importe um extrato em Lançamentos para ver o painel."
                    )
                }
            }
        }
    }
}

// MARK: - Posição
