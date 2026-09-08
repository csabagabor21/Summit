import Foundation
import Combine

@MainActor
final class SessionStore: ObservableObject {
    @Published var users: [AppUser] = [] {
        didSet { persist() }
    }
    @Published var selectedId: String? {
        didSet { persist() }
    }
    var selectedUser: AppUser? { users.first(where: { $0.id == selectedId }) }

    private let key = "firka.users.v1"

    init() {
        load()
        // Screenshot/demo helper: if running in simulator with FIRKA_DEMO=1, inject demo user
        if users.isEmpty, ProcessInfo.processInfo.arguments.contains("-FIRKA_DEMO") || UserDefaults.standard.bool(forKey: "FIRKA_DEMO") {
            let d = AppUser.demo
            users = [d]
            selectedId = d.id
            persist()
        }
    }

    func load() {
        if let data = UserDefaults.standard.data(forKey: key),
           let decoded = try? JSONDecoder().decode(StoredUsers.self, from: data) {
            users = decoded.users
            selectedId = decoded.selectedId
        }
    }
    func persist() {
        let stored = StoredUsers(users: users, selectedId: selectedId)
        if let data = try? JSONEncoder().encode(stored) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }
    func add(_ user: AppUser) {
        if let idx = users.firstIndex(where: { $0.id == user.id }) { users[idx] = user }
        else { users.append(user) }
        selectedId = user.id
        persist()
    }
    func logout() {
        if let id = selectedId { users.removeAll { $0.id == id } }
        selectedId = users.first?.id
        persist()
    }
    /// Kézi iskola-kód felülírás (Beállítások → Fiók): ha a tokenből fejlett
    /// kód nem host (pl. OM-azonosító), a user beírja a böngészős
    /// e-KRÉTA cím elejét (https://EZ.e-kreta.hu) és minden életre kel.
    func updateInstitute(_ code: String) {
        guard let id = selectedId, let idx = users.firstIndex(where: { $0.id == id }) else { return }
        users[idx].instituteCode = code.trimmingCharacters(in: .whitespacesAndNewlines)
        persist()
        objectWillChange.send()
    }
    /// Token refresh után frissíti a kiválasztott user tokenjeit és perzisztálja
    func updateTokens(accessToken: String, refreshToken: String?, expiresIn: Int?) {
        guard let id = selectedId, let idx = users.firstIndex(where: { $0.id == id }) else { return }
        users[idx].accessToken = accessToken
        if let rt = refreshToken, !rt.isEmpty { users[idx].refreshToken = rt }
        if let exp = expiresIn { users[idx].accessTokenExpire = Date().addingTimeInterval(Double(exp - 30)) }
        persist()
        objectWillChange.send()
    }
    var isLoggedIn: Bool { selectedUser != nil }
}
