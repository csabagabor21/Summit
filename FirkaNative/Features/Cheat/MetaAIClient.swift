import Foundation

// MARK: - Meta AI kulcstár
// A kulcs UserDefaults-ban él, és a SummitSync `metaAIKey` mezőjében
// átmegy a többi eszközre (az órára sosem kerül át). A user később
// kapja meg a kulcsot: addig a jegyzetek kézzel is felvehetők,
// a generálás a kulcs megadásakor élesedik.
enum MetaAIKeyStore {
    static let key = "summit.metaAIKey.v1"
    static let changedNotification = Notification.Name("summit.metaAIKeyChanged")

    static var apiKey: String {
        (UserDefaults.standard.string(forKey: key) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    }
    static var hasKey: Bool { !apiKey.isEmpty }

    static func save(_ k: String) {
        UserDefaults.standard.set(k.trimmingCharacters(in: .whitespacesAndNewlines), forKey: key)
        NotificationCenter.default.post(name: changedNotification, object: nil)
    }
    static func clear() { save("") }
}

// MARK: - Közös Gemini-tartalék saját kulcs nélkül (Firebase-ből)
// A kulcs NINCS az appba égetve: futásidőben jön a Firestore
// `public/ai_fallback` docból (`geminiKey` + `geminiModel` stringmezők —
// bárki olvashatja, senki nem írhatja, rotálás = doc-csere konzolból).
// Direkt a legolcsóbb free-tier modell jár hozzá (gyenge minőség!) —
// saját Meta AI-kulccsal a rendes Meta-végpont dolgozik helyette.
// Offline-ra az utolsó ismert érték gyorsítótárazva van.
enum GeminiFallback {
    static let projectId = "summit-14b74"
    /// Firestore-olvasáshoz (publikus doc, lásd a többi REST-hívást).
    static let restKey = "AIzaSyA1TttM0aUUHsvjjAItYMbdID_no1vzg9s"
    static let docId = "ai_fallback"
    /// Alapértelmezett modell, ha a docban nincs más: a legolcsóbb
    /// free-tieres lite (direkt gyenge) — a modellnév a docból
    /// felülírható, appfrissítés nélkül.
    static let defaultModel = "gemini-3.5-flash-lite"
    /// Gemini OpenAI-kompatibilis chat-végpont (ugyanaz a kérés/alak,
    /// mint a Meta-klón — `Authorization: Bearer <API-kulcs>`).
    static let endpoint = URL(string: "https://generativelanguage.googleapis.com/v1beta/openai/chat/completions")!

    struct Config { var key: String; var model: String }
    private static var mem: Config?
    private static let keyCacheKey = "summit.geminiFallbackKey.v1"
    private static let modelCacheKey = "summit.geminiFallbackModel.v1"

    static func config() async -> Config? {
        if let m = mem, !m.key.isEmpty { return m }
        if let doc = await fetchDoc(), let k = doc["geminiKey"], !k.isEmpty {
            let rawModel = doc["geminiModel"]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let c = Config(key: k, model: rawModel.isEmpty ? defaultModel : rawModel)
            mem = c
            UserDefaults.standard.set(c.key, forKey: keyCacheKey)
            UserDefaults.standard.set(c.model, forKey: modelCacheKey)
            return c
        }
        // Offline: utolsó ismert érték (a tartalék attól még élhet).
        if let k = UserDefaults.standard.string(forKey: keyCacheKey), !k.isEmpty {
            let c = Config(key: k, model: UserDefaults.standard.string(forKey: modelCacheKey) ?? defaultModel)
            mem = c
            return c
        }
        return nil
    }

    static func forgetCache() {
        mem = nil
        UserDefaults.standard.removeObject(forKey: keyCacheKey)
        UserDefaults.standard.removeObject(forKey: modelCacheKey)
    }

    private static func fetchDoc() async -> [String: String]? {
        guard let url = URL(string: "https://firestore.googleapis.com/v1/projects/\(projectId)/databases/(default)/documents/public/\(docId)?key=\(restKey)") else { return nil }
        var req = URLRequest(url: url)
        req.timeoutInterval = 15
        guard let (data, resp) = try? await URLSession.shared.data(for: req),
              (resp as? HTTPURLResponse)?.statusCode == 200,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let fields = json["fields"] as? [String: Any] else { return nil }
        var out: [String: String] = [:]
        for (k, v) in fields {
            if let s = (v as? [String: String])?["stringValue"] { out[k] = s }
        }
        return out
    }
}

// MARK: - Meta AI kliens (Meta Model API, OpenAI-kompatibilis)
// A feltöltött anyagok szövegéből csinál témánkénti jegyzetet:
// minden téma egy cím + szöveges bejegyzés. A válasz JSON, amit a
// kliens CheatTopic-fává alakít; a user a lapon utólag szerkesztheti.
// Saját Meta-kulcs nélkül a Firebase-ből jövő közös, ingyenes
// Gemini-tartalék dolgozik (gyenge!) — saját kulccsal a Meta-végpont.
enum MetaAIClient {
    /// Meta Model API, OpenAI-kompatibilis chat-végpont.
    /// MINDIG a contributor-tier: muse-spark-1.3-contributor.
    static let endpoint = URL(string: "https://api.meta.ai/v1/chat/completions")!
    static let model = "muse-spark-1.3-contributor"

