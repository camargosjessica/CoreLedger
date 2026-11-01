#if DEBUG
import Foundation
import SwiftUI
import KausMedia

/// Backend em memória para os `#Preview`: dados de exemplo, sem servidor.
final class PreviewLedgerAPI: LedgerAPI {
    private var accountsList: [AccountDTO]
    private var transactionsList: [TransactionDTO]
    private var rules: [CategoryRule]

    init() {
        let checking = UUID(), card = UUID(), savings = UUID()
        let today = LedgerCalendar.startOfDay(Date())
        func day(_ offset: Int) -> Date { LedgerCalendar.addingDays(offset, to: today) }

        transactionsList = [
            TransactionDTO(id: UUID(), description: "Salário", amount: 6_500, date: day(-20), category: "Salário", accountID: checking),
            TransactionDTO(id: UUID(), description: "Aluguel", amount: -2_100, date: day(-18), category: "Moradia", accountID: checking),
            TransactionDTO(id: UUID(), description: "Mercado Bom Preço", amount: -412.37, date: day(-6), category: "Mercado", accountID: card),
            TransactionDTO(id: UUID(), description: "Farmácia", amount: -58.90, date: day(-3), category: "Saúde", accountID: card),
            TransactionDTO(id: UUID(), description: "Aplicação caixinha", amount: -500, date: day(-2), category: "Guardado", accountID: checking),
            TransactionDTO(
                id: UUID(), description: "Notebook 3/10", amount: -350, date: day(25), category: "Compras",
                accountID: card, isProjected: true, installment: Installment(number: 3, total: 10)
            ),
        ]
        accountsList = [
            AccountDTO(id: checking, name: "Conta corrente", kind: .checking),
            AccountDTO(id: card, name: "Cartão", kind: .creditCard),
            AccountDTO(id: savings, name: "Caixinha viagem", kind: .savings, balance: 3_200),
        ]
        rules = [CategoryRule(id: UUID(), term: "mercado", category: "Mercado", matchKind: .contains)]
        recomputeBalances()
    }

    private func recomputeBalances() {
        accountsList = accountsList.map { account in
            var account = account
            let own = transactionsList.filter { $0.accountID == account.id }
            account.transactionCount = own.count
            if account.kind != .savings {
                account.balance = own.filter { !$0.isProjected }.map(\.amount).sum()
            }
            return account
        }
    }

    // Contas
    func accounts() async throws -> [AccountDTO] { accountsList }
    func createAccount(_ account: AccountDTO) async throws -> AccountDTO {
        var account = account
        account.id = UUID()
        accountsList.append(account)
        return account
    }
    func updateAccount(id: UUID, _ account: AccountDTO) async throws -> AccountDTO { account }
    func deleteAccount(id: UUID) async throws { accountsList.removeAll { $0.id == id } }
    func position() async throws -> FinancialPosition {
        FinancialPosition.make(
            accounts: accountsList.map {
                AccountPosition(accountID: $0.id, name: $0.name, kind: $0.kind, balance: $0.balance ?? .zero)
            },
            upcomingInstallments: transactionsList.filter(\.isProjected).map(\.amount).sum()
        )
    }

    // Lançamentos
    func transactions(_ query: TransactionQuery) async throws -> [TransactionDTO] {
        transactionsList
            .filter { query.accountID == nil || $0.accountID == query.accountID }
            .filter { query.category == nil || $0.category == query.category }
            .filter { transaction in query.from.map { transaction.date >= $0 } ?? true }
            .filter { transaction in query.to.map { transaction.date <= $0 } ?? true }
            .sorted { $0.date > $1.date }
    }
    func createTransaction(_ transaction: TransactionDTO) async throws -> TransactionDTO {
        var transaction = transaction
        transaction.id = UUID()
        transactionsList.append(transaction)
        recomputeBalances()
        return transaction
    }
    func updateTransaction(id: UUID, _ transaction: TransactionDTO) async throws -> TransactionDTO {
        transactionsList = transactionsList.map { $0.id == id ? transaction : $0 }
        recomputeBalances()
        return transaction
    }
    func setTransfer(id: UUID, accountID: UUID?) async throws -> TransactionDTO {
        guard var transaction = transactionsList.first(where: { $0.id == id }) else { throw URLError(.fileDoesNotExist) }
        transaction.transferAccountID = accountID
        return transaction
    }
    func deleteTransaction(id: UUID) async throws { transactionsList.removeAll { $0.id == id } }
    func deleteTransactions(ids: [UUID]) async throws -> BulkDeleteResponse {
        let before = transactionsList.count
        transactionsList.removeAll { $0.id.map(ids.contains) ?? false }
        return BulkDeleteResponse(deleted: before - transactionsList.count)
    }
    func updateTransactions(_ request: BulkUpdateRequest) async throws -> BulkUpdateResponse {
        BulkUpdateResponse(updated: request.ids.count)
    }
    func summary(accountID: UUID?, forecastMonths: Int) async throws -> LedgerProjection {
        Projection.project(
            transactionsList
                .filter { accountID == nil || $0.accountID == accountID }
                .map(Projection.Input.init(transaction:)),
            forecastMonths: forecastMonths
        )
    }

