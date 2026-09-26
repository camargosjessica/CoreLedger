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

        let parsed = StatementParser.parse(content: request.content, filename: request.filename)
        let expand = request.expandInstallments ?? account.accountKind.expandsInstallments
        let transactions = expand ? InstallmentExpander.expand(parsed.transactions) : parsed.transactions

        let categorizer = try await CategoryRuleService(database: database).categorizer()
        let existing = try await existingKeys(
            for: transactions.map { DedupKey.make(accountID: accountID, transaction: $0) }
        )
        let plan = ImportPlanner.plan(transactions: transactions, accountID: accountID, existing: existing)

        for transaction in plan.inserts {
            let model = TransactionModel(
                imported: transaction,
                accountID: accountID,
                category: categorizer.category(for: transaction.description, amount: transaction.amount)
            )
            try await model.create(on: database)
        }

        for confirmation in plan.confirmations {
            guard let model = try await TransactionModel.query(on: database)
                .filter(\.$dedupKey == confirmation.key)
                .first()
            else { continue }

            model.isProjected = false
            model.date = confirmation.transaction.date
            model.amount = confirmation.transaction.amount
            model.externalID = confirmation.transaction.externalID ?? model.externalID
            try await model.update(on: database)
        }

        return ImportReportDTO(
            imported: plan.inserts.count,
            duplicates: plan.duplicates,
            projectedInstallments: plan.inserts.filter(\.isProjected).count,
            confirmedInstallments: plan.confirmations.count,
            failures: parsed.failures
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
