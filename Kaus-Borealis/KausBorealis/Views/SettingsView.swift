import SwiftUI
import KausMedia

struct SettingsView: View {
    @Bindable var store: LedgerStore

    @State private var address = ""
    @State private var token = ""
    @State private var resetScope: ResetScope = .transactions
    @State private var pendingReset = false
    @State private var resetSummary: String?
    @AppStorage(AppAppearance.storageKey) private var appearance: AppAppearance = .system
    @AppStorage(AppAccent.storageKey) private var accent: AppAccent = .indigo

    var body: some View {
        NavigationStack {
            Form {
                Section("Aparência") {
                    Picker(selection: $appearance) {
                        ForEach(AppAppearance.allCases) { option in
                            Text(option.title).tag(option)
                        }
                    } label: {
                        Label("Tema", systemImage: "paintbrush.fill")
                    }
                    .pickerStyle(.segmented)

                    LabeledContent {
                        AccentPicker(selection: $accent)
                    } label: {
                        Label("Cor de destaque", systemImage: "paintpalette.fill")
                    }
                }

                Section("Servidor") {
                    TextField("Endereço", text: $address)
                        .textContentType(.URL)
                        .autocorrectionDisabled()
                    SecureField("API_TOKEN (vazio em desenvolvimento)", text: $token)
                    Button("Aplicar") { apply() }
                        .disabled(URL(string: address) == nil)
                }

                Section("Estado") {
                    LabeledContent {
                        Text("\(store.accounts.count)")
                    } label: {
                        Label("Contas", systemImage: "creditcard.fill")
                    }
                    LabeledContent {
                        Text("\(store.transactions.count)")
                    } label: {
                        Label("Lançamentos", systemImage: "list.bullet.rectangle.portrait.fill")
                    }
                    LabeledContent {
                        Text("\(store.rules.count)")
                    } label: {
                        Label("Regras", systemImage: "slider.horizontal.3")
                    }
                    Button {
                        Task { await store.reload() }
                    } label: {
                        Label("Recarregar", systemImage: "arrow.clockwise")
                    }
                }

                Section {
                    Picker("O que apagar", selection: $resetScope) {
                        ForEach(ResetScope.allCases) { scope in
                            Text(scope.title).tag(scope)
                        }
                    }
                    Button(role: .destructive) {
                        pendingReset = true
                    } label: {
                        Label("Apagar tudo", systemImage: "trash.fill")
                            .foregroundStyle(Color.red)
                    }
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
            .formStyle(.grouped)
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

/// Bolinhas com as cores de destaque; a escolhida leva um check.
private struct AccentPicker: View {
    @Binding var selection: AppAccent

    var body: some View {
        HStack(spacing: 8) {
            ForEach(AppAccent.allCases) { option in
                Button {
                    selection = option
                } label: {
                    Circle()
                        .fill(option.color.gradient)
                        .frame(width: 24, height: 24)
                        .overlay {
                            if option == selection {
                                Image(systemName: "checkmark")
                                    .font(.caption.weight(.bold))
                                    .foregroundStyle(.white)
                            }
                        }
                }
                .buttonStyle(.plain)
                .accessibilityLabel(option.title)
                .help(option.title)
            }
        }
    }
}
