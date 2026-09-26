import XCTest
@testable import KausMedia

final class CategorizerTests: XCTestCase {

    func testUsesProvidedRules_NotHardcodedOnes() {
        let sut = Categorizer(rules: [
            CategoryRule(term: "cantina da vó", category: "Família")
        ])

        XCTAssertEqual(sut.category(for: "CANTINA DA VO - PIX", amount: -42), "Família")
        XCTAssertEqual(sut.category(for: "IFOOD *RESTAURANTE", amount: -42), CategoryRule.uncategorizedDebit)
    }

    func testMatchIsDiacriticAndCaseInsensitive() {
        let sut = Categorizer(rules: [CategoryRule(term: "farmácia", category: "Saúde", matchKind: .contains)])

        XCTAssertEqual(sut.category(for: "DROGASIL FARMACIA", amount: -30), "Saúde")
        XCTAssertEqual(sut.category(for: "drogasil farmácia", amount: -30), "Saúde")
    }

    func testWordMatch_DoesNotMatchInsideAnotherWord() {
        let sut = Categorizer(rules: [CategoryRule(term: "net", category: "Telefone/Internet", matchKind: .word)])

        XCTAssertEqual(sut.category(for: "NET SERVICOS", amount: -120), "Telefone/Internet")
        XCTAssertEqual(sut.category(for: "INTERNET BANDA LARGA", amount: -120), CategoryRule.uncategorizedDebit)
    }

    func testContainsMatch_AcceptsTruncatedPrefixes() {
        let sut = Categorizer(rules: [CategoryRule(term: "supermerc", category: "Mercado", matchKind: .contains)])

        XCTAssertEqual(sut.category(for: "SUPERMERCADO BOM PRECO", amount: -210), "Mercado")
    }

    func testRegexMatch() {
        let sut = Categorizer(rules: [
            CategoryRule(term: "^uber( \\*)? (trip|eats)", category: "Transporte", matchKind: .regex)
        ])

        XCTAssertEqual(sut.category(for: "Uber * Trip 1234", amount: -18), "Transporte")
        XCTAssertEqual(sut.category(for: "Pagamento Uber", amount: -18), CategoryRule.uncategorizedDebit)
    }

    func testPriorityDecidesBetweenOverlappingRules() {
        let rules = [
            CategoryRule(term: "pix", category: "Transferências", matchKind: .word, priority: 90),
            CategoryRule(term: "pix mercado", category: "Mercado", matchKind: .contains, priority: 10)
        ]

        XCTAssertEqual(Categorizer(rules: rules).category(for: "PIX MERCADO CENTRAL", amount: -80), "Mercado")
        XCTAssertEqual(Categorizer(rules: rules).category(for: "PIX ENVIADO", amount: -80), "Transferências")
    }

    func testAmountScopeSeparatesCreditFromDebit() {
        let rules = [
            CategoryRule(term: "transf", category: "Salário", matchKind: .contains, amountScope: .credit, priority: 10),
            CategoryRule(term: "transf", category: "Transferências", matchKind: .contains, amountScope: .debit, priority: 10)
        ]
        let sut = Categorizer(rules: rules)

        XCTAssertEqual(sut.category(for: "TRANSF RECEBIDA", amount: 5000), "Salário")
        XCTAssertEqual(sut.category(for: "TRANSF ENVIADA", amount: -5000), "Transferências")
    }

    func testDisabledRuleIsIgnored() {
        let sut = Categorizer(rules: [
            CategoryRule(term: "uber", category: "Transporte", isEnabled: false)
        ])

        XCTAssertEqual(sut.category(for: "UBER TRIP", amount: -18), CategoryRule.uncategorizedDebit)
    }

    func testFallbackDependsOnSign() {
        let sut = Categorizer(rules: [])

        XCTAssertEqual(sut.category(for: "QUALQUER COISA", amount: 100), CategoryRule.uncategorizedCredit)
        XCTAssertEqual(sut.category(for: "QUALQUER COISA", amount: -100), CategoryRule.uncategorizedDebit)
    }

    func testSeedRules_DoNotMisclassifyKnownFalsePositives() {
        let sut = Categorizer(rules: CategoryRule.seed)

        // "99" solto casava com qualquer descrição contendo 99 no categorizador original.
        XCTAssertNotEqual(sut.category(for: "MERCADO 99 CENTAVOS", amount: -99), "Transporte")
        XCTAssertEqual(sut.category(for: "99APP *TRIP", amount: -25), "Transporte")
        XCTAssertEqual(sut.category(for: "INTERNET VIVO FIBRA", amount: -110), "Telefone/Internet")
    }

    func testTransferCategoriesAreExposed() {
        let sut = Categorizer(rules: CategoryRule.seed)

        XCTAssertTrue(sut.transferCategories.contains("Transferências"))
        XCTAssertFalse(sut.transferCategories.contains("Mercado"))
    }
}
