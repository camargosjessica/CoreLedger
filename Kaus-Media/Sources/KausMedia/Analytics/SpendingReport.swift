import Foundation

/// Como agrupar os gastos: pela categoria do lançamento ou pelas suas tags.
public enum SpendingGrouping: String, Codable, Sendable, CaseIterable {
    case category
    case tag

    public var title: String {
        switch self {
        case .category: return "Categoria"
        case .tag: return "Tag"
        }
    }
}

/// Quanto foi gasto num grupo (categoria ou tag), sempre positivo.
public struct SpendingSlice: Codable, Sendable, Hashable, Identifiable {
    public var group: String
    public var realized: Double
    /// Parcelas previstas que ainda não apareceram numa fatura.
    public var projected: Double

    public var total: Double { realized + projected }
    public var id: String { group }

    public init(group: String, realized: Double = 0, projected: Double = 0) {
        self.group = group
        self.realized = realized
        self.projected = projected
    }
}

public struct SpendingMonth: Codable, Sendable, Hashable, Identifiable {
    public var month: YearMonth
    /// Gasto do mês contando cada lançamento uma vez, mesmo com várias tags.
    public var total: Double
    public var projected: Double
    public var slices: [SpendingSlice]

    public var id: YearMonth { month }

    public init(month: YearMonth, total: Double = 0, projected: Double = 0, slices: [SpendingSlice] = []) {
        self.month = month
        self.total = total
        self.projected = projected
        self.slices = slices
    }
}

/// Gastos de um ano, mês a mês e somados, agrupados por categoria ou tag.
public struct SpendingReport: Codable, Sendable, Hashable {
    /// Grupo dos lançamentos sem nenhuma tag.
    public static let untagged = "Sem tag"

    public var year: Int
    public var grouping: SpendingGrouping
    /// Sempre os 12 meses, de janeiro a dezembro.
    public var months: [SpendingMonth]
    /// Do maior para o menor.
    public var totals: [SpendingSlice]
    public var total: Double

    public init(year: Int, grouping: SpendingGrouping, months: [SpendingMonth], totals: [SpendingSlice], total: Double) {
        self.year = year
        self.grouping = grouping
        self.months = months
        self.totals = totals
        self.total = total
    }
}

public enum SpendingAnalysis {
    public struct Input: Sendable {
        public var date: Date
        public var amount: Double
        public var category: String?
        public var tags: [String]
        public var isProjected: Bool

        public init(date: Date, amount: Double, category: String?, tags: [String] = [], isProjected: Bool = false) {
            self.date = date
            self.amount = amount
            self.category = category
            self.tags = tags
            self.isProjected = isProjected
        }
    }

    /// Só despesas entram. Transferências e aportes (`excludedCategories`) ficam
    /// de fora: o dinheiro só mudou de lugar. Agrupando por tag, um lançamento
    /// com duas tags conta nas duas, mas `total` o conta uma vez só.
    public static func make(
        _ inputs: [Input],
        year: Int,
        grouping: SpendingGrouping,
        excludedCategories: Set<String> = []
    ) -> SpendingReport {
        var months = (1...12).map { SpendingMonth(month: YearMonth(year: year, month: $0)) }
        var cells = Array(repeating: [String: SpendingSlice](), count: 12)
        var yearly: [String: SpendingSlice] = [:]

        for input in inputs where input.amount < 0 {
            let month = YearMonth(date: input.date)
            guard month.year == year else { continue }
            let category = input.category ?? CategoryRule.uncategorizedDebit
            guard !excludedCategories.contains(category) else { continue }

            let value = -input.amount
            let index = month.month - 1
            months[index].total += value
            if input.isProjected { months[index].projected += value }

            let groups: [String]
            switch grouping {
            case .category:
                groups = [category]
            case .tag:
                let tags = TagSet.normalize(input.tags)
                groups = tags.isEmpty ? [SpendingReport.untagged] : tags
            }
            for group in groups {
                add(value, projected: input.isProjected, to: group, in: &cells[index])
                add(value, projected: input.isProjected, to: group, in: &yearly)
            }
        }

        for index in months.indices {
            months[index].slices = sorted(cells[index])
        }
        return SpendingReport(
            year: year,
            grouping: grouping,
            months: months,
            totals: sorted(yearly),
            total: months.reduce(0) { $0 + $1.total }
        )
    }

    private static func add(_ value: Double, projected: Bool, to group: String, in slices: inout [String: SpendingSlice]) {
        var slice = slices[group] ?? SpendingSlice(group: group)
        if projected { slice.projected += value } else { slice.realized += value }
        slices[group] = slice
    }

    private static func sorted(_ slices: [String: SpendingSlice]) -> [SpendingSlice] {
        slices.values.sorted { $0.total != $1.total ? $0.total > $1.total : $0.group < $1.group }
    }
}
