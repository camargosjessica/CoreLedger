import Foundation
import Testing
import KausMedia
@testable import KausBorealis

@Suite("Rotas da API")
struct EndpointTests {
    private let base = URL(string: "http://localhost:8080")!

    private func request<R>(_ endpoint: Endpoint<R>, token: String? = nil) throws -> URLRequest {
        try endpoint.urlRequest(baseURL: base, token: token, encoder: APIClient.encoder)
    }

    private func query(_ request: URLRequest) -> [String: String] {
        let items = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?.queryItems ?? []
        return Dictionary(uniqueKeysWithValues: items.map { ($0.name, $0.value ?? "") })
    }

    @Test func transactionQueryOnlySendsWhatIsSet() throws {
        let account = UUID()
        let from = try #require(DateParser.parse("01/01/2026"))
        let request = try request(.transactions(TransactionQuery(
            accountID: account, search: "", includeProjected: false, from: from, category: "Mercado"
        )))

        #expect(request.httpMethod == "GET")
        #expect(request.url?.path == "/api/transactions")
        #expect(query(request) == [
            "limit": "500",
            "accountID": account.uuidString,
            "from": "2026-01-01T00:00:00Z",
            "includeProjected": "false",
            "category": "Mercado",
        ])
    }

    @Test func bodyIsJSONAndTokenGoesInTheHeader() throws {
        let request = try request(.reset(scope: .transactions), token: "segredo")

        #expect(request.httpMethod == "POST")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer segredo")
        #expect(request.value(forHTTPHeaderField: "Content-Type") == "application/json")
        let body = try JSONDecoder().decode(ResetRequest.self, from: try #require(request.httpBody))
        #expect(body.scope == .transactions)
    }

    @Test func labelsAreEscapedInThePath() throws {
        let request = try request(.renameCategory("Casa › Luz/Água", to: "Moradia"))
        #expect(request.httpMethod == "PUT")
        #expect(request.url?.absoluteString == "http://localhost:8080/api/categories/Casa%20%E2%80%BA%20Luz%2F%C3%81gua")
    }

    @Test func baseURLWithPathPrefixIsKept() throws {
        let request = try Endpoint<[AccountDTO]>.accounts()
            .urlRequest(baseURL: URL(string: "https://exemplo.com/ledger/")!, token: nil, encoder: APIClient.encoder)
        #expect(request.url?.absoluteString == "https://exemplo.com/ledger/api/accounts")
    }

    @Test func spendingPrefersAccountOverKind() throws {
        let account = UUID()
        let request = try request(.spending(year: 2026, grouping: .category, accountID: account, accountKind: .creditCard))
        #expect(query(request) == ["year": "2026", "groupBy": "category", "accountID": account.uuidString])
    }
}
