import Foundation
import Combine
import UIKit

@MainActor
final class KretaClient: ObservableObject {
    var accessToken: String?
    var refreshToken: String?
    var instituteCode: String?
    /// Az ismert lejárat (SummitApp szinkronizálja a SessionStore-ból) —
    /// ez alapján újítunk proaktívan, nem az első 401-re várva.
    var accessTokenExpire: Date?
    /// Ha a refresh tokent a KRÉTA már nem fogadja el: újra be kell jelentkezni.
    /// Ilyenkor a nézetek a legutóbbi adatot tartják meg (nem ürülnek ki).
    /// Tartós állapot: sikeres refresh / újra belépés törli csak.
    @Published var sessionExpired = false
    /// Egyszeri popup-jelzés. A "Később" csak ezt nyugtatja le —
    /// a sessionExpired (és a MOST-kártya feletti piros sáv) megmarad,
    /// az adatok pedig a képernyőn maradnak.
    @Published var showExpiredAlert = false
    var userAgent: String = "eKretaStudent/264745 CFNetwork/1494.0.7 Darwin/23.4.0"
    /// SessionStore callback token frissítés után — SummitApp köti be
    var onTokensRefreshed: ((String, String?, Int?) -> Void)?

    // MARK: - Demo-backend (helyi adatszolgáltatás, hálózat nélkül)
    /// A demo user (instituteCode "demo") ugyanazon a kapun (fetchX) át kap
    /// adatot, mint egy KRÉTA-user — csak a szerver helyett a helyi
    /// DemoData-készletből. Ezért a nézetekben NINCS isDemo-ág: egy adatsáv
    /// van, a demo nem "külön app". A Demo gombbal belépett user rendes
    /// AppUser, kijelentkezésig/új belépésig megmarad.
    static let demoInstitute = "demo"
    private func isDemoBackend(iss: String) -> Bool {
        iss == Self.demoInstitute || instituteCode == Self.demoInstitute
    }

    private let session: URLSession = {
        let c = URLSessionConfiguration.default
        c.timeoutIntervalForRequest = 20
        c.timeoutIntervalForResource = 30
        return URLSession(configuration: c)
    }()

    private var isRefreshing = false
    private var refreshWaiters: [CheckedContinuation<Bool, Never>] = []

    /// - Parameter codeVerifier: az adott belépéshez készült PKCE-verifier
    ///   (`KretaAPI.makeAuthorizationRequest`).
    func exchangeCode(_ code: String, codeVerifier: String) async throws -> TokenResponse {
        var req = URLRequest(url: KretaAPI.login)
        req.httpMethod = "POST"
        req.setValue("application/x-www-form-urlencoded; charset=UTF-8", forHTTPHeaderField: "content-type")
        req.setValue("*/*", forHTTPHeaderField: "accept")
        req.setValue(userAgent, forHTTPHeaderField: "user-agent")
        let body: [String: String] = [
            "code": code,
            "code_verifier": codeVerifier,
            "redirect_uri": KretaAPI.redirectURI,
            "client_id": KretaAPI.clientId,
            "grant_type": "authorization_code"
        ]
        req.httpBody = body.map { "\($0.key)=\($0.value.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? $0.value)" }.joined(separator: "&").data(using: .utf8)
        let (data, resp) = try await session.data(for: req)
        guard let http = resp as? HTTPURLResponse, http.statusCode == 200 else {
            throw KretaError.tokenExchangeFailed(String(data: data, encoding: .utf8) ?? "")
        }
        let decoded = try JSONDecoder().decode(TokenResponse.self, from: data)
        self.accessToken = decoded.access_token
        self.refreshToken = decoded.refresh_token
        self.instituteCode = JWT.instituteCode(from: decoded.access_token) ?? self.instituteCode
        return decoded
    }

    /// Proaktív megújítás: ha a token lejárt vagy 60s-en belül lejár,
    /// frissít — így nem kell megvárni az első 401-et, ami után a nézetek
    /// egy frissítési körre kiürültek ("pár perc után eldobja az adatokat").
    /// Ismeretlen lejáratnál nem találgatunk, marad a 401-es védőháló.
    func ensureValidToken() async -> Bool {
        // Demo-backend: nincs hálózat, nincs lejárat — mindig érvényes.
        if isDemoBackend(iss: instituteCode ?? "") { return true }
        guard accessToken != nil else { return false }
        guard let exp = accessTokenExpire else { return true }
        if exp.timeIntervalSinceNow > 60 { return true }
        return await refreshTokens()
    }

    /// Halott munkamenet: csak az első átmenet dob popupot —
    /// a "Később" utáni újabb hibák már csak a piros sávot tartják életben.
    /// Helyi backend (demo / felhasználónév-jelszavas tesztfiók): nincs
    /// KRÉTA-munkamenet, a tokenek helyiek — itt a lejárat hamis lenne,
    /// ezért sem piros sáv, sem popup, sem hibaüzenet nem keletkezhet.
    private func markExpired() {
        if isDemoBackend(iss: instituteCode ?? "") { return }
        if !sessionExpired {
            sessionExpired = true
            showExpiredAlert = true
        }
    }

    private func markAlive() {
        sessionExpired = false
        showExpiredAlert = false
    }

