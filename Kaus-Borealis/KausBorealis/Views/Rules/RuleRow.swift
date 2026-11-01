import SwiftUI
import KausMedia

struct RuleRow: View {
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
