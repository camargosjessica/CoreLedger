import Charts
import SwiftUI
import KausMedia

/// O mês corrente da grade anual: quanto entrou, quanto saiu e quanto do
/// gasto é básico para sobreviver.
struct PlanMonthCard: View {
    let totals: PlanMonthTotals

    /// Despesas sobre receita; passa de 1 quando se gasta mais do que entra.
    private var usage: Double {
        guard totals.income > 0 else { return totals.expenses < 0 ? .infinity : 0 }
        return abs(totals.expenses) / totals.income
    }

    private var usageLabel: String {
        usage.isFinite
            ? "\(Int((usage * 100).rounded()))% da receita comprometida"
            : "Despesas sem receita no mês"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            CardHeader(title: "Plano do mês") {
                DeltaPill(text: totals.net.signedBRL, color: totals.net < 0 ? Palette.expense : Palette.income)
            }
            ProgressView(value: min(usage, 1))
                .tint(usage >= 1 ? Palette.expense : usage > 0.8 ? Palette.star : Palette.income)
            Text(usageLabel)
                .font(.caption)
                .foregroundStyle(.secondary)
            VStack(spacing: 6) {
                row("Receitas", totals.income, Palette.income)
                row("Despesas", totals.expenses, .primary)
                row("Essenciais", totals.essentialExpenses, Palette.star)
                row("Guardado", totals.saved, .teal)
                Divider()
                row("Acumulado", totals.cumulative, totals.cumulative < 0 ? Palette.expense : Palette.income)
            }
        }
        .card()
    }

    private func row(_ title: String, _ value: Money, _ color: Color) -> some View {
        HStack {
            Text(title)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value.brl)
                .monospacedDigit()
                .foregroundStyle(color)
        }
        .font(.subheadline)
    }
}

// MARK: - Limites
