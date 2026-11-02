import Foundation
import Security

/// Segredos curtos (como o `API_TOKEN`) no Keychain, como item de senha
/// genérica do próprio app. `UserDefaults` grava em texto puro num plist e
/// entra em backups sem criptografia; o Keychain não.
nonisolated struct KeychainStore: Sendable {
    var service: String

    init(service: String = Bundle.main.bundleIdentifier ?? "KausBorealis") {
        self.service = service
    }

    enum Failure: Error, Equatable {
        case unexpectedStatus(OSStatus)
    }

    func string(forKey key: String) throws -> String? {
        var query = baseQuery(for: key)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        switch status {
        case errSecSuccess:
            return (item as? Data).flatMap { String(data: $0, encoding: .utf8) }
        case errSecItemNotFound:
            return nil
        default:
            throw Failure.unexpectedStatus(status)
        }
    }

    /// Grava o valor; `nil` ou vazio apaga o item.
    func set(_ value: String?, forKey key: String) throws {
        guard let value, !value.isEmpty else {
            try remove(key)
            return
        }
        let data = Data(value.utf8)
        let update = [kSecValueData as String: data] as CFDictionary
        let status = SecItemUpdate(baseQuery(for: key) as CFDictionary, update)
        switch status {
        case errSecSuccess:
            return
        case errSecItemNotFound:
            var attributes = baseQuery(for: key)
            attributes[kSecValueData as String] = data
            attributes[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
            let added = SecItemAdd(attributes as CFDictionary, nil)
            guard added == errSecSuccess else { throw Failure.unexpectedStatus(added) }
        default:
            throw Failure.unexpectedStatus(status)
        }
    }

    func remove(_ key: String) throws {
        let status = SecItemDelete(baseQuery(for: key) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw Failure.unexpectedStatus(status)
        }
    }

    private func baseQuery(for key: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
        ]
    }
}
