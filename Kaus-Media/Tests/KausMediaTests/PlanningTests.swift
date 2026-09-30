import XCTest
@testable import KausMedia

final class YearMonthTests: XCTestCase {
    func testNormalizesMonthOverflowAndUnderflow() {
        XCTAssertEqual(YearMonth(year: 2026, month: 13), YearMonth(year: 2027, month: 1))
        XCTAssertEqual(YearMonth(year: 2026, month: 0), YearMonth(year: 2025, month: 12))
        XCTAssertEqual(YearMonth(year: 2026, month: 5).adding(months: -17), YearMonth(year: 2024, month: 12))
    }

    func testRejectsOutOfRangeYears() {
        XCTAssertNil(YearMonth("99999999999999-01"))
        XCTAssertNil(YearMonth("0000-01"))
        XCTAssertEqual(YearMonth("9999-12"), YearMonth(year: 9999, month: 12))
    }

    func testSerializesAsYearDashMonth() throws {
        let encoded = try JSONEncoder().encode(YearMonth(year: 2026, month: 3))
        XCTAssertEqual(String(decoding: encoded, as: UTF8.self), "\"2026-03\"")
        XCTAssertEqual(try JSONDecoder().decode(YearMonth.self, from: encoded), YearMonth(year: 2026, month: 3))
        XCTAssertThrowsError(try JSONDecoder().decode(YearMonth.self, from: Data("\"2026-13\"".utf8)))
    }

    func testClampsDayToLastDayOfMonth() {
        let date = YearMonth(year: 2026, month: 2).date(day: 31)
        XCTAssertEqual(LedgerCalendar.calendar.component(.day, from: date), 28)
        XCTAssertEqual(LedgerCalendar.calendar.component(.month, from: date), 2)
    }

    func testRangeIsInclusiveAndOrdered() {
        let months = YearMonth.range(from: YearMonth(year: 2026, month: 11), to: YearMonth(year: 2027, month: 2))
        XCTAssertEqual(months.map(\.description), ["2026-11", "2026-12", "2027-01", "2027-02"])
        XCTAssertTrue(YearMonth.range(from: YearMonth(year: 2027, month: 2), to: YearMonth(year: 2026, month: 11)).isEmpty)
    }
}

final class RecurringCommitmentTests: XCTestCase {
    private func commitment(
        _ name: String,
        kind: RecurringCommitment.Kind = .expense,
        amount: Double = 100,
        start: YearMonth = YearMonth(year: 2026, month: 1),
        end: YearMonth? = nil,
        overrides: [String: Double] = [:],
        tags: [String] = []
    ) -> RecurringCommitment {
        RecurringCommitment(
            name: name,
            category: name,
            kind: kind,
            amount: amount,
            start: start,
            end: end,
            tags: tags,
            overrides: overrides
        )
    }

    func testSignFollowsKind() {
        let month = YearMonth(year: 2026, month: 3)
        XCTAssertEqual(commitment("Copel").plannedAmount(in: month), -100)
        XCTAssertEqual(commitment("Salário", kind: .income).plannedAmount(in: month), 100)
        XCTAssertEqual(commitment("Cofrinho", kind: .saving).plannedAmount(in: month), -100)
    }

    func testOverrideReplacesDefaultAndZeroSkipsMonth() {
        let copel = commitment("Copel", amount: 500, overrides: ["2026-07": 350, "2026-08": 0])
        XCTAssertEqual(copel.plannedAmount(in: YearMonth(year: 2026, month: 6)), -500)
        XCTAssertEqual(copel.plannedAmount(in: YearMonth(year: 2026, month: 7)), -350)
        XCTAssertEqual(copel.plannedAmount(in: YearMonth(year: 2026, month: 8)), 0)
    }

    func testRespectsWindowAndDisabledFlag() {
        let parcela = commitment("Parcela", start: YearMonth(year: 2026, month: 2), end: YearMonth(year: 2026, month: 4))
        XCTAssertEqual(parcela.plannedAmount(in: YearMonth(year: 2026, month: 1)), 0)
        XCTAssertEqual(parcela.plannedAmount(in: YearMonth(year: 2026, month: 4)), -100)
        XCTAssertEqual(parcela.plannedAmount(in: YearMonth(year: 2026, month: 5)), 0)

        var desligada = parcela
        desligada.isEnabled = false
        XCTAssertEqual(desligada.plannedAmount(in: YearMonth(year: 2026, month: 3)), 0)
    }

