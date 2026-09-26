import SwiftUI
import KausMedia

struct TransactionsView: View {
    @Bindable var store: LedgerStore
    @State private var search = ""
    @State private var isAdding = false
    @State private var isImporting = false
    @State private var isSelecting = false
    @State private var selection: Set<UUID> = []
    @State private var editing: TransactionDTO?
    @State private var pendingDelete: TransactionDTO?
    @State private var isConfirmingBulkDelete = false

    private var grouped: [DayGroup] {
        Dictionary(grouping: store.transactions) { LedgerCalendar.startOfDay($0.date) }
            .map { DayGroup(day: $0.key, items: $0.value) }
            .sorted { $0.day > $1.day }
    }

    /// Projeções ficam de fora do saldo: ainda não saíram da conta.
    private var total: Double {
        store.transactions.filter { !$0.isProjected }.reduce(0) { $0 + $1.amount }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    AccountFilter(store: store)
                    PeriodFilter(store: store)
                    CategoryFilter(store: store)
                    LabeledContent("Saldo do período") {
                        Text(total.brl)
                            .font(.headline)
                            .foregroundStyle(total < 0 ? Color.red : Color.green)
                    }
                }

                if store.transactions.isEmpty && !store.isLoading {
                    ContentUnavailableView(
                        emptyTitle,
                        systemImage: "tray",
                        description: Text(emptyDescription)
                    )
                }

                ForEach(grouped) { group in
                    Section {
                        ForEach(group.items) { transaction in
                            row(for: transaction)
                        }
                    } header: {
                        HStack {
                            Text(group.day.shortDay)
                            Spacer()
                            Text(group.items.reduce(0) { $0 + $1.amount }.brl)
                        }
                    }
                }
            }
            .navigationTitle("Lançamentos")
            .searchable(text: $search, prompt: "Descrição ou categoria")
            .onSubmit(of: .search) { Task { await store.search(search) } }
            .refreshable { await store.reload() }
            .toolbar { toolbarContent }
            .safeAreaInset(edge: .bottom) { selectionBar }
            .sheet(isPresented: $isAdding) { NewTransactionSheet(store: store) }
            .sheet(isPresented: $isImporting) { ImportView(store: store) }
            .sheet(item: $editing) { transaction in
                EditTransactionSheet(store: store, transaction: transaction)
            }
            .confirmationDialog(
                "Apagar \(selection.count) lançamento(s)?",
                isPresented: $isConfirmingBulkDelete,
                titleVisibility: .visible
            ) {
                Button("Apagar", role: .destructive) { deleteSelected() }
            } message: {
                Text("Esta ação não pode ser desfeita.")
            }
            .confirmationDialog(
                "Apagar este lançamento?",
                isPresented: isConfirmingSingleDelete,
                titleVisibility: .visible
            ) {
                Button("Apagar", role: .destructive) { deletePending() }
            } message: {
                Text(pendingDelete?.description ?? "")
            }
        }
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItemGroup(placement: .primaryAction) {
            if isSelecting {
                Button(role: .destructive) {
                    isConfirmingBulkDelete = true
                } label: {
                    Label("Apagar selecionados", systemImage: "trash")
                }
                .disabled(selection.isEmpty)
                Button("Concluir") { endSelection() }
            } else {
                Button { isSelecting = true } label: {
                    Label("Selecionar", systemImage: "checklist")
                }
                Button { isImporting = true } label: {
                    Label("Importar", systemImage: "square.and.arrow.down")
                }
                Button { isAdding = true } label: {
                    Label("Novo", systemImage: "plus")
                }
            }
        }
    }

    @ViewBuilder
    private var selectionBar: some View {
        if isSelecting {
            Text("\(selection.count) selecionado(s)")
                .font(.footnote)
                .frame(maxWidth: .infinity)
                .padding(8)
                .background(.bar)
        }
    }

    @ViewBuilder
    private func row(for transaction: TransactionDTO) -> some View {
        HStack {
            if isSelecting {
                Image(systemName: isSelected(transaction) ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(Color.accentColor)
            }
            TransactionRow(transaction: transaction)
        }
        .contentShape(Rectangle())
        .onTapGesture { tapped(transaction) }
        .swipeActions {
            Button("Apagar", role: .destructive) { pendingDelete = transaction }
            Button("Editar") { editing = transaction }
                .tint(Color.blue)
        }
        .contextMenu {
            Button("Editar…") { editing = transaction }
            Menu("Categoria") {
                ForEach(store.categories, id: \.self) { name in
                    Button(name) { Task { await store.setCategory(name, on: transaction) } }
                }
            }
        }
    }

    private var isConfirmingSingleDelete: Binding<Bool> {
        Binding(
            get: { pendingDelete != nil },
            set: { if !$0 { pendingDelete = nil } }
        )
    }

    private func isSelected(_ transaction: TransactionDTO) -> Bool {
        guard let id = transaction.id else { return false }
        return selection.contains(id)
    }

    private func tapped(_ transaction: TransactionDTO) {
        guard isSelecting else {
            editing = transaction
            return
        }
        guard let id = transaction.id else { return }
        if selection.contains(id) {
            selection.remove(id)
        } else {
            selection.insert(id)
        }
    }

    private func endSelection() {
        isSelecting = false
        selection = []
    }

    private func deleteSelected() {
        let ids = Array(selection)
        Task {
            await store.deleteTransactions(ids: ids)
            endSelection()
        }
    }

    private func deletePending() {
        guard let transaction = pendingDelete else { return }
        pendingDelete = nil
        Task { await store.deleteTransaction(transaction) }
    }

    private var isFiltered: Bool {
        store.selectedCategory != nil || store.period != .all || store.selectedAccountID != nil
    }

    private var emptyTitle: String {
        isFiltered ? "Nada neste filtro" : "Nenhum lançamento"
    }

    private var emptyDescription: String {
        isFiltered
            ? "Ajuste o período, a categoria ou a conta para ver outros lançamentos."
            : "Importe um extrato ou adicione um lançamento manualmente."
    }
}

private struct PeriodFilter: View {
    @Bindable var store: LedgerStore

    var body: some View {
        Picker("Período", selection: $store.period) {
            ForEach(LedgerStore.Period.allCases) { period in
                Text(period.title).tag(period)
            }
        }
        .pickerStyle(.segmented)
    }
}

private struct CategoryFilter: View {
    @Bindable var store: LedgerStore

    var body: some View {
        Picker("Categoria", selection: $store.selectedCategory) {
            Text("Todas").tag(String?.none)
            ForEach(store.categories, id: \.self) { name in
                Text(name).tag(String?.some(name))
            }
        }
    }
}

private struct DayGroup: Identifiable {
    var day: Date
    var items: [TransactionDTO]

    var id: Date { day }
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
                .foregroundStyle(transaction.amount < 0 ? Color.primary : Color.green)
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
