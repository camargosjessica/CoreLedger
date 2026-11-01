import SwiftUI
import KausMedia

struct AccountForm: View {
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
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancelar") { dismiss() }
            }
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
                await store.accounts.update(existing)
            } else {
                await store.accounts.add(name: name, kind: kind)
            }
            dismiss()
        }
    }
}
