import Vapor
import Fluent
import FluentPostgresDriver
import NIOSSL
import KausMedia

// Os DTOs são Sendable nativamente; aqui só ganham a conformidade do Vapor.
extension TransactionDTO: @retroactive Content {}
extension AccountDTO: @retroactive Content {}
extension CategoryRule: @retroactive Content {}
extension ImportRequestDTO: @retroactive Content {}
extension ImportReportDTO: @retroactive Content {}
extension MonthlySummary: @retroactive Content {}
extension LedgerProjection: @retroactive Content {}

@main
struct App {
    static func main() async throws {
        var env = try Environment.detect()
        try LoggingSystem.bootstrap(from: &env)

        let app = try await Application.make(env)
        do {
            try await configure(app)
            try routes(app)
            try await app.execute()
        } catch {
            app.logger.report(error: error)
            try? await app.asyncShutdown()
            throw error
        }
        try await app.asyncShutdown()
    }
}

func configure(_ app: Application) async throws {
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

    // Faturas em CSV/OFX cabem folgadamente em 2 MB.
    app.routes.defaultMaxBodySize = "2mb"

    app.migrations.add(CreateTransactionMigration())
    app.migrations.add(CreateAccountMigration())
    app.migrations.add(CreateCategoryRuleMigration())
    app.migrations.add(AddTransactionImportFieldsMigration())
    app.migrations.add(SeedCategoryRulesMigration())
    try await app.autoMigrate()
}

func routes(_ app: Application) throws {
    try app.register(collection: AccountController())
    try app.register(collection: CategoryRuleController())
    try app.register(collection: TransactionController())
}
