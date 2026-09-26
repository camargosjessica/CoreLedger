import Fluent
import Vapor
import KausMedia

struct TransactionController: RouteCollection {
    func boot(routes: any RoutesBuilder) throws {
        let transactions = routes.grouped("api", "transactions")
        transactions.get(use: index)
        transactions.post(use: create)
        transactions.put(":transactionID", use: update)
        transactions.delete(":transactionID", use: delete)
        transactions.delete(use: deleteBatch)

        routes.post("api", "imports", use: importStatement)
        routes.get("api", "imports", use: batches)
        routes.delete("api", "imports", ":batchID", use: undoImport)
        routes.get("api", "summary", use: summary)
    }

    func index(req: Request) async throws -> [TransactionDTO] {
        let query = try req.query.decode(TransactionQuery.self)

        var builder = TransactionModel.query(on: req.db).sort(\.$date, .descending)
        if let accountID = query.accountID {
            builder = builder.filter(\.$account.$id == accountID)
        }
        if let from = query.from {
            builder = builder.filter(\.$date >= LedgerCalendar.startOfDay(from))
        }
        if let to = query.to {
            // O filtro é por dia: `to` na meia-noite ainda inclui o dia inteiro.
            builder = builder.filter(\.$date < LedgerCalendar.addingDays(1, to: LedgerCalendar.startOfDay(to)))
        }
        if query.includeProjected == false {
            builder = builder.filter(\.$isProjected == false)
        }
        if let search = query.search?.trimmingCharacters(in: .whitespacesAndNewlines), !search.isEmpty {
            builder = builder.group(.or) { group in
                group.filter(\.$description ~~ search).filter(\.$category ~~ search)
            }
        }

        let limit = min(max(query.limit ?? 500, 1), 1000)
        return try await builder
            .range(lower: query.offset ?? 0, upper: (query.offset ?? 0) + limit - 1)
            .all()
            .map { $0.toDTO() }
    }

    /// Criação manual. Idempotente: reenviar o mesmo lançamento devolve o existente
    /// em vez de duplicar.
    func create(req: Request) async throws -> Response {
        let dto = try req.content.decode(TransactionDTO.self)
        guard !dto.description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw Abort(.badRequest, reason: "A descrição é obrigatória")
        }
        if let accountID = dto.accountID, try await AccountModel.find(accountID, on: req.db) == nil {
            throw Abort(.notFound, reason: "Conta não encontrada")
        }

        let model = TransactionModel(newFrom: dto, categorizer: try await req.categoryRules.categorizer())

        if let key = model.dedupKey,
           let existing = try await TransactionModel.query(on: req.db).filter(\.$dedupKey == key).first() {
            return try await existing.toDTO().encodeResponse(status: .ok, for: req)
        }

