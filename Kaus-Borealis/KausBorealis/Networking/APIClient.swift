import Foundation
import KausMedia

/// Endereço e credencial do backend. Ajustáveis na aba Ajustes para quando o
/// Vapor roda noutra porta ou noutra máquina da rede local.
struct APIConfiguration: Equatable, Sendable {
    var baseURL: URL
    var token: String?

    static let defaultBaseURL = URL(string: "http://127.0.0.1:8080")!

    private enum Keys {
        static let baseURL = "api.baseURL"
        static let token = "api.token"
    }

    static func load(from defaults: UserDefaults = .standard) -> APIConfiguration {
        APIConfiguration(
            baseURL: defaults.string(forKey: Keys.baseURL).flatMap(URL.init(string:)) ?? defaultBaseURL,
            token: defaults.string(forKey: Keys.token).flatMap { $0.isEmpty ? nil : $0 }
        )
    }

    func save(to defaults: UserDefaults = .standard) {
        defaults.set(baseURL.absoluteString, forKey: Keys.baseURL)
        defaults.set(token ?? "", forKey: Keys.token)
    }
}

enum APIError: LocalizedError {
    case invalidURL
    case unauthorized
    /// O servidor recusou com uma explicação (`reason` do Vapor).
    case server(status: Int, reason: String)
    case transport(any Error)
    case decoding(any Error)

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Endereço do servidor inválido."
        case .unauthorized:
            return "Token inválido ou ausente. Confira o API_TOKEN em Ajustes."
        case let .server(status, reason):
            return reason.isEmpty ? "O servidor respondeu \(status)." : reason
        case let .transport(error):
            return "Não foi possível falar com o servidor: \(error.localizedDescription)"
        case let .decoding(error):
            return "Resposta inesperada do servidor: \(error.localizedDescription)"
        }
    }
}

/// Acesso às rotas do Kaus-Australis. Todos os tipos trocados são os do
/// Kaus-Media — nenhum modelo é redeclarado aqui.
struct APIClient: Sendable {
    var configuration: APIConfiguration
    var session: URLSession = .shared

    // MARK: Contas

    func accounts() async throws -> [AccountDTO] {
        try await send(.get, "api/accounts")
    }

    func createAccount(_ account: AccountDTO) async throws -> AccountDTO {
        try await send(.post, "api/accounts", body: account)
    }

    func updateAccount(id: UUID, _ account: AccountDTO) async throws -> AccountDTO {
        try await send(.put, "api/accounts/\(id.uuidString)", body: account)
    }

    func deleteAccount(id: UUID) async throws {
        try await sendIgnoringResponse(.delete, "api/accounts/\(id.uuidString)")
    }

    // MARK: Lançamentos

    func transactions(
        accountID: UUID? = nil,
        search: String? = nil,
        includeProjected: Bool = true,
        from: Date? = nil,
        limit: Int = 500
    ) async throws -> [TransactionDTO] {
        var items = [URLQueryItem(name: "limit", value: String(limit))]
        if let accountID {
            items.append(URLQueryItem(name: "accountID", value: accountID.uuidString))
        }
        if let from {
            items.append(URLQueryItem(name: "from", value: ISO8601DateFormatter().string(from: from)))
        }
        if let search, !search.isEmpty {
            items.append(URLQueryItem(name: "search", value: search))
        }
        if !includeProjected {
            items.append(URLQueryItem(name: "includeProjected", value: "false"))
        }
        return try await send(.get, "api/transactions", query: items)
    }

    func createTransaction(_ transaction: TransactionDTO) async throws -> TransactionDTO {
        try await send(.post, "api/transactions", body: transaction)
    }

    func updateTransaction(id: UUID, _ transaction: TransactionDTO) async throws -> TransactionDTO {
        try await send(.put, "api/transactions/\(id.uuidString)", body: transaction)
    }

    func deleteTransaction(id: UUID) async throws {
        try await sendIgnoringResponse(.delete, "api/transactions/\(id.uuidString)")
    }

    func deleteTransactions(ids: [UUID]) async throws -> BulkDeleteResponse {
        try await send(.delete, "api/transactions", body: BulkDeleteRequest(ids: ids))
    }

    // MARK: Importação

    func importStatement(_ request: ImportRequestDTO) async throws -> ImportReportDTO {
        try await send(.post, "api/imports", body: request)
    }

