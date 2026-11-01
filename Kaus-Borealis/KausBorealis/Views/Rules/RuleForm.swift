import SwiftUI
import KausMedia

struct RuleForm: View {
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
                    Toggle("Ativa", isOn: $isEnabled)
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle(rule == nil ? "Nova regra" : "Editar regra")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancelar") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Salvar") {
                    Task {
                        await store.rules.save(draft)
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
