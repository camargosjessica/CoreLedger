import SwiftUI
import KausMedia

/// A grade propriamente dita. Rolagem horizontal porque doze meses não cabem
/// na largura do iPhone.
struct PlanGrid: View {
    let plan: AnnualPlan

    private let labelWidth: CGFloat = 150
    private let columnWidth: CGFloat = 96

    var body: some View {
        ScrollView(.horizontal, showsIndicators: true) {
            VStack(alignment: .leading, spacing: 4) {
                header
                group("Receitas", rows: plan.incomeRows)
                group("Despesas", rows: plan.expenseRows)
                group("Guardado", rows: plan.savingRows)
                Divider()
                totalsRow("Saldo do mês", values: plan.totals.map(\.net))
                totalsRow("Fluxo de caixa", values: plan.totals.map(\.cashFlow))
                totalsRow("Acumulado", values: plan.totals.map(\.cumulative))
                totalsRow("Essenciais", values: plan.totals.map(\.essentialExpenses))
            }
            .padding(.bottom, 8)
        }
    }

    private var header: some View {
        HStack(spacing: 0) {
            Text("Categoria")
                .frame(width: labelWidth, alignment: .leading)
            ForEach(plan.totals) { totals in
                VStack(spacing: 2) {
                    Text(totals.month.startDate.shortMonthYear)
                        .lineLimit(1)
                    if totals.isForecast {
                        Text("previsto")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(width: columnWidth, alignment: .trailing)
            }
        }
        .font(.caption.weight(.semibold))
    }

    @ViewBuilder
    private func group(_ title: String, rows: [PlanRow]) -> some View {
        if !rows.isEmpty {
            Divider()
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            ForEach(rows) { row in
                HStack(spacing: 0) {
                    HStack(spacing: 4) {
                        if row.isEssential {
                            Image(systemName: "exclamationmark.circle")
                                .foregroundStyle(.secondary)
                        }
                        Text(row.category).lineLimit(1)
                    }
                    .frame(width: labelWidth, alignment: .leading)

                    ForEach(plan.months, id: \.description) { month in
                        let value = row.value(in: month)
                        Text(value == 0 ? "—" : value.brl)
                            .foregroundStyle(row.isRealized(in: month) ? Color.primary : Color.secondary)
                            .frame(width: columnWidth, alignment: .trailing)
                    }
                }
                .font(.caption)
            }
        }
    }

    private func totalsRow(_ title: String, values: [Money]) -> some View {
        HStack(spacing: 0) {
            Text(title)
                .frame(width: labelWidth, alignment: .leading)
            ForEach(Array(values.enumerated()), id: \.offset) { item in
                Text(item.element.brl)
                    .frame(width: columnWidth, alignment: .trailing)
            }
        }
        .font(.caption.weight(.semibold))
    }
}
