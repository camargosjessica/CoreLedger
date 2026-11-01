import Foundation
import KausMedia

/// Uma rota do Kaus-Australis: método, caminho, query e corpo, com o tipo de
/// resposta no próprio tipo. Montar a requisição não depende de rede, então
/// cada rota é testável isoladamente.
struct Endpoint<Response: Decodable>: Sendable {
    enum Method: String, Sendable {
        case get = "GET"
        case post = "POST"
        case put = "PUT"
        case delete = "DELETE"
        case patch = "PATCH"
    }

    var method: Method
    /// Caminho relativo à URL base, já codificado para URL.
    var path: String
    var query: [URLQueryItem] = []
    var body: (any Encodable & Sendable)?

    func urlRequest(baseURL: URL, token: String?, encoder: JSONEncoder) throws -> URLRequest {
        // `path` já vem codificado (nomes de categoria passam por
        // `escapedPathComponent`). `appendingPathComponent` codificaria o `%`
        // de novo ("Casa › Luz" virava "Casa%2520%E2..." no servidor).
        guard var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false) else {
            throw APIError.invalidURL
        }
        let basePath = components.percentEncodedPath.hasSuffix("/")
            ? String(components.percentEncodedPath.dropLast())
            : components.percentEncodedPath
        components.percentEncodedPath = basePath + "/" + path
        components.queryItems = query.isEmpty ? nil : query
        guard let url = components.url else { throw APIError.invalidURL }

        var request = URLRequest(url: url)
        request.httpMethod = method.rawValue
        if let token {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try encoder.encode(body)
        }
        return request
    }
}

/// Resposta sem corpo útil (`204 No Content`).
struct NoContent: Decodable, Sendable {}

/// Itens de query só para os valores presentes.
private struct Query {
    private(set) var items: [URLQueryItem] = []

    mutating func add(_ name: String, _ value: String?) {
        if let value { items.append(URLQueryItem(name: name, value: value)) }
    }
}

private func escapedPathComponent(_ text: String) -> String {
    text.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? text
}

// MARK: - Catálogo de rotas

extension Endpoint where Response == [AccountDTO] {
    static func accounts() -> Self { .init(method: .get, path: "api/accounts") }
}

extension Endpoint where Response == AccountDTO {
    static func createAccount(_ account: AccountDTO) -> Self {
        .init(method: .post, path: "api/accounts", body: account)
    }

    static func updateAccount(id: UUID, _ account: AccountDTO) -> Self {
        .init(method: .put, path: "api/accounts/\(id.uuidString)", body: account)
    }
}

extension Endpoint where Response == FinancialPosition {
    /// Posição consolidada de todas as contas: não aceita filtro por conta,
    /// porque o sentido dela é justamente somar caixinhas, contas e cartões.
    static func position() -> Self { .init(method: .get, path: "api/position") }
}

extension Endpoint where Response == [TransactionDTO] {
    static func transactions(_ filter: TransactionQuery) -> Self {
        var query = Query()
        query.add("limit", String(filter.limit))
        query.add("offset", filter.offset > 0 ? String(filter.offset) : nil)
        query.add("accountID", filter.accountID?.uuidString)
        query.add("from", filter.from?.ISO8601Format())
        query.add("to", filter.to?.ISO8601Format())
        query.add("search", filter.search.flatMap { $0.isEmpty ? nil : $0 })
        query.add("includeProjected", filter.includeProjected ? nil : "false")
        query.add("category", filter.category)
        query.add("tag", filter.tag)
        return .init(method: .get, path: "api/transactions", query: query.items)
    }
}

extension Endpoint where Response == TransactionDTO {
    static func createTransaction(_ transaction: TransactionDTO) -> Self {
        .init(method: .post, path: "api/transactions", body: transaction)
    }

    static func updateTransaction(id: UUID, _ transaction: TransactionDTO) -> Self {
        .init(method: .put, path: "api/transactions/\(id.uuidString)", body: transaction)
    }

    /// `accountID` recebe a contrapartida com o valor invertido; `nil` desfaz.
    static func setTransfer(id: UUID, accountID: UUID?) -> Self {
        .init(method: .put, path: "api/transactions/\(id.uuidString)/transfer", body: TransferLinkRequest(accountID: accountID))
    }
}

extension Endpoint where Response == BulkDeleteResponse {
    static func deleteTransactions(ids: [UUID]) -> Self {
        .init(method: .delete, path: "api/transactions", body: BulkDeleteRequest(ids: ids))
    }

    /// Apaga os lançamentos criados por uma importação e restaura as projeções
    /// que ela havia confirmado.
    static func undoImport(batchID: UUID) -> Self {
        .init(method: .delete, path: "api/imports/\(batchID.uuidString)")
    }
}

extension Endpoint where Response == BulkUpdateResponse {
    static func updateTransactions(_ request: BulkUpdateRequest) -> Self {
        .init(method: .patch, path: "api/transactions", body: request)
    }
}

extension Endpoint where Response == LedgerProjection {
    static func summary(accountID: UUID?, forecastMonths: Int) -> Self {
        var query = Query()
        query.add("forecastMonths", String(forecastMonths))
        query.add("accountID", accountID?.uuidString)
        return .init(method: .get, path: "api/summary", query: query.items)
    }
}

extension Endpoint where Response == ImportReportDTO {
    static func importStatement(_ request: ImportRequestDTO) -> Self {
        .init(method: .post, path: "api/imports", body: request)
    }
}

