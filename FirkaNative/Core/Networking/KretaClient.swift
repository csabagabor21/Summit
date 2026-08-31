import Foundation

@MainActor
final class KretaClient: ObservableObject {
    var accessToken: String?
    var refreshToken: String?
    var userAgent: String = "eKretaStudent/264745 CFNetwork/1494.0.7 Darwin/23.4.0"

    private let session: URLSession = {
        let c = URLSessionConfiguration.default
        c.timeoutIntervalForRequest = 20
        c.timeoutIntervalForResource = 30
        return URLSession(configuration: c)
    }()

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
        return decoded
    }

    func get<T: Decodable>(_ url: URL) async throws -> T {
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
        if http.statusCode == 401 { throw KretaError.unauthorized }
        guard 200..<300 ~= http.statusCode else { throw KretaError.http(http.statusCode, String(data: data, encoding: .utf8)) }
        return try JSONDecoder().decode(T.self, from: data)
    }

    func getRaw(_ url: URL) async throws -> Data {
        var req = URLRequest(url: url)
        if let t = accessToken { req.setValue("Bearer \(t)", forHTTPHeaderField: "authorization") }
        req.setValue(userAgent, forHTTPHeaderField: "user-agent")
        let (data, resp) = try await session.data(for: req)
        guard let http = resp as? HTTPURLResponse, 200..<300 ~= http.statusCode else { throw KretaError.network }
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
