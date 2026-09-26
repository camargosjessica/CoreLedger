import SwiftUI
import KausMedia

struct TransactionsView: View {
    @Bindable var store: LedgerStore
    @State private var search = ""
    @State private var isAdding = false
    @State private var isImporting = false

    private var grouped: [(day: Date, items: [TransactionDTO])] {
        Dictionary(grouping: store.transactions) { LedgerCalendar.startOfDay($0.date) }
            .map { (day: $0.key, items: $0.value) }
            .sorted { $0.day > $1.day }
    }

    var body: some View {
        NavigationStack {
            List {
                Section { AccountFilter(store: store) }

                if store.transactions.isEmpty && !store.isLoading {
                    ContentUnavailableView(
                        "Nenhum lançamento",
                        systemImage: "tray",
                        description: Text("Importe um extrato ou adicione um lançamento manualmente.")
                    )
                }

                ForEach(grouped, id: \.day) { group in
                    Section(group.day.shortDay) {
                        ForEach(group.items) { transaction in
                            TransactionRow(transaction: transaction)
                                .swipeActions {
                                    Button("Apagar", role: .destructive) {
                                        Task { await store.deleteTransaction(transaction) }
                                    }
                                }
                        }
                    }
                }
            }
            .navigationTitle("Lançamentos")
            .searchable(text: $search, prompt: "Descrição ou categoria")
            .onSubmit(of: .search) { Task { await store.search(search) } }
            .refreshable { await store.reload() }
            .toolbar {
                Button { isImporting = true } label: { Label("Importar", systemImage: "square.and.arrow.down") }
                Button { isAdding = true } label: { Label("Novo", systemImage: "plus") }
            }
            .sheet(isPresented: $isAdding) { NewTransactionSheet(store: store) }
            .sheet(isPresented: $isImporting) { ImportView(store: store) }
        }
    }
}

struct TransactionRow: View {
    let transaction: TransactionDTO

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(transaction.description)
                    .font(.headline)
                HStack(spacing: 6) {
                    Text(transaction.category ?? CategoryRule.uncategorizedDebit)
                    if let installment = transaction.installment {
                        Text("\(installment.number)/\(installment.total)")
                    }
                    if transaction.isProjected {
                        Text("projetado")
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(.quaternary, in: Capsule())
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            Spacer()
            Text(transaction.amount.brl)
                .font(.headline)
                .foregroundStyle(transaction.amount < 0 ? .primary : .green)
        }
        .padding(.vertical, 2)
    }
}

private struct NewTransactionSheet: View {
    @Bindable var store: LedgerStore
    @Environment(\.dismiss) private var dismiss

    @State private var description = ""
    @State private var amount = ""
    @State private var date = Date()
    @State private var accountID: UUID?
    /// Vazio deixa a categorização para as regras do servidor.
    @State private var category = ""

    var body: some View {
        NavigationStack {
            Form {
                TextField("Descrição", text: $description)
                TextField("Valor (negativo para despesa)", text: $amount)
                DatePicker("Data", selection: $date, displayedComponents: .date)
                Picker("Conta", selection: $accountID) {
                    Text("Sem conta").tag(UUID?.none)
                    ForEach(store.accounts) { account in
                        Text(account.name).tag(account.id)
                    }
                }
                TextField("Categoria (opcional)", text: $category)
            }
            .navigationTitle("Novo lançamento")
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
        let transaction = TransactionDTO(
            description: description,
            amount: value,
            date: date,
            category: category.isEmpty ? nil : category,
            accountID: accountID
        )
        Task {
            await store.addTransaction(transaction)
            dismiss()
        }
    }
}
