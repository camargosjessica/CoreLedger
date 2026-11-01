import SwiftUI
import KausMedia

/// Tela própria de cada conta ou cartão, aberta pela barra lateral: saldo ou
/// fatura, resumo do mês, maiores categorias e os lançamentos do mês.
struct AccountDetailView: View {
    @Bindable var store: LedgerStore
    let accountID: UUID

    @State private var month = YearMonth(date: Date())
    @State private var transactions: [TransactionDTO] = []
    @State private var hasLoaded = false
    @State private var editing: TransactionDTO?
    @State private var isEditingAccount = false
    @State private var isImporting = false

    private var account: AccountDTO? {
        store.accounts.first { $0.id == accountID }
    }

    private var isCard: Bool { account?.kind == .creditCard }

    private var effective: [TransactionDTO] { transactions.filter { !$0.isProjected } }
    private var income: Double { effective.filter { $0.amount > 0 }.reduce(0) { $0 + $1.amount } }
    private var expenses: Double { effective.filter { $0.amount < 0 }.reduce(0) { $0 + $1.amount } }
    private var invoice: Double { -transactions.reduce(0) { $0 + $1.amount } }
    private var installments: Double {
        -transactions.filter { $0.installment != nil }.reduce(0) { $0 + $1.amount }
    }

    private var topCategories: [(category: String, total: Double)] {
        Dictionary(grouping: transactions.filter { $0.amount < 0 && $0.transferAccountID == nil }) {
            CategoryPath.parent(of: $0.category ?? CategoryRule.uncategorizedDebit)
        }
        .map { (category: $0.key, total: -$0.value.reduce(0) { $0 + $1.amount }) }
        .sorted { $0.total > $1.total }
        .prefix(5)
        .map { $0 }
    }

    private var days: [(day: Date, items: [TransactionDTO])] {
        Dictionary(grouping: transactions) { LedgerCalendar.startOfDay($0.date) }
            .map { (day: $0.key, items: $0.value) }
            .sorted { $0.day > $1.day }
    }

    var body: some View {
        CardScreen {
            if let account {
                AccountHero(account: account)
                MonthStepper(month: $month)
                metrics(for: account)
                if !topCategories.isEmpty {
                    categoriesCard
                }
                transactionsCard
            } else {
                EmptyState(
                    symbol: "questionmark.folder",
                    title: "Conta não encontrada",
                    message: "Ela pode ter sido apagada em outro aparelho."
                )
                .card()
            }
        }
        .navigationTitle(account?.name ?? "Conta")
        .toolbar {
            if account != nil {
                Button { isImporting = true } label: {
                    Label(isCard ? "Importar fatura" : "Importar extrato", systemImage: "square.and.arrow.down")
                }
                Button { isEditingAccount = true } label: {
                    Label("Editar conta", systemImage: "pencil")
                }
            }
        }
        .task(id: "\(month)-\(store.dataGeneration)") {
            transactions = await store.transactions(of: accountID, in: month)
            hasLoaded = true
        }
        .refreshable { await store.reload() }
        .sheet(item: $editing) { transaction in
            EditTransactionSheet(store: store, transaction: transaction)
        }
        .sheet(isPresented: $isEditingAccount) {
            NavigationStack { AccountForm(store: store, account: account) }
        }
        .sheet(isPresented: $isImporting) {
            ImportView(store: store, initialAccountID: accountID)
        }
    }

    @ViewBuilder
    private func metrics(for account: AccountDTO) -> some View {
        MetricGrid {
            if isCard {
                MetricTile(
                    title: "Fatura do mês",
                    value: invoice,
                    symbol: "doc.text.fill",
                    color: account.kind.tint,
                    caption: "\(transactions.count) lançamento(s)"
                )
                MetricTile(
                    title: "Parcelas no mês",
                    value: installments,
                    symbol: "square.stack.3d.down.right.fill",
                    color: Palette.star,
                    caption: installments > 0 ? "\(Int((installments / max(invoice, 1) * 100).rounded()))% da fatura" : "Nada parcelado"
                )
                MetricTile(
                    title: "Dívida no cartão",
                    value: account.balance ?? 0,
                    symbol: "creditcard.trianglebadge.exclamationmark",
                    color: Palette.expense,
                    valueColor: (account.balance ?? 0) < 0 ? Palette.expense : .primary,
                    caption: "Inclui parcelas futuras"
                )
            } else {
                MetricTile(
                    title: "Entradas",
                    value: income,
                    symbol: "arrow.down.circle.fill",
                    color: Palette.income,
                    valueColor: Palette.income
                )
                MetricTile(
                    title: "Saídas",
                    value: expenses,
                    symbol: "arrow.up.circle.fill",
                    color: Palette.expense
                )
                MetricTile(
                    title: "Resultado do mês",
                    value: income + expenses,
                    symbol: "plusminus.circle.fill",
                    color: account.kind.tint,
                    valueColor: income + expenses < 0 ? Palette.expense : Palette.income
                )
            }
        }
    }

