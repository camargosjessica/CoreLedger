import XCTest
import KausMedia
@testable import KausAustralis

final class TransactionMappingTests: XCTestCase {

    private let rules = [
        CategoryRule(term: "mercado", category: "Mercado", matchKind: .contains, priority: 10)
    ]

    func testModelFromDTO_UsesCategorizer_WhenCategoryIsNil() {
        let dto = TransactionDTO(
            description: "Compra Mercado",
            amount: -150.50,
            date: Date(),
            category: nil
        )

        let sut = TransactionModel(newFrom: dto, categorizer: Categorizer(rules: rules))

        XCTAssertEqual(sut.category, "Mercado")
        XCTAssertNil(sut.id, "A identidade deve ser atribuída pelo banco, não pelo cliente")
    }

    func testModelFromDTO_FallsBackWhenNoRuleMatches() {
        let dto = TransactionDTO(description: "Compra qualquer", amount: -10, date: Date())

        let sut = TransactionModel(newFrom: dto, categorizer: Categorizer(rules: rules))

        XCTAssertEqual(sut.category, CategoryRule.uncategorizedDebit)
    }

    func testModelFromDTO_IgnoresClientProvidedID() {
        let dto = TransactionDTO(
            id: UUID(),
            description: "Salário",
            amount: 4200,
            date: Date(),
            category: "Receita"
        )

        let sut = TransactionModel(newFrom: dto)

        XCTAssertNil(sut.id)
        XCTAssertEqual(sut.category, "Receita")
    }

    func testModelFromDTO_AssignsDedupKeyAndNormalizesDate() {
        let accountID = UUID()
        let date = DateParser.parse("15/01/2025")!.addingTimeInterval(3600 * 5)
        let dto = TransactionDTO(
            description: "Padaria",
            amount: -18.90,
            date: date,
            category: "Alimentação",
            accountID: accountID
        )

        let sut = TransactionModel(newFrom: dto)

        XCTAssertEqual(sut.date, LedgerCalendar.startOfDay(date))
        XCTAssertEqual(
            sut.dedupKey,
            DedupKey.make(accountID: accountID, date: sut.date, description: "Padaria", amount: -18.90)
        )
    }

    func testToDTO_RoundTripsAllFields() {
        let id = UUID()
        let accountID = UUID()
        let date = Date()
        let model = TransactionModel(
            id: id,
            description: "Aluguel",
            amount: -1800,
            category: "Moradia",
            date: date,
            accountID: accountID,
            dedupKey: "chave",
            isProjected: true,
            installment: Installment(number: 2, total: 6)
        )

        let dto = model.toDTO()

        XCTAssertEqual(dto.id, id)
        XCTAssertEqual(dto.description, "Aluguel")
        XCTAssertEqual(dto.amount, -1800)
        XCTAssertEqual(dto.category, "Moradia")
        XCTAssertEqual(dto.date, date)
        XCTAssertEqual(dto.accountID, accountID)
        XCTAssertTrue(dto.isProjected)
        XCTAssertEqual(dto.installment, Installment(number: 2, total: 6))
        XCTAssertEqual(dto.dedupKey, "chave")
    }
}

final class ImportPlannerTests: XCTestCase {

    private let accountID = UUID()

    private func transaction(_ description: String, _ amount: Double, _ date: String, projected: Bool = false) -> ImportedTransaction {
        ImportedTransaction(
            date: DateParser.parse(date)!,
            description: description,
            amount: amount,
            isProjected: projected
        )
    }

    func testInsertsNewTransactions() {
        let plan = ImportPlanner.plan(
            transactions: [transaction("PADARIA", -18.90, "15/01/2025")],
            accountID: accountID,
            existing: [:]
        )

        XCTAssertEqual(plan.inserts.count, 1)
        XCTAssertEqual(plan.duplicates, 0)
    }

    /// Três compras iguais no mesmo dia são três compras — mas reimportar o
    /// arquivo não pode gerar mais nenhuma.
    func testRepeatedPurchasesAreKeptAndReimportIsIdempotent() {
        let repeated = transaction("PADARIA", -18.90, "15/01/2025")
        let file = [repeated, repeated, repeated]

        let first = ImportPlanner.plan(transactions: file, accountID: accountID, existing: [:])
        XCTAssertEqual(first.inserts.count, 3)
        XCTAssertEqual(Set(first.inserts.map(\.key)).count, 3)

        let stored = Dictionary(uniqueKeysWithValues: first.inserts.map { ($0.key, false) })
        let second = ImportPlanner.plan(transactions: file, accountID: accountID, existing: stored)

        XCTAssertTrue(second.inserts.isEmpty)
        XCTAssertEqual(second.duplicates, 3)
    }

    func testIgnoresTransactionsAlreadyInTheDatabase() {
        let existing = transaction("PADARIA", -18.90, "15/01/2025")
        let key = DedupKey.make(accountID: accountID, transaction: existing)

        let plan = ImportPlanner.plan(
            transactions: [existing],
            accountID: accountID,
            existing: [key: false]
        )

        XCTAssertTrue(plan.inserts.isEmpty)
        XCTAssertEqual(plan.duplicates, 1)
    }

    func testConfirmsProjectedInstallmentInsteadOfDuplicating() {
        let real = ImportedTransaction(
            date: DateParser.parse("17/02/2025")!,
            description: "netshoes",
            amount: -199.90,
            installment: Installment(number: 4, total: 10)
        )
        let key = DedupKey.make(accountID: accountID, transaction: real)

        let plan = ImportPlanner.plan(
            transactions: [real],
            accountID: accountID,
            existing: [key: true]
        )

        XCTAssertTrue(plan.inserts.isEmpty)
        XCTAssertEqual(plan.duplicates, 0)
        XCTAssertEqual(plan.confirmations.count, 1)
        XCTAssertEqual(plan.confirmations.first?.key, key)
    }

