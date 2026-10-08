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
    @State private var isExporting = false
    @State private var exportDocument: CSVFile?

    private var grouped: [DayGroup] {
        Dictionary(grouping: store.transactions) { LedgerCalendar.startOfDay($0.date) }
            .map { DayGroup(day: $0.key, items: $0.value) }
            .sorted { $0.day > $1.day }
    }

    /// Projeções ficam de fora do saldo: ainda não saíram da conta.
    private var realized: [TransactionDTO] { store.transactions.filter { !$0.isProjected } }
    private var total: Double { realized.reduce(0) { $0 + $1.amount } }
    private var income: Double { realized.filter { $0.amount > 0 }.reduce(0) { $0 + $1.amount } }
    private var spending: Double { realized.filter { $0.amount < 0 }.reduce(0) { $0 + $1.amount } }
    /// Com um cartão filtrado num mês futuro, é o valor previsto da fatura.
    private var totalWithProjected: Double { store.transactions.reduce(0) { $0 + $1.amount } }
    private var hasProjected: Bool { store.transactions.contains(where: \.isProjected) }

    var body: some View {
        NavigationStack {
            CardScreen {
                MetricGrid {
                    MetricTile(
                        title: "Saldo do período",
                        value: total,
                        symbol: "equal.circle.fill",
                        color: .indigo,
                        valueColor: total < 0 ? .red : .green
                    )
                    MetricTile(title: "Entradas", value: income, symbol: "arrow.down.left", color: .green)
                    MetricTile(title: "Saídas", value: spending, symbol: "arrow.up.right", color: .red)
                    if hasProjected {
                        MetricTile(
                            title: "Com previstos",
                            value: totalWithProjected,
                            symbol: "calendar.badge.clock",
                            color: .orange,
                            valueColor: totalWithProjected < 0 ? .red : .green
                        )
                    }
                }

                filters

                if store.transactions.isEmpty && !store.isLoading {
                    ContentUnavailableView(
                        emptyTitle,
                        systemImage: "tray",
                        description: Text(emptyDescription)
                    )
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
            .onSubmit(of: .search) { Task { await store.search(search) } }
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
                            ForEach(store.accounts) { account in
                                Text(account.name).tag(account.id)
                            }
                        }
                        .pickerStyle(.inline)
                    }
                    FilterChip(
                        title: store.selectedCategory ?? "Todas as categorias",
                        symbol: "tag",
                        isActive: store.selectedCategory != nil
                    ) {
                        CategoryFilter(store: store)
                            .pickerStyle(.inline)
                    }
                    FilterChip(
                        title: store.selectedTag ?? "Todas as tags",
                        symbol: "number",
                        isActive: store.selectedTag != nil
                    ) {
                        Picker("Tag", selection: $store.selectedTag) {
                            Text("Todas").tag(String?.none)
                            ForEach(store.knownTags, id: \.self) { tag in
                                Text(tag).tag(String?.some(tag))
                            }
                        }
                        .pickerStyle(.inline)
                    }
                }
            }
        }
    }

    private func export() {
        Task {
            guard let transactions = await store.transactionsForExport() else { return }
            exportDocument = CSVFile(text: TransactionCSV.export(transactions))
            isExporting = true
        }
    }

    private var exportFilename: String {
        let account = store.accounts.first { $0.id == store.selectedAccountID }?.name
        let month = store.period == .month ? store.selectedMonth.description : nil
        return (["lancamentos", account, month].compactMap { $0 }).joined(separator: "-")
    }

    private var accountTitle: String {
        store.accounts.first { $0.id == store.selectedAccountID }?.name ?? "Todas as contas"
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
                Button { export() } label: {
                    Label("Exportar CSV", systemImage: "square.and.arrow.up")
                }
                .disabled(store.transactions.isEmpty)
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
                    Button(name) { Task { await store.setCategory(name, on: transaction) } }
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
        store.selectedCategory != nil || store.selectedTag != nil || store.period != .all
            || store.selectedAccountID != nil
    }

    private var emptyTitle: String {
        isFiltered ? "Nada neste filtro" : "Nenhum lançamento"
    }

    private var emptyDescription: String {
        isFiltered
            ? "Ajuste o período, a categoria, a tag ou a conta para ver outros lançamentos."
            : "Importe um extrato ou adicione um lançamento manualmente."
    }
}

