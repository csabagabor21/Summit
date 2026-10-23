import Foundation
import Security

enum KeychainHelper {
    /// Siker esetén errSecSuccess. Sandboxolt, keychain-entitlement
    /// nélküli buildben (pl. aláíratlan Mac Catalyst) errSecMissingEntitlement
    /// (-34018) — a hívó ilyenkor tartalék-tárolót használhat.
    /// `accessible`: a hozzáférhetőségi osztály (pl. a háttérben is olvasandó
    /// tokeneknél `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`);
    /// nil = rendszer-alapértelmezés (csak feloldott eszközön olvasható).
    @discardableResult
    static func save(_ data: Data, service: String, account: String, accessible: CFString? = nil) -> OSStatus {
        let q: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: account]
        SecItemDelete(q as CFDictionary)
        var add = q
        add[kSecValueData as String] = data
        if let accessible { add[kSecAttrAccessible as String] = accessible }
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
