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

    var period: Period = .all {
        didSet { Task { await reloadTransactions() } }
    }

    enum Period: String, CaseIterable, Identifiable {
        case all
        case thisMonth
        case last3Months
        case last12Months

        var id: String { rawValue }

        var title: String {
            switch self {
            case .all: return "Tudo"
            case .thisMonth: return "Mês"
            case .last3Months: return "3 meses"
            case .last12Months: return "12 meses"
            }
        }

        /// Primeiro dia do intervalo; `nil` quando não há limite inferior.
        var start: Date? {
            let now = Date()
            switch self {
            case .all: return nil
            case .thisMonth: return LedgerCalendar.startOfMonth(now)
            case .last3Months: return LedgerCalendar.startOfMonth(LedgerCalendar.addingMonths(-2, to: now))
            case .last12Months: return LedgerCalendar.startOfMonth(LedgerCalendar.addingMonths(-11, to: now))
            }
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

    var categories: [String] {
        Array(Set(rules.map(\.category) + transactions.compactMap(\.category))).sorted()
    }

    func reload() async {
        isLoading = true
        defer { isLoading = false }
        await run {
            let client = self.client
            async let accounts = client.accounts()
            async let transactions = client.transactions(
                accountID: self.selectedAccountID,
                search: self.searchTerm.isEmpty ? nil : self.searchTerm,
                from: self.period.start
            )
            async let rules = client.categoryRules()
            async let projection = client.summary(accountID: self.selectedAccountID)
            async let batches = client.importBatches(accountID: self.selectedAccountID)

            self.accounts = try await accounts
            self.transactions = self.applyingCategoryFilter(to: try await transactions)
            self.rules = try await rules
            self.projection = try await projection
            self.batches = try await batches
        }
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
        await run {
            let all = try await self.client.transactions(
                accountID: self.selectedAccountID,
                search: self.searchTerm.isEmpty ? nil : self.searchTerm,
                from: self.period.start
            )
            self.transactions = self.applyingCategoryFilter(to: all)
        }
    }

    private func applyingCategoryFilter(to items: [TransactionDTO]) -> [TransactionDTO] {
        guard let category = selectedCategory else { return items }
        return items.filter { $0.category == category }
    }

    // MARK: Importação

    /// Devolve o relatório para a tela mostrar quantos entraram, quantos eram
    /// duplicados e quais linhas falharam.
    func importStatement(_ request: ImportRequestDTO) async -> ImportReportDTO? {
        var report: ImportReportDTO?
        await run { report = try await self.client.importStatement(request) }
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
            errorMessage = (error as? APIError)?.errorDescription ?? error.localizedDescription
        }
    }
}
