import Foundation
import KausMedia

extension TransactionModel {
    /// Cria um novo registro a partir do DTO. O `id` enviado pelo cliente é ignorado:
    /// a identidade é sempre atribuída pelo banco. A categoria também: quando o
    /// cliente não informa, quem decide é o categorizador com as regras do banco.
    convenience init(newFrom dto: TransactionDTO, categorizer: Categorizer? = nil) {
        let date = LedgerCalendar.startOfDay(dto.date)
        let category = dto.category
            ?? categorizer?.category(for: dto.description, amount: dto.amount)
            ?? CategoryRule.uncategorizedDebit

        self.init(
            description: dto.description,
            amount: dto.amount,
            category: category,
            date: date,
            accountID: dto.accountID,
            dedupKey: DedupKey.make(
                accountID: dto.accountID,
                date: date,
                description: dto.description,
                amount: dto.amount,
                installment: dto.installment
            ),
            isProjected: dto.isProjected,
            installment: dto.installment
        )
    }

    convenience init(imported: ImportedTransaction, accountID: UUID, category: String) {
        self.init(
            description: imported.description,
            amount: imported.amount,
            category: category,
            date: imported.date,
            accountID: accountID,
            dedupKey: DedupKey.make(accountID: accountID, transaction: imported),
            isProjected: imported.isProjected,
            installment: imported.installment,
            externalID: imported.externalID
        )
    }

    func toDTO() -> TransactionDTO {
        TransactionDTO(
            id: id,
            description: description,
            amount: amount,
            date: date,
            category: category,
            accountID: $account.id,
            isProjected: isProjected,
            installment: installment,
            dedupKey: dedupKey
        )
    }
}
