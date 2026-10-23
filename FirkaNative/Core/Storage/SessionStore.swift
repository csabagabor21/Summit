import Foundation
import Combine
import Security

@MainActor
final class SessionStore: ObservableObject {
    @Published var users: [AppUser] = [] {
        didSet { persist() }
    }
    @Published var selectedId: String? {
        didSet { persist() }
    }
    var selectedUser: AppUser? { users.first(where: { $0.id == selectedId }) }

    /// Régi, nyílt UserDefaults-kulcs (csak az átálláshoz és az aláíratlan
    /// Mac-build tartalékaként).
    private let key = "firka.users.v1"
    /// A KRÉTA access/refresh tokenek a Keychainben élnek, ezen az eszközön,
    /// első feloldás után olvashatóan (a Live Activity háttérfrissítése
    /// zárolt képernyőn is megújít) — nem kerülnek iCloud-mentésbe sem.
    private static let keychainService = "hu.flint.summit.session"
    private static let keychainAccount = "users.v1"
    /// Megvan-e már ez a telepítés a Keychain-tárolóval. A Keychain túléli
    /// az app törlését, a UserDefaults nem: e jelző nélküli indulás =
    /// friss telepítés, ilyenkor a régi telepítés ottmaradt tokenjeit töröljük.
    private static let installedKey = "session.keychain.installed.v1"
    /// Az utoljára kiírt állapot — azonos tartalomnál nincs újabb Keychain-írás.
    private var lastPersisted: Data?
    /// Betöltés közben a didSet-ek nem írnak vissza (egy SessionStore()
    /// példányosítás így nem jár Keychain-írással).
    private var isLoading = false

    init() {
        load()
        // Screenshot/demo helper: if running in simulator with FIRKA_DEMO=1, inject demo user
        if users.isEmpty, ProcessInfo.processInfo.arguments.contains("-FIRKA_DEMO") || UserDefaults.standard.bool(forKey: "FIRKA_DEMO") {
            let d = AppUser.demo
            users = [d]
            selectedId = d.id
            persist()
        }
        // Reviewer-login ellenőrzéshez: -FIRKA_REVIEWER indítási arggal
        // a tesztfiókos user injektálódik (ugyanaz, mint a sikeres
        // tesztfiókos belépés eredménye).
        if users.isEmpty, ProcessInfo.processInfo.arguments.contains("-FIRKA_REVIEWER") {
            let r = AppUser.reviewer
            users = [r]
            selectedId = r.id
            persist()
        }
    }

    func load() {
        let defaults = UserDefaults.standard
        let legacy = defaults.data(forKey: key)
        if !defaults.bool(forKey: Self.installedKey) {
            // Friss telepítés (nincs régi UserDefaults-állapot sem): egy
            // korábbi telepítésből ottmaradt Keychain-tokenek nem léptethetnek
            // be automatikusan.
            if legacy == nil {
                KeychainHelper.delete(service: Self.keychainService, account: Self.keychainAccount)
            }
            defaults.set(true, forKey: Self.installedKey)
        }
        // A nyílt másolat, ha létezik, mindig a frissebb: átállás előtti
        // állapot, aláíratlan Mac-tartalék, vagy egy régebbi build írta
        // vissza (TestFlight-visszalépés) — a Keychainben akkor elavult
        // (esetleg már rotált refresh) token ülne.
        let data = legacy ?? KeychainHelper.load(service: Self.keychainService, account: Self.keychainAccount)
        guard let data, let decoded = try? JSONDecoder().decode(StoredUsers.self, from: data) else { return }
        isLoading = true
        users = decoded.users
        selectedId = decoded.selectedId
        isLoading = false
        if legacy != nil {
            // Átállás: Keychainbe írás, siker esetén a régi nyílt másolat törlődik.
            lastPersisted = nil
            persist()
        } else {
            lastPersisted = try? JSONEncoder().encode(StoredUsers(users: users, selectedId: selectedId))
        }
    }
    func persist() {
        guard !isLoading else { return }
        let stored = StoredUsers(users: users, selectedId: selectedId)
        guard let data = try? JSONEncoder().encode(stored), data != lastPersisted else { return }
        let status = KeychainHelper.save(data, service: Self.keychainService, account: Self.keychainAccount,
                                         accessible: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly)
        if status == errSecSuccess {
            UserDefaults.standard.removeObject(forKey: key)
        } else {
            // Keychain-entitlement nélküli (aláíratlan Mac) build: a régi
            // UserDefaults-út marad, különben ott be sem lehetne lépni.
            UserDefaults.standard.set(data, forKey: key)
        }
        lastPersisted = data
    }
    /// Azonos fiók új belépése (pl. lejárt munkamenet után): ilyenkor a
    /// SummitApp selectedId-figyelője NEM kapcsolhatja ki a szinkront —
    /// csak a valódi fiókváltás (eltérő accountKey) vagy a kijelentkezés.
    var sameAccountRelogin: Bool = false

