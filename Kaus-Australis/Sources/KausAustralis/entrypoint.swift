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
extension CategoryPreviewRequest: @retroactive Content {}
extension CategoryPreviewResponse: @retroactive Content {}
extension RecategorizeResponse: @retroactive Content {}
extension ImportBatchDTO: @retroactive Content {}
extension BulkDeleteRequest: @retroactive Content {}
extension BulkDeleteResponse: @retroactive Content {}
extension ResetRequest: @retroactive Content {}
extension ResetResponse: @retroactive Content {}
extension DeleteCategoryResponse: @retroactive Content {}

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

    // Datas em ISO-8601 nos dois sentidos: o padrão do Vapor é o intervalo desde
    // 2001 em ponto flutuante, que o cliente Swift não lê sem configuração extra.
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    ContentConfiguration.global.use(encoder: encoder, for: .json)
    ContentConfiguration.global.use(decoder: decoder, for: .json)

    // Os filtros de período chegam na query string; sem isto o Vapor esperaria
    // segundos desde 1970 nos parâmetros `from`/`to`.
    ContentConfiguration.global.use(
        urlDecoder: URLEncodedFormDecoder(configuration: .init(dateDecodingStrategy: .iso8601))
    )

    app.migrations.add(CreateTransactionMigration())
    app.migrations.add(CreateAccountMigration())
    app.migrations.add(CreateCategoryRuleMigration())
    app.migrations.add(CreateImportBatchMigration())
    app.migrations.add(AddTransactionImportFieldsMigration())
    app.migrations.add(SeedCategoryRulesMigration())
    try await app.autoMigrate()
}

func routes(_ app: Application) throws {
    let api: any RoutesBuilder
    switch (Environment.get("API_TOKEN"), app.environment) {
    case let (.some(token), _) where !token.isEmpty:
        api = app.grouped(APITokenMiddleware(token: token))
    case (_, .development), (_, .testing):
        app.logger.warning("API_TOKEN ausente: rotas expostas sem autenticação (apenas desenvolvimento)")
        api = app
    default:
        throw Abort(.internalServerError, reason: "API_TOKEN é obrigatório fora de desenvolvimento")
    }

    try api.register(collection: AccountController())
    try api.register(collection: CategoryRuleController())
    try api.register(collection: TransactionController())
    try api.register(collection: MaintenanceController())
}
