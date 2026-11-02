import Fluent
import FluentPostgresDriver
import NIOSSL
import Vapor

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

    app.migrations.add(Migrations.all)
    try await app.autoMigrate()
}
