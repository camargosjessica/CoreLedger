import Vapor
import Fluent
import FluentPostgresDriver
import NIOSSL
import KausMedia

// O DTO agora já é Sendable nativamente, precisamos apenas do Content do Vapor
extension TransactionDTO: @retroactive Content {}

@main
struct App {
    static func main() async throws {
        var env = try Environment.detect()
        try LoggingSystem.bootstrap(from: &env)
        
        let app = try await Application.make(env)
        
        let hostname: String = Environment.get("DATABASE_HOST") ?? "localhost"
        let port: Int = Environment.get("DATABASE_PORT").flatMap(Int.init)
            ?? SQLPostgresConfiguration.ianaPortNumber
        let username: String = Environment.get("DATABASE_USERNAME") ?? "kaus_user"
        let password: String = Environment.get("DATABASE_PASSWORD") ?? "kaus_password"
        let databaseName: String = Environment.get("DATABASE_NAME") ?? "kaus_db"
        let requiresTLS: Bool = Environment.get("DATABASE_TLS").map { $0.lowercased() != "disable" } ?? false
        let tls: PostgresConnection.Configuration.TLS = requiresTLS
            ? .require(try NIOSSLContext(configuration: .makeClientConfiguration()))
            : .disable

        let postgresConfiguration = SQLPostgresConfiguration(
            hostname: hostname,
            port: port,
            username: username,
            password: password,
            database: databaseName,
            tls: tls
        )
        app.databases.use(.postgres(configuration: postgresConfiguration), as: .psql)
        
        app.migrations.add(CreateTransactionMigration())
        try await app.autoMigrate()
        
        // ROTA POST: Criação
        app.post("api", "transactions") { req async throws -> TransactionDTO in
            let dto = try req.content.decode(TransactionDTO.self)
            let model = TransactionModel(newFrom: dto)
            try await model.save(on: req.db)
            return model.toDTO()
        }

        // ROTA GET: Listagem
        app.get("api", "transactions") { req async throws -> [TransactionDTO] in
            let models = try await TransactionModel.query(on: req.db)
                .sort(\.$date, .descending)
                .all()
            return models.map { $0.toDTO() }
        }

        try await app.execute()
        try await app.asyncShutdown()
    }
}
