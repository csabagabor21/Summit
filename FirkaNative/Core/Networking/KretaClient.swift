import Foundation
import Combine

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

    private let session: URLSession = {
        let c = URLSessionConfiguration.default
        c.timeoutIntervalForRequest = 20
        c.timeoutIntervalForResource = 30
        return URLSession(configuration: c)
    }()

    private var isRefreshing = false
    private var refreshWaiters: [CheckedContinuation<Bool, Never>] = []

    func exchangeCode(_ code: String) async throws -> TokenResponse {
        var req = URLRequest(url: KretaAPI.login)
        req.httpMethod = "POST"
        req.setValue("application/x-www-form-urlencoded; charset=UTF-8", forHTTPHeaderField: "content-type")
        req.setValue("*/*", forHTTPHeaderField: "accept")
        req.setValue(userAgent, forHTTPHeaderField: "user-agent")
        let body: [String: String] = [
            "code": code,
            "code_verifier": KretaAPI.codeVerifier,
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
        guard accessToken != nil else { return false }
        guard let exp = accessTokenExpire else { return true }
        if exp.timeIntervalSinceNow > 60 { return true }
        return await refreshTokens()
    }

    /// Halott munkamenet: csak az első átmenet dob popupot —
    /// a "Később" utáni újabb hibák már csak a piros sávot tartják életben.
    private func markExpired() {
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
    func diag(_ s: String) {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        diagLog.append("[\(f.string(from: Date()))] \(s)")
        if diagLog.count > 80 { diagLog.removeFirst(diagLog.count - 80) }
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

    // MARK: - Real data fetchers (used by HomeViewModel)
    func fetchGrades(iss: String) async -> [GradeItem] {
        guard let url = KretaAPI.grades(iss) else { diag("jegyek: rossz URL"); return [] }
        do {
            let dtos: [KretaGradeDTO] = try await get(url)
            let r = dtos.map { $0.toItem() }.sorted { $0.date > $1.date }
            diag("jegyek: \(r.count) db"); return r
        } catch { diagErr("jegyek", error); return [] }
    }
    func fetchTimetable(iss: String, from: Date, to: Date) async -> [LessonItem] {
        guard let url = KretaAPI.timetable(iss, start: from, end: to) else { diag("órarend: rossz URL"); return [] }
        do {
            let dtos: [KretaLessonDTO] = try await get(url)
            let r = dtos.compactMap { $0.toItem() }.sorted { $0.start < $1.start }
            diag("órarend: \(r.count) db"); return r
        } catch { diagErr("órarend", error); return [] }
    }
    func fetchHomework(iss: String) async -> [HomeworkItem] {
        do {
            // refilc mintára, két lépcsőben:
            // 1) lista ?datumTol-lal (utolsó 30 nap) — elemei csak hivatkozások
            // 2) minden házi tartalma külön: HaziFeladatok/{uid}
            // Nincs típus szerinti szűrés: minden visszakapott elem megjelenik.
            let from = Calendar.current.date(byAdding: .day, value: -30, to: Date())!
            guard let listURL = KretaAPI.homework(iss, from: from) else { return [] }
            let listData: Data = try await getRaw(listURL)
            let dtos = KretaHomeworkDTO.lenientDTOs(from: listData)
            // A tartalmas lista-elemeket azonnal elfogadjuk; a csupasz
            // hivatkozásokhoz (csak Uid) lekérjük a HaziFeladatok/{uid} részletet.
            var items = dtos.filter { $0.hasContent }.map { $0.toItem() }
            let have = Set(items.map { $0.id })
            let missing = KretaHomeworkDTO.uids(from: listData).filter { !have.contains($0) }
            if (!missing.isEmpty) {
                let detailed: [HomeworkItem] = await withTaskGroup(of: HomeworkItem?.self) { group in
                    for uid in missing {
                        group.addTask { [self] in
                            guard let detailURL = KretaAPI.homeworkDetail(iss, id: uid) else { return nil }
                            do {
                                let d: Data = try await self.getRaw(detailURL)
                                guard let dto = try? JSONDecoder().decode(KretaHomeworkDTO.self, from: d) else { return nil }
                                return dto.toItem()
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
            diag("házi: \(r.count) db"); return r
        } catch { diagErr("házi", error); return [] }
    }
    func fetchAbsences(iss: String) async -> [AbsenceItem] {
        guard let url = KretaAPI.absences(iss) else { diag("hiányzás: rossz URL"); return [] }
        do {
            let dtos: [KretaAbsenceDTO] = try await get(url)
            let r = dtos.map { $0.toItem() }.sorted { $0.date > $1.date }
            diag("hiányzás: \(r.count) db"); return r
        } catch { diagErr("hiányzás", error); return [] }
    }
    func fetchExams(iss: String) async -> [ExamItem] {
        guard let url = KretaAPI.exams(iss) else { return [] }
        do {
            // Lenient: egy hibás elem nem nullázhatja a teljes dolgozatlistát
            let data: Data = try await getRaw(url)
            let r = KretaExamDTO.lenientItems(from: data).sorted { $0.date < $1.date }
            diag("dolgozat: \(r.count) db"); return r
        } catch { diagErr("dolgozat", error); return [] }
    }
    func fetchMessages() async -> [MessageItem] {
        // eugyintezes - try bejovo, then kimenő
        for endpoint in ["bejovo", "kimenő", "piszkozat"] {
            guard let url = KretaAPI.messages(endpoint) else { continue }
            do {
                let dtos: [KretaMessageDTO] = try await get(url)
                if !dtos.isEmpty {
                    let r = dtos.map { $0.toItem() }.sorted { $0.date > $1.date }
                    diag("üzenet: \(r.count) db"); return r
                }
            } catch { diagErr("üzenet/\(endpoint)", error); continue }
        }
        return []
    }

    // MARK: - Tantárgyak — KRÉTA tudja akkor is ha nincs jegy (Atlagok + órarend fallback + cached)
    func fetchAllSubjectNames(iss: String) async -> [String] {
        var names = Set<String>()
        // 1) Tantárgyi átlagok — minden felvett tárgy, jegy nélkül is
        for url in [KretaAPI.subjectAverages(iss), KretaAPI.subjectAveragesAlt(iss)].compactMap({ $0 }) {
            do {
                let dtos: [KretaSubjectAvgDTO] = try await get(url)
                for d in dtos { if let n = d.subjectName() { names.insert(n) } }
                if !names.isEmpty { break }
            } catch { continue }
        }
        // 2) Órarend fallback — széles időablak, hogy minden tárgy szerepeljen
        if names.isEmpty || names.count < 5 {
            let cal = Calendar.current
            let start = cal.date(byAdding: .day, value: -60, to: Date())!
            let end = cal.date(byAdding: .day, value: 30, to: Date())!
            let lessons = await fetchTimetable(iss: iss, from: start, to: end)
            for l in lessons { names.insert(l.subject) }
        }
        // Szándékosan NINCS cached-union: a cache demo-módból szennyezett lehet,
        // a hívó (GradesView) külön fűzi hozzá megjelenítéshez, mentéshez viszont
        // csak ez a hálózati lista megy.
        return names.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty && $0 != "Ismeretlen" }.sorted()
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

    /// Valódi institut-kód-e (pl. klik035454001)? URL-t, "unknown"-t,
    /// szóközt/pontot tartalmazó szemetet elutasít — a refresh-bodyba
    /// ilyen sosem kerülhet, mert az IDP biztosan eldobná.
    static func validInstituteCode(_ s: String?) -> String? {
        guard let t = s?.trimmingCharacters(in: .whitespacesAndNewlines), !t.isEmpty else { return nil }
        guard t.lowercased() != "unknown", !t.contains("://"), !t.contains("/"), !t.contains(" "), !t.contains(".") else { return nil }
        return t
    }
}
