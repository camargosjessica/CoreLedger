import Foundation
import KausMedia

struct DeleteTransaction: Sendable {
    let unitOfWork: any UnitOfWork

    func callAsFunction(id: UUID) async throws {
        guard let model = try await unitOfWork.transactions.find(id) else {
            throw LedgerError.transactionNotFound
        }
        try await unitOfWork.transactions.delete(model)
    }
}

/// Remoção em lote a partir da seleção na lista.
struct DeleteTransactions: Sendable {
    let unitOfWork: any UnitOfWork

    func callAsFunction(_ request: BulkDeleteRequest) async throws -> BulkDeleteResponse {
        guard !request.ids.isEmpty else { return BulkDeleteResponse(deleted: 0) }
        try TransactionValidation.requireBatchSize(request.ids.count)

        let deleted = try await unitOfWork.transaction { work -> Int in
            let models = try await work.transactions.find(ids: request.ids, includingCounterparts: true)
            for model in models {
                try await work.transactions.delete(model)
            }
            return models.count
        }
        return BulkDeleteResponse(deleted: deleted)
    }
}

/// Edição em lote a partir da seleção na lista: categoria e tags.
/// Contrapartidas ficam de fora e acompanham o original.
struct UpdateTransactions: Sendable {
    let unitOfWork: any UnitOfWork

    func callAsFunction(_ request: BulkUpdateRequest) async throws -> BulkUpdateResponse {
        guard !request.ids.isEmpty else { return BulkUpdateResponse(updated: 0) }
        try TransactionValidation.requireBatchSize(request.ids.count)
        let category = request.normalizedCategory

        let updated = try await unitOfWork.transaction { work -> Int in
            let models = try await work.transactions.find(ids: request.ids, includingCounterparts: false)
            for model in models {
                if let category { model.category = category }
                model.tags = request.applyTags(to: model.tags)
                try await work.transactions.update(model)
                try await work.transactions.syncCounterpart(of: model)
            }
            return models.count
        }
        return BulkUpdateResponse(updated: updated)
    }
}
