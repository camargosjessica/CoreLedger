import XCTest
import KausMedia
@testable import KausAustralis

final class TransactionUseCaseTests: XCTestCase {
    private var work: InMemoryUnitOfWork!
    private let checking = UUID()
    private let savings = UUID()
    private let day = DateParser.parse("15/01/2025")!

    override func setUp() {
        work = InMemoryUnitOfWork()
        work.accountIDs = [checking, savings]
        work.rules = [CategoryRule(term: "padaria", category: "Alimentação", matchKind: .contains)]
    }

    private func seed(
        _ description: String = "PADARIA CENTRAL",
        amount: Money = -18.90,
        account: UUID? = nil,
        dedupKey: String? = nil
    ) async throws -> TransactionModel {
        let accountID = account ?? checking
        let model = TransactionModel(
            description: description,
            amount: amount,
            category: "Alimentação",
            date: day,
            accountID: accountID,
            dedupKey: dedupKey ?? DedupKey.make(accountID: accountID, date: day, description: description, amount: amount)
        )
        try await work.store.create(model)
        return model
    }

    // MARK: Criar

    func testCreate_IsIdempotentByDedupKey() async throws {
        let dto = TransactionDTO(description: "Padaria", amount: -10, date: day, accountID: checking)
        let create = CreateTransaction(unitOfWork: work)

        let first = try await create(dto)
        let second = try await create(dto)

        XCTAssertTrue(first.wasCreated)
        XCTAssertFalse(second.wasCreated)
        XCTAssertEqual(first.transaction.id, second.transaction.id)
        XCTAssertEqual(work.store.all.count, 1)
        XCTAssertEqual(first.transaction.category, "Alimentação")
    }

    func testCreate_RejectsBlankDescriptionAndUnknownAccount() async {
        let create = CreateTransaction(unitOfWork: work)
        await XCTAssertThrowsLedgerError(.descriptionRequired) {
            _ = try await create(TransactionDTO(description: "  ", amount: -1, date: self.day))
        }
        await XCTAssertThrowsLedgerError(.accountNotFound) {
            _ = try await create(TransactionDTO(description: "x", amount: -1, date: self.day, accountID: UUID()))
        }
    }

    // MARK: Editar

    func testUpdate_RecomputesCanonicalKeyButKeepsFileKeys() async throws {
        let canonical = try await seed()
        let fromFile = try await seed("MERCADO", dedupKey: "v1|fitid|abc")
        let update = UpdateTransaction(unitOfWork: work)

        var edited = canonical.toDTO()
        edited.amount = -20
        _ = try await update(id: canonical.id!, with: edited)
        XCTAssertEqual(
            canonical.dedupKey,
            DedupKey.make(accountID: checking, date: day, description: "PADARIA CENTRAL", amount: -20)
        )

        var editedFile = fromFile.toDTO()
        editedFile.amount = -99
        _ = try await update(id: fromFile.id!, with: editedFile)
        XCTAssertEqual(fromFile.dedupKey, "v1|fitid|abc")
    }

    func testUpdate_BlankCategoryFallsBackToRules() async throws {
        let model = try await seed()
        var dto = model.toDTO()
        dto.category = " "
        dto.description = "Padaria nova"

        let result = try await UpdateTransaction(unitOfWork: work)(id: model.id!, with: dto)

        XCTAssertEqual(result.category, "Alimentação")
    }

    func testUpdate_MirrorsCounterpartAndRejectsEditingIt() async throws {
        let origin = try await seed(amount: -250)
        _ = try await LinkTransfer(unitOfWork: work)(id: origin.id!, to: savings)
        let counterpart = try await work.store.counterpart(of: origin.id!)!

        var dto = origin.toDTO()
        dto.amount = -300
        let result = try await UpdateTransaction(unitOfWork: work)(id: origin.id!, with: dto)

        XCTAssertEqual(counterpart.amount, 300)
        XCTAssertEqual(result.transferAccountID, savings)
        await XCTAssertThrowsLedgerError(.counterpartIsReadOnly) {
            _ = try await UpdateTransaction(unitOfWork: self.work)(id: counterpart.id!, with: counterpart.toDTO())
        }
    }

    func testUpdate_RejectsMovingOriginIntoCounterpartAccount() async throws {
        let origin = try await seed(amount: -250)
        _ = try await LinkTransfer(unitOfWork: work)(id: origin.id!, to: savings)

        var dto = origin.toDTO()
        dto.accountID = savings
        await XCTAssertThrowsLedgerError(.transferAlreadyTargetsAccount) {
            _ = try await UpdateTransaction(unitOfWork: self.work)(id: origin.id!, with: dto)
        }
    }

