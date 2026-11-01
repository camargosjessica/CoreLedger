import SwiftUI
import UniformTypeIdentifiers
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
    @State private var isBulkEditing = false
    @State private var isExporting = false
    @State private var exportDocument: CSVFile?

    private var grouped: [DayGroup] {
        Dictionary(grouping: store.transactions.items) { LedgerCalendar.startOfDay($0.date) }
            .map { DayGroup(day: $0.key, items: $0.value) }
            .sorted { $0.day > $1.day }
    }

    /// Projeções ficam de fora do saldo: ainda não saíram da conta.
    private var realized: [TransactionDTO] { store.transactions.items.filter { !$0.isProjected } }
    private var total: Money { realized.reduce(0) { $0 + $1.amount } }
    private var income: Money { realized.filter { $0.amount > 0 }.reduce(0) { $0 + $1.amount } }
    private var spending: Money { realized.filter { $0.amount < 0 }.reduce(0) { $0 + $1.amount } }
    /// Com um cartão filtrado num mês futuro, é o valor previsto da fatura.
    private var totalWithProjected: Money { store.transactions.items.reduce(0) { $0 + $1.amount } }
    private var hasProjected: Bool { store.transactions.items.contains(where: \.isProjected) }

    var body: some View {
        NavigationStack {
            CardScreen {
                MetricGrid {
                    MetricTile(
                        title: "Saldo do período",
                        value: total,
                        symbol: "equal.circle.fill",
                        color: .indigo,
                        valueColor: total < 0 ? Palette.expense : Palette.income
                    )
                    MetricTile(title: "Entradas", value: income, symbol: "arrow.down.left", color: Palette.income)
                    MetricTile(title: "Saídas", value: spending, symbol: "arrow.up.right", color: Palette.expense)
                    if hasProjected {
                        MetricTile(
                            title: "Com previstos",
                            value: totalWithProjected,
                            symbol: "calendar.badge.clock",
                            color: .orange,
                            valueColor: totalWithProjected < 0 ? Palette.expense : Palette.income
                        )
                    }
                }

                filters

                if store.transactions.items.isEmpty && !store.isLoading {
                    EmptyState(
                        symbol: isFiltered ? "line.3.horizontal.decrease" : "tray",
                        title: emptyTitle,
                        message: emptyDescription
                    ) {
                        if hasNarrowingFilter {
                            Button("Limpar filtros", systemImage: "xmark") {
                                store.transactions.selectedCategory = nil
                                store.transactions.selectedTag = nil
                                store.selectedAccountID = nil
                            }
                        } else {
                            Button("Importar", systemImage: "square.and.arrow.down") { isImporting = true }
                            Button("Novo lançamento", systemImage: "plus") { isAdding = true }
                                .buttonStyle(.bordered)
                        }
                    }
                    .card()
                }

                LazyVStack(alignment: .leading, spacing: 16) {
                    ForEach(grouped) { group in
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text(group.day.shortDay)
                                Spacer()
                                Text(group.items.reduce(0) { $0 + $1.amount }.brl)
                                    .monospacedDigit()
                            }
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 4)

                            VStack(spacing: 0) {
                                ForEach(Array(group.items.enumerated()), id: \.element.rowID) { index, transaction in
                                    if index > 0 { RowDivider(inset: isSelecting ? 80 : 48) }
                                    row(for: transaction)
                                }
                            }
                            .card()
                        }
                    }
                }
            }
            .navigationTitle("Lançamentos")
            .searchable(text: $search, prompt: "Descrição ou categoria")
            .onSubmit(of: .search) { Task { await store.transactions.search(search) } }
            .refreshable { await store.reload() }
            .toolbar { toolbarContent }
            .safeAreaInset(edge: .bottom) { selectionBar }
            .sheet(isPresented: $isAdding) { NewTransactionSheet(store: store) }
            .sheet(isPresented: $isImporting) { ImportView(store: store) }
            .fileExporter(
                isPresented: $isExporting,
                document: exportDocument,
                contentType: .commaSeparatedText,
                defaultFilename: exportFilename
            ) { result in
                if case let .failure(error) = result { store.errorMessage = error.localizedDescription }
            }
            .sheet(isPresented: $isBulkEditing) {
                BulkEditSheet(store: store, transactions: selectedTransactions) { endSelection() }
            }
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

    private var filters: some View {
        VStack(alignment: .leading, spacing: 12) {
            PeriodFilter(store: store)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    FilterChip(
                        title: accountTitle,
                        symbol: "building.columns",
                        isActive: store.selectedAccountID != nil
                    ) {
                        Picker("Conta", selection: $store.selectedAccountID) {
                            Text("Todas as contas").tag(UUID?.none)
                            ForEach(store.accounts.all) { account in
                                Text(account.name).tag(account.id)
                            }
                        }
                        .pickerStyle(.inline)
                    }
                    FilterChip(
                        title: store.transactions.selectedCategory ?? "Todas as categorias",
                        symbol: "tag",
                        isActive: store.transactions.selectedCategory != nil
                    ) {
                        CategoryFilter(store: store)
                            .pickerStyle(.inline)
                    }
                }
            }
        }
    }

    private func export() {
        Task {
            guard let transactions = await store.transactions.allForExport() else { return }
            exportDocument = CSVFile(text: TransactionCSV.export(transactions))
            isExporting = true
        }
    }

    private var exportFilename: String {
        let account = store.accounts.all.first { $0.id == store.selectedAccountID }?.name
        let month = store.transactions.period == .month ? store.transactions.selectedMonth.description : nil
        return (["lancamentos", account, month].compactMap { $0 }).joined(separator: "-")
    }

    private var accountTitle: String {
        store.accounts.all.first { $0.id == store.selectedAccountID }?.name ?? "Todas as contas"
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItemGroup(placement: .primaryAction) {
            if isSelecting {
                Button(allSelected ? "Desmarcar todos" : "Selecionar todos") { toggleSelectAll() }
                    .disabled(store.transactions.items.isEmpty)
                Button { isBulkEditing = true } label: {
                    Label("Editar selecionados", systemImage: "square.and.pencil")
                }
                .disabled(selectedTransactions.isEmpty)
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
                Button { export() } label: {
                    Label("Exportar CSV", systemImage: "square.and.arrow.up")
                }
                .disabled(store.transactions.items.isEmpty)
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
        HStack(spacing: 12) {
            if isSelecting {
                Image(systemName: isSelected(transaction) ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(.tint)
            }
            TransactionRow(transaction: transaction)
        }
        .padding(.vertical, 6)
        .contentShape(Rectangle())
        .onTapGesture { tapped(transaction) }
        .contextMenu {
            Button("Editar…", systemImage: "pencil") { editing = transaction }
            Menu("Categoria") {
                ForEach(store.categories, id: \.self) { name in
                    Button(name) { Task { await store.transactions.setCategory(name, on: transaction) } }
                }
            }
            Divider()
            Button("Apagar", systemImage: "trash", role: .destructive) { pendingDelete = transaction }
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

    /// Contrapartidas de transferência ficam de fora: acompanham o original.
    private var selectableIDs: Set<UUID> {
        Set(store.transactions.items.filter { $0.transferSourceID == nil }.compactMap(\.id))
    }

    private var allSelected: Bool {
        !selectableIDs.isEmpty && selectableIDs.isSubset(of: selection)
    }

    private var selectedTransactions: [TransactionDTO] {
        store.transactions.items.filter { transaction in
            transaction.transferSourceID == nil && transaction.id.map { selection.contains($0) } == true
        }
    }

    private func toggleSelectAll() {
        selection = allSelected ? [] : selectableIDs
    }

    private func endSelection() {
        isSelecting = false
        selection = []
    }

    private func deleteSelected() {
        let ids = Array(selection)
        Task {
            await store.transactions.delete(ids: ids)
            endSelection()
        }
    }

    private func deletePending() {
        guard let transaction = pendingDelete else { return }
        pendingDelete = nil
        Task { await store.transactions.delete(transaction) }
    }

    private var isFiltered: Bool {
        store.transactions.selectedCategory != nil || store.transactions.selectedTag != nil || store.transactions.period != .all
            || store.selectedAccountID != nil
    }

    private var hasNarrowingFilter: Bool {
        store.transactions.selectedCategory != nil || store.transactions.selectedTag != nil || store.selectedAccountID != nil
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

struct DayGroup: Identifiable {
    var day: Date
    var items: [TransactionDTO]

    var id: Date { day }
}

extension TransactionDTO {
    /// Lançamentos gravados sempre têm `id`; o resto cai na combinação dos campos.
    var rowID: String {
        id?.uuidString ?? "\(date.timeIntervalSince1970)|\(description)|\(amount)"
    }
}
