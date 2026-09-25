import Foundation
import Security

enum KeychainHelper {
    /// Siker esetén errSecSuccess. Sandboxolt, keychain-entitlement
    /// nélküli buildben (pl. aláíratlan Mac Catalyst) errSecMissingEntitlement
    /// (-34018) — a hívó ilyenkor tartalék-tárolót használhat.
    @discardableResult
    static func save(_ data: Data, service: String, account: String) -> OSStatus {
        let q: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: account]
        SecItemDelete(q as CFDictionary)
        var add = q
        add[kSecValueData as String] = data
        return SecItemAdd(add as CFDictionary, nil)
    }
    static func load(service: String, account: String) -> Data? {
        let q: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: account, kSecReturnData as String: true, kSecMatchLimit as String: kSecMatchLimitOne]
        var out: AnyObject?
        SecItemCopyMatching(q as CFDictionary, &out)
        return out as? Data
    }
    @discardableResult
    static func delete(service: String, account: String) -> OSStatus {
        let q: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: account]
        return SecItemDelete(q as CFDictionary)
    }
}
