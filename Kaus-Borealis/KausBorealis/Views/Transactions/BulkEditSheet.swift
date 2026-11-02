import SwiftUI
import UniformTypeIdentifiers
import KausMedia

/// Mesma categoria e tags em vários lançamentos de uma vez.
struct BulkEditSheet: View {
    @Bindable var store: LedgerStore
    let transactions: [TransactionDTO]
    let onSaved: () -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var category = ""
    @State private var addTags: [String] = []
    @State private var removeTags: Set<String> = []

    /// Tags que algum dos selecionados já tem: as únicas que dá para tirar.
    private var currentTags: [String] {
        TagSet.normalize(transactions.flatMap(\.tags)).sorted()
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Categoria") {
                    CategoryField(category: $category, known: store.categories, placeholder: "Manter a de cada lançamento")
                }

                Section {
                    Text("Vale para os \(transactions.count) lançamento(s) selecionados. O que ficar em branco não muda.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Editar \(transactions.count)")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Salvar") { save() }
                        .disabled(!hasChanges)
                }
            }
        }
    }

    private var hasChanges: Bool {
        !category.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || !addTags.isEmpty || !removeTags.isEmpty
    }

    private func save() {
        let request = BulkUpdateRequest(
            ids: transactions.compactMap(\.id),
            category: category,
            addTags: addTags,
            removeTags: Array(removeTags)
        )
        Task {
            await store.transactions.update(request)
            onSaved()
            dismiss()
        }
    }
}
