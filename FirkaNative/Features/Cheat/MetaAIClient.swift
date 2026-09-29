import Foundation

// MARK: - Meta AI kulcstár
// A kulcs csak ezen az eszközön él (UserDefaults) — belépési adathoz
// hasonlóan a SummitSync-be SOHA nem kerül, az órára sem megy át.
// A user később kapja meg a kulcsot: addig a jegyzetek kézzel is
// felvehetők, a generálás a kulcs megadásakor élesedik.
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

// MARK: - Meta AI kliens (Llama API, OpenAI-kompatibilis)
// A feltöltött anyagok szövegéből csinál témánkénti jegyzetvázlatot:
// téma → altémák rövid, tanulható törzsekkel. A válasz JSON, amit a
// kliens CheatTopic-fává alakít; a user a lapon utólag szerkesztheti.
enum MetaAIClient {
    /// OpenAI-kompatibilis végpont a Llama API-n.
    static let endpoint = URL(string: "https://api.llama.com/compat/v1/chat/completions")!
    static let model = "Llama-4-Maverick-17B-128E-Instruct-FP8"

    enum AIError: LocalizedError {
        case noKey
        case noMaterial
        case network(String)
        case badStatus(Int)
        case badResponse
        var errorDescription: String? {
            switch self {
            case .noKey: return "Nincs Meta AI-kulcs — add meg a lapon a generáláshoz."
            case .noMaterial: return "Nincs anyag a lapon — tölts fel jegyzetet a generáláshoz."
            case .network(let m): return "Hálózati hiba: \(m)"
            case .badStatus(let c): return c == 401 || c == 403
                ? "A kulcsot elutasították (401/403) — ellenőrizd a Meta AI-kulcsot."
                : "A Meta AI hibát adott (\(c)) — próbáld újra később."
            case .badResponse: return "Értelmezhetetlen válasz érkezett — próbáld újra."
            }
        }
    }

    /// Témajegyzékek generálása az anyagok szövegéből.
    static func generateTopics(subject: String, title: String, materials: [CheatMaterial]) async throws -> [CheatTopic] {
        guard MetaAIKeyStore.hasKey else { throw AIError.noKey }
        let corpus = materials.map(\.text).joined(separator: "\n\n").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !corpus.isEmpty else { throw AIError.noMaterial }
        // A modellablak védelme: az eleje (tananyag) számít, a vége vágható.
        let clipped = String(corpus.prefix(24_000))
        let prompt = """
        Tantárgy: \(subject). Témakör: \(title).
        Az alábbi tananyagból készíts tömör, tanulható jegyzetvázlatot magyarul.
        Bontsd 3-8 témára, minden témán belül 2-6 altémára (pl. életrajz, fő művek, elemzés).
        Minden altémához írj 2-6 mondatos lényegre törő összefoglalót.
        Csak az anyagban szereplő tényeket használd, ne találj ki semmit.
        Válaszolj KIZÁRÓLAG érvényes JSON-nal, semmi mással:
        {"topics":[{"title":"...","subtopics":[{"title":"...","body":"..."}]}]}

        TANANYAG:
        \(clipped)
        """
        let body: [String: Any] = [
            "model": model,
            "messages": [
                ["role": "system", "content": "Magyar nyelvű tanulójegyzet-készítő vagy. Mindig csak érvényes JSON-t válaszolsz."],
                ["role": "user", "content": prompt],
            ],
            "temperature": 0.3,
        ]
        var req = URLRequest(url: endpoint)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("Bearer \(MetaAIKeyStore.apiKey)", forHTTPHeaderField: "Authorization")
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
        guard status == 200 else { throw AIError.badStatus(status) }
        guard let topics = Self.parseTopics(from: data), !topics.isEmpty else { throw AIError.badResponse }
        return topics
    }

    // MARK: - Válaszfejtés

    struct WireSub: Decodable { var title: String; var body: String }
    struct WireTopic: Decodable { var title: String; var subtopics: [WireSub] }
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
        return root.topics.map { t in
            CheatTopic(title: t.title, subtopics: t.subtopics.map {
                CheatSubtopic(title: $0.title, body: $0.body)
            })
        }
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
