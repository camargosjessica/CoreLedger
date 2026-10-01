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

    private let columns = [GridItem(.adaptive(minimum: 320), spacing: 16, alignment: .top)]

    var body: some View {
        NavigationStack {
            CardScreen {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 12) {
                        IconBadge(symbol: "wand.and.stars", color: .indigo, size: 40)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Categorização automática")
                                .font(.headline)
                            Text("\(store.rules.count) regras em \(grouped.count) categorias")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button {
                            Task { recategorizeResult = await store.recategorize(onlyUncategorized: false) }
                        } label: {
                            Label("Reaplicar ao histórico", systemImage: "arrow.triangle.2.circlepath")
                        }
                        .buttonStyle(.borderedProminent)
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
                .card()

                LazyVGrid(columns: columns, spacing: 16) {
                    ForEach(grouped) { group in
                        RuleGroupCard(
                            group: group,
                            store: store,
                            onDeleteCategory: { pendingCategoryDeletion = group.category }
                        )
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

/// Uma categoria com as suas regras; tocar numa regra abre a edição.
private struct RuleGroupCard: View {
    let group: RuleGroup
    @Bindable var store: LedgerStore
    let onDeleteCategory: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                CategoryIcon(category: group.category)
                VStack(alignment: .leading, spacing: 2) {
                    Text(group.category)
                        .font(.headline)
                    Text(group.rules.count == 1 ? "1 regra" : "\(group.rules.count) regras")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button(role: .destructive, action: onDeleteCategory) {
                    Label("Apagar categoria", systemImage: "trash")
                        .labelStyle(.iconOnly)
                        .foregroundStyle(Color.red)
                }
                .buttonStyle(.borderless)
            }
            Divider()
            ForEach(group.rules) { rule in
                NavigationLink {
                    RuleForm(store: store, rule: rule)
                } label: {
                    RuleRow(rule: rule)
                }
                .buttonStyle(.plain)
                .contextMenu {
                    Button("Apagar regra", systemImage: "trash", role: .destructive) {
                        Task { await store.deleteRule(rule) }
                    }
                }
            }
        }
        .card()
    }
}

private struct RuleRow: View {
    let rule: CategoryRule

    private var matchTitle: String {
        switch rule.matchKind {
        case .word: return "Palavra inteira"
        case .contains: return "Contém"
        case .regex: return "Expressão regular"
        }
    }

    var body: some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(rule.term)
                    .font(.body.weight(.medium))
                    .strikethrough(!rule.isEnabled)
                    .foregroundStyle(rule.isEnabled ? Color.primary : Color.secondary)
                Text("\(matchTitle) · prioridade \(rule.priority)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                TagChips(tags: rule.tags)
            }
            Spacer()
            if rule.isTransfer {
                DeltaPill(text: "transferência", color: .gray)
            }
            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
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
    @State private var tags: [String] = []

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
            isTransfer: isTransfer,
            tags: tags
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

            Section("Tags sugeridas") {
                TagEditor(tags: $tags, suggestions: store.knownTags)
                Text("Preenchem os lançamentos importados por esta regra; dá para editar depois em cada lançamento.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
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
        .formStyle(.grouped)
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
            tags = rule.tags
        }
    }
}
