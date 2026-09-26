import SwiftUI
import KausMedia

struct AccountsView: View {
    @Bindable var store: LedgerStore
    @State private var isAdding = false

    var body: some View {
        NavigationStack {
            List {
                if store.accounts.isEmpty && !store.isLoading {
                    ContentUnavailableView(
                        "Nenhuma conta",
                        systemImage: "creditcard",
                        description: Text("Crie uma conta para importar extratos e faturas.")
                    )
                }
                ForEach(store.accounts) { account in
                    NavigationLink {
                        AccountForm(store: store, account: account)
                    } label: {
                        AccountRow(account: account)
                    }
                }
                .onDelete { offsets in
                    let selected = offsets.map { store.accounts[$0] }
                    Task { for account in selected { await store.deleteAccount(account) } }
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
        }
    }
}

private struct AccountRow: View {
    let account: AccountDTO

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(account.name)
                .font(.headline)
            HStack {
                Text(account.kind.displayName)
                if let count = account.transactionCount {
                    Text("· \(count) lançamentos")
                }
                Spacer()
                if let balance = account.balance {
                    Text(balance.brl)
                        .foregroundStyle(balance < 0 ? .red : .green)
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
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
        }
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
