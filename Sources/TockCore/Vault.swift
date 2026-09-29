import Foundation
import Security

/// Keeps each Service, secret included, as one generic-password item in the login keychain. Nothing is written to disk
/// outside the keychain.
///
/// Items use the file-based login keychain because the data protection keychain needs a provisioning-profile
/// entitlement that an ad-hoc or self-signed app cannot carry. The keychain grants the app that created an item silent
/// access; a build signed with a different identity triggers a keychain access prompt.
public struct Vault: Sendable {
    public struct Failure: Error, LocalizedError {
        public let status: OSStatus
        public var errorDescription: String? {
            (SecCopyErrorMessageString(status, nil) as String?) ?? "Keychain error \(status)."
        }
    }

    private let keychainService: String

    public init(keychainService: String = "tech.maxanderson.tock") {
        self.keychainService = keychainService
    }

    /// Every stored Service, sorted by issuer then account.
    public func load() throws -> [Service] {
        // The file-based keychain rejects kSecReturnData with kSecMatchLimitAll, so list accounts first and read each item.
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query([kSecMatchLimit: kSecMatchLimitAll, kSecReturnAttributes: true]), &result)
        if status == errSecItemNotFound { return [] }
        guard status == errSecSuccess else { throw Failure(status: status) }
        let accounts = (result as? [[String: Any]] ?? []).compactMap { $0[kSecAttrAccount as String] as? String }
        return try accounts.compactMap(read).sorted {
            ($0.issuer.localizedLowercase, $0.account.localizedLowercase) < ($1.issuer.localizedLowercase, $1.account.localizedLowercase)
        }
    }

    public func save(_ service: Service) throws {
        let data = try JSONEncoder().encode(service)
        let item = query([kSecAttrAccount: service.id.uuidString])
        let label = service.account.isEmpty ? "Tock: \(service.issuer)" : "Tock: \(service.issuer) (\(service.account))"
        var status = SecItemUpdate(item, [kSecValueData: data, kSecAttrLabel: label] as CFDictionary)
        if status == errSecItemNotFound {
            status = SecItemAdd(query([kSecAttrAccount: service.id.uuidString, kSecValueData: data, kSecAttrLabel: label,
                                       kSecAttrAccessible: kSecAttrAccessibleWhenUnlockedThisDeviceOnly]), nil)
        }
        guard status == errSecSuccess else { throw Failure(status: status) }
    }

    public func delete(_ id: UUID) throws {
        let status = SecItemDelete(query([kSecAttrAccount: id.uuidString]))
        guard status == errSecSuccess || status == errSecItemNotFound else { throw Failure(status: status) }
    }

    private func read(account: String) throws -> Service? {
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query([kSecAttrAccount: account, kSecMatchLimit: kSecMatchLimitOne, kSecReturnData: true]), &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else { throw Failure(status: status) }
        // An item this build cannot decode is left in place rather than deleted, so a newer build can still read it.
        return (result as? Data).flatMap { try? JSONDecoder().decode(Service.self, from: $0) }
    }

    private func query(_ extra: [CFString: Any]) -> CFDictionary {
        var query: [CFString: Any] = [kSecClass: kSecClassGenericPassword, kSecAttrService: keychainService]
        query.merge(extra) { _, new in new }
        return query as CFDictionary
    }
}