    // MARK: - Token refresh (2 lépcsős: újrapróbálja a kérést refresh után)
    func refreshTokens() async -> Bool {
        // Demo-backend: nincs mit újítani, de nem is jár le soha.
        if isDemoBackend(iss: instituteCode ?? "") { return true }
        guard let rt = refreshToken, !rt.isEmpty else {
            // Nincs mivel újítani, de token lenne: halott munkamenet → újra belépés kell
            if accessToken != nil { markExpired() }
            return false
        }
        if isRefreshing {
            return await withCheckedContinuation { cont in refreshWaiters.append(cont) }
        }
        isRefreshing = true
        var succeeded = false
        defer {
            isRefreshing = false
            // minden várakozót a VALÓS eredménnyel ébresztünk (a régi kód
            // itt mindig true-t adott, mert a lejárt token is non-nil volt)
            let waiters = refreshWaiters; refreshWaiters = []
            for w in waiters { w.resume(returning: succeeded) }
        }
        // KRÉTA refresh-hez kell az institute_code (pl. ekreta docs: institute_code=xxx&refresh_token=...&grant_type=refresh_token&client_id=...)
        // Szemét (IDP-URL, "unknown") sosem megy ki: az IDP azt is eldobná,
        // és egy hamis "lejárt" popupot kapnánk egy élő munkamenetre.
        let iss = JWT.validInstituteCode(instituteCode)
            ?? JWT.validInstituteCode(JWT.instituteCode(from: accessToken ?? "")) ?? ""
        var req = URLRequest(url: KretaAPI.login)
        req.httpMethod = "POST"
        req.setValue("application/x-www-form-urlencoded; charset=UTF-8", forHTTPHeaderField: "content-type")
        req.setValue("*/*", forHTTPHeaderField: "accept")
        req.setValue(userAgent, forHTTPHeaderField: "user-agent")
        var body: [String: String] = [
            "refresh_token": rt,
            "client_id": KretaAPI.clientId,
            "grant_type": "refresh_token"
        ]
        if !iss.isEmpty && iss != "unknown" { body["institute_code"] = iss }
        req.httpBody = body.map { "\($0.key)=\($0.value.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? $0.value)" }.joined(separator: "&").data(using: .utf8)
        do {
            let (data, resp) = try await session.data(for: req)
            // Nem-HTTP válasz / transzport-hiba: átmeneti, a régi tokenek
            // maradnak — nem jelent lejárt munkamenetet.
            guard let http = resp as? HTTPURLResponse else { diag("refresh: nincs HTTP-válasz"); return false }
            guard http.statusCode == 200 else {
                diag("refresh: HTTP \(http.statusCode)")
                // Csak a 400/401 jelent halott refresh tokent (újra belépés kell).
                // 5xx / 429 / karbantartó-oldal: átmeneti — a következő körben
                // újrapróbáljuk, popup nélkül.
                if http.statusCode == 400 || http.statusCode == 401 { markExpired() }
                return false
            }
            let decoded: TokenResponse
            do {
                decoded = try JSONDecoder().decode(TokenResponse.self, from: data)
            } catch {
                // Sérült / nem-JSON válasz (pl. hibaoldal) ≠ halott munkamenet.
                return false
            }
            self.accessToken = decoded.access_token
            if let nr = decoded.refresh_token, !nr.isEmpty { self.refreshToken = nr }
            if let exp = decoded.expires_in { self.accessTokenExpire = Date().addingTimeInterval(Double(exp - 30)) }
            markAlive()
            diag("refresh: OK")
            onTokensRefreshed?(decoded.access_token, decoded.refresh_token, decoded.expires_in)
            succeeded = true
            return true
        } catch {
            // Transzport-hiba (offline, timeout): átmeneti, nem jelent
            // lejárt munkamenetet — a sessionExpired marad, ahogy volt.
            return false
        }
    }

    private func performGetData(_ url: URL) async throws -> (Data, HTTPURLResponse) {
        var req = URLRequest(url: url)
        req.httpMethod = "GET"
        if let t = accessToken { req.setValue("Bearer \(t)", forHTTPHeaderField: "authorization") }
        req.setValue(userAgent, forHTTPHeaderField: "user-agent")
        req.setValue("application/json", forHTTPHeaderField: "accept")
        if url.absoluteString.contains("kommunikacio/postaladaelemek") {
            req.setValue("hu-HU", forHTTPHeaderField: "X-Uzenet-Lokalizacio")
        }
        let (data, resp) = try await session.data(for: req)
        guard let http = resp as? HTTPURLResponse else { throw KretaError.network }
        return (data, http)
    }

    func diagErr(_ name: String, _ error: Error) {
        var m = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        if m.count > 140 { m = String(m.prefix(140)) + "…" }
        diag("\(name): \(m)")
    }

