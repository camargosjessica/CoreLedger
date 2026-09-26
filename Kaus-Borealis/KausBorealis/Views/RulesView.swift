import SwiftUI
import KausMedia

/// Regras de categorização: o que substitui a lista fixa no código.
struct RulesView: View {
    @Bindable var store: LedgerStore
    @State private var isAdding = false
    @State private var recategorizeResult: Int?
    @State private var pendingCategoryDeletion: String?
    @State private var categoryDeletionResult: String?

    private var grouped: [RuleGroup] {
        Dictionary(grouping: store.rules, by: \.category)
            .map { RuleGroup(category: $0.key, rules: $0.value.sorted { $0.term < $1.term }) }
            .sorted { $0.category < $1.category }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Button("Reaplicar regras ao histórico") {
                        Task { recategorizeResult = await store.recategorize(onlyUncategorized: false) }
                    }
                    if let recategorizeResult {
                        Text("\(recategorizeResult) lançamentos recategorizados")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    if let categoryDeletionResult {
                        Text(categoryDeletionResult)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                ForEach(grouped) { group in
                    Section {
                        ForEach(group.rules) { rule in
                            NavigationLink {
                                RuleForm(store: store, rule: rule)
                            } label: {
                                RuleRow(rule: rule)
                            }
                        }
                        .onDelete { offsets in
                            let selected = offsets.map { group.rules[$0] }
                            Task { for rule in selected { await store.deleteRule(rule) } }
                        }
                    } header: {
                        HStack {
                            Text(group.category)
                            Spacer()
                            Button(role: .destructive) {
                                pendingCategoryDeletion = group.category
                            } label: {
                                Label("Apagar categoria", systemImage: "trash")
                                    .labelStyle(.iconOnly)
                            }
                            .buttonStyle(.borderless)
                        }
                    }
                }
            }
            .navigationTitle("Regras")
            .refreshable { await store.reload() }
            .toolbar {
                Button { isAdding = true } label: { Label("Nova regra", systemImage: "plus") }
            }
            .sheet(isPresented: $isAdding) {
                NavigationStack { RuleForm(store: store, rule: nil) }
            }
            .confirmationDialog(
                pendingCategoryDeletion.map { "Apagar a categoria \($0)?" } ?? "",
                isPresented: isConfirmingCategoryDeletion,
                titleVisibility: .visible
            ) {
                Button("Apagar categoria", role: .destructive) { deleteCategory() }
                Button("Cancelar", role: .cancel) { pendingCategoryDeletion = nil }
            } message: {
                Text("As regras somem e os lançamentos dessa categoria passam pelas regras restantes.")
            }
        }
    }
}

extension RulesView {
    private var isConfirmingCategoryDeletion: Binding<Bool> {
        Binding(
            get: { pendingCategoryDeletion != nil },
            set: { if !$0 { pendingCategoryDeletion = nil } }
        )
    }

    private func deleteCategory() {
        guard let category = pendingCategoryDeletion else { return }
        pendingCategoryDeletion = nil
        Task {
            guard let response = await store.deleteCategory(category) else { return }
            categoryDeletionResult =
                "\(response.removedRules) regra(s) apagada(s), \(response.recategorized) lançamento(s) recategorizado(s)."
        }
    }
}

private struct RuleGroup: Identifiable {
    var category: String
    var rules: [CategoryRule]

    var id: String { category }
}

private struct RuleRow: View {
    let rule: CategoryRule

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(rule.term)
                    .font(.body)
                    .strikethrough(!rule.isEnabled)
                Text("\(rule.matchKind.rawValue) · prioridade \(rule.priority)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if rule.isTransfer {
                Image(systemName: "arrow.left.arrow.right")
                    .foregroundStyle(.secondary)
            }
        }
    }
}

private struct RuleForm: View {
    @Bindable var store: LedgerStore
    let rule: CategoryRule?
    @Environment(\.dismiss) private var dismiss

    @State private var term = ""
    @State private var category = ""
    @State private var matchKind: CategoryRule.MatchKind = .contains
    @State private var amountScope: CategoryRule.AmountScope = .any
    @State private var priority = 100
    @State private var isEnabled = true
    @State private var isTransfer = false

    @State private var sampleDescription = ""
    @State private var sampleAmount = "-100,00"
    @State private var previewResult: String?

    private var draft: CategoryRule {
        CategoryRule(
            id: rule?.id,
            term: term,
            category: category,
            matchKind: matchKind,
            amountScope: amountScope,
            priority: priority,
            isEnabled: isEnabled,
            isTransfer: isTransfer
        )
    }

    var body: some View {
        Form {
            Section("Regra") {
                TextField("Termo", text: $term)
                TextField("Categoria", text: $category)
                Picker("Comparação", selection: $matchKind) {
                    Text("Palavra inteira").tag(CategoryRule.MatchKind.word)
                    Text("Contém").tag(CategoryRule.MatchKind.contains)
                    Text("Expressão regular").tag(CategoryRule.MatchKind.regex)
                }
                Picker("Aplica-se a", selection: $amountScope) {
                    Text("Qualquer valor").tag(CategoryRule.AmountScope.any)
                    Text("Entradas").tag(CategoryRule.AmountScope.credit)
                    Text("Despesas").tag(CategoryRule.AmountScope.debit)
                }
                Stepper("Prioridade: \(priority)", value: $priority, in: 1...999)
                Toggle("Ativa", isOn: $isEnabled)
                Toggle("É transferência", isOn: $isTransfer)
            }

            Section("Testar") {
                TextField("Descrição de exemplo", text: $sampleDescription)
                TextField("Valor", text: $sampleAmount)
                Button("Simular") {
                    Task {
                        let amount = ValueParser.parse(sampleAmount) ?? 0
                        let response = await store.preview(
                            description: sampleDescription,
                            amount: amount,
                            rule: term.isEmpty ? nil : draft
                        )
                        previewResult = response.map { result in
                            result.matchedTerm.map { "\(result.category) (por “\($0)”)" } ?? result.category
                        }
                    }
                }
                .disabled(sampleDescription.isEmpty)
                if let previewResult {
                    Text(previewResult).foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle(rule == nil ? "Nova regra" : "Editar regra")
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Salvar") {
                    Task {
                        await store.saveRule(draft)
                        dismiss()
                    }
                }
                .disabled(term.isEmpty || category.isEmpty)
            }
        }
        .onAppear {
            guard let rule else { return }
            term = rule.term
            category = rule.category
            matchKind = rule.matchKind
            amountScope = rule.amountScope
            priority = rule.priority
            isEnabled = rule.isEnabled
            isTransfer = rule.isTransfer
        }
    }
}
