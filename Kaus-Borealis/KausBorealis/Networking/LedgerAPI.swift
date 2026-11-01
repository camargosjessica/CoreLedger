import Foundation
import KausMedia

/// Filtros de `GET /api/transactions`.
struct TransactionQuery: Equatable, Sendable {
    var accountID: UUID?
    var search: String?
    var includeProjected = true
    var from: Date?
    var to: Date?
    var category: String?
    var tag: String?
    var limit = 500
    var offset = 0
}

/// Tudo o que o app pede ao Kaus-Australis. As stores dependem deste
/// protocolo, não do `APIClient`: nos testes e nos previews entra um fake.
protocol LedgerAPI: Sendable {
    // Contas
    func accounts() async throws -> [AccountDTO]
    func createAccount(_ account: AccountDTO) async throws -> AccountDTO
    func updateAccount(id: UUID, _ account: AccountDTO) async throws -> AccountDTO
    func deleteAccount(id: UUID) async throws
    func position() async throws -> FinancialPosition

    // Lançamentos
    func transactions(_ query: TransactionQuery) async throws -> [TransactionDTO]
    func createTransaction(_ transaction: TransactionDTO) async throws -> TransactionDTO
    func updateTransaction(id: UUID, _ transaction: TransactionDTO) async throws -> TransactionDTO
    func setTransfer(id: UUID, accountID: UUID?) async throws -> TransactionDTO
    func deleteTransaction(id: UUID) async throws
    func deleteTransactions(ids: [UUID]) async throws -> BulkDeleteResponse
    func updateTransactions(_ request: BulkUpdateRequest) async throws -> BulkUpdateResponse
    func summary(accountID: UUID?, forecastMonths: Int) async throws -> LedgerProjection

    // Importação
    func importStatement(_ request: ImportRequestDTO) async throws -> ImportReportDTO
    func importBatches(accountID: UUID?) async throws -> [ImportBatchDTO]
    func undoImport(batchID: UUID) async throws -> BulkDeleteResponse

    // Regras e rótulos
    func categoryRules() async throws -> [CategoryRule]
    func createRule(_ rule: CategoryRule) async throws -> CategoryRule
    func updateRule(id: UUID, _ rule: CategoryRule) async throws -> CategoryRule
    func deleteRule(id: UUID) async throws
    func preview(_ request: CategoryPreviewRequest) async throws -> CategoryPreviewResponse
    func recategorize(accountID: UUID?, onlyUncategorized: Bool) async throws -> RecategorizeResponse
    func categories() async throws -> [String]
    func deleteCategory(_ name: String) async throws -> DeleteCategoryResponse
    func renameCategory(_ name: String, to newName: String) async throws -> LabelChangeResponse
    func renameTag(_ tag: String, to newName: String) async throws -> LabelChangeResponse
    func deleteTag(_ tag: String) async throws -> LabelChangeResponse

    // Análise
    func spending(year: Int, grouping: SpendingGrouping, accountID: UUID?, accountKind: AccountKind?) async throws -> SpendingReport

    // Planejamento
    func commitments() async throws -> [RecurringCommitment]
    func createCommitment(_ commitment: RecurringCommitment) async throws -> RecurringCommitment
    func updateCommitment(id: UUID, _ commitment: RecurringCommitment) async throws -> RecurringCommitment
    func deleteCommitment(id: UUID) async throws
    func limits() async throws -> [CategoryLimit]
    func saveLimit(_ limit: CategoryLimit) async throws -> CategoryLimit
    func deleteLimit(category: String) async throws
    func categorySettings() async throws -> [CategorySetting]
    func saveCategorySetting(_ setting: CategorySetting) async throws -> CategorySetting
    func plan(from: YearMonth, to: YearMonth, openingBalance: Money?) async throws -> PlanResponse

    // Manutenção
    func reset(scope: ResetScope) async throws -> ResetResponse
}

extension APIClient: LedgerAPI {}
