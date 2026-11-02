import Foundation
import KausMedia
import Testing
import Vapor
@testable import KausAustralis

@Suite("Validação de entradas")
struct ValidationTests {
    @Test func requiredTrimsAndRejectsBlank() throws {
        #expect(try Validation.accountName("  Nubank ") == "Nubank")
        #expect(throws: LedgerError.accountNameRequired) { try Validation.accountName("   ") }
    }

    @Test func regexRulesAreBoundedAndCompiled() {
        let long = CategoryRule(term: String(repeating: "a", count: 201), category: "X", matchKind: .regex)
        #expect(throws: LedgerError.regexTooLong(limit: 200)) { try Validation.rule(long) }

        let broken = CategoryRule(term: "(abc", category: "X", matchKind: .regex)
        #expect(throws: LedgerError.invalidRegex("(abc")) { try Validation.rule(broken) }

        let blankCategory = CategoryRule(term: "abc", category: " ", matchKind: .contains)
        #expect(throws: LedgerError.ruleCategoryRequired) { try Validation.rule(blankCategory) }
    }

    @Test func commitmentChecksMonthsAndAmounts() {
        let start = YearMonth(year: 2026, month: 5)
        var commitment = RecurringCommitment(
            name: "Aluguel", category: "Moradia", kind: .expense, amount: 2000, start: start
        )
        #expect(throws: Never.self) { try Validation.commitment(commitment) }

        commitment.end = YearMonth(year: 2026, month: 4)
        #expect(throws: LedgerError.endBeforeStart) { try Validation.commitment(commitment) }

        commitment.end = nil
        commitment.overrides = ["2026-13": 10]
        #expect(throws: LedgerError.invalidOverrideMonth("2026-13")) { try Validation.commitment(commitment) }

        commitment.overrides = [:]
        commitment.priceChanges = ["2026-08": -1]
        #expect(throws: LedgerError.invalidPriceChangeAmount(month: "2026-08")) { try Validation.commitment(commitment) }
    }

    @Test func limitIsNormalizedAndPositive() throws {
        let limit = try Validation.limit(CategoryLimit(category: " Mercado ", monthlyLimit: 800))
        #expect(limit.category == "Mercado")
        #expect(throws: LedgerError.limitMustBePositive) {
            try Validation.limit(CategoryLimit(category: "Mercado", monthlyLimit: 0))
        }
    }

    @Test func errorsKeepTheirHTTPStatusAndMessage() {
        #expect(LedgerError.accountNameTaken("Nubank").status == .conflict)
        #expect(LedgerError.accountNameTaken("Nubank").reason == "Já existe uma conta com o nome Nubank")
        #expect(LedgerError.ruleNotFound.status == .notFound)
        #expect(LedgerError.invalidYearMonth(field: "from").reason == "from deve ser AAAA-MM com ano entre 1 e 9999")
        #expect(LedgerError.emptyFile.status == .badRequest)
    }
}
