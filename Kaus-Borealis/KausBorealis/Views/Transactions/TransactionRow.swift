import SwiftUI
import UniformTypeIdentifiers
import KausMedia

struct TransactionRow: View {
    let transaction: TransactionDTO

    var body: some View {
        HStack(spacing: 12) {
            CategoryIcon(category: transaction.category)
                .opacity(transaction.isProjected ? 0.5 : 1)
            VStack(alignment: .leading, spacing: 4) {
                Text(transaction.description)
                    .font(.headline)
                    .lineLimit(1)
                HStack(spacing: 6) {
                    Text(transaction.category ?? CategoryRule.uncategorizedDebit)
                    if let installment = transaction.installment {
                        Text("\(installment.number)/\(installment.total)")
                    }
                    if transaction.isProjected {
                        Text("futuro")
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(.quaternary, in: Capsule())
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                if let note = transaction.note {
                    Text(note)
                        .font(.caption)
                        .italic()
                        .lineLimit(2)
                }
            }
            Spacer()
            Text(transaction.amount.brl)
                .font(.headline.monospacedDigit())
                .foregroundStyle(transaction.amount < 0 ? Color.primary : Palette.income)
        }
    }
}
