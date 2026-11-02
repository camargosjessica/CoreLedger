import Foundation

/// Falhas de regra de negócio, independentes de HTTP. A tradução para status
/// e mensagem acontece na borda (`LedgerError+Abort.swift`).
enum LedgerError: Error, Equatable, Sendable {
    case transactionNotFound
    case accountNotFound
    case importNotFound
    case descriptionRequired
    /// A contrapartida espelha o original: é ele que deve ser editado.
    case counterpartIsReadOnly
    case transferToSameAccount
    case transferAlreadyTargetsAccount
    case counterpartAlreadyExists
    case duplicateTransaction
    case tooManyItems(limit: Int)
}
