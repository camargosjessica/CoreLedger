import Foundation

/// Agregação mensal e projeção dos próximos meses.
///
/// Três diferenças em relação a uma média simples:
/// 1. o agrupamento usa calendário UTC fixo (`LedgerCalendar`), então nenhum
///    lançamento muda de mês conforme o fuso do dispositivo;
/// 2. categorias marcadas como transferência ficam de fora — PIX e pagamento de
///    fatura inflariam entradas e saídas ao mesmo tempo;
/// 3. as parcelas futuras já contratadas entram no mês em que vão cair, somadas
///    à média histórica (e não substituídas por ela).
public enum Projection {
    public struct Input: Sendable {
        public var date: Date
        public var amount: Double
        public var category: String
        public var isProjected: Bool

        public init(date: Date, amount: Double, category: String, isProjected: Bool) {
            self.date = date
            self.amount = amount
            self.category = category
            self.isProjected = isProjected
        }
    }

    public static func project(
        _ inputs: [Input],
        transferCategories: Set<String> = [],
        forecastMonths: Int = 6,
        baseMonths: Int = 6,
        reference: Date = Date()
    ) -> LedgerProjection {
        let currentMonth = LedgerCalendar.startOfMonth(reference)
        let relevant = inputs.filter { !transferCategories.contains($0.category) }

        let realized = relevant.filter { !$0.isProjected }
        let committed = relevant.filter { $0.isProjected && LedgerCalendar.startOfMonth($0.date) > currentMonth }

        let history = summarize(realized).sorted { $0.month < $1.month }

        guard forecastMonths > 0 else {
            return LedgerProjection(history: history, forecast: [])
        }

        let average = monthlyAverage(of: history.filter { $0.month < currentMonth }, lastMonths: baseMonths)
        let committedByMonth = Dictionary(grouping: committed) { LedgerCalendar.startOfMonth($0.date) }

        let forecast: [MonthlySummary] = (1...forecastMonths).map { offset in
            let month = LedgerCalendar.addingMonths(offset, to: currentMonth)
            var byCategory = average
            var committedExpenses: Double = 0

            for input in committedByMonth[month] ?? [] {
                byCategory[input.category, default: 0] += input.amount
                if input.amount < 0 { committedExpenses += input.amount }
            }

            return MonthlySummary(
                month: month,
                income: byCategory.values.filter { $0 > 0 }.reduce(0, +),
                expenses: byCategory.values.filter { $0 < 0 }.reduce(0, +),
                byCategory: byCategory,
                isForecast: true,
                committedExpenses: committedExpenses
            )
        }

        return LedgerProjection(history: history, forecast: forecast)
    }

    static func summarize(_ inputs: [Input]) -> [MonthlySummary] {
        Dictionary(grouping: inputs) { LedgerCalendar.startOfMonth($0.date) }
            .map { month, items in
                var byCategory: [String: Double] = [:]
                for item in items { byCategory[item.category, default: 0] += item.amount }
                return MonthlySummary(
                    month: month,
                    income: items.filter { $0.amount > 0 }.reduce(0) { $0 + $1.amount },
                    expenses: items.filter { $0.amount < 0 }.reduce(0) { $0 + $1.amount },
                    byCategory: byCategory,
                    isForecast: false
                )
            }
    }

    /// Média por categoria dos últimos meses **fechados**.
    static func monthlyAverage(of history: [MonthlySummary], lastMonths: Int) -> [String: Double] {
        let base = Array(history.sorted { $0.month < $1.month }.suffix(max(1, lastMonths)))
        guard !base.isEmpty else { return [:] }

        var totals: [String: Double] = [:]
        for month in base {
            for (category, value) in month.byCategory { totals[category, default: 0] += value }
        }
        return totals.mapValues { $0 / Double(base.count) }
    }
}

extension Projection.Input {
    public init(transaction: TransactionDTO) {
        self.init(
            date: transaction.date,
            amount: transaction.amount,
            category: transaction.category ?? CategoryRule.uncategorizedDebit,
            isProjected: transaction.isProjected
        )
    }
}