    // MARK: Transferência

    func testLinkTransfer_CreatesMovesAndRemovesCounterpart() async throws {
        let origin = try await seed(amount: -100)
        let link = LinkTransfer(unitOfWork: work)
        let third = UUID()
        work.accountIDs.insert(third)

        let linked = try await link(id: origin.id!, to: savings)
        XCTAssertEqual(linked.transferAccountID, savings)
        let counterpartAmount = try await work.store.counterpart(of: origin.id!)?.amount
        XCTAssertEqual(counterpartAmount, 100)

        let moved = try await link(id: origin.id!, to: third)
        XCTAssertEqual(moved.transferAccountID, third)
        XCTAssertEqual(work.store.all.count, 2)

        let unlinked = try await link(id: origin.id!, to: nil)
        XCTAssertNil(unlinked.transferAccountID)
        XCTAssertEqual(work.store.all.count, 1)
    }

    func testLinkTransfer_RejectsSameAccount() async throws {
        let origin = try await seed()
        await XCTAssertThrowsLedgerError(.transferToSameAccount) {
            _ = try await LinkTransfer(unitOfWork: self.work)(id: origin.id!, to: self.checking)
        }
    }

    // MARK: Lote

    func testBulkUpdate_SkipsCounterpartsAndSyncsThem() async throws {
        let origin = try await seed(amount: -50)
        _ = try await LinkTransfer(unitOfWork: work)(id: origin.id!, to: savings)
        let counterpart = try await work.store.counterpart(of: origin.id!)!

        let response = try await UpdateTransactions(unitOfWork: work)(
            BulkUpdateRequest(ids: [origin.id!, counterpart.id!], category: "Guardado")
        )

        XCTAssertEqual(response.updated, 1)
        XCTAssertEqual(counterpart.category, "Guardado")
    }

    func testBulkDelete_EnforcesLimit() async {
        let ids = (0...TransactionValidation.maxBatchSize).map { _ in UUID() }
        await XCTAssertThrowsLedgerError(.tooManyItems(limit: TransactionValidation.maxBatchSize)) {
            _ = try await DeleteTransactions(unitOfWork: self.work)(BulkDeleteRequest(ids: ids))
        }
    }

    // MARK: Desfazer importação

    func testUndoImport_DeletesCreatedAndRestoresUntouchedConfirmations() async throws {
        let batchID = UUID()
        let created = try await seed("COMPRA NOVA")
        created.$importBatch.id = batchID

        let confirmedDate = DateParser.parse("12/02/2025")!
        let untouched = try await seed("LOJA 2/3", amount: -101)
        untouched.$importBatch.id = batchID
        untouched.date = confirmedDate
        let edited = try await seed("LOJA 3/3", amount: -999)
        edited.$importBatch.id = batchID

        let projectedDate = DateParser.parse("10/02/2025")!
        work.batches[batchID] = ImportBatchModel(
            id: batchID,
            accountID: checking,
            filename: "fatura.csv",
            confirmations: [
                .init(transactionID: untouched.id!, date: projectedDate, amount: -100,
                      confirmedDate: confirmedDate, confirmedAmount: -101),
                .init(transactionID: edited.id!, date: projectedDate, amount: -100,
                      confirmedDate: confirmedDate, confirmedAmount: -100),
            ]
        )

        let response = try await UndoImport(unitOfWork: work)(batchID: batchID)

        XCTAssertEqual(response.deleted, 1)
        XCTAssertEqual(response.restored, 1)
        let deleted = try await work.store.find(created.id!)
        XCTAssertNil(deleted)
        XCTAssertTrue(untouched.isProjected)
        XCTAssertEqual(untouched.amount, -100)
        XCTAssertEqual(untouched.date, projectedDate)
        XCTAssertNil(untouched.$importBatch.id)
        XCTAssertFalse(edited.isProjected, "Editado depois da confirmação: a correção do usuário prevalece")
        XCTAssertNil(work.batches[batchID])
    }
}

func XCTAssertThrowsLedgerError(
    _ expected: LedgerError,
    file: StaticString = #filePath,
    line: UInt = #line,
    _ body: () async throws -> Void
) async {
    do {
        try await body()
        XCTFail("Esperava \(expected), mas nada foi lançado", file: file, line: line)
    } catch let error as LedgerError {
        XCTAssertEqual(error, expected, file: file, line: line)
    } catch {
        XCTFail("Esperava \(expected), veio \(error)", file: file, line: line)
    }
}
