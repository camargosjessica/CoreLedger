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
                        StatTile(title: "Contas", value: store.accounts.count, symbol: "creditcard.fill", color: .purple)
                        StatTile(title: "Lançamentos", value: store.transactions.count, symbol: "list.bullet.rectangle.portrait.fill", color: .blue)
                        StatTile(title: "Regras", value: store.rules.count, symbol: "slider.horizontal.3", color: .orange)
                        StatTile(title: "Importações", value: store.batches.count, symbol: "square.and.arrow.down.fill", color: .teal)
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
                        .frame(width: 30, height: 30)
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

/// Cartão de seção dos Ajustes: ícone colorido, título, explicação opcional.
private struct SettingsCard<Content: View>: View {
    let title: String
    let symbol: String
    let color: Color
    var subtitle: String?
    var isDanger = false
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 12) {
                IconBadge(symbol: symbol, color: color, size: 32)
                VStack(alignment: .leading, spacing: 3) {
                    Text(title).font(.headline)
                    if let subtitle {
                        Text(subtitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            content
        }
        .card()
        .overlay {
            if isDanger {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .strokeBorder(Color.red.opacity(0.45), lineWidth: 1)
            }
        }
    }
}

/// Miniatura do tema: um pedacinho da tela no claro, no escuro ou dividida.
private struct ThemeTile: View {
    let option: AppAppearance
    let isSelected: Bool
    let action: () -> Void

    private let light = Color(hex: 0xF4F1EA)
    private let dark = Color(hex: 0x0A0F1F)

    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                preview
                    .frame(height: 64)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(isSelected ? AnyShapeStyle(TintShapeStyle()) : AnyShapeStyle(Palette.hairline), lineWidth: isSelected ? 2 : 1)
                    )
                HStack(spacing: 4) {
                    if isSelected {
                        Image(systemName: "checkmark.circle.fill").foregroundStyle(.tint)
                    }
                    Text(option.title)
                }
                .font(.caption.weight(isSelected ? .semibold : .regular))
            }
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var preview: some View {
        switch option {
        case .light: sample(background: light, line: Color(hex: 0xE2DCCF))
        case .dark: sample(background: dark, line: Color(hex: 0x26304F))
        case .system:
            HStack(spacing: 0) {
                sample(background: light, line: Color(hex: 0xE2DCCF))
                sample(background: dark, line: Color(hex: 0x26304F))
            }
        }
    }

    private func sample(background: Color, line: Color) -> some View {
        ZStack(alignment: .topLeading) {
            background
            VStack(alignment: .leading, spacing: 5) {
                Capsule().fill(Palette.star).frame(width: 22, height: 5)
                Capsule().fill(line).frame(width: 40, height: 5)
                Capsule().fill(line).frame(width: 30, height: 5)
            }
            .padding(10)
        }
    }
}

/// Contador dos dados guardados no servidor.
private struct StatTile: View {
    let title: String
    let value: Int
    let symbol: String
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Image(systemName: symbol)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(color)
            Text("\(value)")
                .font(.system(.title3, design: .rounded).weight(.bold).monospacedDigit())
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Palette.raised, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}
