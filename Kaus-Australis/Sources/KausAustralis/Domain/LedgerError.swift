import Foundation

/// Falhas de regra de negócio, independentes de HTTP. A tradução para status
/// e mensagem acontece na borda (`LedgerError+Abort.swift`).
enum LedgerError: Error, Equatable, Sendable {
    // Não encontrados
    case transactionNotFound
    case accountNotFound
    case importNotFound
    case ruleNotFound
    case commitmentNotFound

    // Lançamentos
    case descriptionRequired
    /// A contrapartida espelha o original: é ele que deve ser editado.
    case counterpartIsReadOnly
    case transferToSameAccount
    case transferAlreadyTargetsAccount
    case counterpartAlreadyExists
    case duplicateTransaction
    case tooManyItems(limit: Int)
    case emptyFile

    // Contas
    case accountNameRequired
    case accountNameTaken(String)

    // Regras e rótulos
    case ruleTermRequired
    case ruleCategoryRequired
    case regexTooLong(limit: Int)
    case invalidRegex(String)
    case invalidCategory
    case invalidTag
    case newNameRequired
    /// Juntar uma categoria de transferência com uma comum faria os gastos
    /// sumirem da análise.
    case incompatibleCategoryMerge(name: String, current: String)

    // Planejamento
    case nameRequired
    case categoryRequired
    case invalidAmount
    case endBeforeStart
    case invalidOverrideMonth(String)
    case invalidOverrideAmount(month: String)
    case invalidPriceChangeMonth(String)
    case invalidPriceChangeAmount(month: String)
    case invalidYearMonth(field: String)
    case limitMustBePositive
    case invalidYear

    // Manutenção
    case invalidResetConfirmation(expected: String)
}
