import SwiftUI
import KausMedia

/// Seletor de conta usado nas abas que filtram por conta.
struct AccountFilter: View {
    @Bindable var store: LedgerStore

    var body: some View {
        Picker("Conta", selection: $store.selectedAccountID) {
            Text("Todas as contas").tag(UUID?.none)
            ForEach(store.accounts.all) { account in
                Text(account.name).tag(account.id)
            }
        }
        .pickerStyle(.menu)
    }
}

#Preview {
    RootView()
}