    func importBatches(accountID: UUID? = nil) async throws -> [ImportBatchDTO] {
        var items: [URLQueryItem] = []
        if let accountID {
            items.append(URLQueryItem(name: "accountID", value: accountID.uuidString))
        }
        return try await send(.get, "api/imports", query: items)
    }

    /// Apaga os lançamentos criados por uma importação e restaura as projeções
    /// que ela havia confirmado.
    func undoImport(batchID: UUID) async throws -> BulkDeleteResponse {
        try await send(.delete, "api/imports/\(batchID.uuidString)")
    }

    // MARK: Regras

    func categoryRules() async throws -> [CategoryRule] {
        try await send(.get, "api/category-rules")
    }

    func createRule(_ rule: CategoryRule) async throws -> CategoryRule {
        try await send(.post, "api/category-rules", body: rule)
    }

    func updateRule(id: UUID, _ rule: CategoryRule) async throws -> CategoryRule {
        try await send(.put, "api/category-rules/\(id.uuidString)", body: rule)
    }

    func deleteRule(id: UUID) async throws {
        try await sendIgnoringResponse(.delete, "api/category-rules/\(id.uuidString)")
    }

    func preview(_ request: CategoryPreviewRequest) async throws -> CategoryPreviewResponse {
        try await send(.post, "api/category-rules/preview", body: request)
    }

    func recategorize(accountID: UUID? = nil, onlyUncategorized: Bool = false) async throws -> RecategorizeResponse {
        var items: [URLQueryItem] = []
        if let accountID {
            items.append(URLQueryItem(name: "accountID", value: accountID.uuidString))
        }
        if onlyUncategorized {
            items.append(URLQueryItem(name: "onlyUncategorized", value: "true"))
        }
        return try await send(.post, "api/transactions/recategorize", query: items)
    }

    // MARK: Resumo

    func summary(accountID: UUID? = nil, forecastMonths: Int = 6) async throws -> LedgerProjection {
        var items = [URLQueryItem(name: "forecastMonths", value: String(forecastMonths))]
        if let accountID {
            items.append(URLQueryItem(name: "accountID", value: accountID.uuidString))
        }
        return try await send(.get, "api/summary", query: items)
    }

    // MARK: Transporte

    private enum Method: String {
        case get = "GET"
        case post = "POST"
        case put = "PUT"
        case delete = "DELETE"
    }

    private func send<Response: Decodable>(
        _ method: Method,
        _ path: String,
        query: [URLQueryItem] = []
    ) async throws -> Response {
        try decode(try await perform(method, path, query: query, body: nil))
    }

    private func send<Body: Encodable, Response: Decodable>(
        _ method: Method,
        _ path: String,
        query: [URLQueryItem] = [],
        body: Body
    ) async throws -> Response {
        try decode(try await perform(method, path, query: query, body: try Self.encoder.encode(body)))
    }

    private func sendIgnoringResponse(
        _ method: Method,
        _ path: String,
        query: [URLQueryItem] = []
    ) async throws {
        _ = try await perform(method, path, query: query, body: nil)
    }

    private func decode<Response: Decodable>(_ data: Data) throws -> Response {
        do {
            return try Self.decoder.decode(Response.self, from: data)
        } catch {
            throw APIError.decoding(error)
        }
    }

    private func perform(
        _ method: Method,
        _ path: String,
        query: [URLQueryItem],
        body: Data?
    ) async throws -> Data {
        guard var components = URLComponents(
            url: configuration.baseURL.appendingPathComponent(path),
            resolvingAgainstBaseURL: false
        ) else {
            throw APIError.invalidURL
        }
        components.queryItems = query.isEmpty ? nil : query
        guard let url = components.url else { throw APIError.invalidURL }

        var request = URLRequest(url: url)
        request.httpMethod = method.rawValue
        if let token = configuration.token {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = body
        }

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw APIError.transport(error)
        }

        guard let http = response as? HTTPURLResponse else { return data }
        switch http.statusCode {
        case 200..<300:
            return data
        case 401, 403:
            throw APIError.unauthorized
        default:
            throw APIError.server(status: http.statusCode, reason: Self.reason(from: data))
        }
    }

    /// O Vapor devolve `{"error": true, "reason": "..."}` nos erros.
    private static func reason(from data: Data) -> String {
        struct VaporError: Decodable { let reason: String }
        return (try? JSONDecoder().decode(VaporError.self, from: data))?.reason ?? ""
    }

    static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()

    static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()
}
