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
        // Tags enviadas pelo cliente mandam; sem elas, valem as da categoria
        // escolhida ou, se foi o categorizador quem escolheu, as da regra.
        let tags: [String]
        if !dto.tags.isEmpty {
            tags = dto.tags
        } else if dto.category != nil {
            tags = categorizer?.tags(forCategory: category) ?? TagSet.suggested(for: category)
        } else {
            tags = categorizer?.tags(for: dto.description, amount: dto.amount) ?? TagSet.suggested(for: category)
        }

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
            installment: dto.installment,
            tags: tags,
            note: dto.note
        )
    }

    /// - Parameter dedupKey: calculada pelo `ImportPlanner`, que numera compras
    ///   repetidas dentro do mesmo arquivo.
    convenience init(
        imported: ImportedTransaction,
        accountID: UUID,
        category: String,
        dedupKey: String,
        tags: [String] = []
    ) {
        self.init(
            description: imported.description,
            amount: imported.amount,
            category: category,
            date: imported.date,
            accountID: accountID,
            dedupKey: dedupKey,
            isProjected: imported.isProjected,
            installment: imported.installment,
            externalID: imported.externalID,
            tags: tags.isEmpty ? TagSet.suggested(for: category) : tags
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
            dedupKey: dedupKey,
            tags: tags,
            note: note,
            transferSourceID: $transferSource.id
        )
    }
}
