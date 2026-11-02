import Foundation
import KausMedia

/// Edição manual de um lançamento (e da contrapartida que o espelha).
struct UpdateTransaction: Sendable {
    let unitOfWork: any UnitOfWork

    func callAsFunction(id: UUID, with dto: TransactionDTO) async throws -> TransactionDTO {
        guard let model = try await unitOfWork.transactions.find(id) else {
            throw LedgerError.transactionNotFound
        }
        guard model.$transferSource.id == nil else { throw LedgerError.counterpartIsReadOnly }
        try TransactionValidation.requireDescription(dto.description)
        if let accountID = dto.accountID, try await !unitOfWork.accounts.exists(accountID) {
            throw LedgerError.accountNotFound
        }

        let categorizer = try await unitOfWork.categorizer.categorizer()
        Self.apply(dto, to: model, categorizer: categorizer)

        return try await unitOfWork.transaction { work in
            if let counterpart = try await work.transactions.counterpart(of: id),
               counterpart.$account.id == dto.accountID {
                throw LedgerError.transferAlreadyTargetsAccount
            }
            try await work.transactions.update(model)
            try await work.transactions.syncCounterpart(of: model)
            return try await work.transactions.dto(for: model)
        }
    }

    /// Copia a edição para o modelo.
    ///
    /// A chave de dedup só é recalculada quando era derivada dos próprios
    /// campos editados: chaves de FITID ou numeradas por ocorrência
    /// identificam a linha do arquivo, não o conteúdo, e recalculá-las
    /// duplicaria a próxima importação ou colidiria com a ocorrência anterior.
    static func apply(_ dto: TransactionDTO, to model: TransactionModel, categorizer: Categorizer) {
        let date = LedgerCalendar.startOfDay(dto.date)
        let category = dto.category?.trimmingCharacters(in: .whitespacesAndNewlines)
        let keyWasCanonical = model.dedupKey == DedupKey.make(
            accountID: model.$account.id,
            date: model.date,
            description: model.description,
            amount: model.amount,
            installment: model.installment
        )

        model.description = dto.description
        model.amount = dto.amount
        model.date = date
        model.$account.id = dto.accountID
        model.isProjected = dto.isProjected
        model.installmentNumber = dto.installment?.number
        model.installmentTotal = dto.installment?.total
        if let category, !category.isEmpty {
            model.category = category
        } else {
            model.category = categorizer.category(for: dto.description, amount: dto.amount)
        }
        // As tags do corpo são o estado final: mandar lista vazia apaga todas.
        model.tags = TagSet.normalize(dto.tags)
        model.note = dto.note
        if keyWasCanonical {
            model.dedupKey = DedupKey.make(
                accountID: dto.accountID,
                date: date,
                description: dto.description,
                amount: dto.amount,
                installment: dto.installment
            )
        }
    }
}
