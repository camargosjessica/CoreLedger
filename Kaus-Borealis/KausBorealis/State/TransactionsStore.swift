import Foundation
import Observation
import KausMedia

/// Lista de lançamentos com os filtros da aba Lançamentos, o resumo mensal,
/// as próximas parcelas e as importações.
@MainActor
@Observable
final class TransactionsStore {
    private(set) var items: [TransactionDTO] = []
    /// Próximas parcelas projetadas, independentes do filtro de período da
    /// lista e do limite de linhas da página de lançamentos.
    private(set) var upcoming: [TransactionDTO] = []
    private(set) var projection: LedgerProjection?
    private(set) var batches: [ImportBatchDTO] = []

    // MARK: Filtros

    var selectedCategory: String? {
        didSet { if selectedCategory != oldValue { scheduleListReload() } }
    }

    var selectedTag: String? {
        didSet { if selectedTag != oldValue { scheduleListReload() } }
    }

    var period: Period = .all {
        didSet { if period != oldValue { scheduleListReload() } }
    }

    /// Mês do período `.month`. Aceita meses futuros, para ver as parcelas previstas.
    var selectedMonth: YearMonth {
        didSet { if period == .month, selectedMonth != oldValue { scheduleListReload() } }
    }

    private var searchTerm = ""

    /// Consulta da lista em andamento. Uma troca de filtro cancela a anterior,
    /// e só a resposta da consulta mais recente chega à tela.
    @ObservationIgnored private var listTask: Task<Void, Never>?

    @ObservationIgnored private let session: LedgerSession

    init(session: LedgerSession) {
        self.session = session
        self.selectedMonth = session.clock.currentMonth()
    }

    enum Period: String, CaseIterable, Identifiable {
        case all
        case thisMonth
        case last3Months
        case last12Months
        case month

        var id: String { rawValue }

        var title: String {
            switch self {
            case .all: return "Tudo"
            case .thisMonth: return "Mês"
            case .last3Months: return "3 meses"
            case .last12Months: return "12 meses"
            case .month: return "Escolher"
            }
        }

        /// Primeiro dia do intervalo; `nil` quando não há limite inferior.
        func start(now: Date) -> Date? {
            switch self {
            case .all, .month: return nil
            case .thisMonth: return LedgerCalendar.startOfMonth(now)
            case .last3Months: return LedgerCalendar.startOfMonth(LedgerCalendar.addingMonths(-2, to: now))
            case .last12Months: return LedgerCalendar.startOfMonth(LedgerCalendar.addingMonths(-11, to: now))
            }
        }

        /// Último dia do intervalo. Sem ele, um lançamento datado no futuro
        /// (ou uma parcela projetada) entraria no total do período escolhido.
        func end(now: Date) -> Date? {
            guard self != .all, self != .month else { return nil }
            let nextMonth = LedgerCalendar.addingMonths(1, to: LedgerCalendar.startOfMonth(now))
            return LedgerCalendar.addingDays(-1, to: nextMonth)
        }
    }

    private var periodStart: Date? {
        period == .month ? selectedMonth.startDate : period.start(now: session.clock.now())
    }

    private var periodEnd: Date? {
        period == .month
            ? LedgerCalendar.addingDays(-1, to: selectedMonth.adding(months: 1).startDate)
            : period.end(now: session.clock.now())
    }

    /// Consulta com os filtros atuais.
    var query: TransactionQuery {
        TransactionQuery(
            accountID: session.selectedAccountID,
            search: searchTerm.isEmpty ? nil : searchTerm,
            from: periodStart,
            to: periodEnd,
            category: selectedCategory,
            tag: selectedTag
        )
    }

    // MARK: Carga

    /// Parcelas são mensais, então três meses à frente sempre trazem a próxima.
    private static let upcomingWindowDays = 92

    /// A lista filtrada e as próximas parcelas.
    ///
    /// Só retorna quando a consulta mais recente terminou: se outra mudança
    /// substituir esta no meio do caminho, espera a substituta.
    func reloadList() async {
        scheduleListReload()
        await Self.awaitLatest { self.listTask }
    }

    /// O filtro é capturado agora: a consulta reflete o estado do momento da
    /// mudança, e uma consulta já cancelada nem chega a sair.
    /// Espera a tarefa atual e, se ela tiver sido trocada por outra enquanto
    /// isso, espera a nova — até não haver substituição.
    static func awaitLatest(_ current: () -> Task<Void, Never>?) async {
        var waited: Task<Void, Never>?
        while let task = current(), task != waited {
            await task.value
            waited = task
        }
    }

    private func scheduleListReload() {
        listTask?.cancel()
        listTask = Task { [query] in await fetchList(query) }
    }

