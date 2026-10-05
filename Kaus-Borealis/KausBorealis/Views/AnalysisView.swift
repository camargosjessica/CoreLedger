import Charts
import SwiftUI
import KausMedia

/// Para onde foi o dinheiro: gasto de cada mês dividido por categoria ou tag e
/// o ranking do ano, para um cartão, todos os cartões ou todas as contas.
struct AnalysisView: View {
    @Bindable var store: LedgerStore
    @State private var year = YearMonth(date: Date()).year
    @State private var grouping: SpendingGrouping = .category
    @State private var scope: Scope = .cards
    @State private var report: SpendingReport?
    @State private var selectedLabel: String?

    /// Grupos com cor própria no gráfico; o resto vira "Demais" (não "Outros", que é uma categoria).
    private static let chartGroups = 7
    private static let others = "Demais"

    enum Scope: Hashable {
        case all
        case cards
        case account(UUID)
    }

    private struct Request: Hashable {
        var year: Int
        var grouping: SpendingGrouping
        var scope: Scope
        var accounts: [UUID]
        var dataGeneration: Int
    }

    var body: some View {
        NavigationStack {
            CardScreen {
                filters
                if let report {
                    metrics(report)
                    chart(report)
                    breakdown(report)
                } else {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                }
            }
            .navigationTitle("Análise")
            .refreshable { await load() }
            .task(id: request) {
                await load()
            }
        }
    }

    private var request: Request {
        Request(
            year: year,
            grouping: grouping,
            scope: scope,
            accounts: store.accounts.compactMap(\.id),
            dataGeneration: store.dataGeneration
        )
    }

    private func load() async {
        let accountID: UUID?
        let kind: AccountKind?
        switch scope {
        case .all: (accountID, kind) = (nil, nil)
        case .cards: (accountID, kind) = (nil, .creditCard)
        case .account(let id): (accountID, kind) = (id, nil)
        }
        guard let loaded = await store.spending(year: year, grouping: grouping, accountID: accountID, accountKind: kind) else { return }
        report = loaded
        if let selectedLabel, !loaded.months.contains(where: { label($0.month) == selectedLabel }) {
            self.selectedLabel = nil
        }
    }

    // MARK: Filtros

    private var scopeTitle: String {
        switch scope {
        case .all: return "Todas as contas"
        case .cards: return "Todos os cartões"
        case .account(let id): return store.accounts.first { $0.id == id }?.name ?? "Conta"
        }
    }

