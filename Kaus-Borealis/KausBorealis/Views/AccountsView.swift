import SwiftUI
import KausMedia

struct AccountsView: View {
    @Bindable var store: LedgerStore
    @State private var isAdding = false
    @State private var pendingDelete: AccountDTO?

    private let columns = [GridItem(.adaptive(minimum: 240), spacing: 12, alignment: .top)]

    private var groups: [AccountGroup] {
        AccountGroup.Kind.allCases.compactMap { kind in
            let accounts = store.accounts.filter { kind.contains($0.kind) }
            return accounts.isEmpty ? nil : AccountGroup(kind: kind, accounts: accounts)
        }
    }

    private func total(_ kind: AccountGroup.Kind) -> Double {
        store.accounts.filter { kind.contains($0.kind) }.reduce(0) { $0 + ($1.balance ?? 0) }
    }

    var body: some View {
        NavigationStack {
            CardScreen {
                if store.accounts.isEmpty && !store.isLoading {
                    ContentUnavailableView(
                        "Nenhuma conta",
                        systemImage: "creditcard",
                        description: Text("Crie uma conta para importar extratos e faturas.")
                    )
                    .card()
                } else {
                    MetricGrid {
                        ForEach(AccountGroup.Kind.allCases) { kind in
                            MetricTile(
                                title: kind.title,
                                value: total(kind),
                                symbol: kind.symbol,
                                color: kind.color,
                                valueColor: total(kind) < 0 ? .red : .primary
                            )
                        }
                    }
                }

                ForEach(groups) { group in
                    SectionTitle(group.kind.title)
                    LazyVGrid(columns: columns, spacing: 12) {
                        ForEach(group.accounts) { account in
                            NavigationLink {
                                AccountForm(store: store, account: account)
                            } label: {
                                AccountCard(account: account)
                            }
                            .buttonStyle(.plain)
                            .contextMenu {
                                Button("Apagar conta", systemImage: "trash", role: .destructive) {
                                    pendingDelete = account
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Contas")
            .refreshable { await store.reload() }
            .toolbar {
                Button { isAdding = true } label: { Label("Nova conta", systemImage: "plus") }
            }
            .sheet(isPresented: $isAdding) {
                NavigationStack { AccountForm(store: store, account: nil) }
            }
            .confirmationDialog(
                pendingDelete.map { "Apagar a conta \($0.name)?" } ?? "",
                isPresented: Binding(
                    get: { pendingDelete != nil },
                    set: { if !$0 { pendingDelete = nil } }
                ),
                titleVisibility: .visible
            ) {
                Button("Apagar", role: .destructive) {
                    guard let account = pendingDelete else { return }
                    pendingDelete = nil
                    Task { await store.deleteAccount(account) }
                }
                Button("Cancelar", role: .cancel) { pendingDelete = nil }
            }
        }
    }
}

/// Agrupamento das contas como no Resumo: disponível, guardado e cartão.
private struct AccountGroup: Identifiable {
    enum Kind: String, CaseIterable, Identifiable {
        case available
        case saved
        case card

        var id: String { rawValue }

        var title: String {
            switch self {
            case .available: return "Disponível"
            case .saved: return "Guardado"
            case .card: return "Cartões"
            }
        }

        var symbol: String {
            switch self {
            case .available: return AccountKind.checking.symbol
            case .saved: return AccountKind.savings.symbol
            case .card: return AccountKind.creditCard.symbol
            }
        }

        var color: Color {
            switch self {
            case .available: return AccountKind.checking.tint
            case .saved: return AccountKind.savings.tint
            case .card: return AccountKind.creditCard.tint
            }
        }

        func contains(_ kind: AccountKind) -> Bool {
            switch self {
            case .available: return kind == .checking || kind == .cash
            case .saved: return kind.isSavings
            case .card: return kind == .creditCard
            }
        }
    }

    var kind: Kind
    var accounts: [AccountDTO]

    var id: String { kind.rawValue }
}

private struct AccountCard: View {
    let account: AccountDTO

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                IconBadge(symbol: account.kind.symbol, color: account.kind.tint, size: 40)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(account.name)
                    .font(.headline)
                    .lineLimit(1)
                HStack(spacing: 4) {
                    Text(account.kind.displayName)
                    if let count = account.transactionCount {
                        Text("· \(count) lançamentos")
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            Text(account.balance?.brl ?? "—")
                .font(.title2.weight(.bold).monospacedDigit())
                .foregroundStyle((account.balance ?? 0) < 0 ? Color.red : Color.primary)
                .minimumScaleFactor(0.6)
                .lineLimit(1)
        }
        .card()
        .contentShape(Rectangle())
    }
}

private struct AccountForm: View {
    @Bindable var store: LedgerStore
    let account: AccountDTO?
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var kind: AccountKind = .checking

    var body: some View {
        Form {
            TextField("Nome", text: $name)
            Picker("Tipo", selection: $kind) {
                ForEach(AccountKind.allCases, id: \.self) { kind in
                    Text(kind.displayName).tag(kind)
                }
            }
            if kind == .creditCard {
                Text("Faturas desta conta expandem as parcelas futuras na importação.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if kind.isSavings {
                Text("O saldo desta conta entra como dinheiro guardado na posição do Resumo. Use uma conta por caixinha.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .navigationTitle(account == nil ? "Nova conta" : "Editar conta")
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Salvar") { save() }
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .onAppear {
            guard let account else { return }
            name = account.name
            kind = account.kind
        }
    }

    private func save() {
        Task {
            if var existing = account {
                existing.name = name
                existing.kind = kind
                await store.updateAccount(existing)
            } else {
                await store.addAccount(name: name, kind: kind)
            }
            dismiss()
        }
    }
}
