import Foundation
import Testing
import KausMedia
@testable import KausBorealis

@Suite("Formulário de novo lançamento")
struct NewTransactionFormTests {
    private let firstDay = LedgerCalendar.startOfDay(DateParser.parse("10/01/2026")!)

    private func form(count: Int = 1, amount: String = "-100,00") -> NewTransactionForm {
        var form = NewTransactionForm()
        form.description = "IPTU"
        form.date = firstDay
        form.amount = amount
        form.installmentCount = count
        return form
    }

    @Test func singleTransactionNeedsDescriptionAndAmount() {
        var form = form()
        #expect(form.isValid)
        form.description = "   "
        #expect(!form.isValid)
        form.description = "IPTU"
        form.amount = "abc"
        #expect(!form.isValid)
    }

    @Test func installmentsAreMonthlyAndSumExactly() {
        let form = form(count: 3, amount: "-33,33")
        #expect(form.installments.map(\.number) == [1, 2, 3])
        #expect(form.installments.map(\.date) == (0..<3).map { LedgerCalendar.addingMonths($0, to: firstDay) })
        #expect(form.installmentTotal == Money(cents: -9999))
    }

    @Test func manualEditsSurviveRegeneration() {
        var form = form(count: 3)
        form.installments[1].amount = "-150"
        form.amount = "-120"
        #expect(form.installments.map(\.amount) == ["-120", "-150", "-120"])
    }

    @Test func futureDatesBecomeProjected() throws {
        let transactions = try #require(form(count: 3).transactions(today: firstDay))
        #expect(transactions.map(\.isProjected) == [false, true, true])
        #expect(transactions.map(\.installment) == [
            Installment(number: 1, total: 3), Installment(number: 2, total: 3), Installment(number: 3, total: 3),
        ])
        #expect(transactions.allSatisfy { $0.amount == -100 })
    }

    @Test func blankCategoryAndNoteAreOmitted() throws {
        var form = form()
        form.note = "  "
        let transaction = try #require(form.transactions(today: firstDay)?.first)
        #expect(transaction.category == nil)
        #expect(transaction.note == nil)
    }
}
