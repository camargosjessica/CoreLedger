import SwiftUI
import KausMedia

/// Cápsula que abre um menu de filtro; destacada quando o filtro está ativo.
struct FilterChip<Content: View>: View {
    let title: String
    let symbol: String
    var isActive = false
    @ViewBuilder var content: Content

    var body: some View {
        Menu {
            content
        } label: {
            HStack(spacing: 6) {
                Image(systemName: symbol)
                Text(title).lineLimit(1)
                Image(systemName: "chevron.down")
                    .font(.caption2.weight(.bold))
            }
            .font(.subheadline.weight(.medium))
            .foregroundStyle(isActive ? AnyShapeStyle(TintShapeStyle()) : AnyShapeStyle(HierarchicalShapeStyle.primary))
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(
                isActive ? AnyShapeStyle(TintShapeStyle().opacity(0.15)) : AnyShapeStyle(Palette.raised),
                in: Capsule()
            )
        }
        .menuStyle(.button)
        .menuIndicator(.hidden)
        .buttonStyle(.plain)
        .fixedSize()
    }
}

/// Divisória entre linhas dentro de um cartão, alinhada ao texto e não ao ícone.
struct RowDivider: View {
    var inset: CGFloat = 48

    var body: some View {
        Divider().padding(.leading, inset)
    }
}

/// ‹ mês › com atalho para o mês atual, usado no topo das telas por período.
struct MonthStepper: View {
    @Binding var month: YearMonth
    @Environment(\.ledgerClock) private var clock

    private var isCurrent: Bool { month == clock.currentMonth() }

    var body: some View {
        HStack(spacing: 6) {
            stepButton("chevron.left", by: -1)
            Text(month.startDate.monthYear)
                .font(.subheadline.weight(.semibold))
                .frame(minWidth: 130)
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(Palette.raised, in: Capsule())
            stepButton("chevron.right", by: 1)
            if !isCurrent {
                Button("Hoje") { month = clock.currentMonth() }
                    .font(.subheadline)
                    .buttonStyle(.borderless)
            }
        }
    }

    private func stepButton(_ symbol: String, by offset: Int) -> some View {
        Button {
            month = month.adding(months: offset)
        } label: {
            Image(systemName: symbol)
                .font(.footnote.weight(.bold))
                .frame(width: 30, height: 30)
                .background(Palette.raised, in: Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(offset < 0 ? "Mês anterior" : "Próximo mês")
    }
}
