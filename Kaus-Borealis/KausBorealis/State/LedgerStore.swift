import Foundation
import Observation
import KausMedia

/// Estado compartilhado pelas abas. Uma única cópia dos dados evita que cada
/// tela mantenha (e desatualize) a sua.
@MainActor
@Observable
final class LedgerStore {
    private(set) var accounts: [AccountDTO] = []
    private(set) var transactions: [TransactionDTO] = []
    private(set) var rules: [CategoryRule] = []
    private(set) var projection: LedgerProjection?
    private(set) var batches: [ImportBatchDTO] = []
    private(set) var position: FinancialPosition?
    private(set) var plan: AnnualPlan?
    private(set) var commitments: [RecurringCommitment] = []
    private(set) var knownTags: [String] = []
    /// Próximas parcelas projetadas, independentes do filtro de período da
    /// lista e do limite de linhas da página de lançamentos.
    private(set) var upcoming: [TransactionDTO] = []

    /// Ano exibido na grade anual, no formato da planilha (janeiro a dezembro).
    var planYear: Int = YearMonth(date: Date()).year {
        didSet { Task { await reloadPlan() } }
    }

    private(set) var isLoading = false
    var errorMessage: String?
    private var searchTerm = ""

    /// Conta selecionada nos filtros; `nil` significa todas.
    var selectedAccountID: UUID? {
        didSet { Task { await reload() } }
    }

    /// Filtros da lista de lançamentos.
    var selectedCategory: String? {
        didSet { Task { await reloadTransactions() } }
    }

    var selectedTag: String? {
        didSet { Task { await reloadTransactions() } }
    }

    var period: Period = .all {
        didSet { Task { await reloadTransactions() } }
    }

    /// Mês do período `.month`. Aceita meses futuros, para ver as parcelas previstas.
    var selectedMonth = YearMonth(date: Date()) {
        didSet { if period == .month { Task { await reloadTransactions() } } }
    }

    /// Só a resposta da consulta mais recente atualiza a lista.
    private var transactionsGeneration = 0

    private var periodStart: Date? {
        period == .month ? selectedMonth.startDate : period.start
    }

    private var periodEnd: Date? {
        period == .month ? LedgerCalendar.addingDays(-1, to: selectedMonth.adding(months: 1).startDate) : period.end
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
        var start: Date? {
            let now = Date()
            switch self {
            case .all, .month: return nil
            case .thisMonth: return LedgerCalendar.startOfMonth(now)
            case .last3Months: return LedgerCalendar.startOfMonth(LedgerCalendar.addingMonths(-2, to: now))
            case .last12Months: return LedgerCalendar.startOfMonth(LedgerCalendar.addingMonths(-11, to: now))
            }
        }

        /// Último dia do intervalo. Sem ele, um lançamento datado no futuro
        /// (ou uma parcela projetada) entraria no total do período escolhido.
        var end: Date? {
            guard self != .all, self != .month else { return nil }
            let nextMonth = LedgerCalendar.addingMonths(1, to: LedgerCalendar.startOfMonth(Date()))
            return LedgerCalendar.addingDays(-1, to: nextMonth)
        }
    }

    var configuration: APIConfiguration {
        didSet {
            configuration.save()
            Task { await reload() }
        }
    }

    private var client: APIClient { APIClient(configuration: configuration) }

    init(configuration: APIConfiguration = .load()) {
        self.configuration = configuration
    }

    /// Catálogo do servidor somado ao que já está na tela, para incluir o que
    /// acabou de ser criado antes do próximo `reload`.
    var categories: [String] {
        Array(Set(categoryCatalog + rules.map(\.category) + commitments.map(\.category)
            + transactions.compactMap(\.category))).sorted()
    }

    private(set) var categoryCatalog: [String] = []

    /// Muda a cada `reload`, para telas com dados próprios (Análise) recarregarem.
    private(set) var dataGeneration = 0

    func reload() async {
        transactionsGeneration += 1
        let generation = transactionsGeneration
        isLoading = true
        defer { isLoading = false }
        await run {
            let client = self.client
            async let accounts = client.accounts()
            async let transactions = client.transactions(
                accountID: self.selectedAccountID,
                search: self.searchTerm.isEmpty ? nil : self.searchTerm,
                from: self.periodStart,
                to: self.periodEnd,
                category: self.selectedCategory,
                tag: self.selectedTag
            )
            async let rules = client.categoryRules()
            async let catalog = client.categories()
            async let projection = client.summary(accountID: self.selectedAccountID)
            async let batches = client.importBatches(accountID: self.selectedAccountID)
            async let position = client.position()
            async let plan = client.plan(from: self.planStart, to: self.planEnd)
            let today = LedgerCalendar.startOfDay(Date())
            async let upcoming = client.transactions(
                accountID: self.selectedAccountID,
                from: today,
                to: LedgerCalendar.addingDays(Self.upcomingWindowDays, to: today),
                limit: 1000
            )

            self.accounts = try await accounts
            let loaded = try await transactions
            if generation == self.transactionsGeneration { self.transactions = loaded }
            self.rules = try await rules
            self.projection = try await projection
            self.batches = try await batches
            self.position = try await position
            self.upcoming = try await upcoming
                .filter(\.isProjected)
                .sorted { $0.date < $1.date }

            let planResponse = try await plan
            self.plan = planResponse.plan
            self.commitments = planResponse.commitments
            self.knownTags = planResponse.knownTags
            self.categoryCatalog = try await catalog
        }
        dataGeneration += 1
    }

