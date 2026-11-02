import Foundation
import Testing
import KausMedia
@testable import KausBorealis

@MainActor
@Suite("Stores")
struct LedgerStoreTests {
    @Test func fullReloadFillsEveryArea() async {
        let (store, _) = makeStore()
        await store.reload()

        #expect(store.accounts.all.count == 3)
        #expect(store.accounts.position != nil)
        #expect(!store.transactions.items.isEmpty)
        #expect(store.transactions.projection != nil)
        #expect(store.plan.annual != nil)
        #expect(store.rules.all.count == 1)
        #expect(store.errorMessage == nil)
        #expect(store.isReachable)
        #expect(!store.isLoading)
    }

    @Test func selectingAccountFiltersTheList() async throws {
        let (store, api) = makeStore()
        await store.reload()
        let card = try #require(store.accounts.all.first { $0.kind == .creditCard }?.id)

        store.selectedAccountID = card
        await store.reload(.accountFilter)

        #expect(api.listQueries.last?.accountID == card)
        #expect(store.transactions.items.allSatisfy { $0.accountID == card })
    }

    @Test func newerFilterCancelsTheOlderQuery() async throws {
        let api = SpyLedgerAPI()
        api.latency = .milliseconds(200)
        let (store, _) = makeStore(api)

        store.transactions.selectedCategory = "Mercado"
        store.transactions.selectedCategory = "Saúde"
        try await Task.sleep(for: .milliseconds(600))

        #expect(api.listQueries.last?.category == "Saúde")
        #expect(api.completedQueries.filter { $0.limit == 500 }.map(\.category) == ["Saúde"])
        #expect(store.transactions.items.allSatisfy { $0.category == "Saúde" })
        #expect(store.errorMessage == nil, "Cancelamento não é erro")
    }

    @Test func failureIsReportedAndMarksServerUnreachable() async {
        let api = SpyLedgerAPI()
        api.failure = APIError.server(status: 500, reason: "Falhou")
        let (store, _) = makeStore(api)

        await store.reload()

        #expect(store.errorMessage == "Falhou")
        #expect(!store.isReachable)
    }

    @Test func addingTransactionsRefreshesBalances() async throws {
        let (store, _) = makeStore()
        await store.reload()
        let checking = try #require(store.accounts.all.first { $0.kind == .checking })

        await store.transactions.add([
            TransactionDTO(description: "Café", amount: -7.5, date: Date(), accountID: checking.id),
        ])

        let updated = try #require(store.accounts.all.first { $0.id == checking.id })
        #expect(updated.balance == (checking.balance ?? 0) - 7.5)
        #expect(store.transactions.items.contains { $0.description == "Café" })
    }

    @Test func renamingCategoryKeepsTheFilterOnIt() async {
        let (store, _) = makeStore()
        store.transactions.selectedCategory = "Mercado"

        _ = await store.rules.renameCategory("Mercado", to: "Supermercado")

        #expect(store.transactions.selectedCategory == "Supermercado")
    }

    @Test func reloadWaitsForTheQueryThatReplacedIt() async throws {
        let api = SpyLedgerAPI()
        api.latency = .milliseconds(150)
        let (store, _) = makeStore(api)

        async let first: Void = store.transactions.reloadList()
        try await Task.sleep(for: .milliseconds(30))
        store.transactions.selectedCategory = "Saúde"
        await first

        #expect(!store.transactions.items.isEmpty)
        #expect(store.transactions.items.allSatisfy { $0.category == "Saúde" })
    }
}
