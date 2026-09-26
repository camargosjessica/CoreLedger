import SwiftUI
import KausMedia

struct SettingsView: View {
    @Bindable var store: LedgerStore

    @State private var address = ""
    @State private var token = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("Servidor") {
                    TextField("Endereço", text: $address)
                        .textContentType(.URL)
                        .autocorrectionDisabled()
                    SecureField("API_TOKEN (vazio em desenvolvimento)", text: $token)
                    Button("Aplicar") { apply() }
                        .disabled(URL(string: address) == nil)
                }

                Section("Estado") {
                    LabeledContent("Contas", value: "\(store.accounts.count)")
                    LabeledContent("Lançamentos", value: "\(store.transactions.count)")
                    LabeledContent("Regras", value: "\(store.rules.count)")
                    Button("Recarregar") { Task { await store.reload() } }
                }
            }
            .navigationTitle("Ajustes")
            .onAppear {
                address = store.configuration.baseURL.absoluteString
                token = store.configuration.token ?? ""
            }
        }
    }

    private func apply() {
        guard let url = URL(string: address) else { return }
        store.configuration = APIConfiguration(
            baseURL: url,
            token: token.isEmpty ? nil : token
        )
    }
}