    func testTagsAreNormalizedAndEssentialIsDetected() {
        let moradia = commitment("Condomínio", tags: [" Essencial ", "essencial", "Moradia"])
        XCTAssertEqual(moradia.tags, ["essencial", "moradia"])
        XCTAssertTrue(moradia.isEssential)
        XCTAssertFalse(commitment("Netflix").isEssential)
        XCTAssertEqual(TagSet.suggested(for: "Moradia"), [TagSet.essential])
        XCTAssertEqual(TagSet.suggested(for: "Categoria inventada"), [])
    }
}

final class AnnualPlanTests: XCTestCase {
    private let reference = YearMonth(year: 2026, month: 3).date(day: 10)

    private func transaction(
        _ description: String,
        _ amount: Double,
        _ month: YearMonth,
        category: String,
        isProjected: Bool = false
    ) -> TransactionDTO {
        TransactionDTO(
            description: description,
            amount: amount,
            date: month.date(day: 5),
            category: category,
            isProjected: isProjected
        )
    }

    func testRealizedMonthsWinOverPlan() {
        let plan = AnnualPlan.build(
            from: YearMonth(year: 2026, month: 1),
            to: YearMonth(year: 2026, month: 4),
            transactions: [transaction("Copel", -512, YearMonth(year: 2026, month: 1), category: "Moradia")],
            commitments: [
                RecurringCommitment(
                    name: "Copel",
                    category: "Moradia",
                    amount: 500,
                    start: YearMonth(year: 2026, month: 1)
                )
            ],
            reference: reference
        )

        let row = try? XCTUnwrap(plan.rows.first { $0.category == "Moradia" })
        XCTAssertEqual(row?.value(in: YearMonth(year: 2026, month: 1)), -512)
        XCTAssertTrue(row?.isRealized(in: YearMonth(year: 2026, month: 1)) == true)
        // Fevereiro ficou sem extrato e já passou: o plano não reescreve o passado.
        XCTAssertEqual(row?.value(in: YearMonth(year: 2026, month: 2)), 0)
        XCTAssertEqual(row?.value(in: YearMonth(year: 2026, month: 4)), -500)
        XCTAssertFalse(row?.isRealized(in: YearMonth(year: 2026, month: 4)) == true)
    }

    func testTotalsSeparateSavingFromExpense() {
        let month = YearMonth(year: 2026, month: 4)
        let plan = AnnualPlan.build(
            from: month,
            to: month,
            transactions: [],
            commitments: [
                RecurringCommitment(name: "Salário", category: "Salário", kind: .income, amount: 5_000, start: month),
                RecurringCommitment(
                    name: "Condomínio",
                    category: "Moradia",
                    amount: 800,
                    start: month,
                    tags: [TagSet.essential]
                ),
                RecurringCommitment(name: "Netflix", category: "Assinaturas", amount: 50, start: month),
                RecurringCommitment(name: "Cofrinho", category: "Guardado", kind: .saving, amount: 1_000, start: month)
            ],
            reference: reference
        )

        let totals = plan.totals[0]
        XCTAssertEqual(totals.income, 5_000)
        XCTAssertEqual(totals.expenses, -850)
        XCTAssertEqual(totals.saved, -1_000)
        XCTAssertEqual(totals.essentialExpenses, -800)
        XCTAssertEqual(totals.net, 4_150)
        XCTAssertEqual(totals.cashFlow, 3_150)
        XCTAssertEqual(totals.cumulative, 3_150)
    }

    func testCumulativeStartsFromOpeningBalance() {
        let start = YearMonth(year: 2026, month: 4)
        let plan = AnnualPlan.build(
            from: start,
            to: start.adding(months: 1),
            transactions: [],
            commitments: [
                RecurringCommitment(name: "Salário", category: "Salário", kind: .income, amount: 1_000, start: start)
            ],
            openingBalance: 200,
            reference: reference
        )

        XCTAssertEqual(plan.totals.map(\.cumulative), [1_200, 2_200])
        XCTAssertTrue(plan.totals.allSatisfy(\.isForecast))
    }

