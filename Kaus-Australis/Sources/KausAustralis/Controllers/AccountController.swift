import Fluent
import Vapor
import KausMedia

struct AccountController: RouteCollection {
    func boot(routes: any RoutesBuilder) throws {
        let accounts = routes.grouped("api", "accounts")
        accounts.get(use: index)
        accounts.post(use: create)
        accounts.group(":accountID") { account in
            account.put(use: update)
            account.delete(use: delete)
        }
    }

    /// Lista as contas já com saldo e quantidade de lançamentos, agregados em SQL.
    func index(req: Request) async throws -> [AccountDTO] {
        let accounts = try await AccountModel.query(on: req.db).sort(\.$name).all()
        let transactions = try await TransactionModel.query(on: req.db).all()

        let grouped = Dictionary(grouping: transactions) { $0.$account.id }
        return accounts.map { account in
            let own = grouped[account.id] ?? []
            // Parcelas futuras são previsão: entram na projeção, não no saldo.
            return account.toDTO(
                transactionCount: own.count,
                balance: own.filter { !$0.isProjected }.reduce(0) { $0 + $1.amount }
            )
        }
    }

    func create(req: Request) async throws -> Response {
        let dto = try req.content.decode(AccountDTO.self)
        let name = dto.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else {
            throw Abort(.badRequest, reason: "O nome da conta é obrigatório")
        }

        if try await AccountModel.query(on: req.db).filter(\.$name == name).first() != nil {
            throw Abort(.conflict, reason: "Já existe uma conta com o nome \(name)")
        }

        let model = AccountModel(name: name, kind: dto.kind)
        try await model.create(on: req.db)
        return try await model.toDTO(transactionCount: 0, balance: 0).encodeResponse(status: .created, for: req)
    }

    func update(req: Request) async throws -> AccountDTO {
        let model = try await find(req)
        let dto = try req.content.decode(AccountDTO.self)
        let name = dto.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else {
            throw Abort(.badRequest, reason: "O nome da conta é obrigatório")
        }
        model.name = name
        model.kind = dto.kind.rawValue
        try await model.update(on: req.db)
        return model.toDTO()
    }

    /// Remover a conta remove os lançamentos dela (cascade no banco).
    /// A confirmação é responsabilidade do cliente.
    func delete(req: Request) async throws -> HTTPStatus {
        let model = try await find(req)
        try await model.delete(on: req.db)
        return .noContent
    }

    private func find(_ req: Request) async throws -> AccountModel {
        guard let id = req.parameters.get("accountID", as: UUID.self) else {
            throw Abort(.badRequest, reason: "Identificador de conta inválido")
        }
        guard let model = try await AccountModel.find(id, on: req.db) else {
            throw Abort(.notFound, reason: "Conta não encontrada")
        }
        return model
    }
}
