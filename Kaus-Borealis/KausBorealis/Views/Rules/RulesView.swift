import SwiftUI
import KausMedia

/// Categorias com subcategorias, preferências e as regras que as preenchem.
struct RulesView: View {
    @Environment(LedgerStore.self) private var store
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
        Array(Set(store.parentCategories + store.rules.all.map { CategoryPath.parent(of: $0.category) })).sorted()
    }

    private let columns = [GridItem(.adaptive(minimum: 360), spacing: 16, alignment: .top)]

    var body: some View {
        NavigationStack {
            CardScreen {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 12) {
                        IconBadge(symbol: "wand.and.stars", color: .indigo, size: 36)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("\(parents.count) categorias · \(store.rules.all.count) regras")
                                .font(.headline)
                            Text("Toque numa categoria para ver subcategorias, limite e regras.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button {
                            Task { recategorizeResult = await store.rules.recategorize(onlyUncategorized: false) }
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
                    EmptyState(
                        symbol: "square.stack.3d.up",
                        title: "Nenhuma categoria ainda",
                        message: "Crie uma regra ou categorize um lançamento para começar."
                    ) {
                        Button("Nova regra", systemImage: "plus") { newRuleCategory = NewRule(category: "") }
                    }
                    .card()
                }

                LazyVGrid(columns: columns, spacing: 16) {
                    ForEach(parents, id: \.self) { parent in
                        CategoryCard(
                            parent: parent,
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
                                limitText =
                                    store.plan.limit(for: category)
                                    .map { $0.description.replacingOccurrences(of: ".", with: ",") } ?? ""
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
                Button {
                    newRuleCategory = NewRule(category: "")
                } label: {
                    Label("Nova regra", systemImage: "plus")
                }
            }
            .sheet(item: $newRuleCategory) { target in
                NavigationStack { RuleForm(rule: nil, presetCategory: target.category) }
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
                if limitTarget.flatMap(store.plan.limit(for:)) != nil {
                    Button("Remover limite", role: .destructive) { saveLimit(nil) }
                }
                Button("Cancelar", role: .cancel) { limitTarget = nil }
            } message: {
                Text(
                    "O Resumo avisa quando o gasto do mês passa de 80% do limite e quando estoura. O limite de uma categoria inclui as subcategorias."
                )
            }
        }
    }
}

struct NewRule: Identifiable {
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

    private func saveLimit(_ value: Money?) {
        guard let category = limitTarget else { return }
        limitTarget = nil
        Task { await store.plan.setLimit(value, for: category) }
    }

    private func rename() {
        guard let current = renaming else { return }
        renaming = nil
        let typed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !typed.isEmpty else { return }
        let name =
            CategoryPath.child(of: current) == nil
            ? typed
            : CategoryPath.join(CategoryPath.parent(of: current), typed)
        guard name != current else { return }
        Task {
            guard let response = await store.rules.renameCategory(current, to: name) else { return }
            resultMessage =
                "\(response.transactions) lançamento(s), \(response.rules) regra(s) e \(response.commitments) conta(s) fixa(s) atualizado(s)."
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
                guard let response = await store.rules.deleteCategory(target) else { continue }
                rules += response.removedRules
                recategorized += response.recategorized
            }
            resultMessage = "\(rules) regra(s) apagada(s), \(recategorized) lançamento(s) recategorizado(s)."
        }
    }
}

#if DEBUG
    #Preview {
        RulesView().previewLedger()
    }
#endif
