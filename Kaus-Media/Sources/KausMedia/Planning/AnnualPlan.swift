import Foundation

/// Uma linha da grade anual: uma categoria, com um valor por mês.
public struct PlanRow: Codable, Sendable, Hashable, Identifiable {
    public var category: String
    public var kind: RecurringCommitment.Kind
    public var tags: [String]
    /// Valor por mês, com sinal (despesa e aporte negativos), indexado por `YearMonth`.
    public var values: [String: Double]
    /// Meses em que o valor veio de lançamento já confirmado pelo extrato, e não
    /// de parcela projetada ou de compromisso planejado.
    public var realizedMonths: [String]

    public var id: String { category }
    public var total: Double { values.values.reduce(0, +) }
    public var isEssential: Bool { tags.contains(TagSet.essential) }

    public func value(in month: YearMonth) -> Double { values[month.description] ?? 0 }
    public func isRealized(in month: YearMonth) -> Bool { realizedMonths.contains(month.description) }

    public init(
        category: String,
        kind: RecurringCommitment.Kind,
        tags: [String] = [],
        values: [String: Double] = [:],
        realizedMonths: [String] = []
    ) {
        self.category = category
        self.kind = kind
        self.tags = tags
        self.values = values
        self.realizedMonths = realizedMonths
    }
}

/// Fechamento de um mês da grade: o rodapé da planilha.
public struct PlanMonthTotals: Codable, Sendable, Hashable, Identifiable {
    public var month: YearMonth
    public var isForecast: Bool
    public var income: Double
    /// Negativo.
    public var expenses: Double
    /// Negativo: saiu da conta, mas continua sendo seu.
    public var saved: Double
    /// Parte das despesas marcada como `essencial` (negativo).
    public var essentialExpenses: Double
    /// `income + expenses` — o que sobra antes de guardar.
    public var net: Double
    /// `net + saved` — o que de fato entra ou sai da conta no mês.
    public var cashFlow: Double
    /// Soma dos `cashFlow` até este mês, partindo do saldo inicial informado.
    public var cumulative: Double

    public var id: String { month.description }
}

/// Grade anual de despesas, receitas e aportes — a substituta da planilha.
///
/// Cada célula usa o lançamento real quando ele existe e cai para o
/// compromisso cadastrado quando o mês ainda não aconteceu. Meses passados
/// nunca são reescritos pelo planejamento: o extrato é a verdade.
public struct AnnualPlan: Codable, Sendable, Hashable {
    public var months: [YearMonth]
    public var rows: [PlanRow]
    public var totals: [PlanMonthTotals]

    public init(months: [YearMonth] = [], rows: [PlanRow] = [], totals: [PlanMonthTotals] = []) {
        self.months = months
        self.rows = rows
        self.totals = totals
    }

    public var expenseRows: [PlanRow] { rows.filter { $0.kind == .expense } }
    public var incomeRows: [PlanRow] { rows.filter { $0.kind == .income } }
    public var savingRows: [PlanRow] { rows.filter { $0.kind == .saving } }

    public static func build(
        from start: YearMonth,
        to end: YearMonth,
        transactions: [TransactionDTO],
        commitments: [RecurringCommitment],
        savingCategories: Set<String> = ["Guardado"],
        transferCategories: Set<String> = [],
        tagsByCategory: [String: [String]] = [:],
        openingBalance: Double = 0,
        reference: Date = Date()
    ) -> AnnualPlan {
        let months = YearMonth.range(from: start, to: end)
        guard !months.isEmpty else { return AnnualPlan() }

        let currentMonth = YearMonth(date: reference)
        let window = Set(months.map(\.description))
        // Transferências puras (PIX, pagamento de fatura) sairiam duas vezes na
        // grade: uma na conta de origem, outra na despesa que elas quitam.
        let ignored = transferCategories.subtracting(savingCategories)

        var realized: [String: [String: Double]] = [:]
        var projected: [String: [String: Double]] = [:]
        for transaction in transactions {
            let category = transaction.category ?? CategoryRule.uncategorizedDebit
            guard !ignored.contains(category) else { continue }
            let key = YearMonth(date: transaction.date).description
            guard window.contains(key) else { continue }
            if transaction.isProjected {
                projected[category, default: [:]][key, default: 0] += transaction.amount
            } else {
                realized[category, default: [:]][key, default: 0] += transaction.amount
            }
        }

        let commitmentsByCategory = Dictionary(grouping: commitments.filter { !ignored.contains($0.category) }) {
            $0.category
        }

        let categories = Set(realized.keys)
            .union(projected.keys)
            .union(commitmentsByCategory.keys)

        var rows: [PlanRow] = []
        for category in categories {
            let owners = commitmentsByCategory[category] ?? []
            let kind = resolveKind(
                category: category,
                commitments: owners,
                savingCategories: savingCategories,
                realized: realized[category] ?? [:]
            )
            let tags = TagSet.normalize(
                owners.flatMap(\.tags) + (tagsByCategory[category] ?? TagSet.suggested(for: category))
            )

            var values: [String: Double] = [:]
            var realizedMonths: [String] = []
            for month in months {
                let key = month.description
                let confirmed = realized[category]?[key] ?? 0
                let actual = confirmed + (projected[category]?[key] ?? 0)
                let planned = owners.reduce(0) { $0 + $1.plannedAmount(in: month) }
                // O compromisso só preenche o mês enquanto ele não tem lançamento
                // próprio, e nunca reescreve um mês já fechado.
                let usesPlan = actual == 0 && month >= currentMonth
                let value = usesPlan ? planned : actual
                guard value != 0 else { continue }
                values[key] = value
                if confirmed != 0 { realizedMonths.append(key) }
            }

            guard !values.isEmpty else { continue }
            rows.append(
                PlanRow(
                    category: category,
                    kind: kind,
                    tags: tags,
                    values: values,
                    realizedMonths: realizedMonths.sorted()
                )
            )
        }

        rows.sort { ($0.kind.sortOrder, $0.category) < ($1.kind.sortOrder, $1.category) }

        var cumulative = openingBalance
        var totals: [PlanMonthTotals] = []
        for month in months {
            var income: Double = 0
            var expenses: Double = 0
            var saved: Double = 0
            var essential: Double = 0

            for row in rows {
                let value = row.value(in: month)
                guard value != 0 else { continue }
                switch row.kind {
                case .income: income += value
                case .saving: saved += value
                case .expense:
                    expenses += value
                    if row.isEssential { essential += value }
                }
            }

            let net = income + expenses
            let cashFlow = net + saved
            cumulative += cashFlow
            totals.append(
                PlanMonthTotals(
                    month: month,
                    isForecast: month > currentMonth,
                    income: income,
                    expenses: expenses,
                    saved: saved,
                    essentialExpenses: essential,
                    net: net,
                    cashFlow: cashFlow,
                    cumulative: cumulative
                )
            )
        }

        return AnnualPlan(months: months, rows: rows, totals: totals)
    }

    private static func resolveKind(
        category: String,
        commitments: [RecurringCommitment],
        savingCategories: Set<String>,
        realized: [String: Double]
    ) -> RecurringCommitment.Kind {
        if let declared = commitments.first?.kind { return declared }
        if savingCategories.contains(category) { return .saving }
        return realized.values.reduce(0, +) > 0 ? .income : .expense
    }
}

extension RecurringCommitment.Kind {
    var sortOrder: Int {
        switch self {
        case .income: return 0
        case .expense: return 1
        case .saving: return 2
        }
    }
}
