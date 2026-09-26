import SwiftUI
import KausMedia

struct SettingsView: View {
    @Bindable var store: LedgerStore

    @State private var address = ""
    @State private var token = ""
    @State private var resetScope: ResetScope = .transactions
    @State private var pendingReset = false
    @State private var resetSummary: String?

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

                Section {
                    Picker("O que apagar", selection: $resetScope) {
                        ForEach(ResetScope.allCases) { scope in
                            Text(scope.title).tag(scope)
                        }
                    }
                    Button("Apagar tudo", role: .destructive) { pendingReset = true }
                    if let resetSummary {
                        Text(resetSummary)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } header: {
                    Text("Zona de risco")
                } footer: {
                    Text("Não dá para desfazer: reimportar os extratos é o único caminho de volta.")
                }
            }
            .confirmationDialog(
                "Apagar \(resetScope.title.lowercased())?",
                isPresented: $pendingReset,
                titleVisibility: .visible
            ) {
                Button("Apagar tudo", role: .destructive) { reset() }
                Button("Cancelar", role: .cancel) { }
            } message: {
                Text("Esta ação apaga os dados no servidor e não pode ser desfeita.")
            }
            .navigationTitle("Ajustes")
            .onAppear {
                address = store.configuration.baseURL.absoluteString
                token = store.configuration.token ?? ""
            }
        }
    }

    private func reset() {
        Task {
            guard let response = await store.reset(scope: resetScope) else { return }
            resetSummary =
                "\(response.transactions) lançamento(s), \(response.batches) importação(ões), "
                + "\(response.accounts) conta(s) e \(response.rules) regra(s) apagadas."
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
