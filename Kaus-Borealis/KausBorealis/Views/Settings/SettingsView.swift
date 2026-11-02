import SwiftUI
import KausMedia

struct SettingsView: View {
    @Environment(LedgerStore.self) private var store

    @State private var address = ""
    @State private var token = ""
    @State private var resetScope: ResetScope = .transactions
    @State private var pendingReset = false
    @State private var resetSummary: String?
    @AppStorage(AppAppearance.storageKey) private var appearance: AppAppearance = .system
    @AppStorage(AppAccent.storageKey) private var accent: AppAccent = .amber

    private var isConnected: Bool { store.isReachable }

    var body: some View {
        NavigationStack {
            CardScreen {
                header

                SettingsCard(title: "Aparência", symbol: "paintbrush.fill", color: .pink) {
                    HStack(spacing: 12) {
                        ForEach(AppAppearance.allCases) { option in
                            ThemeTile(option: option, isSelected: appearance == option) {
                                appearance = option
                            }
                        }
                    }
                    Divider()
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Cor de destaque")
                            .font(.subheadline.weight(.medium))
                        AccentPicker(selection: $accent)
                    }
                }

                SettingsCard(
                    title: "Servidor",
                    symbol: "server.rack",
                    color: .blue,
                    subtitle: "Onde o Kaus-Australis está rodando. Pelo Tailscale, use o endereço da máquina."
                ) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Endereço").font(.caption).foregroundStyle(.secondary)
                        TextField("http://localhost:8080", text: $address)
                            .textContentType(.URL)
                            .autocorrectionDisabled()
                            .textFieldStyle(.roundedBorder)
                    }
                    VStack(alignment: .leading, spacing: 6) {
                        Text("API_TOKEN").font(.caption).foregroundStyle(.secondary)
                        SecureField("Vazio em desenvolvimento", text: $token)
                            .textFieldStyle(.roundedBorder)
                    }
                    HStack {
                        Button("Testar conexão", systemImage: "bolt.horizontal.fill") {
                            Task { await store.reload() }
                        }
                        .buttonStyle(.bordered)
                        Spacer()
                        Button("Aplicar") { apply() }
                            .buttonStyle(.borderedProminent)
                            .disabled(URL(string: address) == nil)
                    }
                }

                SettingsCard(title: "Seus dados", symbol: "externaldrive.fill", color: .teal) {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 120), spacing: 10)], spacing: 10) {
                        StatTile(title: "Contas", value: store.accounts.all.count, symbol: "creditcard.fill", color: .purple)
                        StatTile(title: "Lançamentos", value: store.transactions.items.count, symbol: "list.bullet.rectangle.portrait.fill", color: .blue)
                        StatTile(title: "Regras", value: store.rules.all.count, symbol: "slider.horizontal.3", color: .orange)
                        StatTile(title: "Importações", value: store.transactions.batches.count, symbol: "square.and.arrow.down.fill", color: .teal)
                    }
                    Button("Recarregar tudo", systemImage: "arrow.clockwise") {
                        Task { await store.reload() }
                    }
                    .buttonStyle(.bordered)
                }

                SettingsCard(
                    title: "Zona de risco",
                    symbol: "exclamationmark.triangle.fill",
                    color: .red,
                    subtitle: "Não dá para desfazer: reimportar os extratos é o único caminho de volta.",
                    isDanger: true
                ) {
                    HStack {
                        Picker("O que apagar", selection: $resetScope) {
                            ForEach(ResetScope.allCases) { scope in
                                Text(scope.title).tag(scope)
                            }
                        }
                        .pickerStyle(.menu)
                        Spacer()
                        Button(role: .destructive) {
                            pendingReset = true
                        } label: {
                            Label("Apagar", systemImage: "trash.fill")
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.red)
                    }
                    if let resetSummary {
                        Text(resetSummary)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .frame(maxWidth: 760, alignment: .leading)
            .frame(maxWidth: .infinity)
            .background(Palette.canvas)
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

    private var header: some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(LinearGradient(colors: [Color(hex: 0x1B2440), Color(hex: 0x0A0F1F)], startPoint: .top, endPoint: .bottom))
                Image(systemName: "sparkle")
                    .font(.system(size: 24, weight: .bold))
                    .foregroundStyle(accent.color)
            }
            .frame(width: 54, height: 54)
            VStack(alignment: .leading, spacing: 4) {
                Text("CoreLedger")
                    .font(.system(.title3, design: .rounded).weight(.bold))
                HStack(spacing: 6) {
                    Circle()
                        .fill(isConnected ? Palette.income : Palette.expense)
                        .frame(width: 8, height: 8)
                    Text(isConnected ? "Conectado a \(store.configuration.baseURL.host() ?? "servidor")" : "Sem conexão com o servidor")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer()
        }
        .card()
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

#if DEBUG
#Preview {
    SettingsView().previewLedger()
}
#endif
