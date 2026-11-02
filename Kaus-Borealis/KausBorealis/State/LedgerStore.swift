import Foundation
import Observation
import KausMedia

/// Coordenador do estado do app. Cada área tem a sua store
/// (`accounts`, `transactions`, `plan`, `rules`); aqui ficam a conexão, a
/// conta em foco, o catálogo de categorias que cruza todas elas e a regra de
/// quem recarrega o quê depois de cada mudança.
@MainActor
@Observable
final class LedgerStore {
    let session: LedgerSession
    let accounts: AccountsStore
    let transactions: TransactionsStore
    let plan: PlanStore
    let rules: RulesStore

    /// Recarga disparada por mudança de filtro ou de conexão; a seguinte cancela a anterior.
    @ObservationIgnored private var reloadTask: Task<Void, Never>?

    init(
        configuration: APIConfiguration = .load(),
        makeAPI: @escaping (APIConfiguration) -> any LedgerAPI = { APIClient(configuration: $0) }
    ) {
        let session = LedgerSession(configuration: configuration, makeAPI: makeAPI)
        let transactions = TransactionsStore(session: session)
        self.session = session
        self.accounts = AccountsStore(session: session)
        self.transactions = transactions
        self.plan = PlanStore(session: session)
        self.rules = RulesStore(session: session, transactions: transactions)
        session.coordinator = self
    }

    // MARK: Recarga

    /// Partes do estado que uma mudança invalida.
    nonisolated struct Scope: OptionSet, Sendable {
        let rawValue: Int

        static let accounts = Scope(rawValue: 1 << 0)
        static let transactions = Scope(rawValue: 1 << 1)
        static let summary = Scope(rawValue: 1 << 2)
        static let batches = Scope(rawValue: 1 << 3)
        static let plan = Scope(rawValue: 1 << 4)
        static let rules = Scope(rawValue: 1 << 5)

        /// O que depende da conta selecionada nos filtros.
        static let accountFilter: Scope = [.transactions, .summary, .batches]
        /// Tudo o que mostra categorias ou tags.
        static let labels: Scope = [.transactions, .summary, .plan, .rules]
        static let all: Scope = [.accounts, .transactions, .summary, .batches, .plan, .rules]
    }

    /// Recarrega em paralelo só o que `scope` cobre.
    func reload(_ scope: Scope = .all) async {
        session.isLoading = true
        session.batchDepth += 1
        defer {
            session.batchDepth -= 1
            session.isLoading = session.batchDepth > 0
        }
        session.errorMessage = nil

        await withTaskGroup(of: Void.self) { group in
            if scope.contains(.accounts) { group.addTask { await self.accounts.reload() } }
            if scope.contains(.transactions) { group.addTask { await self.transactions.reloadList() } }
            if scope.contains(.summary) { group.addTask { await self.transactions.reloadSummary() } }
            if scope.contains(.batches) { group.addTask { await self.transactions.reloadBatches() } }
            if scope.contains(.plan) { group.addTask { await self.plan.reload() } }
            if scope.contains(.rules) { group.addTask { await self.rules.reload() } }
        }
        if scope == .all {
            session.isReachable = session.errorMessage == nil
        }
    }

    private func scheduleReload(_ scope: Scope) {
        reloadTask?.cancel()
        reloadTask = Task { await reload(scope) }
    }

    // MARK: Estado compartilhado

    var configuration: APIConfiguration {
        get { session.configuration }
        set {
            guard newValue != session.configuration else { return }
            session.configuration = newValue
            newValue.save()
            scheduleReload(.all)
        }
    }

    /// Conta selecionada nos filtros; `nil` significa todas.
    var selectedAccountID: UUID? {
        get { session.selectedAccountID }
        set {
            guard newValue != session.selectedAccountID else { return }
            session.selectedAccountID = newValue
            scheduleReload(.accountFilter)
        }
    }

    var errorMessage: String? {
        get { session.errorMessage }
        set { session.errorMessage = newValue }
    }

    var isLoading: Bool { session.isLoading }
    var isReachable: Bool { session.isReachable }
    var dataGeneration: Int { session.dataGeneration }

    // MARK: Catálogo de categorias

    /// Catálogo do servidor somado ao que já está na tela, para incluir o que
    /// acabou de ser criado antes do próximo `reload`.
    var categories: [String] {
        Array(Set(rules.catalog + rules.all.map(\.category) + plan.commitments.map(\.category)
            + transactions.items.compactMap(\.category))).sorted()
    }

    /// Categorias-mãe, para filtros e para a tela de Regras.
    var parentCategories: [String] {
        Array(Set(categories.map(CategoryPath.parent(of:)))).sorted()
    }

    func subcategories(of parent: String) -> [String] {
        categories.filter { $0 != parent && CategoryPath.isWithin($0, parent) }.sorted()
    }

    // MARK: Manutenção

    func reset(scope: ResetScope) async -> ResetResponse? {
        var response: ResetResponse?
        await session.run { response = try await session.api.reset(scope: scope) }
        session.selectedAccountID = nil
        transactions.clearLabelFilters()
        await reload(.all)
        return response
    }

    static func message(for error: any Error) -> String {
        LedgerSession.message(for: error)
    }
}