    // MARK: Planejamento

    /// Parcelas são mensais, então três meses à frente sempre trazem a próxima.
    private static let upcomingWindowDays = 92

    private var planStart: YearMonth { YearMonth(year: planYear, month: 1) }
    private var planEnd: YearMonth { YearMonth(year: planYear, month: 12) }

    func reloadPlan() async {
        await run {
            let response = try await self.client.plan(from: self.planStart, to: self.planEnd)
            self.plan = response.plan
            self.commitments = response.commitments
            self.knownTags = response.knownTags
        }
    }

    func saveCommitment(_ commitment: RecurringCommitment) async {
        await run {
            if let id = commitment.id {
                _ = try await self.client.updateCommitment(id: id, commitment)
            } else {
                _ = try await self.client.createCommitment(commitment)
            }
        }
        await reloadPlan()
    }

    func deleteCommitment(_ commitment: RecurringCommitment) async {
        guard let id = commitment.id else { return }
        await run { try await self.client.deleteCommitment(id: id) }
        await reloadPlan()
    }

    // MARK: Contas

    func addAccount(name: String, kind: AccountKind) async {
        await run {
            _ = try await self.client.createAccount(AccountDTO(name: name, kind: kind))
        }
        await reload()
    }

    func updateAccount(_ account: AccountDTO) async {
        guard let id = account.id else { return }
        await run { _ = try await self.client.updateAccount(id: id, account) }
        await reload()
    }

    func deleteAccount(_ account: AccountDTO) async {
        guard let id = account.id else { return }
        await run { try await self.client.deleteAccount(id: id) }
        await reload()
    }

    // MARK: Lançamentos

    func addTransaction(_ transaction: TransactionDTO) async {
        await run { _ = try await self.client.createTransaction(transaction) }
        await reload()
    }

    func updateTransaction(_ transaction: TransactionDTO) async {
        guard let id = transaction.id else { return }
        await run { _ = try await self.client.updateTransaction(id: id, transaction) }
        await reload()
    }

    /// Salva o lançamento e, se a conta de destino mudou, liga, troca ou
    /// desfaz a contrapartida da transferência.
    func updateTransaction(_ transaction: TransactionDTO, transferTo accountID: UUID?) async {
        guard let id = transaction.id else { return }
        let transferChanged = accountID != transaction.transferAccountID
        await run {
            // Desliga antes de editar: a origem pode estar indo para a conta
            // que hoje recebe a contrapartida.
            if transferChanged, transaction.transferAccountID != nil {
                _ = try await self.client.setTransfer(id: id, accountID: nil)
            }
            _ = try await self.client.updateTransaction(id: id, transaction)
            if transferChanged, let accountID {
                _ = try await self.client.setTransfer(id: id, accountID: accountID)
            }
        }
        await reload()
    }

    /// Atalho do menu de contexto da lista, sem abrir o editor.
    func setCategory(_ category: String, on transaction: TransactionDTO) async {
        var updated = transaction
        updated.category = category
        await updateTransaction(updated)
    }

    func deleteTransaction(_ transaction: TransactionDTO) async {
        guard let id = transaction.id else { return }
        await run { try await self.client.deleteTransaction(id: id) }
        await reload()
    }

    func deleteTransactions(ids: [UUID]) async {
        guard !ids.isEmpty else { return }
        await run { _ = try await self.client.deleteTransactions(ids: ids) }
        await reload()
    }

    func search(_ term: String) async {
        searchTerm = term
        await reloadTransactions()
    }

    private func reloadTransactions() async {
        transactionsGeneration += 1
        let generation = transactionsGeneration
        await run {
            let all = try await self.client.transactions(
                accountID: self.selectedAccountID,
                search: self.searchTerm.isEmpty ? nil : self.searchTerm,
                from: self.periodStart,
                to: self.periodEnd,
                category: self.selectedCategory,
                tag: self.selectedTag
            )
            guard generation == self.transactionsGeneration else { return }
            self.transactions = all
        }
    }

