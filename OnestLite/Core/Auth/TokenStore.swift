import Foundation
import Security

protocol TokenStore: Sendable {
    func load() throws -> StoredSession?
    func save(_ session: StoredSession) throws
    func clear() throws
}

struct KeychainError: Error, Equatable {
    let status: OSStatus
}

/// Guarda la sesión como un único ítem de Keychain, accesible solo con el dispositivo
/// desbloqueado y sin migrar a otros dispositivos ni respaldos.
struct KeychainTokenStore: TokenStore {
    private let service: String
    private let account = "session"

    init(service: String) {
        self.service = service
    }

    func load() throws -> StoredSession? {
        var query = baseQuery()
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        switch status {
        case errSecSuccess:
            guard let data = result as? Data else { return nil }
            return try? JSONCoding.makeDecoder().decode(StoredSession.self, from: data)
        case errSecItemNotFound:
            return nil
        default:
            throw KeychainError(status: status)
        }
    }

    func save(_ session: StoredSession) throws {
        let data = JSONCoding.encode(session)
        let update = SecItemUpdate(baseQuery() as CFDictionary,
                                   [kSecValueData as String: data] as CFDictionary)
        if update == errSecSuccess { return }
        guard update == errSecItemNotFound else { throw KeychainError(status: update) }

        var attributes = baseQuery()
        attributes[kSecValueData as String] = data
        attributes[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        let add = SecItemAdd(attributes as CFDictionary, nil)
        guard add == errSecSuccess else { throw KeychainError(status: add) }
    }

    func clear() throws {
        let status = SecItemDelete(baseQuery() as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError(status: status)
        }
    }

    private func baseQuery() -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
    }
}

/// Implementación en memoria para pruebas y previews.
final class InMemoryTokenStore: TokenStore, @unchecked Sendable {
    private let lock = NSLock()
    private var session: StoredSession?

    init(session: StoredSession? = nil) {
        self.session = session
    }

    func load() throws -> StoredSession? {
        lock.withLock { session }
    }

    func save(_ session: StoredSession) throws {
        lock.withLock { self.session = session }
    }

    func clear() throws {
        lock.withLock { session = nil }
    }
}
