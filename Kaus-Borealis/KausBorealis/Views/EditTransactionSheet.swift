import SwiftUI
import KausMedia

/// Correção de um lançamento já gravado: categoria, descrição, valor, data e conta.
struct EditTransactionSheet: View {
    @Bindable var store: LedgerStore
    let transaction: TransactionDTO
    @Environment(\.dismiss) private var dismiss

    @State private var description: String
    @State private var amount: String
    @State private var date: Date
    @State private var accountID: UUID?
    @State private var category: String

    init(store: LedgerStore, transaction: TransactionDTO) {
        self.store = store
        self.transaction = transaction
        _description = State(initialValue: transaction.description)
        _amount = State(initialValue: String(format: "%.2f", transaction.amount))
        _date = State(initialValue: transaction.date)
        _accountID = State(initialValue: transaction.accountID)
        _category = State(initialValue: transaction.category ?? "")
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Lançamento") {
                    TextField("Descrição", text: $description)
                    TextField("Valor (negativo para despesa)", text: $amount)
                    DatePicker("Data", selection: $date, displayedComponents: .date)
                    Picker("Conta", selection: $accountID) {
                        Text("Sem conta").tag(UUID?.none)
                        ForEach(store.accounts) { account in
                            Text(account.name).tag(account.id)
                        }
                    }
                }

                Section("Categoria") {
                    TextField("Categoria", text: $category)
                    if !store.categories.isEmpty {
                        Picker("Usar existente", selection: $category) {
                            Text("—").tag("")
                            ForEach(store.categories, id: \.self) { name in
                                Text(name).tag(name)
                            }
                        }
                    }
                    Text("Deixe em branco para o servidor aplicar as regras.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if transaction.isProjected {
                    Section {
                        Text("Parcela projetada: ainda não apareceu numa fatura.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("Editar")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Salvar") { save() }
                        .disabled(description.isEmpty || ValueParser.parse(amount) == nil)
                }
            }
        }
    }

    private func save() {
        guard let value = ValueParser.parse(amount) else { return }
        var updated = transaction
        updated.description = description
        updated.amount = value
        updated.date = date
        updated.accountID = accountID
        updated.category = category.isEmpty ? nil : category
        Task {
            await store.updateTransaction(updated)
            dismiss()
        }
    }
}
