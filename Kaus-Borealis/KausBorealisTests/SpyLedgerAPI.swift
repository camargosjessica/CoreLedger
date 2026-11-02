import Foundation
import KausMedia
@testable import KausBorealis

/// Backend em memória que registra as consultas de lançamentos e pode
/// simular latência ou falha.
final class SpyLedgerAPI: InMemoryLedgerAPI {
    private(set) var transactionQueries: [TransactionQuery] = []
    private(set) var completedQueries: [TransactionQuery] = []
    var latency: Duration?
    var failure: (any Error)?

    override func transactions(_ query: TransactionQuery) async throws -> [TransactionDTO] {
        transactionQueries.append(query)
        if let latency { try await Task.sleep(for: latency) }
        if let failure { throw failure }
        let result = try await super.transactions(query)
        completedQueries.append(query)
        return result
    }

    /// Consultas da lista (as das próximas parcelas têm limite 1000 e começam hoje).
    var listQueries: [TransactionQuery] { transactionQueries.filter { $0.limit == 500 } }
}

@MainActor
func makeStore(_ api: SpyLedgerAPI = SpyLedgerAPI()) -> (LedgerStore, SpyLedgerAPI) {
    let store = LedgerStore(configuration: APIConfiguration(baseURL: APIConfiguration.defaultBaseURL)) { _ in api }
    return (store, api)
}
