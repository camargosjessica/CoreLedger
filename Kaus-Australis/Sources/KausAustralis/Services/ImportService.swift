import Fluent
import Vapor
import KausMedia

struct ImportService {
    let database: any Database

    /// Limite por consulta ao checar chaves existentes, para não estourar o
    /// número de parâmetros aceito pelo Postgres em um único `IN`.
    private let keyChunkSize = 500

    /// Lançamentos anteriores consultados para sugerir tags e comentário.
    private let historyLimit = 3000

    func run(_ request: ImportRequestDTO, account: AccountModel) async throws -> ImportReportDTO {
        guard let accountID = account.id else {
            throw Abort(.internalServerError, reason: "Conta sem identificador")
        }

        let parsed = StatementParser.parse(
            content: request.content,
            filename: request.filename,
            format: request.format
        )
        let lines = account.accountKind == .creditCard
            ? CardStatement.normalizeSigns(parsed.transactions)
            : parsed.transactions
        let transactions = InstallmentExpander.label(lines, datedByPurchase: parsed.installmentsDatedByPurchase)

        // Só a fatura de cartão tem mês: reenviá-la troca a importação anterior
        // do mesmo mês, em vez de somar as linhas que mudaram.
        let statementMonth = account.accountKind == .creditCard ? request.statementMonth : nil
        var replacedBatches: [ImportBatchModel] = []
        if let statementMonth {
            replacedBatches = try await ImportBatchModel.query(on: database)
                .filter(\.$account.$id == accountID)
                .filter(\.$statementMonth == statementMonth.description)
                .all()
        }
        let replacedBatchIDs = replacedBatches.compactMap { $0.id }
        var replaced: [TransactionModel] = []
        if !replacedBatchIDs.isEmpty {
            replaced = try await TransactionModel.query(on: database)
                .filter(\.$importBatch.$id ~~ replacedBatchIDs)
                .filter(\.$transferSource.$id == nil)
                .all()
        }
        let replacedIDs = Set(replaced.compactMap { $0.id })
        let replacedKeys = Set(replaced.compactMap { $0.dedupKey })

        let history = replaced.map(Self.labeled) + (try await recentHistory(accountID: accountID))
            .filter { model in model.id.map { !replacedIDs.contains($0) } ?? true }
            .map(Self.labeled)

        let categorizer = try await CategoryRuleService(database: database).categorizer()
        let keys = ImportPlanner.keys(for: transactions, accountID: accountID)
        let existing = try await existingKeys(for: keys).filter { !replacedKeys.contains($0.key) }
        let plan = ImportPlanner.plan(
            transactions: transactions,
            accountID: accountID,
            existing: existing,
            keys: keys
        )

        let batch = ImportBatchModel(accountID: accountID, filename: request.filename, statementMonth: statementMonth)
        var suggested = 0

        // Tudo ou nada: um extrato meio importado deixaria o usuário sem saber
        // o que reimportar, e a segunda tentativa processaria outro conjunto de linhas.
        try await database.transaction { db in
            for model in replaced {
                try await model.delete(on: db)
            }
            for old in replacedBatches {
                try await TransactionModel.query(on: db)
                    .filter(\.$importBatch.$id == old.id)
                    .set(\.$importBatch.$id, to: nil)
                    .update()
                try await old.delete(on: db)
            }

            try await batch.create(on: db)

            for insert in plan.inserts {
                let line = insert.transaction
                let suggestion = LabelSuggester.suggestion(for: line, in: history)
                let category = suggestion?.category
                    ?? categorizer.category(for: line.description, amount: line.amount)
                let ruleTags = categorizer.tags(for: line.description, amount: line.amount)
                let model = TransactionModel(
                    imported: line,
                    accountID: accountID,
                    category: category,
                    dedupKey: insert.key,
                    tags: suggestion.map { TagSet.normalize($0.tags + ($0.category == nil ? ruleTags : [])) } ?? ruleTags
                )
                model.note = suggestion?.note
                if suggestion != nil { suggested += 1 }
                model.$importBatch.id = batch.id
                try await model.create(on: db)
            }

            // Parcelas previstas por importações antigas viram lançamento desta fatura.
            for confirmation in plan.confirmations {
                guard let model = try await TransactionModel.query(on: db)
                    .filter(\.$dedupKey == confirmation.key)
                    .first()
                else { continue }
                model.isProjected = false
                model.date = confirmation.transaction.date
                model.amount = confirmation.transaction.amount
                model.externalID = confirmation.transaction.externalID ?? model.externalID
                model.$importBatch.id = batch.id
                try await model.update(on: db)
                try await model.syncCounterpart(on: db)
            }
        }

        return ImportReportDTO(
            imported: plan.inserts.count + plan.confirmations.count,
            duplicates: plan.duplicates,
            replaced: replaced.count,
            suggested: suggested,
            failures: parsed.failures,
            batchID: batch.id
        )
    }

    /// Lançamentos mais recentes da conta, sem contrapartidas de transferência.
    private func recentHistory(accountID: UUID) async throws -> [TransactionModel] {
        try await TransactionModel.query(on: database)
            .filter(\.$account.$id == accountID)
            .filter(\.$transferSource.$id == nil)
            .sort(\.$date, .descending)
            .limit(historyLimit)
            .all()
    }

    private static func labeled(_ model: TransactionModel) -> LabeledTransaction {
        LabeledTransaction(
            description: model.description,
            installment: model.installment,
            category: model.category,
            tags: model.tags,
            note: model.note
        )
    }

    private func existingKeys(for keys: [String]) async throws -> [String: Bool] {
        var result: [String: Bool] = [:]
        for chunk in stride(from: 0, to: keys.count, by: keyChunkSize).map({ offset in
            Array(keys[offset..<min(offset + keyChunkSize, keys.count)])
        }) {
            let models = try await TransactionModel.query(on: database)
                .filter(\.$dedupKey ~~ chunk)
                .all()
            for model in models {
                guard let key = model.dedupKey else { continue }
                result[key] = model.isProjected
            }
        }
        return result
    }
}
