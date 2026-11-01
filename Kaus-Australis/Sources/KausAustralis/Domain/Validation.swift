import Foundation
import KausMedia

/// Regras de validação das entradas, sem dependência de HTTP nem de banco.
/// Cada função devolve o valor já normalizado (ex.: sem espaços nas pontas)
/// ou lança o `LedgerError` correspondente.
enum Validation {
    /// Texto obrigatório, sem espaços nas pontas.
    static func required(_ text: String, or error: LedgerError) throws -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw error }
        return trimmed
    }

    static func accountName(_ name: String) throws -> String {
        try required(name, or: .accountNameRequired)
    }

    // MARK: Regras

    /// A regra é aplicada a cada lançamento em importações e recategorizações
    /// em massa: um padrão longo e ambíguo custa caro multiplicado por milhares.
    static let regexLengthLimit = 200

    static func rule(_ rule: CategoryRule) throws {
        _ = try required(rule.term, or: .ruleTermRequired)
        _ = try required(rule.category, or: .ruleCategoryRequired)
        if rule.matchKind == .regex {
            guard rule.term.count <= regexLengthLimit else { throw LedgerError.regexTooLong(limit: regexLengthLimit) }
            guard (try? NSRegularExpression(pattern: rule.term)) != nil else {
                throw LedgerError.invalidRegex(rule.term)
            }
        }
    }

    // MARK: Planejamento

    static func commitment(_ commitment: RecurringCommitment) throws {
        _ = try required(commitment.name, or: .nameRequired)
        _ = try required(commitment.category, or: .categoryRequired)
        guard commitment.amount >= 0 else { throw LedgerError.invalidAmount }
        if let end = commitment.end, end < commitment.start {
            throw LedgerError.endBeforeStart
        }
        for (month, value) in commitment.overrides {
            guard YearMonth(month) != nil else { throw LedgerError.invalidOverrideMonth(month) }
            guard value >= 0 else { throw LedgerError.invalidOverrideAmount(month: month) }
        }
        for (month, value) in commitment.priceChanges {
            guard YearMonth(month) != nil else { throw LedgerError.invalidPriceChangeMonth(month) }
            guard value >= 0 else { throw LedgerError.invalidPriceChangeAmount(month: month) }
        }
    }

    static func limit(_ limit: CategoryLimit) throws -> CategoryLimit {
        var limit = limit
        limit.category = try required(limit.category, or: .categoryRequired)
        guard limit.monthlyLimit > 0 else { throw LedgerError.limitMustBePositive }
        return limit
    }

    static func setting(_ setting: CategorySetting) throws -> CategorySetting {
        var setting = setting
        setting.category = try required(setting.category, or: .categoryRequired)
        return setting
    }

    /// `AAAA-MM` opcional de um parâmetro de consulta.
    static func month(_ text: String?, field: String) throws -> YearMonth? {
        guard let text else { return nil }
        guard let month = YearMonth(text) else { throw LedgerError.invalidYearMonth(field: field) }
        return month
    }

    static func year(_ year: Int) throws -> Int {
        guard (1...9998).contains(year) else { throw LedgerError.invalidYear }
        return year
    }

    // MARK: Manutenção

    static func resetConfirmation(_ request: ResetRequest) throws {
        guard request.confirmation == ResetRequest.confirmationPhrase else {
            throw LedgerError.invalidResetConfirmation(expected: ResetRequest.confirmationPhrase)
        }
    }
}