    func testTransfersAreIgnoredButSavingsAreKept() {
        let month = YearMonth(year: 2026, month: 1)
        let plan = AnnualPlan.build(
            from: month,
            to: month,
            transactions: [
                transaction("Pagamento fatura", -900, month, category: "Cartão de crédito"),
                transaction("Aplicação caixinha", -300, month, category: "Guardado"),
                transaction("Mercado", -200, month, category: "Mercado")
            ],
            commitments: [],
            transferCategories: ["Cartão de crédito", "Guardado"],
            reference: reference
        )

        XCTAssertNil(plan.rows.first { $0.category == "Cartão de crédito" })
        XCTAssertEqual(plan.savingRows.first?.category, "Guardado")
        XCTAssertEqual(plan.totals[0].saved, -300)
        XCTAssertEqual(plan.totals[0].expenses, -200)
    }

    func testProjectedInstallmentsFillFutureMonths() {
        let future = YearMonth(year: 2026, month: 6)
        let plan = AnnualPlan.build(
            from: YearMonth(year: 2026, month: 3),
            to: future,
            transactions: [
                transaction("Geladeira 4/10", -250, future, category: "Casa", isProjected: true)
            ],
            commitments: [],
            reference: reference
        )

        let row = plan.rows.first { $0.category == "Casa" }
        XCTAssertEqual(row?.value(in: future), -250)
        XCTAssertEqual(plan.totals.last?.expenses, -250)
    }

    func testUnpaidCommitmentStillCountsWhenAnotherInSameCategoryPosted() {
        let month = YearMonth(year: 2026, month: 3)
        let plan = AnnualPlan.build(
            from: month,
            to: month,
            transactions: [transaction("PIX JOAO", -1_000, month, category: "Moradia")],
            commitments: [
                RecurringCommitment(name: "Aluguel", category: "Moradia", amount: 1_000, start: month),
                RecurringCommitment(name: "Copel", category: "Moradia", amount: 200, start: month)
            ],
            reference: reference
        )

        XCTAssertEqual(plan.rows.first { $0.category == "Moradia" }?.value(in: month), -1_200)
    }

    func testOffsettingEntriesDoNotReviveCommitment() {
        let month = YearMonth(year: 2026, month: 3)
        let plan = AnnualPlan.build(
            from: month,
            to: month,
            transactions: [
                transaction("Copel", -100, month, category: "Moradia"),
                transaction("Estorno Copel", 100, month, category: "Moradia")
            ],
            commitments: [RecurringCommitment(name: "Copel", category: "Moradia", amount: 100, start: month)],
            reference: reference
        )

        let row = plan.rows.first { $0.category == "Moradia" }
        XCTAssertEqual(row?.value(in: month), 0)
        XCTAssertTrue(row?.isRealized(in: month) == true)
        XCTAssertEqual(plan.totals[0].expenses, 0)
    }

    func testProjectedCreditsAreIncome() {
        let future = YearMonth(year: 2026, month: 6)
        let plan = AnnualPlan.build(
            from: future,
            to: future,
            transactions: [transaction("Reembolso", 500, future, category: "Reembolso", isProjected: true)],
            commitments: [],
            reference: reference
        )

        XCTAssertEqual(plan.totals[0].income, 500)
        XCTAssertEqual(plan.totals[0].expenses, 0)
    }

    func testEssentialTotalsFollowTransactionTags() {
        let month = YearMonth(year: 2026, month: 1)
        var untagged = transaction("Mercado", -100, month, category: "Mercado")
        untagged.tags = ["variável"]
        var tagged = transaction("Presente", -40, month, category: "Presentes")
        tagged.tags = [TagSet.essential]
        let inherited = transaction("Supermercado", -60, month, category: "Mercado")

        let plan = AnnualPlan.build(
            from: month,
            to: month,
            transactions: [untagged, tagged, inherited],
            commitments: [],
            reference: reference
        )

        XCTAssertEqual(plan.totals[0].expenses, -200)
        XCTAssertEqual(plan.totals[0].essentialExpenses, -100)
    }

    func testVariableSpendingKeepsPlanAsFloorWithinCurrentMonth() {
        let month = YearMonth(year: 2026, month: 3)
        let budget = RecurringCommitment(name: "Feira", category: "Mercado", amount: 800, start: month)
        func plan(_ amounts: [Double]) -> Double? {
            AnnualPlan.build(
                from: month,
                to: month,
                transactions: amounts.map { transaction("Supermercado", $0, month, category: "Mercado") },
                commitments: [budget],
                reference: reference
            ).rows.first?.value(in: month)
        }

        XCTAssertEqual(plan([-100]), -800)
        XCTAssertEqual(plan([-500, -400]), -900)
    }
}
