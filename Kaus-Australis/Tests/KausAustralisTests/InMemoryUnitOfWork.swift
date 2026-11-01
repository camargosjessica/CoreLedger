import Foundation
import KausMedia
@testable import KausAustralis

/// Repositórios em memória para testar os casos de uso sem Postgres.
///
/// `transaction` não faz rollback: os testes verificam o resultado de
/// operações bem-sucedidas e os erros lançados antes de qualquer gravação.
final class InMemoryUnitOfWork: UnitOfWork, @unchecked Sendable {
    let store = InMemoryTransactionRepository()
    var accountIDs: Set<UUID> = []
    var batches: [UUID: ImportBatchModel] = [:]
    var rules: [CategoryRule] = []

    var transactions: any TransactionRepository { store }
    var accounts: any AccountRepository { Accounts(owner: self) }
    var importBatches: any ImportBatchRepository { Batches(owner: self) }
    var categorizer: any CategorizerSource { Rules(owner: self) }

    func transaction<T: Sendable>(_ work: @escaping @Sendable (any UnitOfWork) async throws -> T) async throws -> T {
        try await work(self)
    }

    private struct Accounts: AccountRepository {
        let owner: InMemoryUnitOfWork
        func exists(_ id: UUID) async throws -> Bool { owner.accountIDs.contains(id) }
    }

    private struct Batches: ImportBatchRepository {
        let owner: InMemoryUnitOfWork
        func find(_ id: UUID) async throws -> ImportBatchModel? { owner.batches[id] }
        func delete(_ batch: ImportBatchModel) async throws {
            if let id = batch.id { owner.batches[id] = nil }
        }
    }

    private struct Rules: CategorizerSource {
        let owner: InMemoryUnitOfWork
        func categorizer() async throws -> Categorizer { Categorizer(rules: owner.rules) }
    }
}

final class InMemoryTransactionRepository: TransactionRepository, @unchecked Sendable {
    private(set) var models: [UUID: TransactionModel] = [:]

    var all: [TransactionModel] { Array(models.values) }

    func list(_ filter: TransactionFilter) async throws -> [TransactionModel] {
        all.filter { filter.accountID == nil || $0.$account.id == filter.accountID }
            .sorted { $0.date > $1.date }
    }

    func find(_ id: UUID) async throws -> TransactionModel? { models[id] }

    func find(ids: [UUID], includingCounterparts: Bool) async throws -> [TransactionModel] {
        ids.compactMap { models[$0] }
            .filter { includingCounterparts || $0.$transferSource.id == nil }
    }

    func find(dedupKey: String) async throws -> TransactionModel? {
        all.first { $0.dedupKey == dedupKey }
    }

    func counterpart(of sourceID: UUID) async throws -> TransactionModel? {
        all.first { $0.$transferSource.id == sourceID }
    }

    func counterparts(of sourceIDs: [UUID]) async throws -> [TransactionModel] {
        let ids = Set(sourceIDs)
        return all.filter { $0.$transferSource.id.map(ids.contains) ?? false }
    }

    func inBatch(_ batchID: UUID) async throws -> [TransactionModel] {
        all.filter { $0.$importBatch.id == batchID }
    }

    func create(_ model: TransactionModel) async throws {
        try checkUnique(model)
        if model.id == nil { model.id = UUID() }
        models[model.id!] = model
    }

    func update(_ model: TransactionModel) async throws {
        try checkUnique(model)
        models[model.id!] = model
    }

    func delete(_ model: TransactionModel) async throws {
        guard let id = model.id else { return }
        models[id] = nil
        // ON DELETE CASCADE da contrapartida.
        for counterpart in all where counterpart.$transferSource.id == id {
            models[counterpart.id!] = nil
        }
    }

    /// Imita os índices únicos de `dedup_key` e `transfer_source_id`.
    private func checkUnique(_ model: TransactionModel) throws {
        for other in all where other.id != model.id {
            if let key = model.dedupKey, other.dedupKey == key { throw LedgerError.duplicateTransaction }
            if let source = model.$transferSource.id, other.$transferSource.id == source {
                throw LedgerError.duplicateTransaction
            }
        }
    }
}