    /// Todos os lançamentos dos filtros atuais, sem o limite de uma página da lista.
    func transactionsForExport() async -> [TransactionDTO]? {
        let pageSize = 1000
        var all: [TransactionDTO] = []
        var finished = false
        await run {
            while true {
                let page = try await self.client.transactions(
                    accountID: self.selectedAccountID,
                    search: self.searchTerm.isEmpty ? nil : self.searchTerm,
                    from: self.periodStart,
                    to: self.periodEnd,
                    category: self.selectedCategory,
                    tag: self.selectedTag,
                    limit: pageSize,
                    offset: all.count
                )
                all += page
                if page.count < pageSize { break }
            }
            finished = true
        }
        return finished ? all : nil
    }

    // MARK: Importação

    /// Devolve o relatório para a tela mostrar quantos entraram, quantos eram
    /// duplicados e quais linhas falharam.
    /// Lança o erro em vez de usar `errorMessage`, para a tela mostrá-lo junto do arquivo.
    func importStatement(_ request: ImportRequestDTO) async throws -> ImportReportDTO {
        let report = try await client.importStatement(request)
        await reload()
        return report
    }

    /// Desfaz a importação inteira: apaga o que ela criou e devolve as projeções
    /// confirmadas ao estado anterior.
    func undoImport(batchID: UUID) async -> BulkDeleteResponse? {
        var response: BulkDeleteResponse?
        await run { response = try await self.client.undoImport(batchID: batchID) }
        await reload()
        return response
    }

    // MARK: Regras

    func saveRule(_ rule: CategoryRule) async {
        await run {
            if let id = rule.id {
                _ = try await self.client.updateRule(id: id, rule)
            } else {
                _ = try await self.client.createRule(rule)
            }
        }
        await reload()
    }

    func deleteRule(_ rule: CategoryRule) async {
        guard let id = rule.id else { return }
        await run { try await self.client.deleteRule(id: id) }
        await reload()
    }

    /// Apaga a categoria inteira: as regras que a produzem somem e os
    /// lançamentos que a usavam voltam a passar pelas regras restantes.
    func deleteCategory(_ name: String) async -> DeleteCategoryResponse? {
        var response: DeleteCategoryResponse?
        await run { response = try await self.client.deleteCategory(name) }
        if selectedCategory == name { selectedCategory = nil }
        await reload()
        return response
    }

    func renameCategory(_ name: String, to newName: String) async -> LabelChangeResponse? {
        var response: LabelChangeResponse?
        await run { response = try await self.client.renameCategory(name, to: newName) }
        if response != nil, selectedCategory == name { selectedCategory = newName }
        await reload()
        return response
    }

    func renameTag(_ tag: String, to newName: String) async -> LabelChangeResponse? {
        var response: LabelChangeResponse?
        await run { response = try await self.client.renameTag(tag, to: newName) }
        if response != nil, selectedTag == tag { selectedTag = TagSet.normalize([newName]).first }
        await reload()
        return response
    }

    func deleteTag(_ tag: String) async -> LabelChangeResponse? {
        var response: LabelChangeResponse?
        await run { response = try await self.client.deleteTag(tag) }
        if selectedTag == tag { selectedTag = nil }
        await reload()
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
        await run {
            report = try await self.client.spending(
                year: year,
                grouping: grouping,
                accountID: accountID,
                accountKind: accountKind
            )
        }
        return report
    }

    // MARK: Manutenção

    func reset(scope: ResetScope) async -> ResetResponse? {
        var response: ResetResponse?
        await run { response = try await self.client.reset(scope: scope) }
        selectedAccountID = nil
        selectedCategory = nil
        selectedTag = nil
        await reload()
        return response
    }

    func preview(description: String, amount: Double, rule: CategoryRule?) async -> CategoryPreviewResponse? {
        var response: CategoryPreviewResponse?
        await run {
            response = try await self.client.preview(
                CategoryPreviewRequest(description: description, amount: amount, rule: rule)
            )
        }
        return response
    }

    /// Reaplica as regras ao histórico — sem isso, uma regra nova só valeria
    /// para lançamentos futuros.
    func recategorize(onlyUncategorized: Bool) async -> Int? {
        var updated: Int?
        await run {
            updated = try await self.client.recategorize(
                accountID: self.selectedAccountID,
                onlyUncategorized: onlyUncategorized
            ).updated
        }
        await reload()
        return updated
    }

    private func run(_ operation: () async throws -> Void) async {
        do {
            try await operation()
            errorMessage = nil
        } catch {
            errorMessage = Self.message(for: error)
        }
    }

    static func message(for error: any Error) -> String {
        (error as? APIError)?.errorDescription ?? error.localizedDescription
    }
}