    func get<T: Decodable>(_ url: URL) async throws -> T {
        _ = await ensureValidToken()
        var (data, http) = try await performGetData(url)
        if http.statusCode == 401 {
            diag("\(shortURL(url)): 401 → refresh")
            if await refreshTokens() {
                (data, http) = try await performGetData(url)
                if http.statusCode == 401 { markExpired(); throw KretaError.unauthorized }
            } else {
                throw KretaError.unauthorized
            }
        }
        guard 200..<300 ~= http.statusCode else {
            diag("\(shortURL(url)): HTTP \(http.statusCode)")
            throw KretaError.http(http.statusCode, String(data: data, encoding: .utf8))
        }
        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            diag("\(shortURL(url)): decode-hiba (\(data.count) byte)")
            throw error
        }
    }

    func getRaw(_ url: URL) async throws -> Data {
        _ = await ensureValidToken()
        var req = URLRequest(url: url)
        if let t = accessToken { req.setValue("Bearer \(t)", forHTTPHeaderField: "authorization") }
        req.setValue(userAgent, forHTTPHeaderField: "user-agent")
        var (data, resp) = try await session.data(for: req)
        guard var http = resp as? HTTPURLResponse else { throw KretaError.network }
        if http.statusCode == 401 {
            diag("\(shortURL(url)): 401 → refresh")
            if await refreshTokens() {
                var retry = URLRequest(url: url)
                if let t = accessToken { retry.setValue("Bearer \(t)", forHTTPHeaderField: "authorization") }
                retry.setValue(userAgent, forHTTPHeaderField: "user-agent")
                (data, resp) = try await session.data(for: retry)
                guard let h2 = resp as? HTTPURLResponse else { throw KretaError.network }
                http = h2
                if http.statusCode == 401 { markExpired(); throw KretaError.unauthorized }
            } else {
                throw KretaError.unauthorized
            }
        }
        guard 200..<300 ~= http.statusCode else {
            diag("\(shortURL(url)): HTTP \(http.statusCode)")
            throw KretaError.network
        }
        return data
    }

    /// OIDC userinfo — ha a JWT-ben nincs institut-kód, innen még kinyerhető.
    /// Saját rövid timeoutos sessionnel: a loginban hívjuk, nem akaszthatja
    /// meg a belépést, ha az IDP nem válaszol.
    func fetchUserInfo() async -> [String: Any]? {
        guard let t = accessToken else { return nil }
        let c = URLSessionConfiguration.default
        c.timeoutIntervalForRequest = 8
        c.timeoutIntervalForResource = 10
        let quick = URLSession(configuration: c)
        var req = URLRequest(url: KretaAPI.userinfo)
        req.setValue("Bearer \(t)", forHTTPHeaderField: "authorization")
        req.setValue(userAgent, forHTTPHeaderField: "user-agent")
        req.setValue("application/json", forHTTPHeaderField: "accept")
        guard let (data, resp) = try? await quick.data(for: req),
              let http = resp as? HTTPURLResponse, 200..<300 ~= http.statusCode,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        return json
    }

    // MARK: - Diagnosztika (Beállítások → Diagnosztika)
    /// Időbélyegzett hálózati napló: endpoint + HTTP-státusz + darabszám.
    /// Ha "semmi nem jön be", ez mutatja meg, hogy 401/404/üres-200/dns-hiba.
    @Published var diagLog: [String] = []
    /// Órarend-kulcsnapló launch-onként egyszer (a heti darabolás miatt
    /// egy refresh sok órarend-hívást indít — nem spammelhet mindegyik).
    private var loggedTimetableKeys = false
    func diag(_ s: String) {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        diagLog.append("[\(f.string(from: Date()))] \(s)")
        if diagLog.count > 80 { diagLog.removeFirst(diagLog.count - 80) }
    }

    /// PII-mentes JSON-kulcsnapló: csak a kulcsnevek + a csatolmány-gyanús
    /// kulcsok típus-összefoglalója (értékek, fájlnevek nélkül). Megmutatja,
    /// hol laknak a csatolmányok: lista-elemben, részletben, milyen kulcson.
    func diagJsonKeys(_ data: Data, label: String) {
        if let d = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            let keys = d.keys.sorted().joined(separator: ",")
            let atts = KretaAttachmentParser.attachmentValueSummary(in: d)
            var line = "\(label) kulcsok: \(keys)"
            if !atts.isEmpty { line += " | " + atts.joined(separator: " ") }
            if line.count > 350 { line = String(line.prefix(350)) + "…" }
            diag(line)
            return
        }
        guard let arr = try? JSONSerialization.jsonObject(with: data) as? [Any] else {
            diag("\(label): nem JSON (\(data.count) byte)")
            return
        }
        var keys = Set<String>()
        var attHits = 0
        var attSamples: [String] = []
        for el in arr {
            guard let d = el as? [String: Any] else { continue }
            keys.formUnion(d.keys)
            let sum = KretaAttachmentParser.attachmentValueSummary(in: d)
            if !sum.isEmpty {
                attHits += 1
                if attSamples.count < 2 { attSamples.append(contentsOf: sum) }
            }
        }
        var line = "\(label) kulcsok (\(arr.count) elem): \(keys.sorted().joined(separator: ","))"
        if attHits > 0 { line += " [csatolmánykulcs \(attHits) elemben: \(attSamples.joined(separator: " "))]" }
        if line.count > 350 { line = String(line.prefix(350)) + "…" }
        diag(line)
    }
    private func shortURL(_ url: URL) -> String {
        (url.host ?? "?") + url.path
    }

    /// Száraz institut-próba: működik-e ez a kód hostként ezzel a tokennel?
    /// Direkt kérés refresh és flagek nélkül — csak a 200 számít.
    /// (A rövid kód DNS-hibával, a rossz suli 401-gyel esik ki, némán.)
    func probeInstitute(_ cand: String) async -> Data? {
        guard let url = KretaAPI.student(cand) else { return nil }
        var req = URLRequest(url: url)
        if let t = accessToken { req.setValue("Bearer \(t)", forHTTPHeaderField: "authorization") }
        req.setValue(userAgent, forHTTPHeaderField: "user-agent")
        req.setValue("application/json", forHTTPHeaderField: "accept")
        guard let (data, resp) = try? await session.data(for: req),
              let http = resp as? HTTPURLResponse, 200..<300 ~= http.statusCode else { return nil }
        diag("próba \(cand): OK")
        return data
    }

    // MARK: - Válasz-gyorstár (tabváltáskor ne töltődjön újra a hálózat)
    /// Memóriabeli, TTL-alapú válasz-gyorstár + single-flight: a tabok
    /// `.task`-ja minden megjelenéskor újra lefut — e nélkül minden
    /// tabváltás teljes KRÉTA-lehúzást indítana (a Feladatok tab pl.
    /// 5 párhuzamos hívás + akár 15 hét órarend mellé).
    /// - Friss (TTL-en belüli) találat: hálózat nélkül, azonnal vissza —
    ///   a tabváltás ilyenkor nem nyúl a KRÉTÁ-hoz, a régi adat marad.
    /// - Lejárt/hiányzó (`force` is): hálózat a háttérben, sikerre a
    ///   tároló felülíródik, a nézet a megérkező adattal dinamikusan frissül.
    /// - Sikertelen válasz sosem íródik a tárolóba; hibára a lejárt
    ///   tárolt érték jön vissza (ha van), különben üres lista.
    /// Fiókváltáskor/kijelentkezéskor ürül (invalidateCache).
    static let cacheTTL: TimeInterval = 300
    private struct CacheEntry { let value: Any; let at: Date }
    private var responseCache: [String: CacheEntry] = [:]
    private var inFlight: [String: Task<Any, Never>] = [:]

    /// Fiókváltáskor/kijelentkezéskor: a másik user adata nem szivároghat át.
    func invalidateCache() {
        responseCache.removeAll()
    }

    private func cachedValue<T>(key: String) -> T? {
        guard let e = responseCache[key],
              Date().timeIntervalSince(e.at) < Self.cacheTTL else { return nil }
        return e.value as? T
    }
    private func staleValue<T>(key: String) -> T? { responseCache[key]?.value as? T }
    private func storeValue(_ value: Any, key: String) { responseCache[key] = CacheEntry(value: value, at: Date()) }

    /// Nap-pontos kulcsrész dátumtartományokhoz (órarend, naptári napok).
    private static func dayKey(_ d: Date) -> String {
        let c = Calendar.current.dateComponents([.year, .month, .day], from: d)
        return "\(c.year ?? 0)-\(c.month ?? 0)-\(c.day ?? 0)"
    }

    /// Egyidejű azonos hívások összevonása: az első indítja a munkát,
    /// a többi ugyanannak a Tasknak az eredményét várja meg (pl. Főoldal
    /// + Jegyek tab egyszerre kér jegyeket — egy hálózati kör fut).
    private func singleFlight<T>(key: String, work: @escaping () async -> T) async -> T {
        if let f = inFlight[key], let v = await f.value as? T { return v }
        let t = Task<Any, Never> { await work() as Any }
        inFlight[key] = t
        defer { inFlight[key] = nil }
        return (await t.value as? T)!
    }

    // MARK: - Real data fetchers (used by HomeViewModel)
    func fetchGrades(iss: String, force: Bool = false) async -> [GradeItem] {
        if isDemoBackend(iss: iss) {
            let r = DemoData.gradesExpanded().sorted { $0.date > $1.date }
            diag("jegyek: \(r.count) db (demo)"); return r
        }
        let key = "grades:\(iss)"
        if !force, let hit: [GradeItem] = cachedValue(key: key) { return hit }
        return await singleFlight(key: key) {
            guard let url = KretaAPI.grades(iss) else { self.diag("jegyek: rossz URL"); return self.staleValue(key: key) ?? [] }
            do {
                let dtos: [KretaGradeDTO] = try await self.get(url)
                let r = dtos.map { $0.toItem() }.sorted { $0.date > $1.date }
                self.storeValue(r, key: key)
                self.diag("jegyek: \(r.count) db"); return r
            } catch { self.diagErr("jegyek", error); return self.staleValue(key: key) ?? [] }
        }
    }
    func fetchTimetable(iss: String, from: Date, to: Date, force: Bool = false) async -> [LessonItem] {
        if isDemoBackend(iss: iss) {
            // A 6 órás demo-sablon csempézve a kért tartományra — a heti
            // lapozás is ezen át megy, külön demo-ág nélkül a nézetekben.
            let r = DemoData.lessons(from: from, to: to)
            diag("órarend: \(r.count) db (demo)"); return r
        }
        let key = "tt:\(iss):\(Self.dayKey(from)):\(Self.dayKey(to))"
        if !force, let hit: [LessonItem] = cachedValue(key: key) { return hit }
        return await singleFlight(key: key) {
            await self.fetchTimetableNetwork(iss: iss, from: from, to: to, key: key)
        }
    }

    /// A fetchTimetable hálózati magja (a gyorstár/single-flight burkon belül).
    private func fetchTimetableNetwork(iss: String, from: Date, to: Date, key: String) async -> [LessonItem] {
        guard let url = KretaAPI.timetable(iss, start: from, end: to) else { diag("órarend: rossz URL"); return staleValue(key: key) ?? [] }
        do {
            // Firka-minta: az órarendi elem hordozza a csatolmányokat
            // (`Csatolmanyok: [{Uid, Nev}]`) — Uid alapján fűzzük az órákhoz,
            // a Feladatok tab innen kapja meg a házi fájljait is.
            // Elemenkénti toleráns dekódolás: egy hibás óra nem nullázza a hetet.
            let data: Data = try await getRaw(url)
            if !loggedTimetableKeys {
                loggedTimetableKeys = true
                diagJsonKeys(data, label: "órarend-minta")
            }
            let atts = KretaAttachmentParser.attachmentsByUid(from: data)
            let r = KretaLessonDTO.lenientItems(from: data).map { item in
                item.withAttachments(atts[item.id] ?? [])
            }.sorted { $0.start < $1.start }
            // Minden sikeres valós órarend a közös tárgy-cache-be is beolvad:
            // a Felmentés/Kerekítés lista és a Jegyek tab jegy nélküli tárgyai
            // így akkor is megvannak, ha az átlag-végpontok halottak.
            Self.mergeCachedSubjects(r.map(\.subject))
            let attCount = r.reduce(0) { $0 + $1.attachments.count }
            storeValue(r, key: key)
            diag("órarend: \(r.count) db" + (attCount > 0 ? " (\(attCount) csatolmány)" : "")); return r
        } catch { diagErr("órarend", error); return staleValue(key: key) ?? [] }
    }
    /// Naptári napok (tanév rendje) az órarend üres napjainak feliratához
    /// („Tanítás nélküli munkanap (Nem órarendi nap) (Hétfő)").
    /// Hibára üres lista — a nézet ilyenkor a régi általános szövegre esik.
    func fetchCalendarDays(iss: String, from: Date, to: Date, force: Bool = false) async -> [SchoolDayInfo] {
        if isDemoBackend(iss: iss) { return [] }
        let key = "cal:\(iss):\(Self.dayKey(from)):\(Self.dayKey(to))"
        if !force, let hit: [SchoolDayInfo] = cachedValue(key: key) { return hit }
        return await singleFlight(key: key) {
            await self.fetchCalendarDaysNetwork(iss: iss, from: from, to: to, key: key)
        }
    }

    private func fetchCalendarDaysNetwork(iss: String, from: Date, to: Date, key: String) async -> [SchoolDayInfo] {
        guard let url = KretaAPI.calendarDays(iss, from: from, to: to) else { diag("naptárnapok: rossz URL"); return staleValue(key: key) ?? [] }
        do {
            let data: Data = try await getRaw(url)
            let r = KretaCalendarDayDTO.items(from: data).sorted { $0.date < $1.date }
            storeValue(r, key: key)
            diag("naptárnapok: \(r.count) db"); return r
        } catch { diagErr("naptárnapok", error); return staleValue(key: key) ?? [] }
    }
    func fetchHomework(iss: String, force: Bool = false) async -> [HomeworkItem] {
        if isDemoBackend(iss: iss) {
            let r = DemoData.homeworks()
            diag("házi: \(r.count) db (demo)"); return r
        }
        let key = "hw:\(iss)"
        if !force, let hit: [HomeworkItem] = cachedValue(key: key) { return hit }
        return await singleFlight(key: key) {
            await self.fetchHomeworkNetwork(iss: iss, key: key)
        }
    }

    private func fetchHomeworkNetwork(iss: String, key: String) async -> [HomeworkItem] {
        do {
            // refilc mintára, két lépcsőben:
            // 1) lista ?datumTol-lal (utolsó 30 nap) — elemei csak hivatkozások
            // 2) minden házi tartalma külön: HaziFeladatok/{uid}
            // Nincs típus szerinti szűrés: minden visszakapott elem megjelenik.
            let from = Calendar.current.date(byAdding: .day, value: -30, to: Date())!
            guard let listURL = KretaAPI.homework(iss, from: from) else { return [] }
            let listData: Data = try await getRaw(listURL)
            diagJsonKeys(listData, label: "házi-lista")
            let dtos = KretaHomeworkDTO.lenientDTOs(from: listData)
            // A lista-elemek maguk is hordozhatnak csatolmányt — Uid alapján.
            let listAtts = KretaAttachmentParser.attachmentsByUid(from: listData)
            // A tartalmas lista-elemeket azonnal elfogadjuk; a csupasz
            // hivatkozásokhoz (csak Uid) lekérjük a HaziFeladatok/{uid} részletet.
            var items = dtos.filter { $0.hasContent }.map { item in
                let it = item.toItem()
                return it.withAttachments(listAtts[it.id] ?? [])
            }
            let have = Set(items.map { $0.id })
            let missing = KretaHomeworkDTO.uids(from: listData).filter { !have.contains($0) }
            if (!missing.isEmpty) {
                let detailed: [HomeworkItem] = await withTaskGroup(of: HomeworkItem?.self) { group in
                    for uid in missing {
                        group.addTask { [self] in
                            guard let detailURL = KretaAPI.homeworkDetail(iss, id: uid) else { return nil }
                            do {
                                let d: Data = try await self.getRaw(detailURL)
                                // A részlet tömb is lehet (nem csak dict) — mindkettőt fogadjuk,
                                // különben a házi némán eltűnik a listáról.
                                let dto: KretaHomeworkDTO?
                                if let single = try? JSONDecoder().decode(KretaHomeworkDTO.self, from: d) {
                                    dto = single
                                } else {
                                    dto = KretaHomeworkDTO.lenientDTOs(from: d).first
                                }
                                await self.diagJsonKeys(d, label: "házi-részlet")
                                guard let dto else { return nil }
                                return dto.toItem().withAttachments(KretaAttachmentParser.attachments(from: d))
                            } catch { return nil }
                        }
                    }
                    var out: [HomeworkItem] = []
                    for await item in group { if let item { out.append(item) } }
                    return out
                }
                items.append(contentsOf: detailed)
            }
            // Készítetlen előre: a Főoldal csak az első 3-at mutatja, a kész/régi
            // lejárt házik nem szoríthatják ki az új feladatot.
            let r = items.sorted {
                if $0.isDone != $1.isDone { return !$0.isDone }
                return $0.deadline < $1.deadline
            }
            storeValue(r, key: key)
            diag("házi: \(r.count) db"); return r
        } catch { diagErr("házi", error); return staleValue(key: key) ?? [] }
    }

    /// Házi-részletek pótlása a Feladatok tabnak: a lista NEM hozza a fájlokat
    /// (csak `IsCsatolasEngedelyezes`-flaget), és az órák `Csatolmanyok`-ja is
    /// lehet végig üres — ilyenkor a `HaziFeladatok/{uid}` részlet adja a
    /// csatolmányokat. Csak a fájl nélküli házikhoz kérdez (kíméli a KRÉTÁ-t).
    func fetchHomeworkDetails(_ items: [HomeworkItem], iss: String) async -> [HomeworkItem] {
        if isDemoBackend(iss: iss) { return items }
        let needy = items.filter { $0.attachments.isEmpty }
        guard !needy.isEmpty else { return items }
        let found: [String: [AttachmentItem]] = await withTaskGroup(of: (String, [AttachmentItem]).self) { group in
            for hw in needy {
                group.addTask { [self] in
                    let detailKey = "hwdetail:\(iss):\(hw.id)"
                    if let hit: [AttachmentItem] = await self.cachedValue(key: detailKey), !hit.isEmpty {
                        return (hw.id, hit)
                    }
                    guard let url = KretaAPI.homeworkDetail(iss, id: hw.id),
                          let d: Data = try? await self.getRaw(url) else { return (hw.id, []) }
                    await self.diagJsonKeys(d, label: "házi-részlet")
                    let atts = KretaAttachmentParser.attachments(from: d)
                    if !atts.isEmpty { await self.storeValue(atts, key: detailKey) }
                    return (hw.id, atts)
                }
            }
            var out: [String: [AttachmentItem]] = [:]
            for await (id, atts) in group { out[id] = atts }
            return out
        }
        let hits = found.values.filter { !$0.isEmpty }.count
        if hits > 0 { diag("házi-részlet: \(hits) házihoz van fájl") }
        return items.map { hw in
            guard let atts = found[hw.id], !atts.isEmpty else { return hw }
            return hw.withAttachments(atts)
        }
    }
    func fetchAbsences(iss: String, force: Bool = false) async -> [AbsenceItem] {
        if isDemoBackend(iss: iss) {
            let r = DemoData.absences()
            diag("hiányzás: \(r.count) db (demo)"); return r
        }
        let key = "abs:\(iss)"
        if !force, let hit: [AbsenceItem] = cachedValue(key: key) { return hit }
        return await singleFlight(key: key) {
            guard let url = KretaAPI.absences(iss) else { self.diag("hiányzás: rossz URL"); return self.staleValue(key: key) ?? [] }
            do {
                let dtos: [KretaAbsenceDTO] = try await self.get(url)
                let r = dtos.map { $0.toItem() }.sorted { $0.date > $1.date }
                self.storeValue(r, key: key)
                self.diag("hiányzás: \(r.count) db"); return r
            } catch { self.diagErr("hiányzás", error); return self.staleValue(key: key) ?? [] }
        }
    }
    func fetchExams(iss: String, force: Bool = false) async -> [ExamItem] {
        if isDemoBackend(iss: iss) {
            let r = DemoData.exams().sorted { $0.date < $1.date }
            diag("dolgozat: \(r.count) db (demo)"); return r
        }
        let key = "ex:\(iss)"
        if !force, let hit: [ExamItem] = cachedValue(key: key) { return hit }
        return await singleFlight(key: key) {
            await self.fetchExamsNetwork(iss: iss, key: key)
        }
    }

    private func fetchExamsNetwork(iss: String, key: String) async -> [ExamItem] {
        guard let url = KretaAPI.exams(iss) else { return staleValue(key: key) ?? [] }
        do {
            // Lenient: egy hibás elem nem nullázhatja a teljes dolgozatlistát
            let data: Data = try await getRaw(url)
            let atts = KretaAttachmentParser.attachmentsByUid(from: data)
            let r = KretaExamDTO.lenientItems(from: data).map { item in
                item.withAttachments(atts[item.id] ?? [])
            }.sorted { $0.date < $1.date }
            storeValue(r, key: key)
            diag("dolgozat: \(r.count) db"); return r
        } catch { diagErr("dolgozat", error); return staleValue(key: key) ?? [] }
    }
    /// Postaláda-doboz (e-Ügyintézés): beérkezett / elküldött / törölt.
    /// A doboznevek az ekreta-docs-v3 szerint (`beerkezett`, `elkuldott`,
    /// `torolt`) — a régi `bejovo`/`kimenő`/`piszkozat` nevekre az API
    /// nem válaszolt, ezért nem töltődött be semmi.
    /// Megnyitott (olvasottá tett) üzenetek ID-i — a lista és a főoldali
    /// csengő-jelvény is ezt figyeli. Szerver-oldali olvasott-végpont nincs
    /// dokumentálva (ekreta-docs-v3: "Marking message as read: not sure
    /// yet"), ezért a megnyitás helyben, optimistán jelöl, és a következő
    /// lista-lehúzáskor is rávetítjük a szerver által még olvasatlannak
    /// jelentett tételekre. Újraindításkor is megmarad (500-as sapkával).
    @Published var readMessageIDs: Set<String> = Set(UserDefaults.standard.stringArray(forKey: "firka.readMessages.v1") ?? [])
    /// Megnyitás → olvasott: azonnali helyi jelölés + perzisztálás.
    func markMessageRead(_ id: String) {
        guard !id.isEmpty, !readMessageIDs.contains(id) else { return }
        readMessageIDs.insert(id)
        // A halmaz nem nőhet végtelenre: legfeljebb 500 ID-t őrzünk.
        let kept = Array(readMessageIDs.suffix(500))
        readMessageIDs = Set(kept)
        UserDefaults.standard.set(kept, forKey: "firka.readMessages.v1")
    }
    /// Szerver/demo-lista + helyi olvasott-jelölések összefésülése.
    private func applyingLocalRead(_ items: [MessageItem]) -> [MessageItem] {
        guard !readMessageIDs.isEmpty else { return items }
        return items.map { readMessageIDs.contains($0.id) ? $0.withRead() : $0 }
    }
    func fetchMessages(box: KretaAPI.Mailbox, force: Bool = false) async -> [MessageItem] {
        if isDemoBackend(iss: instituteCode ?? "") {
            // Demo: csak a beérkezettben van tartalom, az elküldött/törölt üres.
            if box == .incoming {
                let r = applyingLocalRead(DemoData.messages())
                diag("üzenet/\(box.rawValue): \(r.count) db (demo)"); return r
            }
            diag("üzenet/\(box.rawValue): 0 db (demo)"); return []
        }
        let key = "msg:\(box.rawValue):\(instituteCode ?? "?")"
        if !force, let hit: [MessageItem] = cachedValue(key: key) {
            // Olvasott-jelölések időközben változhattak — a tárolt listára is rávetítjük.
            return applyingLocalRead(hit)
        }
        return await singleFlight(key: key) {
            guard let url = KretaAPI.messages(box) else { self.diag("üzenet/\(box.rawValue): rossz URL"); return self.staleValue(key: key).map(self.applyingLocalRead) ?? [] }
            do {
                let data: Data = try await self.getRaw(url)
                let items = KretaMessageDTO.lenientItems(from: data).sorted { $0.date > $1.date }
                // Nyers (jelöletlen) lista megy a tárolóba — a visszaolvasáskor
                // vetítjük rá az aktuális olvasott-jelöléseket.
                self.storeValue(items, key: key)
                let r = self.applyingLocalRead(items)
                self.diag("üzenet/\(box.rawValue): \(r.count) db"); return r
            } catch { self.diagErr("üzenet/\(box.rawValue)", error); return self.staleValue(key: key).map(self.applyingLocalRead) ?? [] }
        }
    }

    /// Kompat: a főoldali csengő-jelvény a beérkezett dobozt figyeli.
    func fetchMessages(force: Bool = false) async -> [MessageItem] { await fetchMessages(box: .incoming, force: force) }

    /// Elektronikus feljegyzések (KRÉTA-wide broadcast mindenkinek):
    /// intézeti Ellenőrző API `Sajat/Feljegyzesek` — nem a postaláda.
    func fetchNotes(iss: String, force: Bool = false) async -> [NoteItem] {
        if isDemoBackend(iss: iss) {
            let r = DemoData.notes()
            diag("feljegyzés: \(r.count) db (demo)"); return r
        }
        let key = "notes:\(iss)"
        if !force, let hit: [NoteItem] = cachedValue(key: key) { return hit }
        return await singleFlight(key: key) {
            guard let url = KretaAPI.notes(iss) else { self.diag("feljegyzés: rossz URL"); return self.staleValue(key: key) ?? [] }
            do {
                let data: Data = try await self.getRaw(url)
                let r = KretaNoteDTO.lenientItems(from: data).sorted { $0.date > $1.date }
                self.storeValue(r, key: key)
                self.diag("feljegyzés: \(r.count) db"); return r
            } catch { self.diagErr("feljegyzés", error); return self.staleValue(key: key) ?? [] }
        }
    }

    // MARK: - Üzenet-részlet + csatolmány-letöltés (PDF-megnyitáshoz)

    /// Egy üzenet törzse + csatolmányai (`postaladaelemek/{id}`).
    /// Demo-backend: helyből, hálózat nélkül.
    func fetchMessageDetail(_ message: MessageItem) async -> MessageItem {
        if isDemoBackend(iss: instituteCode ?? "") { return message }
        guard let url = KretaAPI.messageDetail(id: message.id) else { return message }
        do {
            let data: Data = try await getRaw(url)
            guard let parsed = KretaMessageDetail.parse(from: data) else { return message }
            var updated = message.withDetail(body: parsed.body, attachments: KretaAttachmentParser.attachments(from: data))
            if let s = parsed.sender, !s.isEmpty, (message.sender == "Üzenet" || message.sender.isEmpty) {
                updated = MessageItem(id: updated.id, sender: s, subject: parsed.subject ?? updated.subject,
                                      date: parsed.date ?? updated.date, isRead: updated.isRead,
                                      body: updated.body, attachments: updated.attachments)
            }
            return updated
        } catch { return message }
    }

    /// Csatolmány-letöltés: (fájl-név, tartalom). Refilc-sorrendben próbál,
    /// az első VALÓDI fájlválaszt adja vissza. Demo-backend: helyben generált minta-PDF.
    /// - `ownerId` (házi-uid) megmaradt a hívóhelyek kompatibilitásáért, de a
    ///   Refilc-útvonalhoz nem kell: a `Csatolmany/{uid}` önmagában címez.
    func downloadAttachment(_ att: AttachmentItem, ownerId: String? = nil) async -> (fileName: String, data: Data)? {
        if isDemoBackend(iss: instituteCode ?? "") {
            return (att.name, Self.demoPDF(title: att.name))
        }
        let iss = JWT.validInstituteCode(instituteCode)
            ?? JWT.validInstituteCode(JWT.instituteCode(from: accessToken ?? "")) ?? ""
        var urls: [URL] = []
        // 1) Házi/dolgozat: intézeti Ellenőrző, egyes számú Csatolmany/{uid}.
        if !iss.isEmpty, let u = KretaAPI.homeworkAttachment(iss, attachmentId: att.id) { urls.append(u) }
        // 2) Üzenet: e-Ügyintézés fileservice (a részlet `azonosito`-jával).
        if let u = KretaAPI.messageAttachment(att.id) { urls.append(u) }
        for url in urls {
            do {
                let data: Data = try await getRaw(url)
                // Hibaoldal (JSON/HTML) nem fájl: a QuickLook egy .pdf néven
                // mentett hibaoldaltól csak üres nézetet adna — dobjuk, és
                // próbáljuk a következő útvonalat / jelezzük a hibát.
                if KretaDownloadSniff.looksLikeFileData(data, fileName: att.name) { return (att.name, data) }
                diag("csatolmány: nem fájl-válasz (\(att.name), \(data.count) byte)")
            } catch { continue }
        }
        diag("csatolmány: letöltés sikertelen (\(att.name))")
        return nil
    }

    /// Helyben generált egyoldalas minta-PDF (demo-mód + offline teszt).
    static func demoPDF(title: String) -> Data {
        let fmt = UIGraphicsPDFRendererFormat()
        let renderer = UIGraphicsPDFRenderer(bounds: CGRect(x: 0, y: 0, width: 595, height: 842), format: fmt)
        return renderer.pdfData { ctx in
            ctx.beginPage()
            let titleAttrs: [NSAttributedString.Key: Any] = [.font: UIFont.boldSystemFont(ofSize: 22)]
            let bodyAttrs: [NSAttributedString.Key: Any] = [.font: UIFont.systemFont(ofSize: 13)]
            (title as NSString).draw(at: CGPoint(x: 48, y: 64), withAttributes: titleAttrs)
            let body = "Ez egy demo csatolmány a Summit appból.\n\nÉles KRÉTA-fiókkal itt a valódi fájl (PDF, kép, dokumentum) nyílik meg." as NSString
            body.draw(in: CGRect(x: 48, y: 110, width: 500, height: 600), withAttributes: bodyAttrs)
        }
    }

    // MARK: - Tárgy-cache (firka.cachedSubjects.v1)
    /// Közös tárgy-cache a Jegyek tab, a Felmentés és a Kerekítés listáihoz.
    /// Csak valós backendről töltjük (demo sosem szennyezi); a hívók a
    /// hálózati listával egyesítve mutatják. Üres/„Ismeretlen” nem kerül be.
    static let cachedSubjectsKey = "firka.cachedSubjects.v1"
    static func mergeCachedSubjects(_ names: [String]) {
        let clean = names.map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty && $0 != "Ismeretlen" }
        guard !clean.isEmpty else { return }
        var set = Set(UserDefaults.standard.stringArray(forKey: cachedSubjectsKey) ?? [])
        let before = set.count
        set.formUnion(clean)
        guard set.count != before else { return }
        UserDefaults.standard.set(set.sorted(), forKey: cachedSubjectsKey)
    }

    // MARK: - Tantárgyak — KRÉTA tudja akkor is ha nincs jegy (Atlagok + órarend fallback + cached)
    func fetchAllSubjectNames(iss: String, force: Bool = false) async -> [String] {
        if isDemoBackend(iss: iss) {
            // Demo-tárgyak jegyekből + órarendből, plusz egy üres "Etika" —
            // showcase a "Nincs jegy" állapotra (eddig a GradesView rakta hozzá).
            var demo = Set(DemoData.gradesExpanded().map(\.subject))
            demo.formUnion(DemoData.lessonsToday().map(\.subject))
            demo.insert("Etika")
            return demo.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty && $0 != "Ismeretlen" }.sorted()
        }
        let key = "subjects:\(iss)"
        if !force, let hit: [String] = cachedValue(key: key) { return hit }
        return await singleFlight(key: key) {
            await self.fetchAllSubjectNamesNetwork(iss: iss, key: key)
        }
    }

    private func fetchAllSubjectNamesNetwork(iss: String, key: String) async -> [String] {
        var names = Set<String>()
        // 1) Tantárgyi átlagok — minden felvett tárgy, jegy nélkül is
        for url in [KretaAPI.subjectAverages(iss), KretaAPI.subjectAveragesAlt(iss)].compactMap({ $0 }) {
            do {
                let dtos: [KretaSubjectAvgDTO] = try await get(url)
                for d in dtos { if let n = d.subjectName() { names.insert(n) } }
                if !names.isEmpty { break }
            } catch { continue }
        }
        // 2) Órarend fallback — HETI ablakokban. A régi egyetlen 90 napos
        //    kérés (−60…+30 nap) a KRÉTÁ-tól HTTP 400 ModelValidacio-t kapott
        //    (túl széles datumTol–datumIg tartomány), így ahol az átlag-
        //    végpontok halottak (siszc-mathiasz: 500/403), a lista üresen
        //    maradt → a Jegyek tab nem mutatta a jegy nélküli tárgyakat, és
        //    a Felmentés képernyőnek sem volt mit felsorolnia. A heti kérés
        //    ugyanaz, ami az Órarend tabon is működik.
        if names.isEmpty || names.count < 5 {
            let cal = Calendar.current
            let weekStart = cal.dateInterval(of: .weekOfYear, for: Date())?.start ?? cal.startOfDay(for: Date())
            // 3 hét vissza + aktuális + 1 hét előre, párhuzamosan — tanév
            // eleji (0 jegy) helyzetben is összegyűlik minden felvett tárgy.
            let weekly: [[LessonItem]] = await withTaskGroup(of: [LessonItem].self) { group in
                for w in [-3, -2, -1, 0, 1] {
                    guard let from = cal.date(byAdding: .weekOfYear, value: w, to: weekStart),
                          let to = cal.date(byAdding: .day, value: 7, to: from) else { continue }
                    group.addTask { [self] in await self.fetchTimetable(iss: iss, from: from, to: to) }
                }
                var out: [[LessonItem]] = []
                for await part in group { out.append(part) }
                return out
            }
            for l in weekly.joined() { names.insert(l.subject) }
        }
        // Szándékosan NINCS cached-union: a cache demo-módból szennyezett lehet,
        // a hívó (GradesView) külön fűzi hozzá megjelenítéshez, mentéshez viszont
        // csak ez a hálózati lista megy.
        let r = names.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty && $0 != "Ismeretlen" }.sorted()
        if !r.isEmpty { storeValue(r, key: key) }
        return r
    }
}