    private var filters: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Button { year -= 1 } label: { Image(systemName: "chevron.left") }
                    .buttonStyle(.borderless)
                Text(String(year))
                    .font(.title3.weight(.semibold).monospacedDigit())
                    .frame(minWidth: 60)
                Button { year += 1 } label: { Image(systemName: "chevron.right") }
                    .buttonStyle(.borderless)
                Spacer()
                Picker("Agrupar por", selection: $grouping) {
                    ForEach(SpendingGrouping.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                .fixedSize()
            }
            FilterChip(title: scopeTitle, symbol: "creditcard", isActive: scope != .all) {
                Picker("Contas", selection: $scope) {
                    Text("Todos os cartões").tag(Scope.cards)
                    Text("Todas as contas").tag(Scope.all)
                    ForEach(store.accounts) { account in
                        if let id = account.id {
                            Text(account.name).tag(Scope.account(id))
                        }
                    }
                }
                .pickerStyle(.inline)
            }
        }
        .card()
    }

    // MARK: Números do ano

    private func metrics(_ report: SpendingReport) -> some View {
        let activeMonths = report.months.filter { $0.total > 0 }.count
        return MetricGrid {
            MetricTile(title: "Gasto em \(report.year)", value: report.total, symbol: "cart.fill", color: .red)
            MetricTile(
                title: "Média por mês",
                value: activeMonths == 0 ? 0 : report.total / Double(activeMonths),
                symbol: "chart.bar.fill",
                color: .orange
            )
            MetricTile(
                title: "Ainda previsto",
                value: report.months.reduce(0) { $0 + $1.projected },
                symbol: "clock.fill",
                color: .gray
            )
            if let top = report.totals.first {
                MetricTile(
                    title: "Maior: \(top.group)",
                    value: top.total,
                    symbol: CategoryStyle.of(top.group).symbol,
                    color: CategoryStyle.of(top.group).color
                )
            }
        }
    }

    // MARK: Gráfico mensal

    private struct BarPoint: Identifiable {
        var month: String
        var group: String
        var value: Double
        var isProjected: Bool

        var id: String { "\(month)|\(group)|\(isProjected)" }
    }

    private func label(_ month: YearMonth) -> String { month.startDate.shortMonth }

    private func chartGroups(_ report: SpendingReport) -> [String] {
        let top = report.totals.prefix(Self.chartGroups).map(\.group)
        return report.totals.count > Self.chartGroups ? top + [Self.others] : top
    }

    private func points(_ report: SpendingReport) -> [BarPoint] {
        let top = Set(report.totals.prefix(Self.chartGroups).map(\.group))
        return report.months.flatMap { month in
            var merged: [String: SpendingSlice] = [:]
            for slice in month.slices {
                let group = top.contains(slice.group) ? slice.group : Self.others
                var current = merged[group] ?? SpendingSlice(group: group)
                current.realized += slice.realized
                current.projected += slice.projected
                merged[group] = current
            }
            return merged.values.flatMap { slice in
                [
                    BarPoint(month: label(month.month), group: slice.group, value: slice.realized, isProjected: false),
                    BarPoint(month: label(month.month), group: slice.group, value: slice.projected, isProjected: true)
                ].filter { $0.value > 0 }
            }
        }
    }

    private func color(_ group: String) -> Color {
        group == Self.others ? .gray : CategoryStyle.of(group).color
    }

    private func chart(_ report: SpendingReport) -> some View {
        let groups = chartGroups(report)
        return VStack(alignment: .leading, spacing: 12) {
            CardHeader(title: "Gasto por mês") {
                if selectedLabel != nil {
                    Button("Ver o ano") { selectedLabel = nil }
                        .font(.caption)
                }
            }
            if report.total == 0 {
                Text("Sem despesas neste ano.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Chart(points(report)) { point in
                    BarMark(
                        x: .value("Mês", point.month),
                        y: .value("Gasto", point.value)
                    )
                    .foregroundStyle(by: .value("Grupo", point.group))
                    .opacity(selectedLabel == nil || selectedLabel == point.month ? (point.isProjected ? 0.45 : 1) : 0.25)
                }
                .chartXScale(domain: report.months.map { label($0.month) })
                .chartForegroundStyleScale(domain: groups, range: groups.map(color))
                .chartXSelection(value: $selectedLabel)
                .chartYAxis {
                    AxisMarks { value in
                        AxisGridLine()
                        AxisValueLabel {
                            if let amount = value.as(Double.self) {
                                Text(amount, format: .number.notation(.compactName))
                            }
                        }
                    }
                }
                .frame(height: 260)
                Text("Toque num mês para ver o detalhe. Barras mais claras são parcelas previstas.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .card()
    }

    // MARK: Ranking

    private func breakdown(_ report: SpendingReport) -> some View {
        let month = report.months.first { label($0.month) == selectedLabel }
        let slices = month?.slices ?? report.totals
        let total = month?.total ?? report.total
        let title = month.map { "Detalhe de \($0.month.startDate.monthYear)" }
            ?? "\(report.grouping == .category ? "Categorias" : "Tags") de \(report.year)"

        return VStack(alignment: .leading, spacing: 12) {
            CardHeader(title: title) {
                Text(total.brl)
                    .font(.subheadline.weight(.semibold).monospacedDigit())
            }
            if slices.isEmpty {
                Text("Sem despesas.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            ForEach(slices) { slice in
                HStack(spacing: 12) {
                    CategoryIcon(category: slice.group, size: 32)
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(slice.group)
                                .font(.subheadline.weight(.medium))
                            Spacer()
                            Text(slice.total.brl)
                                .font(.subheadline.monospacedDigit())
                        }
                        ProgressView(value: total > 0 ? min(slice.total / total, 1) : 0)
                            .tint(color(slice.group))
                        HStack {
                            Text(total > 0 ? "\(Int((slice.total / total * 100).rounded()))%" : "")
                            Spacer()
                            if slice.projected > 0 {
                                Text("\(slice.projected.brl) previsto")
                            }
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                }
            }
            if report.grouping == .tag {
                Text("Um lançamento com mais de uma tag aparece em cada uma; o total conta ele uma vez só.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .card()
    }
}
