import Fluent
import Vapor
import KausMedia

struct TransactionController: RouteCollection {
    func boot(routes: any RoutesBuilder) throws {
        let transactions = routes.grouped("api", "transactions")
        transactions.get(use: index)
        transactions.post(use: create)
        transactions.put(":transactionID", use: update)
        transactions.put(":transactionID", "transfer", use: setTransfer)
        transactions.delete(":transactionID", use: delete)
        transactions.delete(use: deleteBatch)
        transactions.patch(use: updateBatch)

        routes.post("api", "imports", use: importStatement)
        routes.get("api", "imports", use: batches)
        routes.delete("api", "imports", ":batchID", use: undoImport)
        routes.get("api", "summary", use: summary)
    }

    func index(req: Request) async throws -> [TransactionDTO] {
        let query = try req.query.decode(TransactionQuery.self)
        let repository = req.unitOfWork.transactions
        let models = try await repository.list(query.filter)
        return try await repository.dtos(for: models)
    }

    func setTransfer(req: Request) async throws -> TransactionDTO {
        let request = try req.content.decode(TransferLinkRequest.self)
        return try await LinkTransfer(unitOfWork: req.unitOfWork)(
            id: try req.parameters.uuid("transactionID"),
            to: request.accountID
        )
    }

    func create(req: Request) async throws -> Response {
        let dto = try req.content.decode(TransactionDTO.self)
        let result = try await CreateTransaction(unitOfWork: req.unitOfWork)(dto)
        return try await result.transaction.encodeResponse(status: result.wasCreated ? .created : .ok, for: req)
    }

    func update(req: Request) async throws -> TransactionDTO {
        let id = try req.parameters.uuid("transactionID")
        let dto = try req.content.decode(TransactionDTO.self)
        return try await UpdateTransaction(unitOfWork: req.unitOfWork)(id: id, with: dto)
    }

    func delete(req: Request) async throws -> HTTPStatus {
        try await DeleteTransaction(unitOfWork: req.unitOfWork)(
            id: try req.parameters.uuid("transactionID")
        )
        return .noContent
    }

    func deleteBatch(req: Request) async throws -> BulkDeleteResponse {
        try await DeleteTransactions(unitOfWork: req.unitOfWork)(req.content.decode(BulkDeleteRequest.self))
    }

    func updateBatch(req: Request) async throws -> BulkUpdateResponse {
        try await UpdateTransactions(unitOfWork: req.unitOfWork)(req.content.decode(BulkUpdateRequest.self))
    }

    func batches(req: Request) async throws -> [ImportBatchDTO] {
        let query = try req.query.decode(TransactionQuery.self)
        var builder = ImportBatchModel.query(on: req.db).sort(\.$createdAt, .descending)
        if let accountID = query.accountID {
            builder = builder.filter(\.$account.$id == accountID)
        }
        let batches = try await builder.limit(50).all()
        let counts = try await req.transactionTotals.countByBatch(batches.compactMap(\.id))
        return batches.map { batch in
            batch.toDTO(transactionCount: batch.id.flatMap { counts[$0] } ?? 0)
        }
    }

    func undoImport(req: Request) async throws -> BulkDeleteResponse {
        try await UndoImport(unitOfWork: req.unitOfWork)(
            batchID: try req.parameters.uuid("batchID")
        )
    }

    /// Importa um extrato ou fatura. A fatura de cartão com mês substitui a anterior do mesmo mês.
    func importStatement(req: Request) async throws -> ImportReportDTO {
        let request = try req.content.decode(ImportRequestDTO.self)
        let account = try await AccountModel.find(request.accountID, on: req.db, or: .accountNotFound)
        guard !request.content.isEmpty else { throw LedgerError.emptyFile }
        return try await ImportService(database: req.db).run(request, account: account)
    }

    /// Resumo mensal + projeção dos próximos meses.
    func summary(req: Request) async throws -> LedgerProjection {
        let query = try req.query.decode(SummaryQuery.self)

        // Somando todas as contas, a contrapartida anularia a origem.
        let inputs = try await req.transactionTotals.monthlyInputs(
            accountID: query.accountID,
            excludingCounterparts: query.accountID == nil
        )

        let transferCategories = try await req.categoryRules.categorizer().transferCategories
        return Projection.project(
            inputs,
            transferCategories: query.includeTransfers == true ? [] : transferCategories,
            forecastMonths: min(max(query.forecastMonths ?? 6, 0), 24),
            reference: req.ledgerClock.now()
        )
    }
}

struct TransactionQuery: Content {
    var accountID: UUID?
    var from: Date?
    var to: Date?
    var search: String?
    var includeProjected: Bool?
    var category: String?
    var tag: String?
    var limit: Int?
    var offset: Int?
}

extension TransactionQuery {
    var filter: TransactionFilter {
        TransactionFilter(
            accountID: accountID,
            from: from,
            to: to,
            search: search,
            includeProjected: includeProjected ?? true,
            category: category,
            tag: tag,
            limit: min(max(limit ?? 500, 1), 1000),
            offset: max(offset ?? 0, 0)
        )
    }
}

struct SummaryQuery: Content {
    var accountID: UUID?
    var forecastMonths: Int?
    var includeTransfers: Bool?
}