extension Endpoint where Response == [ImportBatchDTO] {
    static func importBatches(accountID: UUID?) -> Self {
        var query = Query()
        query.add("accountID", accountID?.uuidString)
        return .init(method: .get, path: "api/imports", query: query.items)
    }
}

extension Endpoint where Response == [CategoryRule] {
    static func categoryRules() -> Self { .init(method: .get, path: "api/category-rules") }
}

extension Endpoint where Response == CategoryRule {
    static func createRule(_ rule: CategoryRule) -> Self {
        .init(method: .post, path: "api/category-rules", body: rule)
    }

    static func updateRule(id: UUID, _ rule: CategoryRule) -> Self {
        .init(method: .put, path: "api/category-rules/\(id.uuidString)", body: rule)
    }
}

extension Endpoint where Response == CategoryPreviewResponse {
    static func preview(_ request: CategoryPreviewRequest) -> Self {
        .init(method: .post, path: "api/category-rules/preview", body: request)
    }
}

extension Endpoint where Response == RecategorizeResponse {
    static func recategorize(accountID: UUID?, onlyUncategorized: Bool) -> Self {
        var query = Query()
        query.add("accountID", accountID?.uuidString)
        query.add("onlyUncategorized", onlyUncategorized ? "true" : nil)
        return .init(method: .post, path: "api/transactions/recategorize", query: query.items)
    }
}

extension Endpoint where Response == [String] {
    /// Todas as categorias em uso no servidor, sem filtro nem paginação.
    static func categories() -> Self { .init(method: .get, path: "api/categories") }
}

extension Endpoint where Response == DeleteCategoryResponse {
    /// Apaga a categoria inteira: some das regras e os lançamentos que a usavam
    /// voltam a passar pelas regras restantes.
    static func deleteCategory(_ name: String) -> Self {
        .init(method: .delete, path: "api/categories/\(escapedPathComponent(name))")
    }
}

extension Endpoint where Response == LabelChangeResponse {
    /// Troca o nome da categoria em lançamentos, regras e compromissos.
    static func renameCategory(_ name: String, to newName: String) -> Self {
        .init(method: .put, path: "api/categories/\(escapedPathComponent(name))", body: RenameLabelRequest(name: newName))
    }

    static func renameTag(_ tag: String, to newName: String) -> Self {
        .init(method: .put, path: "api/tags/\(escapedPathComponent(tag))", body: RenameLabelRequest(name: newName))
    }

    static func deleteTag(_ tag: String) -> Self {
        .init(method: .delete, path: "api/tags/\(escapedPathComponent(tag))")
    }
}

extension Endpoint where Response == SpendingReport {
    /// Gastos do ano por categoria ou tag. Sem `accountID`, `accountKind` limita
    /// às contas daquele tipo (ex.: todos os cartões).
    static func spending(year: Int, grouping: SpendingGrouping, accountID: UUID?, accountKind: AccountKind?) -> Self {
        var query = Query()
        query.add("year", String(year))
        query.add("groupBy", grouping.rawValue)
        query.add("accountID", accountID?.uuidString)
        query.add("accountKind", accountID == nil ? accountKind?.rawValue : nil)
        return .init(method: .get, path: "api/analytics/spending", query: query.items)
    }
}

extension Endpoint where Response == [RecurringCommitment] {
    static func commitments() -> Self { .init(method: .get, path: "api/commitments") }
}

extension Endpoint where Response == RecurringCommitment {
    static func createCommitment(_ commitment: RecurringCommitment) -> Self {
        .init(method: .post, path: "api/commitments", body: commitment)
    }

    static func updateCommitment(id: UUID, _ commitment: RecurringCommitment) -> Self {
        .init(method: .put, path: "api/commitments/\(id.uuidString)", body: commitment)
    }
}

extension Endpoint where Response == [CategoryLimit] {
    static func limits() -> Self { .init(method: .get, path: "api/limits") }
}

extension Endpoint where Response == CategoryLimit {
    static func saveLimit(_ limit: CategoryLimit) -> Self { .init(method: .put, path: "api/limits", body: limit) }
}

extension Endpoint where Response == [CategorySetting] {
    static func categorySettings() -> Self { .init(method: .get, path: "api/category-settings") }
}

extension Endpoint where Response == CategorySetting {
    static func saveCategorySetting(_ setting: CategorySetting) -> Self {
        .init(method: .put, path: "api/category-settings", body: setting)
    }
}

extension Endpoint where Response == PlanResponse {
    /// Grade anual: linhas por categoria, colunas por mês.
    static func plan(from: YearMonth, to: YearMonth, openingBalance: Money?) -> Self {
        var query = Query()
        query.add("from", from.description)
        query.add("to", to.description)
        query.add("openingBalance", openingBalance?.description)
        return .init(method: .get, path: "api/plan", query: query.items)
    }
}

extension Endpoint where Response == ResetResponse {
    static func reset(scope: ResetScope) -> Self {
        .init(method: .post, path: "api/reset", body: ResetRequest(scope: scope))
    }
}

extension Endpoint where Response == NoContent {
    static func deleteAccount(id: UUID) -> Self { .init(method: .delete, path: "api/accounts/\(id.uuidString)") }
    static func deleteTransaction(id: UUID) -> Self { .init(method: .delete, path: "api/transactions/\(id.uuidString)") }
    static func deleteRule(id: UUID) -> Self { .init(method: .delete, path: "api/category-rules/\(id.uuidString)") }
    static func deleteCommitment(id: UUID) -> Self { .init(method: .delete, path: "api/commitments/\(id.uuidString)") }
    static func deleteLimit(category: String) -> Self { .init(method: .delete, path: "api/limits/\(escapedPathComponent(category))") }
}
