import XCTest
@testable import KausMedia

final class FinancialPositionTests: XCTestCase {
    private func account(_ name: String, _ kind: AccountKind, _ balance: Double) -> AccountPosition {
        AccountPosition(accountID: UUID(), name: name, kind: kind, balance: balance)
    }

    func testSeparatesSavedFromAvailableAndDebt() {
        let position = FinancialPosition.make(accounts: [
            account("Conta corrente", .checking, 1_200),
            account("Caixinha viagem", .savings, 2_000),
            account("Tesouro", .investment, 5_000),
            account("Carteira", .cash, 100),
            account("Cartão", .creditCard, -1_500)
        ])

        XCTAssertEqual(position.available, 1_300)
        XCTAssertEqual(position.saved, 7_000)
        XCTAssertEqual(position.creditCardDebt, 1_500)
        XCTAssertEqual(position.net, 6_800)
        XCTAssertEqual(position.status, .positive)
    }

    func testCreditBalanceOnCardReducesDebt() {
        let position = FinancialPosition.make(accounts: [
            account("Cartão", .creditCard, 50)
        ])

        XCTAssertEqual(position.creditCardDebt, -50)
        XCTAssertEqual(position.net, 50)
    }

    func testStatusIsEvenWithinACent() {
        let position = FinancialPosition.make(accounts: [
            account("Conta", .checking, 1_000),
            account("Cartão", .creditCard, -1_000.001)
        ])

        XCTAssertEqual(position.status, .even)
    }

    func testNegativeWhenCardExceedsMoney() {
        let position = FinancialPosition.make(accounts: [
            account("Conta", .checking, 300),
            account("Caixinha", .savings, 200),
            account("Cartão", .creditCard, -900)
        ])

        XCTAssertEqual(position.status, .negative)
        XCTAssertEqual(position.net, -400)
    }

    /// Parcelas futuras não são dívida realizada: aparecem à parte, sempre
    /// positivas, sem mexer no líquido.
    func testUpcomingInstallmentsStayOutOfNet() {
        let position = FinancialPosition.make(
            accounts: [account("Conta", .checking, 500)],
            upcomingInstallments: -800
        )

        XCTAssertEqual(position.upcomingInstallments, 800)
        XCTAssertEqual(position.net, 500)
    }

    func testSavingsTransfersAreNotExpenses() {
        let categorizer = Categorizer(rules: CategoryRule.seed)
        let category = categorizer.category(for: "APLICACAO CAIXINHA VIAGEM", amount: -500)

        XCTAssertEqual(category, "Guardado")
        XCTAssertTrue(categorizer.transferCategories.contains("Guardado"))
    }
}
