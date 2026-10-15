import SwiftUI
import KausMedia

struct RootView: View {
    @State private var store = LedgerStore()
    @State private var selection: SidebarItem = .summary
    @AppStorage(AppAppearance.storageKey) private var appearance: AppAppearance = .system
    @AppStorage(AppAccent.storageKey) private var accent: AppAccent = .amber

    private var banks: [SidebarAccount] { sidebarAccounts { $0 == .checking || $0 == .cash } }
    private var savings: [SidebarAccount] { sidebarAccounts { $0.isSavings } }
    private var cards: [SidebarAccount] { sidebarAccounts { $0 == .creditCard } }

    private func sidebarAccounts(_ include: (AccountKind) -> Bool) -> [SidebarAccount] {
        store.accounts
            .filter { include($0.kind) }
            .compactMap { account in account.id.map { SidebarAccount(id: $0, account: account) } }
            .sorted { $0.account.name.localizedStandardCompare($1.account.name) == .orderedAscending }
    }

    var body: some View {
        // Barra lateral no Mac e no iPad, barra de abas no iPhone. Cada conta
        // tem a sua entrada na barra lateral; no iPhone elas ficam em Contas.
        TabView(selection: $selection) {
            Tab("Resumo", systemImage: "sparkles", value: SidebarItem.summary) {
                SummaryView(store: store)
            }
            TabSection("Dia a dia") {
                Tab("Lançamentos", systemImage: "list.bullet.rectangle.portrait.fill", value: SidebarItem.transactions) {
                    TransactionsView(store: store)
                }
            }
            TabSection("Planejar") {
                Tab("Análise", systemImage: "chart.bar.xaxis", value: SidebarItem.analysis) {
                    AnalysisView(store: store)
                }
                Tab("Plano", systemImage: "calendar", value: SidebarItem.plan) {
                    PlanView(store: store)
                }
            }
            accountSection("Bancos", banks)
            accountSection("Cartões", cards)
            accountSection("Caixinhas", savings)
            TabSection("Configurar") {
                Tab("Contas", systemImage: "creditcard.fill", value: SidebarItem.accounts) {
                    AccountsView(store: store)
                }
                Tab("Regras", systemImage: "slider.horizontal.3", value: SidebarItem.rules) {
                    RulesView(store: store)
                }
                Tab("Ajustes", systemImage: "gearshape.fill", value: SidebarItem.settings) {
                    SettingsView(store: store)
                }
            }
        }
        .tabViewStyle(.sidebarAdaptable)
        .tabViewSidebarHeader { SidebarBrand() }
        .tabViewSidebarFooter { SidebarNetWorth(store: store) }
        .tint(accent.color)
        .preferredColorScheme(appearance.colorScheme)
        .task { await store.reload() }
        .onChange(of: store.accounts) {
            if case let .account(id) = selection, !store.accounts.contains(where: { $0.id == id }) {
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
                        AccountDetailView(store: store, accountID: item.id)
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

private struct SidebarAccount: Identifiable {
    let id: UUID
    let account: AccountDTO
}

/// Marca no topo da barra lateral.
private struct SidebarBrand: View {
    var body: some View {
        HStack(spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(LinearGradient(colors: [Color(hex: 0x1B2440), Color(hex: 0x0A0F1F)], startPoint: .top, endPoint: .bottom))
                Image(systemName: "sparkle")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(Palette.star)
            }
            .frame(width: 30, height: 30)
            VStack(alignment: .leading, spacing: 0) {
                Text("CoreLedger")
                    .font(.system(.headline, design: .rounded))
                Text("finanças pessoais")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Patrimônio sempre à vista no rodapé da barra lateral.
private struct SidebarNetWorth: View {
    let store: LedgerStore

    private var total: Double { store.accounts.reduce(0) { $0 + ($1.balance ?? 0) } }

    var body: some View {
        if !store.accounts.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                Text("Patrimônio")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(total.brl)
                    .font(.system(.title3, design: .rounded).weight(.bold).monospacedDigit())
                    .foregroundStyle(total < 0 ? Palette.expense : Color.primary)
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Palette.raised, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
    }
}

/// Seletor de conta usado nas abas que filtram por conta.
struct AccountFilter: View {
    @Bindable var store: LedgerStore

    var body: some View {
        Picker("Conta", selection: $store.selectedAccountID) {
            Text("Todas as contas").tag(UUID?.none)
            ForEach(store.accounts) { account in
                Text(account.name).tag(account.id)
            }
        }
        .pickerStyle(.menu)
    }
}

#Preview {
    RootView()
}