struct TokenResponse: Codable {
    let access_token: String
    let refresh_token: String?
    let id_token: String?
    let expires_in: Int?
    let token_type: String?
}

enum KretaError: Error, LocalizedError {
    case network, unauthorized, tokenExchangeFailed(String), http(Int, String?)
    var errorDescription: String? {
        switch self {
        case .network: return "Hálózati hiba"
        case .unauthorized: return "Lejárt munkamenet"
        case .tokenExchangeFailed(let s): return "Token hiba: \(s)"
        case .http(let c, let b): return "HTTP \(c): \(b ?? "")"
        }
    }
}

enum JWT {
    static func payload(_ token: String) -> [String: Any]? {
        let parts = token.split(separator: ".")
        guard parts.count >= 2 else { return nil }
        var b64 = String(parts[1]).replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        while b64.count % 4 != 0 { b64.append("=") }
        guard let data = Data(base64Encoded: b64), let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        return json
    }
    /// Eszközfüggetlen user-kulcs a beállítás-szinkronhoz: a JWT `sub`
    /// (KRÉTA-azonosító, pl. OM) vagy `email` — minden eszközön azonos,
    /// szemben az AppUser belépésenkénti UUID-jével. Csak kulcsképzésre,
    /// sehova nem küldjük és nem tároljuk.
    static func stableUserKey(from token: String) -> String? {
        guard let p = payload(token) else { return nil }
        let raw = (p["sub"] as? String) ?? (p["email"] as? String) ?? ""
        let t = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard t.count >= 2, t.count <= 128 else { return nil }
        let low = t.lowercased()
        guard low != "user" && low != "demo" && low != "unknown" else { return nil }
        return t
    }
    static func instituteCode(from token: String) -> String? {
        guard let p = payload(token) else { return nil }
        // Kulcs-keresés kisbetűsen: az IDP claim-neve ("kreta:institute_code"
        // vs. "kreta:iss" stb.) implementációnként eltérhet — a pontos
        // egyezés törékeny volt, hiányzó kulcsnál "unknown" lett az institut,
        // és onnantól minden refresh halott volt.
        for (k, v) in p {
            let lk = k.lowercased()
            guard lk.contains("institute") || lk == "kreta:iss" else { continue }
            if let s = v as? String, validInstituteCode(s) != nil { return s }
        }
        // aud: gyakran "*.e-kreta.hu" host (string vagy tömb) — az aldomain az institut.
        if let aud = p["aud"] {
            if let s = aud as? String, let v = instituteFromHost(s) { return v }
            if let arr = aud as? [String] {
                for s in arr { if let v = instituteFromHost(s) { return v } }
            }
        }
        // Bármely csupasz "*.e-kreta.hu" claim-érték (URL-t nem, csak hostot).
        for (_, v) in p {
            if let s = v as? String, !s.contains("://"), let c = instituteFromHost(s) { return c }
        }
        // Az "iss" tipikusan az IDP URL-je (https://idp.e-kreta.hu) —
        // az nem institut-kód, ilyet sosem adunk vissza.
        if let iss = p["iss"] as? String, validInstituteCode(iss) != nil { return iss }
        return nil
    }

