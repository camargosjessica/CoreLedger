import Foundation
import Testing
@testable import KausBorealis

@Suite("Configuração da API", .serialized)
struct APIConfigurationTests {
    @Test func tokenGoesToKeychainAndLegacyCopyIsMoved() throws {
        let suite = "kausborealis.tests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        let keychain = KeychainStore(service: suite)
        defer {
            defaults.removePersistentDomain(forName: suite)
            try? keychain.remove("api.token")
        }

        defaults.set("legado", forKey: "api.token")
        let loaded = APIConfiguration.load(from: defaults, keychain: keychain)

        #expect(loaded.token == "legado")
        #expect(defaults.string(forKey: "api.token") == nil, "O token não fica no plist")
        #expect(try keychain.string(forKey: "api.token") == "legado")

        APIConfiguration(baseURL: loaded.baseURL, token: nil).save(to: defaults, keychain: keychain)
        #expect(try keychain.string(forKey: "api.token") == nil)
    }

    @Test func cancellationIsNotAnError() {
        #expect(LedgerSession.isCancellation(CancellationError()))
        #expect(LedgerSession.isCancellation(APIError.transport(URLError(.cancelled))))
        #expect(!LedgerSession.isCancellation(APIError.transport(URLError(.timedOut))))
    }
}
