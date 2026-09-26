import Foundation

/// O que apagar num `POST /api/reset`. Cada opção inclui as anteriores:
/// não faz sentido apagar contas e manter lançamentos órfãos.
public enum ResetScope: String, Codable, Sendable, CaseIterable, Identifiable {
    /// Apaga lançamentos e histórico de importações.
    case transactions
    /// Apaga também as contas.
    case accounts
    /// Apaga também as regras de categorização.
    case everything

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .transactions: return "Lançamentos e importações"
        case .accounts: return "Lançamentos e contas"
        case .everything: return "Tudo, inclusive regras"
        }
    }
}

public struct ResetRequest: Codable, Sendable {
    public var scope: ResetScope
    /// Frase de confirmação exigida pelo servidor, para que um `POST` acidental
    /// não limpe a base.
    public var confirmation: String

    public static let confirmationPhrase = "APAGAR TUDO"

    public init(scope: ResetScope, confirmation: String = ResetRequest.confirmationPhrase) {
        self.scope = scope
        self.confirmation = confirmation
    }
}

public struct ResetResponse: Codable, Sendable {
    public var transactions: Int
    public var batches: Int
    public var accounts: Int
    public var rules: Int

    public init(transactions: Int = 0, batches: Int = 0, accounts: Int = 0, rules: Int = 0) {
        self.transactions = transactions
        self.batches = batches
        self.accounts = accounts
        self.rules = rules
    }
}

/// Resultado de apagar uma categoria inteira: as regras somem e os lançamentos
/// que a usavam são recategorizados com as regras restantes.
public struct DeleteCategoryResponse: Codable, Sendable {
    public var removedRules: Int
    public var recategorized: Int

    public init(removedRules: Int, recategorized: Int) {
        self.removedRules = removedRules
        self.recategorized = recategorized
    }
}
