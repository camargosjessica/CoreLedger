import SwiftUI
import KausMedia

/// Cadastro de um compromisso, incluindo os valores combinados mês a mês — o
/// equivalente a digitar um número diferente numa coluna da planilha.
struct CommitmentSheet: View {
    @Environment(LedgerStore.self) private var store
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
    @State private var overrides: [String: Money]
    @State private var priceChanges: [String: Money]
    @State private var accountID: UUID?
    @State private var notes: String

    @State private var overrideMonth: YearMonth
    @State private var overrideValue = ""
    @State private var changeMonth: YearMonth
    @State private var changeValue = ""

    init(commitment: RecurringCommitment?) {
        self.commitment = commitment
        let current = YearMonth(date: Date())
        _name = State(initialValue: commitment?.name ?? "")
        _category = State(initialValue: commitment?.category ?? "")
        _kind = State(initialValue: commitment?.kind ?? .expense)
        _amount = State(initialValue: commitment.map { $0.amount.description } ?? "")
        _dayOfMonth = State(initialValue: commitment?.dayOfMonth ?? 1)
        _start = State(initialValue: commitment?.start ?? current)
        _hasEnd = State(initialValue: commitment?.end != nil)
        _end = State(initialValue: commitment?.end ?? current.adding(months: 11))
        _tags = State(initialValue: commitment?.tags ?? [])
        _isEnabled = State(initialValue: commitment?.isEnabled ?? true)
        _overrides = State(initialValue: commitment?.overrides ?? [:])
        _priceChanges = State(initialValue: commitment?.priceChanges ?? [:])
        _accountID = State(initialValue: commitment?.accountID)
        _notes = State(initialValue: commitment?.notes ?? "")
        _overrideMonth = State(initialValue: commitment?.start ?? current)
        _changeMonth = State(initialValue: max(current, commitment?.start ?? current))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Compromisso") {
                    TextField("Nome", text: $name)
                    CategoryField(category: $category, known: store.categories)
                    Picker("Tipo", selection: $kind) {
                        ForEach(RecurringCommitment.Kind.allCases, id: \.self) { option in
                            Text(option.displayName).tag(option)
                        }
                    }
                    TextField(priceChanges.isEmpty ? "Valor mensal" : "Valor inicial", text: $amount)
                    Stepper("Dia \(dayOfMonth)", value: $dayOfMonth, in: 1...31)
                    Picker("Conta", selection: $accountID) {
                        Text("Sem conta").tag(UUID?.none)
                        ForEach(store.accounts.all) { account in
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

                Section("Reajustes") {
                    ForEach(sortedPriceChanges, id: \.key) { item in
                        HStack {
                            Text("A partir de \(item.key)")
                            Spacer()
                            Text(item.value.brl)
                            Button {
                                priceChanges.removeValue(forKey: item.key)
                            } label: {
                                Image(systemName: "minus.circle")
                            }
                            .buttonStyle(.borderless)
                            .foregroundStyle(Color.red)
                        }
                    }
                    MonthPicker(title: "A partir de", month: $changeMonth)
                    HStack {
                        TextField("Novo valor", text: $changeValue)
                        Button("Adicionar") {
                            guard let value = ValueParser.parse(changeValue), value != 0 else { return }
                            priceChanges[changeMonth.description] = abs(value)
                            changeValue = ""
                        }
                        .buttonStyle(.borderless)
                        .disabled(!(ValueParser.parse(changeValue).map { $0 != 0 } ?? false))
                    }
                    Text("O valor novo vale daquele mês em diante, e os meses anteriores continuam com o valor de antes. Ex.: aluguel reajustado em maio.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
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
                    Text("Vale só para aquele mês, como uma conta de luz que veio diferente.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("Notas") {
                    TextField("Opcional", text: $notes, axis: .vertical)
                }
            }
            .formStyle(.grouped)
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

    private var sortedPriceChanges: [(key: String, value: Money)] {
        priceChanges.sorted { $0.key < $1.key }.map { (key: $0.key, value: $0.value) }
    }

    private var sortedOverrides: [(key: String, value: Money)] {
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
            priceChanges: priceChanges,
            accountID: accountID,
            notes: notes.isEmpty ? nil : notes
        )
        Task {
            await store.plan.saveCommitment(updated)
            dismiss()
        }
    }
}
