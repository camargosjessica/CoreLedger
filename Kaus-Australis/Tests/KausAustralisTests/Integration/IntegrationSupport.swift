import Fluent
import FluentSQL
import Foundation
import KausMedia
import Testing
import Vapor
import VaporTesting
@testable import KausAustralis

/// Testes de integração: sobem o app inteiro (rotas, migrations, Postgres).
///
/// Rodam só com `KAUS_INTEGRATION_TESTS=1` e num banco próprio
/// (`DATABASE_TEST_NAME`, padrão `kaus_test`), que é esvaziado antes de cada
/// teste. O nome precisa conter "test", para nunca apagar o banco de uso.
enum Integration {
    static let isEnabled = ProcessInfo.processInfo.environment["KAUS_INTEGRATION_TESTS"] == "1"

    static var databaseName: String {
        ProcessInfo.processInfo.environment["DATABASE_TEST_NAME"] ?? "kaus_test"
    }

    private static let tables = [
        "transactions", "import_batches", "accounts", "category_rules",
        "recurring_commitments", "category_limits", "category_settings",
    ]

    /// App configurado contra o banco de teste, com as tabelas vazias.
    static func withApp(
        environment: [String: String?] = [:],
        clock: LedgerClock? = nil,
        _ test: (Application) async throws -> Void
    ) async throws {
        let name = databaseName
        guard name.contains("test") else {
            Issue.record("DATABASE_TEST_NAME precisa conter 'test' (recebido: \(name))")
            return
        }
        setenv("DATABASE_NAME", name, 1)
        for (key, value) in environment {
            if let value { setenv(key, value, 1) } else { unsetenv(key) }
        }
        defer {
            for key in environment.keys { unsetenv(key) }
        }

        try await VaporTesting.withApp(
            configure: { app in
                if let clock { app.ledgerClock = clock }
                try await configure(app)
                try await truncate(app.db)
                try routes(app)
            }, test)
    }

    private static func truncate(_ database: any Database) async throws {
        guard let sql = database as? any SQLDatabase else { return }
        let list = tables.map { "\"\($0)\"" }.joined(separator: ", ")
        try await sql.raw("TRUNCATE \(unsafeRaw: list) CASCADE").run()
    }
}

// MARK: - Atalhos de requisição

extension Application {
    func post<Body: Content>(_ path: String, _ body: Body) async throws -> TestingHTTPResponse {
        try await testing().sendRequest(.POST, path) { try $0.content.encode(body) }
    }

    func put<Body: Content>(_ path: String, _ body: Body) async throws -> TestingHTTPResponse {
        try await testing().sendRequest(.PUT, path) { try $0.content.encode(body) }
    }

    func get(_ path: String) async throws -> TestingHTTPResponse {
        try await testing().sendRequest(.GET, path)
    }

    func delete(_ path: String) async throws -> TestingHTTPResponse {
        try await testing().sendRequest(.DELETE, path)
    }

    func createAccount(_ name: String, kind: AccountKind) async throws -> UUID {
        let response = try await post("api/accounts", AccountDTO(name: name, kind: kind))
        return try #require(try response.content.decode(AccountDTO.self).id)
    }

    @discardableResult
    func createTransaction(
        _ description: String,
        _ amount: Money,
        on date: String,
        account: UUID?,
        projected: Bool = false
    ) async throws -> TransactionDTO {
        let dto = TransactionDTO(
            description: description,
            amount: amount,
            date: try #require(DateParser.parse(date)),
            accountID: account,
            isProjected: projected
        )
        return try await post("api/transactions", dto).content.decode(TransactionDTO.self)
    }
}
