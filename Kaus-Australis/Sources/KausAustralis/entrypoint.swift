import Vapor
import Fluent
import FluentPostgresDriver
import KausMedia

// O DTO agora já é Sendable nativamente, precisamos apenas do Content do Vapor
extension TransactionDTO: @retroactive Content {}

@main
struct App {
    static func main() async throws {
        var env = try Environment.detect()
        try LoggingSystem.bootstrap(from: &env)
        
        let app = try await Application.make(env)
        
        app.databases.use(.postgres(
            configuration: .init(
                hostname: "localhost",
                username: "kaus_user",
                password: "kaus_password",
                database: "kaus_db",
                tls: .disable
            )
        ), as: .psql)
        
        app.migrations.add(CreateTransactionMigration())
        try await app.autoMigrate()
        
        // ROTA POST: Criação
        app.post("api", "transactions") { req async throws -> TransactionDTO in
            let dto = try req.content.decode(TransactionDTO.self)
            
            let model = TransactionModel(
                description: dto.description,
                amount: dto.amount,
                category: dto.category ?? "Geral", // Fallback caso o frontend não envie
                date: dto.date
            )
            
            try await model.save(on: req.db)
            
            return TransactionDTO(
                id: model.id,
                description: model.description,
                amount: model.amount,
                date: model.date,
                category: model.category
            )
        }

        // ROTA GET: Listagem
        app.get("api", "transactions") { req async throws -> [TransactionDTO] in
            let models = try await TransactionModel.query(on: req.db).all()
            
            return models.map { model in
                TransactionDTO(
                    id: model.id,
                    description: model.description,
                    amount: model.amount,
                    date: model.date,
                    category: model.category
                )
            }
        }

        try await app.execute()
        try await app.asyncShutdown()
    }
}
