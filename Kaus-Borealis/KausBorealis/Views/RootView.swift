import SwiftUI
import KausMedia

struct RootView: View {
    @State private var store = LedgerStore()

    var body: some View {
        TabView {
            SummaryView(store: store)
                .tabItem { Label("Resumo", systemImage: "chart.bar") }
            TransactionsView(store: store)
                .tabItem { Label("Lançamentos", systemImage: "list.bullet") }
            AccountsView(store: store)
                .tabItem { Label("Contas", systemImage: "creditcard") }
            RulesView(store: store)
                .tabItem { Label("Regras", systemImage: "slider.horizontal.3") }
            SettingsView(store: store)
                .tabItem { Label("Ajustes", systemImage: "gear") }
        }
        .task { await store.reload() }
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
