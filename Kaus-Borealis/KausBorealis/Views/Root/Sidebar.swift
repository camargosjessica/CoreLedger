import SwiftUI
import KausMedia

struct SidebarAccount: Identifiable {
    let id: UUID
    let account: AccountDTO
}

/// Marca no topo da barra lateral.
struct SidebarBrand: View {
    var body: some View {
        HStack(spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(LinearGradient(colors: [Color(hex: 0x1B2440), Color(hex: 0x0A0F1F)], startPoint: .top, endPoint: .bottom))
                Image(systemName: "sparkle")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(Palette.star)
            }
            .frame(width: 30, height: 30)
            VStack(alignment: .leading, spacing: 0) {
                Text("CoreLedger")
                    .font(.system(.headline, design: .rounded))
                Text("finanças pessoais")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Patrimônio sempre à vista no rodapé da barra lateral.
struct SidebarNetWorth: View {
    let accounts: [AccountDTO]

    private var total: Money { accounts.compactMap(\.balance).sum() }

    var body: some View {
        if !accounts.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                Text("Patrimônio")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(total.brl)
                    .font(.system(.title3, design: .rounded).weight(.bold).monospacedDigit())
                    .foregroundStyle(total < 0 ? Palette.expense : Color.primary)
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Palette.raised, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
    }
}
