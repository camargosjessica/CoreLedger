import SwiftUI
import KausMedia

/// Seletor de conta usado nas abas que filtram por conta.
struct AccountFilter: View {
    @Environment(LedgerStore.self) private var store

    var body: some View {
        Picker("Conta", selection: Bindable(store).selectedAccountID) {
            Text("Todas as contas").tag(UUID?.none)
            ForEach(store.accounts.all) { account in
                Text(account.name).tag(account.id)
            }
        }
        .pickerStyle(.menu)
    }
}

#if DEBUG
#Preview {
    AccountFilter().previewLedger()
}
#endif
