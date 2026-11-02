import SwiftUI
import KausMedia

/// A aba que substitui a planilha: gráficos e grade de categorias por mês do
/// ano escolhido, com os valores realizados do extrato e os meses à frente
/// preenchidos pelos compromissos.
struct PlanView: View {
    @Bindable var store: LedgerStore

    @State private var editing: RecurringCommitment?
    @State private var isCreating = false

    private var plan: AnnualPlan? { store.plan.annual }

    private let columns = [GridItem(.adaptive(minimum: 280), spacing: 12, alignment: .top)]

    var body: some View {
        NavigationStack {
            CardScreen {
                Picker("Ano", selection: Bindable(store.plan).year) {
                    ForEach(years, id: \.self) { year in
                        Text(String(year)).tag(year)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()

                if let plan, !plan.rows.isEmpty {
                    MetricGrid {
                        MetricTile(
                            title: "Receitas no ano",
                            value: plan.totals.reduce(0) { $0 + $1.income },
                            symbol: "arrow.down.left",
                            color: Palette.income
                        )
                        MetricTile(
                            title: "Despesas no ano",
                            value: plan.totals.reduce(0) { $0 + $1.expenses },
                            symbol: "arrow.up.right",
                            color: Palette.expense
                        )
                        MetricTile(
                            title: "Guardado no ano",
                            value: plan.totals.reduce(0) { $0 + $1.saved },
                            symbol: "lock.shield.fill",
                            color: .teal
                        )
                        MetricTile(
                            title: "Acumulado em dezembro",
                            value: plan.totals.last?.cumulative ?? 0,
                            symbol: "chart.line.uptrend.xyaxis",
                            color: Palette.star,
                            valueColor: (plan.totals.last?.cumulative ?? 0) < 0 ? Palette.expense : Palette.income
                        )
                    }

                    PlanCharts(year: store.plan.year, totals: plan.totals)

                    VStack(alignment: .leading, spacing: 12) {
                        CardHeader(title: "Grade anual") {
                            Text("valores em cinza são previstos")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        PlanGrid(plan: plan)
                    }
                    .card()
                } else {
                    EmptyState(
                        symbol: "calendar",
                        title: "Nada previsto para \(String(store.plan.year))",
                        message: "Importe extratos ou cadastre um compromisso para montar a grade."
                    ) {
                        Button("Novo compromisso", systemImage: "plus") { isCreating = true }
                    }
                    .card()
                }

                SectionTitle("Compromissos")
                if store.plan.commitments.isEmpty {
                    EmptyNote(symbol: "repeat", text: "Cadastre aluguel, luz, salário, aporte na caixinha…")
                        .card()
                }
                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(store.plan.commitments) { commitment in
                        Button {
                            editing = commitment
                        } label: {
                            CommitmentCard(commitment: commitment)
                        }
                        .buttonStyle(.plain)
                        .contextMenu {
                            Button("Editar…", systemImage: "pencil") { editing = commitment }
                            Button("Apagar", systemImage: "trash", role: .destructive) {
                                Task { await store.plan.deleteCommitment(commitment) }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Plano")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button { isCreating = true } label: { Label("Novo compromisso", systemImage: "plus") }
                }
            }
            .refreshable { await store.plan.reloadGrid() }
            .sheet(isPresented: $isCreating) {
                CommitmentSheet(store: store, commitment: nil)
            }
            .sheet(item: $editing) { commitment in
                CommitmentSheet(store: store, commitment: commitment)
            }
        }
    }

    private var years: [Int] {
        let current = YearMonth(date: Date()).year
        return Array((current - 1)...(current + 2))
    }
}
