import Foundation
import Security
import NotchProtocol

/// Secrets extensions keep in the login Keychain, one generic password per key.
/// Only the app touches the Keychain; extension code asks through its runner.
/// Calls can block while macOS asks for Keychain access, so keep them off the
/// main thread.
public struct ExtensionSecretStore: Sendable {
    public static let maximumCount = 32

    /// Distinguishes test items from the app's real ones.
    let servicePrefix: String

    public init() { servicePrefix = "NotchNotch" }
    init(servicePrefix: String) { self.servicePrefix = servicePrefix }

    private func service(_ extensionID: String) -> String { "\(servicePrefix): \(extensionID)" }

    private func query(_ extensionID: String, key: String? = nil) -> [CFString: Any] {
        var query: [CFString: Any] = [kSecClass: kSecClassGenericPassword, kSecAttrService: service(extensionID)]
        if let key { query[kSecAttrAccount] = key }
        return query
    }

    public func value(extensionID: String, key: String) throws -> String? {
        var query = query(extensionID, key: key)
        query[kSecReturnData] = true
        query[kSecMatchLimit] = kSecMatchLimitOne
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data else { throw Self.error(status) }
        return String(data: data, encoding: .utf8)
    }

    public func set(extensionID: String, key: String, value: String) throws {
        let data = Data(value.utf8)
        let update = SecItemUpdate(query(extensionID, key: key) as CFDictionary, [kSecValueData: data] as CFDictionary)
        if update == errSecSuccess { return }
        guard update == errSecItemNotFound else { throw Self.error(update) }
        guard try keys(extensionID: extensionID).count < Self.maximumCount else {
            throw ProtocolError.invalid("An extension can keep up to \(Self.maximumCount) secrets.")
        }
        var item = query(extensionID, key: key)
        item[kSecValueData] = data
        item[kSecAttrLabel] = "\(service(extensionID)) – \(key)"
        item[kSecAttrDescription] = "NotchNotch extension secret"
        let status = SecItemAdd(item as CFDictionary, nil)
        guard status == errSecSuccess else { throw Self.error(status) }
    }

    public func delete(extensionID: String, key: String) throws {
        let status = SecItemDelete(query(extensionID, key: key) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw Self.error(status) }
    }

    /// Names of the stored secrets, never their values.
    public func keys(extensionID: String) throws -> [String] {
        var query = query(extensionID)
        query[kSecReturnAttributes] = true
        query[kSecMatchLimit] = kSecMatchLimitAll
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return [] }
        guard status == errSecSuccess, let items = result as? [[CFString: Any]] else { throw Self.error(status) }
        return items.compactMap { $0[kSecAttrAccount] as? String }.sorted()
    }

    /// Removes every secret of an extension, for example when it is removed.
    public func deleteAll(extensionID: String) throws {
        let status = SecItemDelete(query(extensionID) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw Self.error(status) }
    }

    private static func error(_ status: OSStatus) -> Error {
        let message = SecCopyErrorMessageString(status, nil) as String? ?? "Keychain error \(status)"
        return ProtocolError.invalid(status == errSecUserCanceled || status == errSecAuthFailed
                                     ? "Keychain access was not allowed." : message)
    }
}