    // Importação
    func importStatement(_ request: ImportRequestDTO) async throws -> ImportReportDTO { ImportReportDTO() }
    func importBatches(accountID: UUID?) async throws -> [ImportBatchDTO] { [] }
    func undoImport(batchID: UUID) async throws -> BulkDeleteResponse { BulkDeleteResponse(deleted: 0) }

    // Regras e rótulos
    func categoryRules() async throws -> [CategoryRule] { rules }
    func createRule(_ rule: CategoryRule) async throws -> CategoryRule { rules.append(rule); return rule }
    func updateRule(id: UUID, _ rule: CategoryRule) async throws -> CategoryRule { rule }
    func deleteRule(id: UUID) async throws { rules.removeAll { $0.id == id } }
    func preview(_ request: CategoryPreviewRequest) async throws -> CategoryPreviewResponse {
        CategoryPreviewResponse(category: Categorizer(rules: rules).category(for: request.description, amount: request.amount))
    }
    func recategorize(accountID: UUID?, onlyUncategorized: Bool) async throws -> RecategorizeResponse {
        RecategorizeResponse(updated: 0)
    }
    func categories() async throws -> [String] { Array(Set(transactionsList.compactMap(\.category))).sorted() }
    func deleteCategory(_ name: String) async throws -> DeleteCategoryResponse {
        DeleteCategoryResponse(removedRules: 0, recategorized: 0)
    }
    func renameCategory(_ name: String, to newName: String) async throws -> LabelChangeResponse { LabelChangeResponse() }
    func renameTag(_ tag: String, to newName: String) async throws -> LabelChangeResponse { LabelChangeResponse() }
    func deleteTag(_ tag: String) async throws -> LabelChangeResponse { LabelChangeResponse() }

    // Análise
    func spending(year: Int, grouping: SpendingGrouping, accountID: UUID?, accountKind: AccountKind?) async throws -> SpendingReport {
        SpendingReport(year: year, grouping: grouping, months: [], totals: [], total: .zero)
    }

    // Planejamento
    func commitments() async throws -> [RecurringCommitment] { [] }
    func createCommitment(_ commitment: RecurringCommitment) async throws -> RecurringCommitment { commitment }
    func updateCommitment(id: UUID, _ commitment: RecurringCommitment) async throws -> RecurringCommitment { commitment }
    func deleteCommitment(id: UUID) async throws {}
    func limits() async throws -> [CategoryLimit] { [CategoryLimit(category: "Mercado", monthlyLimit: 800)] }
    func saveLimit(_ limit: CategoryLimit) async throws -> CategoryLimit { limit }
    func deleteLimit(category: String) async throws {}
    func categorySettings() async throws -> [CategorySetting] { [] }
    func saveCategorySetting(_ setting: CategorySetting) async throws -> CategorySetting { setting }
    func plan(from: YearMonth, to: YearMonth, openingBalance: Money?) async throws -> PlanResponse {
        PlanResponse(plan: AnnualPlan(), commitments: [], knownTags: [])
    }

    // Manutenção
    func reset(scope: ResetScope) async throws -> ResetResponse { ResetResponse() }
}

extension LedgerStore {
    /// Store com dados de exemplo para os `#Preview`.
    static func preview() -> LedgerStore {
        let api = PreviewLedgerAPI()
        return LedgerStore(configuration: APIConfiguration(baseURL: APIConfiguration.defaultBaseURL)) { _ in api }
    }
}

extension View {
    /// Injeta uma store de exemplo já carregada.
    func previewLedger(_ store: LedgerStore? = nil) -> some View {
        let store = store ?? .preview()
        return environment(store).task { await store.reload() }
    }
}
#endif
