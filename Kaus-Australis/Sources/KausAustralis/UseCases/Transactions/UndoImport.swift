import Foundation
import KausMedia

/// Desfaz uma importação: apaga o que ela criou e devolve as projeções que
/// ela confirmou ao estado anterior.
struct UndoImport: Sendable {
    let unitOfWork: any UnitOfWork

    func callAsFunction(batchID: UUID) async throws -> BulkDeleteResponse {
        guard let batch = try await unitOfWork.importBatches.find(batchID) else {
            throw LedgerError.importNotFound
        }

        return try await unitOfWork.transaction { work in
            // As projeções confirmadas também pertencem ao lote, mas não foram
            // criadas por ele: são revertidas, não apagadas.
            let confirmed = Set(batch.confirmations.map(\.transactionID))
            let created = try await work.transactions.inBatch(batchID)
                .filter { model in model.id.map { !confirmed.contains($0) } ?? true }
            for model in created {
                try await work.transactions.delete(model)
            }

            var restored = 0
            for snapshot in batch.confirmations {
                guard let model = try await work.transactions.find(snapshot.transactionID) else { continue }
                guard Self.restore(model, from: snapshot) else { continue }
                // O lote que projetou a parcela pode já ter sido desfeito: nesse
                // caso a projeção fica órfã em vez de apontar para um lote morto.
                if let previousBatchID = snapshot.previousBatchID {
                    model.$importBatch.id = try await work.importBatches.find(previousBatchID)?.id
                } else {
                    model.$importBatch.id = nil
                }
                try await work.transactions.update(model)
                try await work.transactions.syncCounterpart(of: model)
                restored += 1
            }

            try await work.importBatches.delete(batch)
            return BulkDeleteResponse(deleted: created.count, restored: restored)
        }
    }

    /// Devolve a projeção ao estado de antes da confirmação.
    ///
    /// - Returns: `false` quando o lançamento foi editado depois da
    ///   confirmação: a correção do usuário vale mais do que o estado que
    ///   esta importação deixou.
    static func restore(_ model: TransactionModel, from snapshot: ImportBatchModel.ConfirmationSnapshot) -> Bool {
        if let confirmedDate = snapshot.confirmedDate, let confirmedAmount = snapshot.confirmedAmount {
            guard model.date == confirmedDate, model.amount == confirmedAmount, !model.isProjected else {
                return false
            }
        }
        model.isProjected = true
        model.date = snapshot.date
        model.amount = snapshot.amount
        model.externalID = snapshot.externalID
        return true
    }
}
