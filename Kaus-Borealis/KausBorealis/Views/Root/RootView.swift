import SwiftUI
import KausMedia

struct RootView: View {
    @Environment(LedgerStore.self) private var store
    @State private var selection: SidebarItem = .summary
    @AppStorage(AppAppearance.storageKey) private var appearance: AppAppearance = .system
    @AppStorage(AppAccent.storageKey) private var accent: AppAccent = .amber

    private var banks: [SidebarAccount] { sidebarAccounts { $0 == .checking || $0 == .cash } }
    private var savings: [SidebarAccount] { sidebarAccounts { $0.isSavings } }
    private var cards: [SidebarAccount] { sidebarAccounts { $0 == .creditCard } }

    private func sidebarAccounts(_ include: (AccountKind) -> Bool) -> [SidebarAccount] {
        store.accounts.all
            .filter { include($0.kind) }
            .compactMap { account in account.id.map { SidebarAccount(id: $0, account: account) } }
            .sorted { $0.account.name.localizedStandardCompare($1.account.name) == .orderedAscending }
    }

    var body: some View {
        // Barra lateral no Mac e no iPad, barra de abas no iPhone. Cada conta
        // tem a sua entrada na barra lateral; no iPhone elas ficam em Contas.
        TabView(selection: $selection) {
            Tab("Resumo", systemImage: "sparkles", value: SidebarItem.summary) {
                SummaryView()
            }
            TabSection("Dia a dia") {
                Tab("Lançamentos", systemImage: "list.bullet.rectangle.portrait.fill", value: SidebarItem.transactions) {
                    TransactionsView()
                }
            }
            TabSection("Planejar") {
                Tab("Análise", systemImage: "chart.bar.xaxis", value: SidebarItem.analysis) {
                    AnalysisView()
                }
                Tab("Plano", systemImage: "calendar", value: SidebarItem.plan) {
                    PlanView()
                }
            }
            accountSection("Bancos", banks)
            accountSection("Cartões", cards)
            accountSection("Caixinhas", savings)
            TabSection("Configurar") {
                Tab("Contas", systemImage: "creditcard.fill", value: SidebarItem.accounts) {
                    AccountsView()
                }
                Tab("Regras", systemImage: "slider.horizontal.3", value: SidebarItem.rules) {
                    RulesView()
                }
                Tab("Ajustes", systemImage: "gearshape.fill", value: SidebarItem.settings) {
                    SettingsView()
                }
            }
        }
        .tabViewStyle(.sidebarAdaptable)
        .tabViewSidebarHeader { SidebarBrand() }
        .tabViewSidebarFooter { SidebarNetWorth(accounts: store.accounts.all) }
        .tint(accent.color)
        .preferredColorScheme(appearance.colorScheme)
        .task { await store.reload() }
        .onChange(of: store.accounts.all) {
            if case let .account(id) = selection, !store.accounts.all.contains(where: { $0.id == id }) {
                selection = .accounts
            }
        }
        .alert(
            "Erro",
            isPresented: Binding(
                get: { store.errorMessage != nil },
                set: { if !$0 { store.errorMessage = nil } }
            )
        ) {
            Button("Ok", role: .cancel) { store.errorMessage = nil }
        } message: {
            Text(store.errorMessage ?? "")
        }
    }

    private func accountSection(_ title: String, _ accounts: [SidebarAccount]) -> some TabContent<SidebarItem> {
        TabSection(title) {
            ForEach(accounts) { item in
                Tab(item.account.name, systemImage: item.account.kind.symbol, value: SidebarItem.account(item.id)) {
                    NavigationStack {
                        AccountDetailView(accountID: item.id)
                    }
                }
                .badge(Text(item.account.balance?.brl ?? ""))
                .defaultVisibility(.hidden, for: .tabBar)
            }
        }
        .defaultVisibility(.hidden, for: .tabBar)
    }
}

enum SidebarItem: Hashable {
    case summary
    case transactions
    case analysis
    case plan
    case accounts
    case rules
    case settings
    case account(UUID)
}

#if DEBUG
    #Preview {
        RootView().previewLedger()
    }
#endif
