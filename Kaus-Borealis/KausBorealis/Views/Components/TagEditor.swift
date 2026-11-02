import SwiftUI
import KausMedia

/// Edição de tags livres: as sugeridas pela regra vêm preenchidas, e daqui dá
/// para tirar, trocar ou inventar outras.
struct TagEditor: View {
    @Binding var tags: [String]
    var suggestions: [String] = []

    @State private var newTag = ""

    private var available: [String] {
        suggestions.filter { !tags.contains($0) }
    }

    var body: some View {
        if !tags.isEmpty {
            ForEach(tags, id: \.self) { tag in
                HStack {
                    Label(tag, systemImage: "tag")
                    Spacer()
                    Button {
                        tags.removeAll { $0 == tag }
                    } label: {
                        Image(systemName: "minus.circle")
                    }
                    .buttonStyle(.borderless)
                    .foregroundStyle(Color.red)
                }
            }
        }

        HStack {
            TextField("Nova tag", text: $newTag)
                .onSubmit(add)
            Button("Adicionar", action: add)
                .buttonStyle(.borderless)
                .disabled(TagSet.normalize([newTag]).isEmpty)
        }

        if !available.isEmpty {
            Menu("Usar existente") {
                ForEach(available, id: \.self) { tag in
                    Button(tag) { tags = TagSet.normalize(tags + [tag]) }
                }
            }
        }
    }

    private func add() {
        tags = TagSet.normalize(tags + [newTag])
        newTag = ""
    }
}

/// Marcadores compactos para listas.
struct TagChips: View {
    let tags: [String]

    var body: some View {
        if !tags.isEmpty {
            Text(tags.map { "#\($0)" }.joined(separator: " "))
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }
}
