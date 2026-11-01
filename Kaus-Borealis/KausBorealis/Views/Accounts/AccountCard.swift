import SwiftUI
import KausMedia

struct AccountCard: View {
    let account: AccountDTO

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                IconBadge(symbol: account.kind.symbol, color: account.kind.tint, size: 40)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(account.name)
                    .font(.headline)
                    .lineLimit(1)
                HStack(spacing: 4) {
                    Text(account.kind.displayName)
                    if let count = account.transactionCount {
                        Text("· \(count) lançamentos")
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            Text(account.balance?.brl ?? "—")
                .font(.title2.weight(.bold).monospacedDigit())
                .foregroundStyle((account.balance ?? 0) < 0 ? Palette.expense : Color.primary)
                .minimumScaleFactor(0.6)
                .lineLimit(1)
        }
        .card()
        .contentShape(Rectangle())
    }
}