private struct PeriodFilter: View {
    @Bindable var store: LedgerStore

    var body: some View {
        VStack(spacing: 8) {
            Picker("Período", selection: $store.period) {
                ForEach(LedgerStore.Period.allCases) { period in
                    Text(period.title).tag(period)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            if store.period == .month {
                HStack {
                    Button {
                        store.selectedMonth = store.selectedMonth.adding(months: -1)
                    } label: {
                        Label("Mês anterior", systemImage: "chevron.left")
                    }
                    Spacer()
                    Text(store.selectedMonth.startDate.monthYear)
                        .font(.headline)
                    Spacer()
                    Button {
                        store.selectedMonth = store.selectedMonth.adding(months: 1)
                    } label: {
                        Label("Próximo mês", systemImage: "chevron.right")
                    }
                }
                .labelStyle(.iconOnly)
                .buttonStyle(.borderless)
            }
        }
    }
}

/// Documento para o `fileExporter`. O BOM faz o Excel abrir os acentos certos.
private struct CSVFile: FileDocument {
    static var readableContentTypes: [UTType] { [.commaSeparatedText] }

    var text: String

    init(text: String) {
        self.text = text
    }

    init(configuration: ReadConfiguration) throws {
        text = configuration.file.regularFileContents.flatMap { String(data: $0, encoding: .utf8) } ?? ""
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: Data(("\u{FEFF}" + text).utf8))
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
        HStack(spacing: 12) {
            CategoryIcon(category: transaction.category)
                .opacity(transaction.isProjected ? 0.5 : 1)
            VStack(alignment: .leading, spacing: 4) {
                Text(transaction.description)
                    .font(.headline)
                    .lineLimit(1)
                HStack(spacing: 6) {
                    Text(transaction.category ?? CategoryRule.uncategorizedDebit)
                    if let installment = transaction.installment {
                        Text("\(installment.number)/\(installment.total)")
                    }
                    if transaction.isProjected {
                        Text("futuro")
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(.quaternary, in: Capsule())
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                if let note = transaction.note {
                    Text(note)
                        .font(.caption)
                        .italic()
                        .lineLimit(2)
                }
                TagChips(tags: transaction.tags)
            }
            Spacer()
            Text(transaction.amount.brl)
                .font(.headline.monospacedDigit())
                .foregroundStyle(transaction.amount < 0 ? Color.primary : Color.green)
        }
    }
}

/// Lançamento manual. Com mais de uma parcela (ex.: IPTU em 10 vezes), gera uma
/// linha por mês, cada uma com data e valor editáveis antes de salvar.
private struct NewTransactionSheet: View {
    @Bindable var store: LedgerStore
    @Environment(\.dismiss) private var dismiss

    @State private var description = ""
    @State private var amount = ""
    @State private var date = Date()
    @State private var accountID: UUID?
    /// Vazio deixa a categorização para as regras do servidor.
    @State private var category = ""
    @State private var tags: [String] = []
    @State private var note = ""
    @State private var installmentCount = 1
    @State private var installments: [InstallmentDraft] = []

    var body: some View {
        NavigationStack {
            Form {
                Section("Lançamento") {
                    TextField("Descrição", text: $description)
                    TextField(installmentCount > 1 ? "Valor de cada parcela (negativo para despesa)" : "Valor (negativo para despesa)", text: $amount)
                    DatePicker(installmentCount > 1 ? "Primeira parcela" : "Data", selection: $date, displayedComponents: .date)
                    Picker("Conta", selection: $accountID) {
                        Text("Sem conta").tag(UUID?.none)
                        ForEach(store.accounts) { account in
                            Text(account.name).tag(account.id)
                        }
                    }
                    Stepper("Parcelas: \(installmentCount)", value: $installmentCount, in: 1...60)
                }

                if installmentCount > 1 {
                    Section {
                        ForEach($installments) { $draft in
                            HStack {
                                Text("\(draft.number)/\(installmentCount)")
                                    .font(.callout.monospacedDigit())
                                    .foregroundStyle(.secondary)
                                    .frame(minWidth: 44, alignment: .leading)
                                DatePicker("Data", selection: $draft.date, displayedComponents: .date)
                                    .labelsHidden()
                                TextField("Valor", text: $draft.amount)
                                    .multilineTextAlignment(.trailing)
                            }
                        }
                    } header: {
                        Text("Parcelas")
                    } footer: {
                        Text("Total: \(installmentTotal.brl). Ajuste a data ou o valor de qualquer parcela antes de salvar. Parcelas com data futura não entram no saldo até o dia chegar.")
                    }
                }

                Section("Categoria") {
                    TextField("Categoria (opcional)", text: $category)
                    if !store.categories.isEmpty {
                        Picker("Usar existente", selection: $category) {
                            Text("—").tag("")
                            ForEach(store.categories, id: \.self) { name in
                                Text(name).tag(name)
                            }
                        }
                    }
                }

                Section("Tags") {
                    TagEditor(tags: $tags, suggestions: store.knownTags)
                }

                Section("Comentário") {
                    TextField("O que foi essa compra?", text: $note, axis: .vertical)
                        .lineLimit(1...4)
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Novo lançamento")
            .onChange(of: installmentCount) { regenerate() }
            .onChange(of: amount) { regenerate() }
            .onChange(of: date) { regenerate() }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(installmentCount > 1 ? "Salvar \(installmentCount)" : "Salvar") { save() }
                        .disabled(description.isEmpty || !isValid)
                }
            }
        }
    }

    private var isValid: Bool {
        guard installmentCount > 1 else { return ValueParser.parse(amount) != nil }
        return installments.count == installmentCount
            && installments.allSatisfy { ValueParser.parse($0.amount) != nil }
    }

    private var installmentTotal: Double {
        installments.compactMap { ValueParser.parse($0.amount) }.reduce(0, +)
    }

    /// Refaz as parcelas a partir do valor e da primeira data, mantendo as que
    /// o usuário já ajustou à mão.
    private func regenerate() {
        guard installmentCount > 1 else {
            installments = []
            return
        }
        installments = (1...installmentCount).map { number in
            if let edited = installments.first(where: { $0.number == number && $0.isEdited }) {
                return edited
            }
            return InstallmentDraft(
                number: number,
                date: LedgerCalendar.addingMonths(number - 1, to: date),
                amount: amount
            )
        }
    }

    private func save() {
        let category = category.isEmpty ? nil : category
        let note = TransactionNote.normalize(note)
        let today = LedgerCalendar.startOfDay(Date())
        let transactions: [TransactionDTO]
        if installmentCount > 1 {
            transactions = installments.compactMap { draft in
                guard let value = ValueParser.parse(draft.amount) else { return nil }
                return TransactionDTO(
                    description: description,
                    amount: value,
                    date: draft.date,
                    category: category,
                    accountID: accountID,
                    isProjected: LedgerCalendar.startOfDay(draft.date) > today,
                    installment: Installment(number: draft.number, total: installmentCount),
                    tags: tags,
                    note: note
                )
            }
        } else {
            guard let value = ValueParser.parse(amount) else { return }
            transactions = [
                TransactionDTO(
                    description: description,
                    amount: value,
                    date: date,
                    category: category,
                    accountID: accountID,
                    isProjected: LedgerCalendar.startOfDay(date) > today,
                    tags: tags,
                    note: note
                ),
            ]
        }
        Task {
            await store.addTransactions(transactions)
            dismiss()
        }
    }
}

private struct InstallmentDraft: Identifiable {
    var id: Int { number }
    let number: Int
    var date: Date {
        didSet { isEdited = true }
    }
    var amount: String {
        didSet { isEdited = true }
    }
    private(set) var isEdited = false

    init(number: Int, date: Date, amount: String) {
        self.number = number
        self.date = date
        self.amount = amount
    }
}

private extension TransactionDTO {
    /// Lançamentos gravados sempre têm `id`; o resto cai na combinação dos campos.
    var rowID: String {
        id?.uuidString ?? "\(date.timeIntervalSince1970)|\(description)|\(amount)"
    }
}
