import Foundation
import KausMedia

/// Rascunho de um lançamento manual. Com mais de uma parcela (ex.: IPTU em
/// 10 vezes), gera uma linha por mês, cada uma com data e valor editáveis.
///
/// Mora fora da view para que as regras (validação, geração das parcelas,
/// montagem dos DTOs) sejam testáveis sem SwiftUI.
struct NewTransactionForm {
    var description = ""
    var amount = "" {
        didSet { regenerate() }
    }
    var date = Date() {
        didSet { regenerate() }
    }
    var accountID: UUID?
    /// Vazio deixa a categorização para as regras do servidor.
    var category = ""
    var tags: [String] = []
    var note = ""
    var installmentCount = 1 {
        didSet { regenerate() }
    }
    var installments: [InstallmentDraft] = []

    var hasInstallments: Bool { installmentCount > 1 }

    var isValid: Bool {
        guard !description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }
        guard hasInstallments else { return ValueParser.parse(amount) != nil }
        return installments.count == installmentCount
            && installments.allSatisfy { ValueParser.parse($0.amount) != nil }
    }

    var installmentTotal: Money {
        installments.compactMap { ValueParser.parse($0.amount) }.sum()
    }

    /// Refaz as parcelas a partir do valor e da primeira data, mantendo as que
    /// o usuário já ajustou à mão.
    mutating func regenerate() {
        guard hasInstallments else {
            installments = []
            return
        }
        installments = (1...installmentCount).map { number in
            if let edited = installments.first(where: { $0.number == number && $0.isEdited }) {
                return edited
            }
            return InstallmentDraft(
                number: number,
                date: LedgerCalendar.addingMonths(number - 1, to: date),
                amount: amount
            )
        }
    }

    /// Os lançamentos a criar; `nil` enquanto o formulário é inválido.
    /// Datas futuras entram como previstas: não contam no saldo até o dia chegar.
    func transactions(today: Date = Date()) -> [TransactionDTO]? {
        guard isValid else { return nil }
        let category = category.isEmpty ? nil : category
        let note = TransactionNote.normalize(note)
        let today = LedgerCalendar.startOfDay(today)

        func make(amount: Money, date: Date, installment: Installment?) -> TransactionDTO {
            TransactionDTO(
                description: description,
                amount: amount,
                date: date,
                category: category,
                accountID: accountID,
                isProjected: LedgerCalendar.startOfDay(date) > today,
                installment: installment,
                tags: tags,
                note: note
            )
        }

        guard hasInstallments else {
            return ValueParser.parse(amount).map { [make(amount: $0, date: date, installment: nil)] }
        }
        return installments.compactMap { draft in
            ValueParser.parse(draft.amount).map {
                make(amount: $0, date: draft.date, installment: Installment(number: draft.number, total: installmentCount))
            }
        }
    }
}

struct InstallmentDraft: Identifiable, Equatable {
    var id: Int { number }
    let number: Int
    var date: Date {
        didSet { isEdited = true }
    }
    var amount: String {
        didSet { isEdited = true }
    }
    private(set) var isEdited = false

    init(number: Int, date: Date, amount: String) {
        self.number = number
        self.date = date
        self.amount = amount
    }
}
