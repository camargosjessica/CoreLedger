import SwiftUI
import KausMedia

/// Categorias com subcategorias, preferências e as regras que as preenchem.
struct RulesView: View {
    @Bindable var store: LedgerStore
    @State private var newRuleCategory: NewRule?
    @State private var expanded: Set<String> = []
    @State private var recategorizeResult: Int?
    @State private var pendingDeletion: String?
    @State private var resultMessage: String?
    @State private var renaming: String?
    @State private var newName = ""
    @State private var limitTarget: String?
    @State private var limitText = ""

    private var parents: [String] {
        Array(Set(store.parentCategories + store.rules.map { CategoryPath.parent(of: $0.category) })).sorted()
    }

    private let columns = [GridItem(.adaptive(minimum: 360), spacing: 16, alignment: .top)]

    var body: some View {
        NavigationStack {
            CardScreen {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 12) {
                        IconBadge(symbol: "wand.and.stars", color: .indigo, size: 36)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("\(parents.count) categorias · \(store.rules.count) regras")
                                .font(.headline)
                            Text("Toque numa categoria para ver subcategorias, limite e regras.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button {
                            Task { recategorizeResult = await store.recategorize(onlyUncategorized: false) }
                        } label: {
                            Label("Reaplicar ao histórico", systemImage: "arrow.triangle.2.circlepath")
                        }
                        .buttonStyle(.bordered)
                    }
                    if let recategorizeResult {
                        Text("\(recategorizeResult) lançamentos recategorizados")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    if let resultMessage {
                        Text(resultMessage)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .card()

                if parents.isEmpty {
                    ContentUnavailableView(
                        "Nenhuma categoria ainda",
                        systemImage: "square.stack.3d.up",
                        description: Text("Crie uma regra ou categorize um lançamento para começar.")
                    )
                }

                LazyVGrid(columns: columns, spacing: 16) {
                    ForEach(parents, id: \.self) { parent in
                        CategoryCard(
                            parent: parent,
                            store: store,
                            isExpanded: expanded.contains(parent),
                            onToggle: {
                                if expanded.contains(parent) { expanded.remove(parent) } else { expanded.insert(parent) }
                            },
                            onRename: { category in
                                newName = CategoryPath.child(of: category) ?? category
                                renaming = category
                            },
                            onDelete: { pendingDeletion = $0 },
                            onSetLimit: { category in
                                limitText = store.limit(for: category)
                                    .map { String(format: "%.2f", $0).replacingOccurrences(of: ".", with: ",") } ?? ""
                                limitTarget = category
                            },
                            onNewRule: { newRuleCategory = NewRule(category: parent) }
                        )
                    }
                }
            }
            .navigationTitle("Regras")
            .refreshable { await store.reload() }
            .toolbar {
                Button { newRuleCategory = NewRule(category: "") } label: { Label("Nova regra", systemImage: "plus") }
            }
            .sheet(item: $newRuleCategory) { target in
                NavigationStack { RuleForm(store: store, rule: nil, presetCategory: target.category) }
            }
            .confirmationDialog(
                pendingDeletion.map { "Apagar \($0)?" } ?? "",
                isPresented: isConfirmingDeletion,
                titleVisibility: .visible
            ) {
                Button("Apagar", role: .destructive) { delete() }
                Button("Cancelar", role: .cancel) { pendingDeletion = nil }
            } message: {
                Text("As regras somem e os lançamentos passam pelas regras restantes. Apagar uma categoria apaga também as subcategorias.")
            }
            .alert(renaming.map { "Renomear \($0)" } ?? "", isPresented: isRenaming) {
                TextField("Novo nome", text: $newName)
                Button("Salvar") { rename() }
                Button("Cancelar", role: .cancel) { renaming = nil }
            } message: {
                Text("Muda em todos os lançamentos, regras e contas fixas. Se o nome já existir, as duas se juntam.")
            }
            .alert(limitTarget.map { "Limite mensal de \($0)" } ?? "", isPresented: isEditingLimit) {
                TextField("Valor, ex.: 800,00", text: $limitText)
                Button("Salvar") { saveLimit(ValueParser.parse(limitText).map(abs)) }
                if limitTarget.flatMap(store.limit(for:)) != nil {
                    Button("Remover limite", role: .destructive) { saveLimit(nil) }
                }
                Button("Cancelar", role: .cancel) { limitTarget = nil }
            } message: {
                Text("O Resumo avisa quando o gasto do mês passa de 80% do limite e quando estoura. O limite de uma categoria inclui as subcategorias.")
            }
        }
    }
}

private struct NewRule: Identifiable {
    var category: String
    var id: String { category }
}

extension RulesView {
    private var isConfirmingDeletion: Binding<Bool> {
        Binding(get: { pendingDeletion != nil }, set: { if !$0 { pendingDeletion = nil } })
    }

    private var isEditingLimit: Binding<Bool> {
        Binding(get: { limitTarget != nil }, set: { if !$0 { limitTarget = nil } })
    }

    private var isRenaming: Binding<Bool> {
        Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })
    }

    private func saveLimit(_ value: Double?) {
        guard let category = limitTarget else { return }
        limitTarget = nil
        Task { await store.setLimit(value, for: category) }
    }

    private func rename() {
        guard let current = renaming else { return }
        renaming = nil
        let typed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !typed.isEmpty else { return }
        let name = CategoryPath.child(of: current) == nil
            ? typed
            : CategoryPath.join(CategoryPath.parent(of: current), typed)
        guard name != current else { return }
        Task {
            guard let response = await store.renameCategory(current, to: name) else { return }
            resultMessage = "\(response.transactions) lançamento(s), \(response.rules) regra(s) e \(response.commitments) conta(s) fixa(s) atualizado(s)."
        }
    }

    private func delete() {
        guard let category = pendingDeletion else { return }
        pendingDeletion = nil
        let targets = store.subcategories(of: category) + [category]
        Task {
            var rules = 0
            var recategorized = 0
            for target in targets {
                guard let response = await store.deleteCategory(target) else { continue }
                rules += response.removedRules
                recategorized += response.recategorized
            }
            resultMessage = "\(rules) regra(s) apagada(s), \(recategorized) lançamento(s) recategorizado(s)."
        }
    }
}

