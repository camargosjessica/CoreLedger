import SwiftUI
import KausMedia

/// Categoria e subcategoria opcional, gravadas juntas como "Categoria › Sub".
struct CategoryField: View {
    @Binding var category: String
    let known: [String]
    var placeholder = "Categoria"

    private var parent: String { CategoryPath.parent(of: category) }

    /// Texto da subcategoria como digitado, sem aparar espaços no meio da digitação.
    private var rawChild: String {
        guard let range = category.range(of: CategoryPath.separator) else { return "" }
        return String(category[range.upperBound...])
    }

    private var parents: [String] {
        Array(Set(known.map(CategoryPath.parent(of:)))).sorted()
    }

    private var children: [String] {
        Array(Set(known.filter { CategoryPath.parent(of: $0) == parent }.compactMap(CategoryPath.child(of:)))).sorted()
    }

    private var parentBinding: Binding<String> {
        Binding(get: { parent }, set: { category = Self.compose($0, rawChild) })
    }

    private var childBinding: Binding<String> {
        Binding(get: { rawChild }, set: { category = Self.compose(parent, $0) })
    }

    private static func compose(_ parent: String, _ child: String) -> String {
        child.isEmpty ? parent : parent + CategoryPath.separator + child
    }

    var body: some View {
        HStack {
            TextField(placeholder, text: parentBinding)
            suggestions(parents, selection: parentBinding)
        }
        HStack {
            TextField("Subcategoria (opcional)", text: childBinding)
            suggestions(children, selection: childBinding)
        }
        .disabled(parent.isEmpty)
    }

    private func suggestions(_ options: [String], selection: Binding<String>) -> some View {
        Menu {
            ForEach(options, id: \.self) { option in
                Button(option) { selection.wrappedValue = option }
            }
        } label: {
            Image(systemName: "chevron.down.circle")
        }
        .menuStyle(.button)
        .buttonStyle(.borderless)
        .fixedSize()
        .disabled(options.isEmpty)
    }
}