    /// "xyz.e-kreta.hu" hostból institut-kód (xyz) — URL-ből, path-ból nem.
    static func instituteFromHost(_ host: String) -> String? {
        let h = host.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard h.hasSuffix(".e-kreta.hu") else { return nil }
        return validInstituteCode(String(h.dropLast(".e-kreta.hu".count)))
    }

    /// OIDC userinfo JSON-ből institut: lapos "institute" kulcsok, "*.e-kreta.hu"
    /// hostok, plusz egy szint mélyen a "code" mező (pl. institute: {code: ...}).
    static func instituteCodeFromUserInfo(_ info: [String: Any]) -> String? {
        allInstituteCandidates(fromUserInfo: info).first
    }

    /// Minden institut-jelölt a tokenből, sorrendben, duplum nélkül.
    /// A tokenben lehet rövid kód (pl. "680545" — az NEM host) és hosszú
    /// is: a hívó végigpróbálja és az első működőt tartja meg, nem tippel.
    static func allInstituteCandidates(from token: String) -> [String] {
        guard let p = payload(token) else { return [] }
        var out: [String] = []
        func add(_ s: String?) {
            guard let t = s?.trimmingCharacters(in: .whitespacesAndNewlines), !t.isEmpty,
                  t.lowercased() != "unknown", !t.contains("://"), !t.contains(" "), !t.contains("/"),
                  (t.contains(".") == false || instituteFromHost(t) != nil),
                  !out.contains(t) else { return }
            out.append(t)
        }
        // ELSŐ a pontos kulcs (a "régen működött" viselkedés) — a ciklus
        // szótár-sorrendje egy rövid kódos társkulcsot is elkaphatott.
        for k in p.keys where k.lowercased() == "kreta:institute_code" { add(p[k] as? String) }
        for (k, v) in p {
            let lk = k.lowercased()
            if lk == "kreta:institute_code" { continue }
            if lk.contains("institute") || lk == "kreta:iss" { add(v as? String) }
        }
        if let aud = p["aud"] {
            if let s = aud as? String { add(instituteFromHost(s)) }
            if let arr = aud as? [String] { for s in arr { add(instituteFromHost(s)) } }
        }
        for (_, v) in p {
            if let s = v as? String, !s.contains("://"), let c = instituteFromHost(s) { add(c) }
        }
        return Array(out.prefix(8))
    }