/// Uma categoria-mãe: fechada mostra só o resumo; aberta mostra a chave
/// essencial, o limite, as subcategorias e as regras.
private struct CategoryCard: View {
    let parent: String
    @Bindable var store: LedgerStore
    let isExpanded: Bool
    let onToggle: () -> Void
    let onRename: (String) -> Void
    let onDelete: (String) -> Void
    let onSetLimit: (String) -> Void
    let onNewRule: () -> Void

    private var subcategories: [String] { store.subcategories(of: parent) }

    private var rules: [CategoryRule] {
        store.rules
            .filter { CategoryPath.isWithin($0.category, parent) }
            .sorted { ($0.category, $0.term) < ($1.category, $1.term) }
    }

    private var summary: String {
        var parts: [String] = []
        if !subcategories.isEmpty {
            parts.append(subcategories.count == 1 ? "1 subcategoria" : "\(subcategories.count) subcategorias")
        }
        parts.append(rules.count == 1 ? "1 regra" : "\(rules.count) regras")
        if let limit = store.limit(for: parent) { parts.append("limite \(limit.brl)") }
        return parts.joined(separator: " · ")
    }

    private var essentialBinding: Binding<Bool> {
        Binding(
            get: { store.isEssential(parent) },
            set: { value in Task { await store.setEssential(value, for: parent) } }
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button(action: onToggle) {
                HStack(spacing: 12) {
                    CategoryIcon(category: parent, size: 36)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(parent)
                            .font(.headline)
                        Text(summary)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    if store.isEssential(parent) {
                        DeltaPill(text: "essencial", color: Palette.income)
                    }
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.tertiary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isExpanded {
                Divider()
                Toggle("Essencial", isOn: essentialBinding)
                HStack {
                    Button(store.limit(for: parent).map { "Limite \($0.brl)/mês" } ?? "Definir limite mensal") {
                        onSetLimit(parent)
                    }
                    .buttonStyle(.borderless)
                    Spacer()
                    Menu {
                        Button("Renomear", systemImage: "pencil") { onRename(parent) }
                        Button("Apagar", systemImage: "trash", role: .destructive) { onDelete(parent) }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                    .menuStyle(.button)
                    .buttonStyle(.borderless)
                    .fixedSize()
                }

                if !subcategories.isEmpty {
                    sectionTitle("Subcategorias")
                    ForEach(subcategories, id: \.self) { sub in
                        subcategoryRow(sub)
                    }
                }

                sectionTitle("Regras")
                ForEach(rules) { rule in
                    NavigationLink {
                        RuleForm(store: store, rule: rule, presetCategory: rule.category)
                    } label: {
                        RuleRow(rule: rule, parent: parent)
                    }
                    .buttonStyle(.plain)
                    .contextMenu {
                        Button("Apagar regra", systemImage: "trash", role: .destructive) {
                            Task { await store.deleteRule(rule) }
                        }
                    }
                }
                Button("Nova regra", systemImage: "plus", action: onNewRule)
                    .buttonStyle(.borderless)
            }
        }
        .card()
    }

    private func sectionTitle(_ title: String) -> some View {
        Text(title)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
    }

    private func subcategoryRow(_ sub: String) -> some View {
        HStack(spacing: 8) {
            Circle()
                .fill(CategoryStyle.of(parent).color)
                .frame(width: 6, height: 6)
            Text(CategoryPath.child(of: sub) ?? sub)
            if let limit = store.limit(for: sub) {
                Text("limite \(limit.brl)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            if store.isEssential(sub) {
                DeltaPill(text: "essencial", color: Palette.income)
            }
            Spacer()
            Menu {
                Button(
                    store.isEssential(sub) ? "Não é essencial" : "Marcar como essencial",
                    systemImage: "checkmark.seal"
                ) {
                    let value = !store.isEssential(sub)
                    Task { await store.setEssential(value, for: sub) }
                }
                Button("Limite mensal…", systemImage: "gauge.with.needle") { onSetLimit(sub) }
                Button("Renomear", systemImage: "pencil") { onRename(sub) }
                Button("Apagar", systemImage: "trash", role: .destructive) { onDelete(sub) }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .menuStyle(.button)
            .buttonStyle(.borderless)
            .fixedSize()
        }
        .font(.subheadline)
    }
}

private struct RuleRow: View {
    let rule: CategoryRule
    let parent: String

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
                Text(([CategoryPath.child(of: rule.category)].compactMap { $0 } + [matchTitle]).joined(separator: " · "))
                    .font(.caption)
                    .foregroundStyle(.secondary)
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
    var presetCategory = ""
    @Environment(\.dismiss) private var dismiss

    @State private var term = ""
    @State private var category = ""
    @State private var matchKind: CategoryRule.MatchKind = .contains
    @State private var amountScope: CategoryRule.AmountScope = .any
    @State private var priority = 100
    @State private var isEnabled = true
    @State private var isTransfer = false
    @State private var tags: [String] = []

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
                CategoryField(category: $category, known: store.categories)
            }

            Section {
                DisclosureGroup("Avançado") {
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
            guard let rule else {
                category = presetCategory
                return
            }
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
