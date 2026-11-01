import SwiftUI
import KausMedia

struct AccountsView: View {
    @Environment(LedgerStore.self) private var store
    @State private var isAdding = false
    @State private var pendingDelete: AccountDTO?
    @State private var editing: AccountDTO?

    private let columns = [GridItem(.adaptive(minimum: 240), spacing: 12, alignment: .top)]

    private var groups: [AccountGroup] {
        AccountGroup.Kind.allCases.compactMap { kind in
            let accounts = store.accounts.all.filter { kind.contains($0.kind) }
            return accounts.isEmpty ? nil : AccountGroup(kind: kind, accounts: accounts)
        }
    }

    private func total(_ kind: AccountGroup.Kind) -> Money {
        store.accounts.all.filter { kind.contains($0.kind) }.reduce(0) { $0 + ($1.balance ?? 0) }
    }

    var body: some View {
        NavigationStack {
            CardScreen {
                if store.accounts.all.isEmpty && !store.isLoading {
                    EmptyState(
                        symbol: "creditcard",
                        title: "Nenhuma conta",
                        message: "Crie uma conta para importar extratos e faturas."
                    ) {
                        Button("Nova conta", systemImage: "plus") { isAdding = true }
                    }
                    .card()
                } else {
                    MetricGrid {
                        ForEach(AccountGroup.Kind.allCases) { kind in
                            MetricTile(
                                title: kind.title,
                                value: total(kind),
                                symbol: kind.symbol,
                                color: kind.color,
                                valueColor: total(kind) < 0 ? Palette.expense : .primary
                            )
                        }
                    }
                }

                ForEach(groups) { group in
                    SectionTitle(group.kind.title)
                    LazyVGrid(columns: columns, spacing: 12) {
                        ForEach(group.accounts) { account in
                            NavigationLink {
                                if let id = account.id {
                                    AccountDetailView(accountID: id)
                                }
                            } label: {
                                AccountCard(account: account)
                            }
                            .buttonStyle(.plain)
                            .contextMenu {
                                Button("Editar conta", systemImage: "pencil") {
                                    editing = account
                                }
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
                NavigationStack { AccountForm(account: nil) }
            }
            .sheet(item: $editing) { account in
                NavigationStack { AccountForm(account: account) }
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
                    Task { await store.accounts.delete(account) }
                }
                Button("Cancelar", role: .cancel) { pendingDelete = nil }
            }
        }
    }
}

/// Agrupamento das contas como no Resumo: disponível, guardado e cartão.
struct AccountGroup: Identifiable {
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

#if DEBUG
#Preview {
    AccountsView().previewLedger()
}
#endif
