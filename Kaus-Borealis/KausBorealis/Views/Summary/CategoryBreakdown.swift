import Charts
import SwiftUI
import KausMedia

struct CategoryTotal: Identifiable {
    var category: String
    var total: Money

    var id: String { category }
}

func expenseTotals(_ summary: MonthlySummary) -> [CategoryTotal] {
    summary.byCategory
        .filter { $0.value < 0 }
        .map { CategoryTotal(category: $0.key, total: abs($0.value)) }
        .sorted { $0.total > $1.total }
}

/// Atalho visual do mês: um bloco colorido por categoria de despesa.
struct CategoryStrip: View {
    let summary: MonthlySummary

    var body: some View {
        let totals = expenseTotals(summary)
        if !totals.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Text("Categorias · \(summary.month.monthYear)")
                    .font(.headline)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(totals) { entry in
                            CategoryTile(entry: entry)
                        }
                    }
                    .padding(.bottom, 4)
                }
            }
        }
    }
}

struct CategoryTile: View {
    let entry: CategoryTotal

    var body: some View {
        let style = CategoryStyle.of(entry.category)
        VStack(alignment: .leading, spacing: 6) {
            Image(systemName: style.symbol)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(style.color)
                .frame(width: 32, height: 32)
                .background(style.color.opacity(0.16), in: Circle())
            Spacer(minLength: 0)
            Text(displayName(entry.category))
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)
            Text(entry.total.brl)
                .font(.system(.callout, design: .rounded).weight(.bold).monospacedDigit())
        }
        .padding(14)
        .frame(width: 150, height: 120, alignment: .leading)
        .background(Palette.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(alignment: .bottom) {
            Capsule()
                .fill(style.color)
                .frame(height: 3)
                .padding(.horizontal, 14)
        }
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(Palette.hairline, lineWidth: 1)
        )
    }
}

/// Onde o dinheiro foi no mês: rosca com o total no centro e a fatia de cada categoria.
struct CategoryBreakdownCard: View {
    let summary: MonthlySummary

    var body: some View {
        let all = expenseTotals(summary)
        let total = all.reduce(0) { $0 + $1.total }
        let top = Array(all.prefix(6))
        VStack(alignment: .leading, spacing: 14) {
            CardHeader(title: "Despesas por categoria")
            if top.isEmpty {
                EmptyNote(symbol: "chart.pie", text: "Sem despesas neste mês.")
            } else {
                Chart(top) { entry in
                    SectorMark(
                        angle: .value("Total", entry.total),
                        innerRadius: .ratio(0.64),
                        angularInset: 1.5
                    )
                    .cornerRadius(4)
                    .foregroundStyle(CategoryStyle.of(entry.category).color)
                }
                .chartBackground { _ in
                    VStack(spacing: 2) {
                        Text("Total")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(total.brl)
                            .font(.system(.headline, design: .rounded).weight(.bold).monospacedDigit())
                            .minimumScaleFactor(0.6)
                            .lineLimit(1)
                    }
                    .padding(.horizontal, 40)
                }
                .frame(height: 180)
                VStack(spacing: 8) {
                    ForEach(top) { entry in
                        HStack(spacing: 8) {
                            Circle()
                                .fill(CategoryStyle.of(entry.category).color)
                                .frame(width: 8, height: 8)
                            Text(displayName(entry.category))
                                .font(.subheadline)
                                .lineLimit(1)
                            Spacer()
                            Text(entry.total.brl)
                                .font(.subheadline.monospacedDigit())
                            Text(percent(entry.total, of: total))
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.secondary)
                                .frame(width: 38, alignment: .trailing)
                        }
                    }
                }
            }
        }
        .card()
    }

    private func percent(_ value: Money, of total: Money) -> String {
        guard total > 0 else { return "" }
        return "\(Int((value / total * 100).rounded()))%"
    }
}

/// Primeira letra maiúscula, sem mexer no restante ("cartão de crédito" → "Cartão de crédito").
func displayName(_ category: String) -> String {
    category.prefix(1).uppercased() + category.dropFirst()
}

// MARK: - Plano e tendências
