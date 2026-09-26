import Fluent
import Vapor
import KausMedia

struct ImportService {
    let database: any Database

    /// Limite por consulta ao checar chaves existentes, para não estourar o
    /// número de parâmetros aceito pelo Postgres em um único `IN`.
    private let keyChunkSize = 500

    func run(_ request: ImportRequestDTO, account: AccountModel) async throws -> ImportReportDTO {
        guard let accountID = account.id else {
            throw Abort(.internalServerError, reason: "Conta sem identificador")
        }

        let parsed = StatementParser.parse(
            content: request.content,
            filename: request.filename,
            format: request.format
        )
        let expand = request.expandInstallments ?? account.accountKind.expandsInstallments
        let transactions = expand ? InstallmentExpander.expand(parsed.transactions) : parsed.transactions

        let categorizer = try await CategoryRuleService(database: database).categorizer()
        let existing = try await existingKeys(
            for: ImportPlanner.keys(for: transactions, accountID: accountID)
        )
        let plan = ImportPlanner.plan(transactions: transactions, accountID: accountID, existing: existing)

        let batch = ImportBatchModel(accountID: accountID, filename: request.filename)

        // Tudo ou nada: um extrato meio importado deixaria o usuário sem saber
        // o que reimportar, e a segunda tentativa processaria outro conjunto de linhas.
        try await database.transaction { db in
            try await batch.create(on: db)

            for insert in plan.inserts {
                let model = TransactionModel(
                    imported: insert.transaction,
                    accountID: accountID,
                    category: categorizer.category(
                        for: insert.transaction.description,
                        amount: insert.transaction.amount
                    ),
                    dedupKey: insert.key
                )
                model.$importBatch.id = batch.id
                try await model.create(on: db)
            }

            var snapshots: [ImportBatchModel.ConfirmationSnapshot] = []
            for confirmation in plan.confirmations {
                guard let model = try await TransactionModel.query(on: db)
                    .filter(\.$dedupKey == confirmation.key)
                    .first()
                else { continue }

                // Estado anterior guardado antes da escrita: é o que desfaz a
                // confirmação sem transformar a projeção num lançamento real.
                if let id = model.id {
                    snapshots.append(
                        ImportBatchModel.ConfirmationSnapshot(
                            transactionID: id,
                            date: model.date,
                            amount: model.amount,
                            externalID: model.externalID
                        )
                    )
                }

                model.isProjected = false
                model.date = confirmation.transaction.date
                model.amount = confirmation.transaction.amount
                model.externalID = confirmation.transaction.externalID ?? model.externalID
                try await model.update(on: db)
            }

            if !snapshots.isEmpty {
                batch.confirmations = snapshots
                try await batch.update(on: db)
            }
        }

        return ImportReportDTO(
            imported: plan.inserts.count,
            duplicates: plan.duplicates,
            projectedInstallments: plan.inserts.filter(\.transaction.isProjected).count,
            confirmedInstallments: plan.confirmations.count,
            failures: parsed.failures,
            batchID: batch.id
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