    func testRealTransactionWinsOverProjectedOneInTheSameBatch() {
        let projected = ImportedTransaction(
            date: DateParser.parse("10/02/2025")!,
            description: "netshoes",
            amount: -199.90,
            installment: Installment(number: 4, total: 10),
            isProjected: true
        )
        let real = ImportedTransaction(
            date: DateParser.parse("17/02/2025")!,
            description: "netshoes",
            amount: -199.90,
            installment: Installment(number: 4, total: 10)
        )

        let plan = ImportPlanner.plan(
            transactions: [projected, real],
            accountID: accountID,
            existing: [:]
        )

        XCTAssertEqual(plan.inserts.count, 1)
        XCTAssertFalse(plan.inserts[0].transaction.isProjected, "A parcela real substitui a projetada")
        XCTAssertEqual(plan.duplicates, 0, "Substituição não conta como duplicata descartada")
    }

    func testCreditCardInvoiceProducesFutureInstallments() {
        let invoice = """
        Data;Descrição;Valor
        15/01/2025;NETSHOES PARC 03/10;-199,90
        15/01/2025;PADARIA CENTRAL;-18,90
        """

        let parsed = StatementParser.parse(content: invoice, filename: "fatura.csv")
        let expanded = InstallmentExpander.expand(parsed.transactions)
        let plan = ImportPlanner.plan(transactions: expanded, accountID: accountID, existing: [:])

        XCTAssertEqual(plan.inserts.count, 9, "8 parcelas (3/10 a 10/10) + padaria")
        XCTAssertEqual(plan.inserts.filter(\.transaction.isProjected).count, 7)
    }
}

final class ImportBatchTests: XCTestCase {

    func testBatchDTOCarriesConfirmationCount() {
        let accountID = UUID()
        let sut = ImportBatchModel(
            accountID: accountID,
            filename: "fatura.csv",
            confirmations: [
                ImportBatchModel.ConfirmationSnapshot(
                    transactionID: UUID(),
                    date: DateParser.parse("15/01/2025")!,
                    amount: -120,
                    externalID: "FIT-1"
                )
            ]
        )

        let dto = sut.toDTO(transactionCount: 7)

        XCTAssertEqual(dto.accountID, accountID)
        XCTAssertEqual(dto.filename, "fatura.csv")
        XCTAssertEqual(dto.transactionCount, 7)
        XCTAssertEqual(dto.confirmedCount, 1)
    }

    /// O estado anterior é o que permite devolver a parcela à condição de projeção.
    func testConfirmationSnapshotRoundTrip() throws {
        let snapshot = ImportBatchModel.ConfirmationSnapshot(
            transactionID: UUID(),
            date: DateParser.parse("10/02/2025")!,
            amount: -89.90,
            externalID: nil
        )

        let data = try JSONEncoder().encode([snapshot])
        let decoded = try JSONDecoder().decode([ImportBatchModel.ConfirmationSnapshot].self, from: data)

        XCTAssertEqual(decoded.first?.transactionID, snapshot.transactionID)
        XCTAssertEqual(decoded.first?.amount, snapshot.amount)
        XCTAssertNil(decoded.first?.externalID)
    }

    /// Lotes gravados antes de o snapshot registrar dono e estado confirmado
    /// continuam legíveis; desfazê-los só perde a verificação de conflito.
    func testConfirmationSnapshotDecodesLegacyPayload() throws {
        let id = UUID()
        let json = """
        [{"transactionID":"\(id.uuidString)","date":760000000,"amount":-50}]
        """

        let decoded = try JSONDecoder().decode(
            [ImportBatchModel.ConfirmationSnapshot].self,
            from: Data(json.utf8)
        )

        XCTAssertEqual(decoded.first?.transactionID, id)
        XCTAssertNil(decoded.first?.previousBatchID)
        XCTAssertNil(decoded.first?.confirmedAmount)
    }
}

final class TransactionEditKeyTests: XCTestCase {
    private let accountID = UUID()

    /// Chave canônica: derivada dos próprios campos, pode ser recalculada na edição.
    func testCanonicalKeyIsRecognized() {
        let date = DateParser.parse("15/01/2025")!
        let key = DedupKey.make(
            accountID: accountID,
            date: date,
            description: "PADARIA CENTRAL",
            amount: -18.90,
            installment: nil
        )

        XCTAssertEqual(
            key,
            DedupKey.make(
                accountID: accountID,
                date: date,
                description: "PADARIA CENTRAL",
                amount: -18.90,
                installment: nil
            )
        )
    }

    /// Chave de FITID e chave numerada por ocorrência não são reproduzíveis a
    /// partir dos campos: editar não pode recalculá-las.
    func testExternalAndSuffixedKeysDifferFromCanonical() {
        let date = DateParser.parse("15/01/2025")!
        let canonical = DedupKey.make(
            accountID: accountID,
            date: date,
            description: "PADARIA CENTRAL",
            amount: -18.90,
            installment: nil
        )

        let fromExternalID = DedupKey.make(
            accountID: accountID,
            date: date,
            description: "PADARIA CENTRAL",
            amount: -18.90,
            installment: nil,
            externalID: "FIT-7"
        )

        XCTAssertNotEqual(canonical, fromExternalID)
        XCTAssertNotEqual(canonical, "\(canonical)#2")
    }
}
