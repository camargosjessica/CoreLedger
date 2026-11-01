import Foundation
import KausMedia

/// Liga, troca ou desfaz a contrapartida de uma transferência: uma saída da
/// conta corrente vira entrada na caixinha escolhida, e vice-versa.
struct LinkTransfer: Sendable {
    let unitOfWork: any UnitOfWork

    /// - Parameter accountID: conta que recebe a contrapartida; `nil` desfaz a ligação.
    func callAsFunction(id: UUID, to accountID: UUID?) async throws -> TransactionDTO {
        guard let model = try await unitOfWork.transactions.find(id) else {
            throw LedgerError.transactionNotFound
        }
        guard model.$transferSource.id == nil else { throw LedgerError.counterpartIsReadOnly }
        if let accountID {
            guard accountID != model.$account.id else { throw LedgerError.transferToSameAccount }
            guard try await unitOfWork.accounts.exists(accountID) else { throw LedgerError.accountNotFound }
        }

        return try await unitOfWork.transaction { work in
            let existing = try await work.transactions.counterpart(of: id)
            switch (existing, accountID) {
            case (nil, nil):
                break
            case (let counterpart?, nil):
                try await work.transactions.delete(counterpart)
            case (let counterpart?, let accountID?):
                counterpart.mirror(model)
                counterpart.$account.id = accountID
                try await work.transactions.update(counterpart)
            case (nil, let accountID?):
                let counterpart = TransactionModel()
                counterpart.mirror(model)
                counterpart.$account.id = accountID
                do {
                    try await work.transactions.create(counterpart)
                } catch LedgerError.duplicateTransaction {
                    // Corrida com outra requisição: o índice de contrapartida já existe.
                    throw LedgerError.counterpartAlreadyExists
                }
            }
            return try await work.transactions.dto(for: model)
        }
    }
}