        try await model.create(on: req.db)
        return try await model.toDTO().encodeResponse(status: .created, for: req)
    }

    /// Edição manual. A chave de dedup só é recalculada quando era derivada dos
    /// próprios campos editados: chaves de FITID ou numeradas por ocorrência
    /// identificam a linha do arquivo, não o conteúdo, e recalculá-las duplicaria
    /// a próxima importação ou colidiria com a ocorrência anterior.
    func update(req: Request) async throws -> TransactionDTO {
        guard let id = req.parameters.get("transactionID", as: UUID.self) else {
            throw Abort(.badRequest, reason: "Identificador inválido")
        }
        guard let model = try await TransactionModel.find(id, on: req.db) else {
            throw Abort(.notFound, reason: "Lançamento não encontrado")
        }
        let dto = try req.content.decode(TransactionDTO.self)
        guard !dto.description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw Abort(.badRequest, reason: "A descrição é obrigatória")
        }
        if let accountID = dto.accountID, try await AccountModel.find(accountID, on: req.db) == nil {
            throw Abort(.notFound, reason: "Conta não encontrada")
        }

        let date = LedgerCalendar.startOfDay(dto.date)
        let category = dto.category?.trimmingCharacters(in: .whitespacesAndNewlines)

        let previousCanonicalKey = DedupKey.make(
            accountID: model.$account.id,
            date: model.date,
            description: model.description,
            amount: model.amount,
            installment: model.installmentNumber.flatMap { number in
                model.installmentTotal.map { Installment(number: number, total: $0) }
            }
        )
        let keyWasCanonical = model.dedupKey == previousCanonicalKey

        model.description = dto.description
        model.amount = dto.amount
        model.date = date
        model.$account.id = dto.accountID
        model.isProjected = dto.isProjected
        model.installmentNumber = dto.installment?.number
        model.installmentTotal = dto.installment?.total
        if let category, !category.isEmpty {
            model.category = category
        } else {
            model.category = try await req.categoryRules.categorizer()
                .category(for: dto.description, amount: dto.amount)
        }
        if keyWasCanonical {
            model.dedupKey = DedupKey.make(
                accountID: dto.accountID,
                date: date,
                description: dto.description,
                amount: dto.amount,
                installment: dto.installment
            )
        }

        do {
            try await model.update(on: req.db)
        } catch let error as any DatabaseError where error.isConstraintFailure {
            throw Abort(.conflict, reason: "Já existe um lançamento igual nessa data e conta")
        }
        return model.toDTO()
    }

    func delete(req: Request) async throws -> HTTPStatus {
        guard let id = req.parameters.get("transactionID", as: UUID.self) else {
            throw Abort(.badRequest, reason: "Identificador inválido")
        }
        guard let model = try await TransactionModel.find(id, on: req.db) else {
            throw Abort(.notFound, reason: "Lançamento não encontrado")
        }
        try await model.delete(on: req.db)
        return .noContent
    }

    /// Remoção em lote a partir da seleção na lista.
    func deleteBatch(req: Request) async throws -> BulkDeleteResponse {
        let request = try req.content.decode(BulkDeleteRequest.self)
        guard !request.ids.isEmpty else { return BulkDeleteResponse(deleted: 0) }
        guard request.ids.count <= 1000 else {
            throw Abort(.badRequest, reason: "No máximo 1000 lançamentos por vez")
        }

        let deleted = try await req.db.transaction { db -> Int in
            let models = try await TransactionModel.query(on: db)
                .filter(\.$id ~~ request.ids)
                .all()
            for model in models {
                try await model.delete(on: db)
            }
            return models.count
        }
        return BulkDeleteResponse(deleted: deleted)
    }

    func batches(req: Request) async throws -> [ImportBatchDTO] {
        let query = try req.query.decode(TransactionQuery.self)
        var builder = ImportBatchModel.query(on: req.db).sort(\.$createdAt, .descending)
        if let accountID = query.accountID {
            builder = builder.filter(\.$account.$id == accountID)
        }
        let batches = try await builder.limit(50).all()

        var result: [ImportBatchDTO] = []
        for batch in batches {
            guard let id = batch.id else { continue }
            let count = try await TransactionModel.query(on: req.db)
                .filter(\.$importBatch.$id == id)
                .count()
            result.append(batch.toDTO(transactionCount: count))
        }
        return result
    }

    /// Desfaz uma importação: apaga o que ela criou e devolve as projeções que
    /// ela confirmou ao estado anterior.
    func undoImport(req: Request) async throws -> BulkDeleteResponse {
        guard let id = req.parameters.get("batchID", as: UUID.self) else {
            throw Abort(.badRequest, reason: "Identificador inválido")
        }
        guard let batch = try await ImportBatchModel.find(id, on: req.db) else {
            throw Abort(.notFound, reason: "Importação não encontrada")
        }

        return try await req.db.transaction { db -> BulkDeleteResponse in
            // As projeções confirmadas também pertencem ao lote, mas não foram
            // criadas por ele: são revertidas, não apagadas.
            let confirmed = Set(batch.confirmations.map(\.transactionID))
            let created = try await TransactionModel.query(on: db)
                .filter(\.$importBatch.$id == id)
                .all()
                .filter { model in model.id.map { !confirmed.contains($0) } ?? true }
            for model in created {
                try await model.delete(on: db)
            }

            var restored = 0
            for snapshot in batch.confirmations {
                guard let model = try await TransactionModel.find(snapshot.transactionID, on: db) else { continue }
                // Editado depois da confirmação: a correção do usuário vale mais
                // do que o estado que esta importação deixou.
                if let confirmedDate = snapshot.confirmedDate, let confirmedAmount = snapshot.confirmedAmount {
                    guard model.date == confirmedDate, model.amount == confirmedAmount, !model.isProjected else { continue }
                }
                model.isProjected = true
                model.date = snapshot.date
                model.amount = snapshot.amount
                model.externalID = snapshot.externalID
                // O lote que projetou a parcela pode já ter sido desfeito: nesse
                // caso a projeção fica órfã em vez de apontar para um lote morto.
                if let previousBatchID = snapshot.previousBatchID {
                    model.$importBatch.id = try await ImportBatchModel.find(previousBatchID, on: db)?.id
                } else {
                    model.$importBatch.id = nil
                }
                try await model.update(on: db)
                restored += 1
            }

            try await batch.delete(on: db)
            return BulkDeleteResponse(deleted: created.count, restored: restored)
        }
    }

    /// Importa um extrato ou fatura. Faturas de cartão geram também as parcelas futuras.
    func importStatement(req: Request) async throws -> ImportReportDTO {
        let request = try req.content.decode(ImportRequestDTO.self)
        guard let account = try await AccountModel.find(request.accountID, on: req.db) else {
            throw Abort(.notFound, reason: "Conta não encontrada")
        }
        guard !request.content.isEmpty else {
            throw Abort(.badRequest, reason: "Arquivo vazio")
        }
        return try await ImportService(database: req.db).run(request, account: account)
    }

    /// Resumo mensal + projeção dos próximos meses.
    func summary(req: Request) async throws -> LedgerProjection {
        let query = try req.query.decode(SummaryQuery.self)

        var builder = TransactionModel.query(on: req.db)
        if let accountID = query.accountID {
            builder = builder.filter(\.$account.$id == accountID)
        }
        let transactions = try await builder.all()

        let transferCategories = try await req.categoryRules.categorizer().transferCategories
        return Projection.project(
            transactions.map {
                Projection.Input(
                    date: $0.date,
                    amount: $0.amount,
                    category: $0.category,
                    isProjected: $0.isProjected
                )
            },
            transferCategories: query.includeTransfers == true ? [] : transferCategories,
            forecastMonths: min(max(query.forecastMonths ?? 6, 0), 24),
            baseMonths: min(max(query.baseMonths ?? 6, 1), 24)
        )
    }
}

struct TransactionQuery: Content {
    var accountID: UUID?
    var from: Date?
    var to: Date?
    var search: String?
    var includeProjected: Bool?
    var limit: Int?
    var offset: Int?
}

struct SummaryQuery: Content {
    var accountID: UUID?
    var forecastMonths: Int?
    var baseMonths: Int?
    var includeTransfers: Bool?
}