    private var categoriesCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            CardHeader(title: isCard ? "Para onde foi a fatura" : "Maiores gastos")
            let largest = topCategories.first?.total ?? 1
            ForEach(topCategories, id: \.category) { item in
                HStack(spacing: 12) {
                    CategoryIcon(category: item.category, size: 30)
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text(item.category)
                                .font(.subheadline.weight(.medium))
                                .lineLimit(1)
                            Spacer()
                            Text(item.total.brl)
                                .font(.subheadline.monospacedDigit())
                        }
                        GeometryReader { proxy in
                            Capsule()
                                .fill(Palette.raised)
                                .overlay(alignment: .leading) {
                                    Capsule()
                                        .fill(CategoryStyle.of(item.category).color.gradient)
                                        .frame(width: proxy.size.width * max(item.total / largest, 0.02))
                                }
                        }
                        .frame(height: 6)
                    }
                }
            }
        }
        .card()
    }

    private var transactionsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            CardHeader(title: "Lançamentos") {
                if !transactions.isEmpty {
                    Text("\(transactions.count)")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Palette.raised, in: Capsule())
                }
            }
            if transactions.isEmpty {
                if hasLoaded {
                    EmptyState(
                        symbol: isCard ? "creditcard" : "building.columns",
                        title: "Nada em \(month.startDate.monthYear)",
                        message: isCard
                            ? "Importe a fatura deste mês para ver os gastos do cartão."
                            : "Importe o extrato para ver as entradas e saídas desta conta."
                    ) {
                        Button(isCard ? "Importar fatura" : "Importar extrato", systemImage: "square.and.arrow.down") {
                            isImporting = true
                        }
                    }
                } else {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                        .padding()
                }
            } else {
                ForEach(days, id: \.day) { group in
                    Text(group.day.shortDay)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .textCase(.uppercase)
                        .padding(.top, 4)
                    ForEach(group.items) { transaction in
                        Button { editing = transaction } label: {
                            TransactionRow(transaction: transaction)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        if transaction.id != group.items.last?.id {
                            RowDivider()
                        }
                    }
                }
            }
        }
        .card()
    }
}

/// Destaque do topo: cartão de crédito desenhado como um cartão de verdade;
/// as demais contas, como um painel de saldo na cor do tipo.
private struct AccountHero: View {
    let account: AccountDTO

    private var tint: Color { account.kind.tint }
    private var balance: Double { account.balance ?? 0 }

    var body: some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [tint.opacity(0.95), Color(hex: 0x0A0F1F)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            Circle()
                .fill(Palette.star.opacity(0.18))
                .frame(width: 220, height: 220)
                .blur(radius: 30)
                .offset(x: 180, y: -90)
            Image(systemName: "sparkle")
                .font(.system(size: 14))
                .foregroundStyle(Palette.star)
                .offset(x: 24, y: 22)
                .frame(maxWidth: .infinity, alignment: .trailing)
                .padding(.trailing, 40)

            VStack(alignment: .leading, spacing: 18) {
                HStack(spacing: 12) {
                    if account.kind == .creditCard {
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(Palette.star.gradient)
                            .frame(width: 42, height: 30)
                            .overlay {
                                Image(systemName: "simcard.fill")
                                    .font(.system(size: 14))
                                    .foregroundStyle(.black.opacity(0.35))
                            }
                    } else {
                        Image(systemName: account.kind.symbol)
                            .font(.system(size: 18, weight: .semibold))
                            .frame(width: 42, height: 42)
                            .background(.white.opacity(0.16), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text(account.name)
                            .font(.headline)
                        Text(account.kind.displayName)
                            .font(.caption)
                            .opacity(0.75)
                    }
                    Spacer()
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(account.kind == .creditCard ? "Dívida atual" : "Saldo atual")
                        .font(.caption.weight(.medium))
                        .textCase(.uppercase)
                        .opacity(0.7)
                    Text(account.balance?.brl ?? "—")
                        .font(.system(size: 34, weight: .bold, design: .rounded).monospacedDigit())
                        .minimumScaleFactor(0.5)
                        .lineLimit(1)
                }

                if let count = account.transactionCount {
                    Text("\(count) lançamentos no total")
                        .font(.caption)
                        .opacity(0.7)
                }
            }
            .padding(22)
        }
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity, minHeight: 190)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
    }
}
