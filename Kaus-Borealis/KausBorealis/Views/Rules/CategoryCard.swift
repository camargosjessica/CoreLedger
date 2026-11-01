import SwiftUI
import KausMedia

/// Uma categoria-mãe: fechada mostra só o resumo; aberta mostra a chave
/// essencial, o limite, as subcategorias e as regras.
struct CategoryCard: View {
    let parent: String
    @Environment(LedgerStore.self) private var store
    let isExpanded: Bool
    let onToggle: () -> Void
    let onRename: (String) -> Void
    let onDelete: (String) -> Void
    let onSetLimit: (String) -> Void
    let onNewRule: () -> Void

    private var subcategories: [String] { store.subcategories(of: parent) }

    private var rules: [CategoryRule] {
        store.rules.all
            .filter { CategoryPath.isWithin($0.category, parent) }
            .sorted { ($0.category, $0.term) < ($1.category, $1.term) }
    }

    private var summary: String {
        var parts: [String] = []
        if !subcategories.isEmpty {
            parts.append(subcategories.count == 1 ? "1 subcategoria" : "\(subcategories.count) subcategorias")
        }
        parts.append(rules.count == 1 ? "1 regra" : "\(rules.count) regras")
        if let limit = store.plan.limit(for: parent) { parts.append("limite \(limit.brl)") }
        return parts.joined(separator: " · ")
    }

    private var essentialBinding: Binding<Bool> {
        Binding(
            get: { store.plan.isEssential(parent) },
            set: { value in Task { await store.plan.setEssential(value, for: parent) } }
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
                    if store.plan.isEssential(parent) {
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
                    Button(store.plan.limit(for: parent).map { "Limite \($0.brl)/mês" } ?? "Definir limite mensal") {
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
                        RuleForm(rule: rule, presetCategory: rule.category)
                    } label: {
                        RuleRow(rule: rule, parent: parent)
                    }
                    .buttonStyle(.plain)
                    .contextMenu {
                        Button("Apagar regra", systemImage: "trash", role: .destructive) {
                            Task { await store.rules.delete(rule) }
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
            if let limit = store.plan.limit(for: sub) {
                Text("limite \(limit.brl)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            if store.plan.isEssential(sub) {
                DeltaPill(text: "essencial", color: Palette.income)
            }
            Spacer()
            Menu {
                Button(
                    store.plan.isEssential(sub) ? "Não é essencial" : "Marcar como essencial",
                    systemImage: "checkmark.seal"
                ) {
                    let value = !store.plan.isEssential(sub)
                    Task { await store.plan.setEssential(value, for: sub) }
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