    func add(_ user: AppUser) {
        if let cur = selectedId.flatMap({ id in users.first(where: { $0.id == id }) }),
           cur.id != user.id, cur.accountKey == user.accountKey {
            sameAccountRelogin = true
        }
        // Régi UUID-sor takarítása: azonos fiók nem maradhat duplikátumként
        // (a stabil id bevezetése előtti belépések maradványa).
        users.removeAll { $0.id != user.id && $0.accountKey == user.accountKey }
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
    /// A heartbeathez használandó iskolanév: a kézi felülírás nyer, ha van,
    /// különben az adatlapból jött név.
    var heartbeatSchoolName: String? {
        guard let u = selectedUser else { return nil }
        if let o = u.schoolNameOverride?.trimmingCharacters(in: .whitespacesAndNewlines), !o.isEmpty {
            return o
        }
        return u.schoolName
    }
    /// Kézi iskolanév mentése a kiválasztott userhez (üres = törlés).
    func setSchoolOverride(_ name: String) {
        guard let id = selectedId, let idx = users.firstIndex(where: { $0.id == id }) else { return }
        let t = name.trimmingCharacters(in: .whitespacesAndNewlines)
        users[idx].schoolNameOverride = t.isEmpty ? nil : t
        persist()
        objectWillChange.send()
    }
    /// Képernyőn mutatandó név: a Beállításokban megadott becenév, ha van,
    /// különben a KRÉTA-név. A becenév eszköz-helyi (NicknameStore),
    /// sosem szinkronizálódik és a heartbeatbe sem kerül.
    var displayName: String {
        guard let u = selectedUser else { return "Diák" }
        return NicknameStore.displayName(for: u)
    }

    /// Utólagos iskolanév-pótlás: ha a kiválasztott userhez nincs használható
    /// iskolanév (üres, vagy szűrt demo/kód-név), a TanuloAdatlapból tölti be
    /// a KRÉTA-beli intézménynevet. Demo vagy kód nélküli userhez nem nyúl —
    /// a heartbeat-szűrővel összhangban (lásd AnalyticsStore).
    /// - Returns: van-e most küldhető iskolanév.
    func refreshSchoolName(kreta: KretaClient) async -> Bool {
        guard let id = selectedId, let idx = users.firstIndex(where: { $0.id == id }) else { return false }
        let code = users[idx].instituteCode.trimmingCharacters(in: .whitespacesAndNewlines)
        let low = code.lowercased()
        guard !code.isEmpty, low != "demo", low != "unknown" else { return false }
        if let o = users[idx].schoolNameOverride?.trimmingCharacters(in: .whitespacesAndNewlines),
           !o.isEmpty, AnalyticsStore.isRealSchoolName(o) { return true }
        if AnalyticsStore.isRealSchoolName(users[idx].schoolName) { return true }
        if let data = await kreta.probeInstitute(code),
           let name = (try? JSONDecoder().decode(StudentResponse.self, from: data))?.IntezmenyNeve?
                .trimmingCharacters(in: .whitespacesAndNewlines),
           AnalyticsStore.isRealSchoolName(name) {
            users[idx].schoolName = name
            persist()
            objectWillChange.send()
            return true
        }
        // Második forrás: a token és a userinfo névszerű claimjei —
        // ennél a fióknál az adatlap üres nevet ad, innen még jöhet valódi.
        if let at = kreta.accessToken,
           let hit = JWT.schoolNameCandidates(fromJWT: at).first(where: { AnalyticsStore.isRealSchoolName($0) }) {
            users[idx].schoolName = hit
            persist()
            objectWillChange.send()
            return true
        }
        if let info = await kreta.fetchUserInfo(),
           let hit = JWT.schoolNameCandidates(from: info).first(where: { AnalyticsStore.isRealSchoolName($0) }) {
            users[idx].schoolName = hit
            persist()
            objectWillChange.send()
            return true
        }
        return false
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
