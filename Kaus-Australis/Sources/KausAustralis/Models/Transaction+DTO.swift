import Foundation
import KausMedia

extension TransactionModel {
    /// Cria um novo registro a partir do DTO. O `id` enviado pelo cliente é ignorado:
    /// a identidade é sempre atribuída pelo banco.
    convenience init(newFrom dto: TransactionDTO, defaultCategory: String = "Geral") {
        self.init(
            description: dto.description,
            amount: dto.amount,
            category: dto.category ?? defaultCategory,
            date: dto.date
        )
    }

    func toDTO() -> TransactionDTO {
        TransactionDTO(
            id: id,
            description: description,
            amount: amount,
            date: date,
            category: category
        )
    }
}