    enum AIError: LocalizedError {
        case noKey
        case noMaterial
        case network(String)
        case badStatus(Int)
        case rateLimited
        case badResponse
        var errorDescription: String? {
            switch self {
            case .noKey: return "Nincs AI-elérés — ellenőrizd a netet, vagy adj meg saját Meta AI-kulcsot."
            case .noMaterial: return "Nincs anyag a lapon — tölts fel jegyzetet a generáláshoz."
            case .network(let m): return "Hálózati hiba: \(m)"
            case .badStatus(let c): return c == 401 || c == 403
                ? "A kulcsot elutasították (401/403) — ellenőrizd a Meta AI-kulcsot."
                : "Az AI hibát adott (\(c)) — próbáld újra később."
            case .rateLimited: return "A közös ingyenes keret épp betelt (429) — próbáld később, vagy adj meg saját Meta AI-kulcsot."
            case .badResponse: return "Értelmezhetetlen válasz érkezett — próbáld újra."
            }
        }
    }

    /// Témajegyzékek generálása az anyagok szövegéből.
    static func generateTopics(subject: String, title: String, materials: [CheatMaterial]) async throws -> [CheatTopic] {
        // Szolgáltató-választás: saját kulcs → Meta, különben a közös
        // Firebase-es Gemini-tartalék (ha az sem érhető el, nincs generálás).
        let target: URL
        let targetModel: String
        let authKey: String
        if MetaAIKeyStore.hasKey {
            target = Self.endpoint
            targetModel = Self.model
            authKey = MetaAIKeyStore.apiKey
        } else {
            guard let fb = await GeminiFallback.config() else { throw AIError.noKey }
            target = GeminiFallback.endpoint
            targetModel = fb.model
            authKey = fb.key
        }
        let corpus = materials.map(\.text).joined(separator: "\n\n").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !corpus.isEmpty else { throw AIError.noMaterial }
        // A modellablak védelme: az eleje (tananyag) számít, a vége vágható.
        let clipped = String(corpus.prefix(24_000))
        let prompt = """
        Tantárgy: \(subject). Témakör: \(title).
        Az alábbi tananyagból készíts tanulható jegyzetet magyarul.
        Bontsd 3-8 témára (pl. életrajz, fő művek, elemzés).
        TARTALOM: semmit ne hagyj ki — ami az anyagban benne van, az
        mind kerüljön bele, annyira szóról szóra, amennyire csak lehet.
        Ne rövidíts, ne foglalj össze, ne hagyj el részleteket. A te dolgod
        CSAK a tagolás: a teljes szöveget tedd áttekinthető, tanulható formába.
        FORMÁZÁS (kötelező, Markdown): a body SOHA nem lehet egybefüggő
        szövegtömb — tagold bekezdésekre, és MINDEN bekezdés, cím és lista
        között pontosan egy üres sor legyen. Használj ### alcímeket
        és - felsorolást, ahol illik. Ne találj ki semmit, csak az anyagban
        szereplő tényeket használd.
        Válaszolj KIZÁRÓLAG érvényes JSON-nal, semmi mással:
        {"topics":[{"title":"...","body":"..."}]}

        TANANYAG:
        \(clipped)
        """
        let body: [String: Any] = [
            "model": targetModel,
            "messages": [
                ["role": "system", "content": "Magyar nyelvű tanulójegyzet-készítő vagy. Mindig csak érvényes JSON-t válaszolsz."],
                ["role": "user", "content": prompt],
            ],
            "temperature": 0.3,
        ]
        var req = URLRequest(url: target)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("Bearer \(authKey)", forHTTPHeaderField: "Authorization")
        req.httpBody = try? JSONSerialization.data(withJSONObject: body)
        req.timeoutInterval = 90
        let data: Data
        let status: Int
        do {
            let (d, resp) = try await URLSession.shared.data(for: req)
            data = d
            status = (resp as? HTTPURLResponse)?.statusCode ?? -1
        } catch {
            throw AIError.network(error.localizedDescription)
        }
        // A közös tartalék-keret kimerülése külön, érthető üzenetet kap
        // (429) — ilyenkor a saját kulcs a kiút.
        if status == 429 { throw AIError.rateLimited }
        guard status == 200 else { throw AIError.badStatus(status) }
        guard let topics = Self.parseTopics(from: data), !topics.isEmpty else { throw AIError.badResponse }
        return topics
    }

    // MARK: - Válaszfejtés

    struct WireTopic: Decodable { var title: String; var body: String }
    struct WireRoot: Decodable { var topics: [WireTopic] }
    struct WireChoiceMsg: Decodable { var content: String? }
    struct WireChoice: Decodable { var message: WireChoiceMsg? }
    struct WireResp: Decodable { var choices: [WireChoice]? }

    static func parseTopics(from data: Data) -> [CheatTopic]? {
        guard let resp = try? JSONDecoder().decode(WireResp.self, from: data),
              let content = resp.choices?.first?.message?.content,
              !content.isEmpty else { return nil }
        // A modell néha ```json kerítésbe teszi — azt lefejtjük.
        let json = Self.stripFences(content)
        guard let jdata = json.data(using: .utf8),
              let root = try? JSONDecoder().decode(WireRoot.self, from: jdata),
              !root.topics.isEmpty else { return nil }
        return root.topics.map { CheatTopic(title: $0.title, body: CheatTopic.normalizedBody($0.body)) }
    }

    static func stripFences(_ s: String) -> String {
        let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
        guard t.hasPrefix("```") else { return t }
        var lines = t.components(separatedBy: "\n")
        if lines.first?.hasPrefix("```") == true { lines.removeFirst() }
        if lines.last?.trimmingCharacters(in: .whitespaces) == "```" { lines.removeLast() }
        return lines.joined(separator: "\n")
    }
}
