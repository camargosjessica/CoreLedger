import SwiftUI
import KausMedia

struct CommitmentCard: View {
    let commitment: RecurringCommitment
    @Environment(\.ledgerClock) private var clock

    private var amountColor: Color {
        switch commitment.kind {
        case .income: return .green
        case .saving: return .teal
        case .expense: return .primary
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            CategoryIcon(category: commitment.category, size: 40)
                .opacity(commitment.isEnabled ? 1 : 0.4)
            VStack(alignment: .leading, spacing: 4) {
                Text(commitment.name)
                    .font(.headline)
                    .lineLimit(1)
                Text("\(commitment.category) · dia \(commitment.dayOfMonth)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Label(period, systemImage: "calendar")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 6) {
                Text(commitment.plannedAmount(in: referenceMonth).brl)
                    .font(.headline.monospacedDigit())
                    .foregroundStyle(amountColor)
                DeltaPill(
                    text: commitment.isEnabled ? commitment.kind.displayName : "Pausado",
                    color: commitment.isEnabled ? amountColor : .gray
                )
            }
        }
        .card()
        .contentShape(Rectangle())
    }

    /// Mês de hoje, limitado à vigência, para o cartão mostrar o valor atual.
    private var referenceMonth: YearMonth {
        let current = max(clock.currentMonth(), commitment.start)
        guard let end = commitment.end else { return current }
        return min(current, end)
    }

    private var period: String {
        guard let end = commitment.end else { return "desde \(commitment.start.description)" }
        return "\(commitment.start.description) → \(end.description)"
    }
}
