import Foundation
import KausMedia

/// Criação manual. Idempotente: reenviar o mesmo lançamento devolve o
/// existente em vez de duplicar.
struct CreateTransaction: Sendable {
    let unitOfWork: any UnitOfWork

    struct Result: Sendable {
        var transaction: TransactionDTO
        /// `false` quando o lançamento já existia e foi só devolvido.
        var wasCreated: Bool
    }

    func callAsFunction(_ dto: TransactionDTO) async throws -> Result {
        try TransactionValidation.requireDescription(dto.description)
        if let accountID = dto.accountID, try await !unitOfWork.accounts.exists(accountID) {
            throw LedgerError.accountNotFound
        }

        let categorizer = try await unitOfWork.categorizer.categorizer()
        let model = TransactionModel(newFrom: dto, categorizer: categorizer)

        if let key = model.dedupKey, let existing = try await unitOfWork.transactions.find(dedupKey: key) {
            return Result(transaction: existing.toDTO(), wasCreated: false)
        }

        try await unitOfWork.transactions.create(model)
        return Result(transaction: model.toDTO(), wasCreated: true)
    }
}

enum TransactionValidation {
    static func requireDescription(_ description: String) throws {
        guard !description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw LedgerError.descriptionRequired
        }
    }

    /// Lotes vindos da seleção na lista.
    static let maxBatchSize = 1000

    static func requireBatchSize(_ count: Int) throws {
        guard count <= maxBatchSize else { throw LedgerError.tooManyItems(limit: maxBatchSize) }
    }
}
