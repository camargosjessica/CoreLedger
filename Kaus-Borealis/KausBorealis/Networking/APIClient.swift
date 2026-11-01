import Foundation
import KausMedia

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
/// Kaus-Media — nenhum modelo é redeclarado aqui. As rotas em si estão em
/// `Endpoint`; o cliente só envia, trata o status e decodifica.
struct APIClient: Sendable {
    var configuration: APIConfiguration
    var session: URLSession = .shared

    // MARK: Contas

    func accounts() async throws -> [AccountDTO] { try await send(.accounts()) }
    func createAccount(_ account: AccountDTO) async throws -> AccountDTO { try await send(.createAccount(account)) }
    func updateAccount(id: UUID, _ account: AccountDTO) async throws -> AccountDTO {
        try await send(.updateAccount(id: id, account))
    }
    func deleteAccount(id: UUID) async throws { try await send(.deleteAccount(id: id)) }
    func position() async throws -> FinancialPosition { try await send(.position()) }

    // MARK: Lançamentos

    func transactions(_ query: TransactionQuery) async throws -> [TransactionDTO] { try await send(.transactions(query)) }
    func createTransaction(_ transaction: TransactionDTO) async throws -> TransactionDTO {
        try await send(.createTransaction(transaction))
    }
    func updateTransaction(id: UUID, _ transaction: TransactionDTO) async throws -> TransactionDTO {
        try await send(.updateTransaction(id: id, transaction))
    }
    func setTransfer(id: UUID, accountID: UUID?) async throws -> TransactionDTO {
        try await send(.setTransfer(id: id, accountID: accountID))
    }
    func deleteTransaction(id: UUID) async throws { try await send(.deleteTransaction(id: id)) }
    func deleteTransactions(ids: [UUID]) async throws -> BulkDeleteResponse { try await send(.deleteTransactions(ids: ids)) }
    func updateTransactions(_ request: BulkUpdateRequest) async throws -> BulkUpdateResponse {
        try await send(.updateTransactions(request))
    }
    func summary(accountID: UUID?, forecastMonths: Int) async throws -> LedgerProjection {
        try await send(.summary(accountID: accountID, forecastMonths: forecastMonths))
    }

    // MARK: Importação

    func importStatement(_ request: ImportRequestDTO) async throws -> ImportReportDTO { try await send(.importStatement(request)) }
    func importBatches(accountID: UUID?) async throws -> [ImportBatchDTO] { try await send(.importBatches(accountID: accountID)) }
    func undoImport(batchID: UUID) async throws -> BulkDeleteResponse { try await send(.undoImport(batchID: batchID)) }

    // MARK: Regras e rótulos

    func categoryRules() async throws -> [CategoryRule] { try await send(.categoryRules()) }
    func createRule(_ rule: CategoryRule) async throws -> CategoryRule { try await send(.createRule(rule)) }
    func updateRule(id: UUID, _ rule: CategoryRule) async throws -> CategoryRule { try await send(.updateRule(id: id, rule)) }
    func deleteRule(id: UUID) async throws { try await send(.deleteRule(id: id)) }
    func preview(_ request: CategoryPreviewRequest) async throws -> CategoryPreviewResponse { try await send(.preview(request)) }
    func recategorize(accountID: UUID?, onlyUncategorized: Bool) async throws -> RecategorizeResponse {
        try await send(.recategorize(accountID: accountID, onlyUncategorized: onlyUncategorized))
    }
    func categories() async throws -> [String] { try await send(.categories()) }
    func deleteCategory(_ name: String) async throws -> DeleteCategoryResponse { try await send(.deleteCategory(name)) }
    func renameCategory(_ name: String, to newName: String) async throws -> LabelChangeResponse {
        try await send(.renameCategory(name, to: newName))
    }
    func renameTag(_ tag: String, to newName: String) async throws -> LabelChangeResponse {
        try await send(.renameTag(tag, to: newName))
    }
    func deleteTag(_ tag: String) async throws -> LabelChangeResponse { try await send(.deleteTag(tag)) }

    // MARK: Análise

    func spending(year: Int, grouping: SpendingGrouping, accountID: UUID?, accountKind: AccountKind?) async throws -> SpendingReport {
        try await send(.spending(year: year, grouping: grouping, accountID: accountID, accountKind: accountKind))
    }

    // MARK: Planejamento

    func commitments() async throws -> [RecurringCommitment] { try await send(.commitments()) }
    func createCommitment(_ commitment: RecurringCommitment) async throws -> RecurringCommitment {
        try await send(.createCommitment(commitment))
    }
    func updateCommitment(id: UUID, _ commitment: RecurringCommitment) async throws -> RecurringCommitment {
        try await send(.updateCommitment(id: id, commitment))
    }
    func deleteCommitment(id: UUID) async throws { try await send(.deleteCommitment(id: id)) }
    func limits() async throws -> [CategoryLimit] { try await send(.limits()) }
    func saveLimit(_ limit: CategoryLimit) async throws -> CategoryLimit { try await send(.saveLimit(limit)) }
    func deleteLimit(category: String) async throws { try await send(.deleteLimit(category: category)) }
    func categorySettings() async throws -> [CategorySetting] { try await send(.categorySettings()) }
    func saveCategorySetting(_ setting: CategorySetting) async throws -> CategorySetting {
        try await send(.saveCategorySetting(setting))
    }
    func plan(from: YearMonth, to: YearMonth, openingBalance: Money?) async throws -> PlanResponse {
        try await send(.plan(from: from, to: to, openingBalance: openingBalance))
    }

    // MARK: Manutenção

    func reset(scope: ResetScope) async throws -> ResetResponse { try await send(.reset(scope: scope)) }

    // MARK: Transporte

    func send<Response: Decodable>(_ endpoint: Endpoint<Response>) async throws -> Response {
        let data = try await perform(endpoint)
        do {
            return try Self.decoder.decode(Response.self, from: data)
        } catch {
            throw APIError.decoding(error)
        }
    }

    /// Rotas sem corpo de resposta: o status basta.
    func send(_ endpoint: Endpoint<NoContent>) async throws {
        _ = try await perform(endpoint)
    }

    private func perform<Response>(_ endpoint: Endpoint<Response>) async throws -> Data {
        let request = try endpoint.urlRequest(
            baseURL: configuration.baseURL,
            token: configuration.token,
            encoder: Self.encoder
        )

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
