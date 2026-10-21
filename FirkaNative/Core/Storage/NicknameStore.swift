import Foundation

/// Becenév — eszköz-helyi, fiókonkénti megjelenítési név.
///
/// SZÁNDÉKOSAN NEM szinkronizált: személyes adat, ezért a SummitSync
/// payloadba semmilyen formában nem kerülhet (ld. AGENTS.md sync-szabályt),
/// és a heartbeat/analitika továbbra is a valódi KRÉTA-nevet használja.
/// Csak a képernyőn megjelenő név (üdvözlés, profil) cserélődik le rá.
enum NicknameStore {
    static let changedNotification = Notification.Name("summit.nicknameChanged")
    static let maxLength = 24

    private static func key(userId: String?, accountKey: String?) -> String? {
        if let accountKey, !accountKey.isEmpty { return "summit.nickname.\(accountKey)" }
        if let userId, !userId.isEmpty { return "summit.nickname.\(userId)" }
        return nil
    }

    private static func normalized(_ raw: String) -> String? {
        let t = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return nil }
        return String(t.prefix(maxLength))
    }

    static func load(userId: String?, accountKey: String?) -> String? {
        guard let k = key(userId: userId, accountKey: accountKey) else { return nil }
        guard let raw = UserDefaults.standard.string(forKey: k) else { return nil }
        return normalized(raw)
    }

    static func load(for user: AppUser) -> String? {
        load(userId: user.id, accountKey: user.accountKey)
    }

    static func save(_ raw: String, userId: String?, accountKey: String?) {
        guard let k = key(userId: userId, accountKey: accountKey) else { return }
        guard let value = normalized(raw) else { return clear(userId: userId, accountKey: accountKey) }
        UserDefaults.standard.set(value, forKey: k)
        NotificationCenter.default.post(name: changedNotification, object: nil)
    }

    static func save(_ raw: String, for user: AppUser) {
        save(raw, userId: user.id, accountKey: user.accountKey)
    }

    static func clear(userId: String?, accountKey: String?) {
        guard let k = key(userId: userId, accountKey: accountKey) else { return }
        UserDefaults.standard.removeObject(forKey: k)
        NotificationCenter.default.post(name: changedNotification, object: nil)
    }

    static func clear(for user: AppUser) {
        clear(userId: user.id, accountKey: user.accountKey)
    }

    /// Képernyőn mutatandó név: becenév, ha van, különben a KRÉTA-név.
    static func displayName(kretaName: String, userId: String?, accountKey: String?) -> String {
        load(userId: userId, accountKey: accountKey) ?? kretaName
    }

    static func displayName(for user: AppUser) -> String {
        load(for: user) ?? user.name
    }
}
