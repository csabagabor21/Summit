import Foundation

@MainActor
final class KretaClient: ObservableObject {
    var accessToken: String?
    var refreshToken: String?
    var instituteCode: String?
    var userAgent: String = "eKretaStudent/264745 CFNetwork/1494.0.7 Darwin/23.4.0"
    /// SessionStore callback token frissítés után — FlintApp köti be
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

    // MARK: - Token refresh (2 lépcsős: újrapróbálja a kérést refresh után)
    func refreshTokens() async -> Bool {
        guard let rt = refreshToken, !rt.isEmpty else { return false }
        if isRefreshing {
            return await withCheckedContinuation { cont in refreshWaiters.append(cont) }
        }
        isRefreshing = true
        defer {
            isRefreshing = false
            let ok = accessToken != nil
            // minden várakozót felébresztünk
            let waiters = refreshWaiters; refreshWaiters = []
            for w in waiters { w.resume(returning: ok) }
        }
        // KRÉTA refresh-hez kell az institute_code (pl. ekreta docs: institute_code=xxx&refresh_token=...&grant_type=refresh_token&client_id=...)
        let iss = instituteCode ?? JWT.instituteCode(from: accessToken ?? "") ?? ""
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
            guard let http = resp as? HTTPURLResponse, http.statusCode == 200 else { return false }
            let decoded = try JSONDecoder().decode(TokenResponse.self, from: data)
            self.accessToken = decoded.access_token
            if let nr = decoded.refresh_token, !nr.isEmpty { self.refreshToken = nr }
            onTokensRefreshed?(decoded.access_token, decoded.refresh_token, decoded.expires_in)
            return true
        } catch { return false }
    }

    private func performGetData(_ url: URL) async throws -> (Data, HTTPURLResponse) {
        var req = URLRequest(url: url)
        req.httpMethod = "GET"
        if let t = accessToken { req.setValue("Bearer \(t)", forHTTPHeaderField: "authorization") }
        req.setValue(userAgent, forHTTPHeaderField: "user-agent")
        req.setValue("application/json", forHTTPHeaderField: "accept")
        if url.absoluteString.contains("kommunikacio/uzenetek") {
            req.setValue("hu-HU", forHTTPHeaderField: "X-Uzenet-Lokalizacio")
        }
        let (data, resp) = try await session.data(for: req)
        guard let http = resp as? HTTPURLResponse else { throw KretaError.network }
        return (data, http)
    }

    func get<T: Decodable>(_ url: URL) async throws -> T {
        var (data, http) = try await performGetData(url)
        if http.statusCode == 401 {
            if await refreshTokens() {
                (data, http) = try await performGetData(url)
                if http.statusCode == 401 { throw KretaError.unauthorized }
            } else {
                throw KretaError.unauthorized
            }
        }
        guard 200..<300 ~= http.statusCode else { throw KretaError.http(http.statusCode, String(data: data, encoding: .utf8)) }
        return try JSONDecoder().decode(T.self, from: data)
    }

    func getRaw(_ url: URL) async throws -> Data {
        var req = URLRequest(url: url)
        if let t = accessToken { req.setValue("Bearer \(t)", forHTTPHeaderField: "authorization") }
        req.setValue(userAgent, forHTTPHeaderField: "user-agent")
        var (data, resp) = try await session.data(for: req)
        guard var http = resp as? HTTPURLResponse else { throw KretaError.network }
        if http.statusCode == 401 {
            if await refreshTokens() {
                var retry = URLRequest(url: url)
                if let t = accessToken { retry.setValue("Bearer \(t)", forHTTPHeaderField: "authorization") }
                retry.setValue(userAgent, forHTTPHeaderField: "user-agent")
                (data, resp) = try await session.data(for: retry)
                guard let h2 = resp as? HTTPURLResponse else { throw KretaError.network }
                http = h2
                if http.statusCode == 401 { throw KretaError.unauthorized }
            } else {
                throw KretaError.unauthorized
            }
        }
        guard 200..<300 ~= http.statusCode else { throw KretaError.network }
        return data
    }

    // MARK: - Real data fetchers (used by HomeViewModel)
    func fetchGrades(iss: String) async -> [GradeItem] {
        do {
            let dtos: [KretaGradeDTO] = try await get(KretaAPI.grades(iss))
            return dtos.map { $0.toItem() }.sorted { $0.date > $1.date }
        } catch { return [] }
    }
    func fetchTimetable(iss: String, from: Date, to: Date) async -> [LessonItem] {
        do {
            let dtos: [KretaLessonDTO] = try await get(KretaAPI.timetable(iss, start: from, end: to))
            return dtos.compactMap { $0.toItem() }.sorted { $0.start < $1.start }
        } catch { return [] }
    }
    func fetchHomework(iss: String) async -> [HomeworkItem] {
        do {
            let dtos: [KretaHomeworkDTO] = try await get(KretaAPI.homework(iss))
            return dtos.map { $0.toItem() }.sorted { $0.deadline < $1.deadline }
        } catch { return [] }
    }
    func fetchAbsences(iss: String) async -> [AbsenceItem] {
        do {
            let dtos: [KretaAbsenceDTO] = try await get(KretaAPI.absences(iss))
            return dtos.map { $0.toItem() }.sorted { $0.date > $1.date }
        } catch { return [] }
    }
    func fetchExams(iss: String) async -> [ExamItem] {
        do {
            let dtos: [KretaExamDTO] = try await get(KretaAPI.exams(iss))
            return dtos.map { $0.toItem() }.sorted { $0.date < $1.date }
        } catch { return [] }
    }
    func fetchMessages() async -> [MessageItem] {
        // eugyintezes - try bejovo, then kimenő
        for endpoint in ["bejovo", "kimenő", "piszkozat"] {
            do {
                let dtos: [KretaMessageDTO] = try await get(KretaAPI.messages(endpoint))
                if !dtos.isEmpty { return dtos.map { $0.toItem() }.sorted { $0.date > $1.date } }
            } catch { continue }
        }
        return []
    }

    // MARK: - Tantárgyak — KRÉTA tudja akkor is ha nincs jegy (Atlagok + órarend fallback + cached)
    func fetchAllSubjectNames(iss: String) async -> [String] {
        var names = Set<String>()
        // 1) Tantárgyi átlagok — minden felvett tárgy, jegy nélkül is
        for url in [KretaAPI.subjectAverages(iss), KretaAPI.subjectAveragesAlt(iss)] {
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
        (payload(token)?["kreta:institute_code"] as? String) ?? (payload(token)?["iss"] as? String) ?? (payload(token)?["kreta:iss"] as? String)
    }
}
