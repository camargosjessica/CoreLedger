import Charts
import SwiftUI
import KausMedia

/// Limites por categoria no mês atual, dos mais apertados para os mais folgados.
struct LimitsCard: View {
    let statuses: [CategoryLimitStatus]

    private var overCount: Int { statuses.filter { $0.level() == .over }.count }
    private var nearCount: Int { statuses.filter { $0.level() == .near }.count }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            CardHeader(title: "Limites do mês") {
                if overCount > 0 {
                    DeltaPill(text: overCount == 1 ? "1 estourado" : "\(overCount) estourados", color: Palette.expense)
                } else if nearCount > 0 {
                    DeltaPill(text: nearCount == 1 ? "1 no limite" : "\(nearCount) no limite", color: Palette.star)
                } else {
                    DeltaPill(text: "Tudo em dia", color: Palette.income)
                }
            }
            ForEach(statuses) { status in
                LimitRow(status: status)
            }
        }
        .card()
    }
}

struct LimitRow: View {
    let status: CategoryLimitStatus

    private var color: Color {
        switch status.level() {
        case .over: return Palette.expense
        case .near: return Palette.star
        case .ok: return Palette.income
        }
    }

    private var caption: String {
        switch status.level() {
        case .over: return "Passou \((-status.remaining).brl) do limite"
        case .near: return "Faltam \(status.remaining.brl) · \(Int((status.ratio * 100).rounded()))% usado"
        case .ok: return "Faltam \(status.remaining.brl)"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                CategoryIcon(category: status.category, size: 24)
                Text(displayName(status.category))
                    .font(.subheadline)
                    .lineLimit(1)
                Spacer()
                Text("\(status.spent.brl) de \(status.limit.brl)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            ProgressView(value: min(status.ratio, 1))
                .tint(color)
            Text(caption)
                .font(.caption2)
                .foregroundStyle(status.level() == .ok ? Color.secondary : color)
        }
    }
}

// MARK: - Listas
