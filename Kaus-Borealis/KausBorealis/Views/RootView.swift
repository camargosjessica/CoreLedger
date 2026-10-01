import SwiftUI
import KausMedia

struct RootView: View {
    @State private var store = LedgerStore()

    var body: some View {
        // Barra lateral no Mac e no iPad, barra de abas no iPhone.
        TabView {
            Tab("Resumo", systemImage: "square.grid.2x2.fill") {
                SummaryView(store: store)
            }
            Tab("Lançamentos", systemImage: "list.bullet.rectangle.portrait.fill") {
                TransactionsView(store: store)
            }
            Tab("Plano", systemImage: "calendar") {
                PlanView(store: store)
            }
            Tab("Contas", systemImage: "creditcard.fill") {
                AccountsView(store: store)
            }
            Tab("Regras", systemImage: "slider.horizontal.3") {
                RulesView(store: store)
            }
            Tab("Ajustes", systemImage: "gearshape.fill") {
                SettingsView(store: store)
            }
        }
        .tabViewStyle(.sidebarAdaptable)
        .tint(.indigo)
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
