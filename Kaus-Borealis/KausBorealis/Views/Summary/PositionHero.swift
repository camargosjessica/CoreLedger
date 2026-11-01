import Charts
import SwiftUI
import KausMedia

/// Cartão escuro de destaque: patrimônio líquido e o veredito
/// positiva/empatada/negativa, com guardado, disponível e cartão logo abaixo.
struct PositionHero: View {
    let position: FinancialPosition

    private var statusColor: Color {
        switch position.status {
        case .positive: return Palette.income
        case .even: return Palette.star
        case .negative: return Palette.expense
        }
    }

    private var savings: [AccountPosition] {
        position.accounts.filter { $0.kind.isSavings }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Patrimônio líquido")
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.7))
                    Text(position.net.brl)
                        .font(.system(size: 34, weight: .bold, design: .rounded).monospacedDigit())
                        .foregroundStyle(.white)
                        .minimumScaleFactor(0.6)
                        .lineLimit(1)
                }
                Spacer()
                DeltaPill(text: position.status.title, color: statusColor)
            }

            HStack(spacing: 12) {
                HeroMetric(title: "Disponível", value: position.available, symbol: "building.columns.fill", color: .blue)
                HeroMetric(title: "Guardado", value: position.saved, symbol: "lock.shield.fill", color: .teal)
                HeroMetric(title: "Cartão", value: -position.creditCardDebt, symbol: "creditcard.fill", color: .purple)
            }

            if !savings.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(savings) { account in
                            Label("\(account.name) · \(account.balance.brl)", systemImage: account.kind.symbol)
                                .font(.caption)
                                .foregroundStyle(.white.opacity(0.85))
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(.white.opacity(0.1), in: Capsule())
                        }
                    }
                }
            }

            if position.upcomingInstallments > 0 {
                Label(
                    "\(position.upcomingInstallments.brl) em parcelas ainda por vir",
                    systemImage: "calendar.badge.clock"
                )
                .font(.caption)
                .foregroundStyle(.white.opacity(0.7))
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            LinearGradient(
                colors: [Color(hex: 0x0E1430), Color(hex: 0x1F2B55)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .overlay(alignment: .topTrailing) {
                Circle()
                    .fill(Palette.star.opacity(0.22))
                    .frame(width: 220, height: 220)
                    .blur(radius: 70)
                    .offset(x: 60, y: -80)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(.white.opacity(0.08), lineWidth: 1)
        )
    }
}

struct HeroMetric: View {
    let title: String
    let value: Money
    let symbol: String
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: symbol)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(color)
                    .frame(width: 24, height: 24)
                    .background(color.opacity(0.2), in: Circle())
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.7))
            }
            Text(value.brl)
                .font(.subheadline.weight(.semibold).monospacedDigit())
                .foregroundStyle(.white)
                .minimumScaleFactor(0.7)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

// MARK: - Categorias
