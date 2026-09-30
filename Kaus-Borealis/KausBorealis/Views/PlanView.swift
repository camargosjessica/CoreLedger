import SwiftUI
import KausMedia

/// A aba que substitui a planilha: grade de categorias por mês, com os valores
/// realizados do extrato e os meses à frente preenchidos pelos compromissos.
struct PlanView: View {
    @Bindable var store: LedgerStore

    @State private var editing: RecurringCommitment?
    @State private var isCreating = false

    private var plan: AnnualPlan? { store.plan }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Picker("Ano", selection: $store.planYear) {
                        ForEach(years, id: \.self) { year in
                            Text(String(year)).tag(year)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                if let plan, !plan.rows.isEmpty {
                    Section("Grade anual") {
                        PlanGrid(plan: plan)
                            .listRowInsets(EdgeInsets())
                    }
                } else {
                    Section {
                        ContentUnavailableView(
                            "Nada previsto para \(String(store.planYear))",
                            systemImage: "calendar",
                            description: Text("Importe extratos ou cadastre um compromisso para montar a grade.")
                        )
                    }
                }

                Section("Compromissos") {
                    if store.commitments.isEmpty {
                        Text("Cadastre aluguel, luz, salário, aporte na caixinha…")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    ForEach(store.commitments) { commitment in
                        Button {
                            editing = commitment
                        } label: {
                            CommitmentRow(commitment: commitment)
                        }
                        .buttonStyle(.plain)
                        .swipeActions {
                            Button("Apagar", role: .destructive) {
                                Task { await store.deleteCommitment(commitment) }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Plano")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button { isCreating = true } label: { Image(systemName: "plus") }
                }
            }
            .refreshable { await store.reloadPlan() }
            .sheet(isPresented: $isCreating) {
                CommitmentSheet(store: store, commitment: nil)
            }
            .sheet(item: $editing) { commitment in
                CommitmentSheet(store: store, commitment: commitment)
            }
        }
    }

    private var years: [Int] {
        let current = YearMonth(date: Date()).year
        return Array((current - 1)...(current + 2))
    }
}

/// A grade propriamente dita. Rolagem horizontal porque doze meses não cabem
/// na largura do iPhone.
private struct PlanGrid: View {
    let plan: AnnualPlan

    private let labelWidth: CGFloat = 150
    private let columnWidth: CGFloat = 96

    var body: some View {
        ScrollView(.horizontal, showsIndicators: true) {
            VStack(alignment: .leading, spacing: 4) {
                header
                group("Receitas", rows: plan.incomeRows)
                group("Despesas", rows: plan.expenseRows)
                group("Guardado", rows: plan.savingRows)
                Divider()
                totalsRow("Saldo do mês", values: plan.totals.map(\.net))
                totalsRow("Fluxo de caixa", values: plan.totals.map(\.cashFlow))
                totalsRow("Acumulado", values: plan.totals.map(\.cumulative))
                totalsRow("Essenciais", values: plan.totals.map(\.essentialExpenses))
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
        }
    }

    private var header: some View {
        HStack(spacing: 0) {
            Text("Categoria")
                .frame(width: labelWidth, alignment: .leading)
            ForEach(plan.totals) { totals in
                VStack(spacing: 2) {
                    Text(totals.month.startDate.monthYear)
                        .lineLimit(1)
                    if totals.isForecast {
                        Text("previsto")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(width: columnWidth, alignment: .trailing)
            }
        }
        .font(.caption.weight(.semibold))
    }

    @ViewBuilder
    private func group(_ title: String, rows: [PlanRow]) -> some View {
        if !rows.isEmpty {
            Divider()
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            ForEach(rows) { row in
                HStack(spacing: 0) {
                    HStack(spacing: 4) {
                        if row.isEssential {
                            Image(systemName: "exclamationmark.circle")
                                .foregroundStyle(.secondary)
                        }
                        Text(row.category).lineLimit(1)
                    }
                    .frame(width: labelWidth, alignment: .leading)

                    ForEach(plan.months, id: \.description) { month in
                        let value = row.value(in: month)
                        Text(value == 0 ? "—" : value.brl)
                            .foregroundStyle(row.isRealized(in: month) ? Color.primary : Color.secondary)
                            .frame(width: columnWidth, alignment: .trailing)
                    }
                }
                .font(.caption)
            }
        }
    }

    private func totalsRow(_ title: String, values: [Double]) -> some View {
        HStack(spacing: 0) {
            Text(title)
                .frame(width: labelWidth, alignment: .leading)
            ForEach(Array(values.enumerated()), id: \.offset) { item in
                Text(item.element.brl)
                    .frame(width: columnWidth, alignment: .trailing)
            }
        }
        .font(.caption.weight(.semibold))
    }
}

private struct CommitmentRow: View {
    let commitment: RecurringCommitment

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(commitment.name)
                Spacer()
                Text(commitment.plannedAmount(in: commitment.start).brl)
                    .foregroundStyle(commitment.kind == .income ? Color.green : Color.primary)
            }
            HStack(spacing: 6) {
                Text(commitment.category)
                Text("dia \(commitment.dayOfMonth)")
                Text(period)
                if !commitment.isEnabled { Text("pausado") }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            TagChips(tags: commitment.tags)
        }
    }

    private var period: String {
        guard let end = commitment.end else { return "desde \(commitment.start.description)" }
        return "\(commitment.start.description) → \(end.description)"
    }
}

/// Cadastro de um compromisso, incluindo os valores combinados mês a mês — o
/// equivalente a digitar um número diferente numa coluna da planilha.
private struct CommitmentSheet: View {
    @Bindable var store: LedgerStore
    let commitment: RecurringCommitment?
    @Environment(\.dismiss) private var dismiss

    @State private var name: String
    @State private var category: String
    @State private var kind: RecurringCommitment.Kind
    @State private var amount: String
    @State private var dayOfMonth: Int
    @State private var start: YearMonth
    @State private var hasEnd: Bool
    @State private var end: YearMonth
    @State private var tags: [String]
    @State private var isEnabled: Bool
    @State private var overrides: [String: Double]
    @State private var accountID: UUID?
    @State private var notes: String

    @State private var overrideMonth: YearMonth
    @State private var overrideValue = ""

    init(store: LedgerStore, commitment: RecurringCommitment?) {
        self.store = store
        self.commitment = commitment
        let current = YearMonth(date: Date())
        _name = State(initialValue: commitment?.name ?? "")
        _category = State(initialValue: commitment?.category ?? "")
        _kind = State(initialValue: commitment?.kind ?? .expense)
        _amount = State(initialValue: commitment.map { String(format: "%.2f", $0.amount) } ?? "")
        _dayOfMonth = State(initialValue: commitment?.dayOfMonth ?? 1)
        _start = State(initialValue: commitment?.start ?? current)
        _hasEnd = State(initialValue: commitment?.end != nil)
        _end = State(initialValue: commitment?.end ?? current.adding(months: 11))
        _tags = State(initialValue: commitment?.tags ?? [])
        _isEnabled = State(initialValue: commitment?.isEnabled ?? true)
        _overrides = State(initialValue: commitment?.overrides ?? [:])
        _accountID = State(initialValue: commitment?.accountID)
        _notes = State(initialValue: commitment?.notes ?? "")
        _overrideMonth = State(initialValue: commitment?.start ?? current)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Compromisso") {
                    TextField("Nome", text: $name)
                    TextField("Categoria", text: $category)
                    if !store.categories.isEmpty {
                        Picker("Usar existente", selection: $category) {
                            Text("—").tag("")
                            ForEach(store.categories, id: \.self) { existing in
                                Text(existing).tag(existing)
                            }
                        }
                    }
                    Picker("Tipo", selection: $kind) {
                        ForEach(RecurringCommitment.Kind.allCases, id: \.self) { option in
                            Text(option.displayName).tag(option)
                        }
                    }
                    TextField("Valor mensal", text: $amount)
                    Stepper("Dia \(dayOfMonth)", value: $dayOfMonth, in: 1...31)
                    Picker("Conta", selection: $accountID) {
                        Text("Sem conta").tag(UUID?.none)
                        ForEach(store.accounts) { account in
                            Text(account.name).tag(account.id)
                        }
                    }
                    Toggle("Ativo", isOn: $isEnabled)
                }

                Section("Período") {
                    MonthPicker(title: "Início", month: $start)
                    Toggle("Tem fim", isOn: $hasEnd)
                    if hasEnd {
                        MonthPicker(title: "Fim", month: $end)
                    }
                }

                Section("Tags") {
                    TagEditor(tags: $tags, suggestions: store.knownTags)
                }

                Section("Valores por mês") {
                    ForEach(sortedOverrides, id: \.key) { item in
                        HStack {
                            Text(item.key)
                            Spacer()
                            Text(item.value.brl)
                            Button {
                                overrides.removeValue(forKey: item.key)
                            } label: {
                                Image(systemName: "minus.circle")
                            }
                            .buttonStyle(.borderless)
                            .foregroundStyle(Color.red)
                        }
                    }
                    MonthPicker(title: "Mês", month: $overrideMonth)
                    HStack {
                        TextField("Valor (0 zera o mês)", text: $overrideValue)
                        Button("Definir") {
                            guard let value = ValueParser.parse(overrideValue) else { return }
                            overrides[overrideMonth.description] = abs(value)
                            overrideValue = ""
                        }
                        .buttonStyle(.borderless)
                        .disabled(ValueParser.parse(overrideValue) == nil)
                    }
                    Text("Use quando o valor mudar num mês específico, como o reajuste da luz.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("Notas") {
                    TextField("Opcional", text: $notes, axis: .vertical)
                }
            }
            .navigationTitle(commitment == nil ? "Novo compromisso" : "Editar compromisso")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Salvar") { save() }
                        .disabled(!isValid)
                }
            }
        }
    }