    private func fetchList(_ query: TransactionQuery) async {
        guard !Task.isCancelled else { return }
        let accountID = query.accountID
        await session.run {
            let api = session.api
            let today = session.clock.today()
            async let list = api.transactions(query)
            async let upcoming = api.transactions(TransactionQuery(
                accountID: accountID,
                from: today,
                to: LedgerCalendar.addingDays(Self.upcomingWindowDays, to: today),
                limit: 1000
            ))
            let loaded = try await list
            let next = try await upcoming
            try Task.checkCancellation()
            self.items = loaded
            self.upcoming = next.filter(\.isProjected).sorted { $0.date < $1.date }
        }
        session.didReloadTransactions()
    }

    func reloadSummary() async {
        await session.run {
            self.projection = try await session.api.summary(accountID: session.selectedAccountID, forecastMonths: 6)
        }
    }

    func reloadBatches() async {
        await session.run {
            self.batches = try await session.api.importBatches(accountID: session.selectedAccountID)
        }
    }

    func search(_ term: String) async {
        searchTerm = term
        await reloadList()
    }

    /// Todos os lançamentos dos filtros atuais, sem o limite de uma página da lista.
    func allForExport() async -> [TransactionDTO]? {
        let pageSize = 1000
        var all: [TransactionDTO] = []
        var page = query
        page.limit = pageSize
        let finished = await session.run {
            while true {
                page.offset = all.count
                let loaded = try await session.api.transactions(page)
                all += loaded
                if loaded.count < pageSize { break }
            }
        }
        return finished ? all : nil
    }

    // MARK: Mudanças

    /// O que muda junto com um lançamento: saldos, resumo e a grade do plano.
    private static let affected: LedgerStore.Scope = [.transactions, .accounts, .summary, .plan]

    /// Parcelas de um lançamento manual: todas sobem antes de recarregar a lista.
    func add(_ transactions: [TransactionDTO]) async {
        await session.run {
            for transaction in transactions {
                _ = try await session.api.createTransaction(transaction)
            }
        }
        await session.refresh(Self.affected)
    }

    func update(_ transaction: TransactionDTO) async {
        guard let id = transaction.id else { return }
        await session.run { _ = try await session.api.updateTransaction(id: id, transaction) }
        await session.refresh(Self.affected)
    }

    /// Salva o lançamento e, se a conta de destino mudou, liga, troca ou
    /// desfaz a contrapartida da transferência.
    func update(_ transaction: TransactionDTO, transferTo accountID: UUID?) async {
        guard let id = transaction.id else { return }
        let transferChanged = accountID != transaction.transferAccountID
        await session.run {
            let api = session.api
            // Desliga antes de editar: a origem pode estar indo para a conta
            // que hoje recebe a contrapartida.
            if transferChanged, transaction.transferAccountID != nil {
                _ = try await api.setTransfer(id: id, accountID: nil)
            }
            _ = try await api.updateTransaction(id: id, transaction)
            if transferChanged, let accountID {
                _ = try await api.setTransfer(id: id, accountID: accountID)
            }
        }
        await session.refresh(Self.affected)
    }

    /// Atalho do menu de contexto da lista, sem abrir o editor.
    func setCategory(_ category: String, on transaction: TransactionDTO) async {
        var updated = transaction
        updated.category = category
        await update(updated)
    }

    func delete(_ transaction: TransactionDTO) async {
        guard let id = transaction.id else { return }
        await session.run { try await session.api.deleteTransaction(id: id) }
        await session.refresh(Self.affected)
    }

    func delete(ids: [UUID]) async {
        guard !ids.isEmpty else { return }
        await session.run { _ = try await session.api.deleteTransactions(ids: ids) }
        await session.refresh(Self.affected)
    }

    func update(_ request: BulkUpdateRequest) async {
        guard !request.ids.isEmpty else { return }
        await session.run { _ = try await session.api.updateTransactions(request) }
        await session.refresh(Self.affected)
    }

    // MARK: Importação

    /// Devolve o relatório para a tela mostrar quantos entraram, quantos eram
    /// duplicados e quais linhas falharam.
    /// Lança o erro em vez de usar `errorMessage`, para a tela mostrá-lo junto do arquivo.
    func importStatement(_ request: ImportRequestDTO) async throws -> ImportReportDTO {
        let report = try await session.api.importStatement(request)
        await session.refresh(Self.affected.union(.batches))
        return report
    }

    /// Desfaz a importação inteira: apaga o que ela criou e devolve as projeções
    /// confirmadas ao estado anterior.
    func undoImport(batchID: UUID) async -> BulkDeleteResponse? {
        var response: BulkDeleteResponse?
        await session.run { response = try await session.api.undoImport(batchID: batchID) }
        await session.refresh(Self.affected.union(.batches))
        return response
    }

    // MARK: Análise

    func spending(
        year: Int,
        grouping: SpendingGrouping,
        accountID: UUID?,
        accountKind: AccountKind?
    ) async -> SpendingReport? {
        var report: SpendingReport?
        await session.run {
            report = try await session.api.spending(
                year: year,
                grouping: grouping,
                accountID: accountID,
                accountKind: accountKind
            )
        }
        return report
    }

    /// Volta os filtros ao padrão (depois de apagar tudo, por exemplo).
    func clearLabelFilters() {
        selectedCategory = nil
        selectedTag = nil
    }
}