    /// Minden institut-jelölt userinfo JSON-ből (lapos + egy szint mély).
    static func allInstituteCandidates(fromUserInfo info: [String: Any]) -> [String] {
        var out: [String] = []
        func add(_ s: String?) {
            guard let t = s?.trimmingCharacters(in: .whitespacesAndNewlines), !t.isEmpty,
                  t.lowercased() != "unknown", !t.contains("://"), !t.contains(" "), !t.contains("/"),
                  (t.contains(".") == false || instituteFromHost(t) != nil),
                  !out.contains(t) else { return }
            out.append(t)
        }
        for (k, v) in info {
            if let s = v as? String {
                if k.lowercased().contains("institute") { add(s) }
                if !s.contains("://"), let c = instituteFromHost(s) { add(c) }
            } else if let d = v as? [String: Any],
                      k.lowercased().contains("institute") || k.lowercased().contains("school") {
                for (kk, vv) in d where kk.lowercased().contains("code") { add(vv as? String) }
            }
        }
        return Array(out.prefix(8))
    }

    /// Iskolanév-jelöltek tokenből/userinfóból: az "institute"/"school"/
    /// "intezmeny" kulcsok szóközös, tulajdonnév-szerű értékei egy szint
    /// mélyig. A kód-kinyerés az ilyet direkt eldobja (szóköz miatt) —
    /// itt pont az kell. A hívó validál (AnalyticsStore.isRealSchoolName).
    static func schoolNameCandidates(fromJWT token: String) -> [String] {
        guard let p = payload(token) else { return [] }
        return schoolNameCandidates(from: p)
    }
    static func schoolNameCandidates(from info: [String: Any]) -> [String] {
        var out: [String] = []
        func add(_ s: String?) {
            guard let t = s?.trimmingCharacters(in: .whitespacesAndNewlines),
                  t.count >= 2, t.count <= 120, !out.contains(t) else { return }
            out.append(t)
        }
        for (k, v) in info {
            let lk = k.lowercased()
            let isNameKey = lk.contains("school") || lk.contains("institute") || lk.contains("intezmeny") || lk.contains("intézmény")
            if let s = v as? String {
                if isNameKey { add(s) }
            } else if let d = v as? [String: Any], isNameKey {
                for (kk, vv) in d where kk.lowercased().contains("name") || kk.lowercased().contains("nev") || kk.lowercased().contains("név") {
                    add(vv as? String)
                }
            }
        }
        return Array(out.prefix(8))
    }

    /// Valódi institut-kód-e (pl. klik035454001)? URL-t, "unknown"-t,
    /// szóközt/pontot tartalmazó szemetet elutasít — a refresh-bodyba
    /// ilyen sosem kerülhet, mert az IDP biztosan eldobná.
    static func validInstituteCode(_ s: String?) -> String? {
        guard let t = s?.trimmingCharacters(in: .whitespacesAndNewlines), !t.isEmpty else { return nil }
        guard t.lowercased() != "unknown", !t.contains("://"), !t.contains("/"), !t.contains(" "), !t.contains(".") else { return nil }
        return t
    }
}