    private var sortedOverrides: [(key: String, value: Double)] {
        overrides.sorted { $0.key < $1.key }.map { (key: $0.key, value: $0.value) }
    }

    private var isValid: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty
            && !category.trimmingCharacters(in: .whitespaces).isEmpty
            && (ValueParser.parse(amount).map { $0 != 0 } ?? false)
            && (!hasEnd || end >= start)
    }

    private func save() {
        guard let value = ValueParser.parse(amount) else { return }
        let updated = RecurringCommitment(
            id: commitment?.id,
            name: name,
            category: category,
            kind: kind,
            amount: abs(value),
            dayOfMonth: dayOfMonth,
            start: start,
            end: hasEnd ? end : nil,
            tags: tags,
            isEnabled: isEnabled,
            overrides: overrides,
            accountID: accountID,
            notes: notes.isEmpty ? nil : notes
        )
        Task {
            await store.saveCommitment(updated)
            dismiss()
        }
    }
}

/// Mês e ano, sem dia — o compromisso vale para o mês inteiro.
private struct MonthPicker: View {
    let title: String
    @Binding var month: YearMonth

    var body: some View {
        DatePicker(
            title,
            selection: Binding(
                get: { month.startDate },
                set: { month = YearMonth(date: $0) }
            ),
            displayedComponents: .date
        )
    }
}
