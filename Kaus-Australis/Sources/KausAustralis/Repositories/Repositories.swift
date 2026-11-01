import Foundation
import KausMedia

/// Filtros da listagem de lançamentos.
struct TransactionFilter: Sendable, Equatable {
    var accountID: UUID?
    var from: Date?
    var to: Date?
    var search: String?
    var includeProjected = true
    var category: String?
    var tag: String?
    var limit = 500
    var offset = 0
}

/// Acesso aos lançamentos. Os casos de uso dependem deste protocolo, não do
/// Fluent: nos testes ele é trocado por uma versão em memória.
protocol TransactionRepository: Sendable {
    func list(_ filter: TransactionFilter) async throws -> [TransactionModel]
    func find(_ id: UUID) async throws -> TransactionModel?
    func find(ids: [UUID], includingCounterparts: Bool) async throws -> [TransactionModel]
    func find(dedupKey: String) async throws -> TransactionModel?
    /// Contrapartida de transferência criada a partir de `sourceID`.
    func counterpart(of sourceID: UUID) async throws -> TransactionModel?
    func counterparts(of sourceIDs: [UUID]) async throws -> [TransactionModel]
    func inBatch(_ batchID: UUID) async throws -> [TransactionModel]
    /// - Throws: `LedgerError.duplicateTransaction` quando a chave de dedup já existe.
    func create(_ model: TransactionModel) async throws
    /// - Throws: `LedgerError.duplicateTransaction` quando a chave de dedup já existe.
    func update(_ model: TransactionModel) async throws
    func delete(_ model: TransactionModel) async throws
}

protocol AccountRepository: Sendable {
    func exists(_ id: UUID) async throws -> Bool
}

protocol ImportBatchRepository: Sendable {
    func find(_ id: UUID) async throws -> ImportBatchModel?
    func delete(_ batch: ImportBatchModel) async throws
}

protocol CategorizerSource: Sendable {
    func categorizer() async throws -> Categorizer
}

/// Conjunto de repositórios que compartilham a mesma conexão — e, dentro de
/// `transaction`, a mesma transação de banco.
protocol UnitOfWork: Sendable {
    var transactions: any TransactionRepository { get }
    var accounts: any AccountRepository { get }
    var importBatches: any ImportBatchRepository { get }
    var categorizer: any CategorizerSource { get }

    /// Executa `work` atomicamente: ou tudo é gravado, ou nada.
    func transaction<T: Sendable>(_ work: @escaping @Sendable (any UnitOfWork) async throws -> T) async throws -> T
}

// MARK: - Regras compartilhadas

extension TransactionRepository {
    /// `toDTO()` com `transferAccountID`, que mora na contrapartida e não na origem.
    func dtos(for models: [TransactionModel]) async throws -> [TransactionDTO] {
        let ids = models.compactMap(\.id)
        guard !ids.isEmpty else { return [] }
        var accountBySource: [UUID: UUID] = [:]
        for counterpart in try await counterparts(of: ids) {
            if let source = counterpart.$transferSource.id, let account = counterpart.$account.id {
                accountBySource[source] = account
            }
        }
        return models.map { model in
            var dto = model.toDTO()
            dto.transferAccountID = model.id.flatMap { accountBySource[$0] }
            return dto
        }
    }

    func dto(for model: TransactionModel) async throws -> TransactionDTO {
        try await dtos(for: [model])[0]
    }

    /// Re-espelha a contrapartida, se houver, depois de `model` mudar.
    func syncCounterpart(of model: TransactionModel) async throws {
        guard let id = model.id, let counterpart = try await counterpart(of: id) else { return }
        counterpart.mirror(model)
        try await update(counterpart)
    }
}
