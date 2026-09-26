import Fluent
import Vapor
import KausMedia

/// Limpeza da base. Existe para recomeçar depois de uma importação errada sem
/// precisar mexer no Postgres à mão.
struct MaintenanceController: RouteCollection {
    func boot(routes: any RoutesBuilder) throws {
        routes.post("api", "reset", use: reset)
    }

    func reset(req: Request) async throws -> ResetResponse {
        let request = try req.content.decode(ResetRequest.self)
        guard request.confirmation == ResetRequest.confirmationPhrase else {
            throw Abort(.badRequest, reason: "Confirmação inválida: envie \"\(ResetRequest.confirmationPhrase)\"")
        }

        return try await req.db.transaction { db in
            var response = ResetResponse()

            let transactions = try await TransactionModel.query(on: db).all()
            for model in transactions {
                try await model.delete(on: db)
            }
            response.transactions = transactions.count

            let batches = try await ImportBatchModel.query(on: db).all()
            for model in batches {
                try await model.delete(on: db)
            }
            response.batches = batches.count

            if request.scope == .accounts || request.scope == .everything {
                let accounts = try await AccountModel.query(on: db).all()
                for model in accounts {
                    try await model.delete(on: db)
                }
                response.accounts = accounts.count
            }

            if request.scope == .everything {
                let rules = try await CategoryRuleModel.query(on: db).all()
                for model in rules {
                    try await model.delete(on: db)
                }
                response.rules = rules.count
            }

            return response
        }
    }
}
