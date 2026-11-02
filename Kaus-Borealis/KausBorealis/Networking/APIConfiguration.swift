import Foundation
import OSLog

/// Endereço e credencial do backend. Ajustáveis na aba Ajustes para quando o
/// Vapor roda noutra porta ou noutra máquina da rede local.
///
/// O endereço fica no `UserDefaults`; o token, no Keychain.
nonisolated struct APIConfiguration: Equatable, Sendable {
    var baseURL: URL
    var token: String?

    static let defaultBaseURL = URL(string: "http://127.0.0.1:8080")!

    private enum Keys {
        static let baseURL = "api.baseURL"
        static let token = "api.token"
    }

    private static let logger = Logger(subsystem: "KausBorealis", category: "APIConfiguration")

    static func load(
        from defaults: UserDefaults = .standard,
        keychain: KeychainStore = KeychainStore()
    ) -> APIConfiguration {
        APIConfiguration(
            baseURL: defaults.string(forKey: Keys.baseURL).flatMap(URL.init(string:)) ?? defaultBaseURL,
            token: loadToken(from: defaults, keychain: keychain)
        )
    }

    func save(
        to defaults: UserDefaults = .standard,
        keychain: KeychainStore = KeychainStore()
    ) {
        defaults.set(baseURL.absoluteString, forKey: Keys.baseURL)
        do {
            try keychain.set(token, forKey: Keys.token)
        } catch {
            Self.logger.error("Não foi possível gravar o token no Keychain: \(String(describing: error))")
        }
    }

    /// Lê do Keychain. Versões anteriores guardavam o token no `UserDefaults`:
    /// se ainda houver um lá, ele é movido para o Keychain e apagado do plist.
    private static func loadToken(from defaults: UserDefaults, keychain: KeychainStore) -> String? {
        if let legacy = defaults.string(forKey: Keys.token) {
            defaults.removeObject(forKey: Keys.token)
            if !legacy.isEmpty {
                do {
                    try keychain.set(legacy, forKey: Keys.token)
                } catch {
                    logger.error("Não foi possível migrar o token para o Keychain: \(String(describing: error))")
                    return legacy
                }
            }
        }
        do {
            return try keychain.string(forKey: Keys.token).flatMap { $0.isEmpty ? nil : $0 }
        } catch {
            logger.error("Não foi possível ler o token do Keychain: \(String(describing: error))")
            return nil
        }
    }
}
