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

        var entries: [String: [String: [TransactionDTO]]] = [:]
        for transaction in transactions {
            let category = transaction.category ?? CategoryRule.uncategorizedDebit
            guard !ignored.contains(category) else { continue }
            let key = YearMonth(date: transaction.date).description
            guard window.contains(key) else { continue }
            entries[category, default: [:]][key, default: []].append(transaction)
        }

        let commitmentsByCategory = Dictionary(grouping: commitments.filter { !ignored.contains($0.category) }) {
            $0.category
        }

        let categories = Set(entries.keys).union(commitmentsByCategory.keys)

        var rows: [PlanRow] = []
        var essentialByMonth: [String: Double] = [:]
        for category in categories {
            let owners = commitmentsByCategory[category] ?? []
            let byMonth = entries[category] ?? [:]
            let kind = resolveKind(
                category: category,
                commitments: owners,
                savingCategories: savingCategories,
                recorded: byMonth.values.flatMap { $0 }
            )
            let tags = TagSet.normalize(
                owners.flatMap(\.tags) + (tagsByCategory[category] ?? TagSet.suggested(for: category))
            )
            // Sem tags próprias, o lançamento ou compromisso herda as da linha.
            let isEssential: ([String]) -> Bool = { own in
                (own.isEmpty ? tags : own).contains(TagSet.essential)
            }

            var values: [String: Double] = [:]
            var realizedMonths: [String] = []
            for month in months {
                let key = month.description
                let recorded = byMonth[key] ?? []
                var value = recorded.reduce(0) { $0 + $1.amount }
                var essential = recorded.reduce(0) { isEssential($1.tags) ? $0 + $1.amount : $0 }
                // Meses já fechados ficam só com o extrato. Do mês atual em diante,
                // o que não casou por nome vale o maior entre o lançado e o previsto:
                // a conta que ainda não caiu continua prevista, e o gasto que já
                // passou do previsto aparece inteiro.
                if month >= currentMonth {
                    let split = match(owners, in: month, recorded: recorded)
                    let plannedRest = split.open.reduce(0) { $0 + $1.plannedAmount(in: month) }
                    let actualRest = split.unmatched.reduce(0) { $0 + $1.amount }
                    if plannedRest != 0 && abs(plannedRest) > abs(actualRest) {
                        value += plannedRest - actualRest
                        essential -= split.unmatched.reduce(0) { isEssential($1.tags) ? $0 + $1.amount : $0 }
                        essential += split.open.reduce(0) {
                            isEssential($1.tags) ? $0 + $1.plannedAmount(in: month) : $0
                        }
                    }
                }
                guard value != 0 || !recorded.isEmpty else { continue }
                values[key] = value
                if recorded.contains(where: { !$0.isProjected }) { realizedMonths.append(key) }
                if kind == .expense { essentialByMonth[key, default: 0] += essential }
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

            for row in rows {
                let value = row.value(in: month)
                guard value != 0 else { continue }
                switch row.kind {
                case .income: income += value
                case .saving: saved += value
                case .expense: expenses += value
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
                    essentialExpenses: essentialByMonth[month.description] ?? 0,
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
        recorded: [TransactionDTO]
    ) -> RecurringCommitment.Kind {
        if let declared = commitments.first?.kind { return declared }
        if savingCategories.contains(category) { return .saving }
        return recorded.reduce(0) { $0 + $1.amount } > 0 ? .income : .expense
    }

    /// Separa os compromissos do mês que já têm lançamento com o nome deles na
    /// descrição. Cada lançamento quita no máximo um compromisso.
    private static func match(
        _ commitments: [RecurringCommitment],
        in month: YearMonth,
        recorded: [TransactionDTO]
    ) -> (open: [RecurringCommitment], unmatched: [TransactionDTO]) {
        var open = commitments.filter { $0.plannedAmount(in: month) != 0 }
        var unmatched: [TransactionDTO] = []
        for transaction in recorded {
            let description = TextNormalizer.normalize(transaction.description)
            let byName = open.firstIndex { commitment in
                let name = TextNormalizer.normalize(commitment.name)
                return !name.isEmpty && description.contains(name)
            }
            if let byName {
                open.remove(at: byName)
            } else {
                unmatched.append(transaction)
            }
        }
        return (open, unmatched)
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
