import Charts
import SwiftUI
import KausMedia

struct TransactionListCard: View {
    let title: String
    let transactions: [TransactionDTO]
    let showsDate: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            CardHeader(title: title)
            ForEach(transactions) { transaction in
                HStack(spacing: 12) {
                    CategoryIcon(category: transaction.category, size: 32)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(transaction.description)
                            .font(.subheadline.weight(.medium))
                            .lineLimit(1)
                        Text(subtitle(for: transaction))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    Spacer()
                    Text(transaction.amount.brl)
                        .font(.subheadline.weight(.semibold).monospacedDigit())
                        .foregroundStyle(transaction.amount < 0 ? Palette.expense : Palette.income)
                }
            }
        }
        .card()
    }

    private func subtitle(for transaction: TransactionDTO) -> String {
        var parts = [transaction.category ?? CategoryRule.uncategorizedDebit]
        if let installment = transaction.installment {
            parts.append("\(installment.number)/\(installment.total)")
        }
        if showsDate {
            parts.append(transaction.date.shortDay)
        }
        return parts.joined(separator: " · ")
    }
}
