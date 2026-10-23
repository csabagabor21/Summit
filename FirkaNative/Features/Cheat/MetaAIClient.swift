import Foundation
import Security
import UIKit
import PDFKit

// MARK: - Meta AI kulcstár
// A kulcs a Keychainben él (ezen az eszközön, első feloldás után
// olvashatóan), és a SummitSync `metaAIKey` mezőjében — végponttól
// végpontig titkosítva — megy át a többi eszközre; az órára a
// WatchConnectivity-context tolja át (WatchSyncSender.pushMetaKeyNow +
// minden push). A user később kapja meg a kulcsot: addig a jegyzetek
// kézzel is felvehetők, a generálás a kulcs megadásakor élesedik.
enum MetaAIKeyStore {
    /// Régi, nyílt UserDefaults-kulcs — csak az átálláshoz és az
    /// aláíratlan (Keychain-entitlement nélküli) Mac-build tartalékaként.
    static let key = "summit.metaAIKey.v1"
    static let changedNotification = Notification.Name("summit.metaAIKeyChanged")
    private static let keychainService = "hu.flint.summit.metaai"
    private static let keychainAccount = "apiKey"
    private static let installedKey = "summit.metaAIKey.keychain.installed.v1"

    private static let lock = NSLock()
    nonisolated(unsafe) private static var cache: String?

    static var apiKey: String {
        lock.lock()
        defer { lock.unlock() }
        if let cache { return cache }
        let value = loadAndMigrate()
        cache = value
        return value
    }
    static var hasKey: Bool { !apiKey.isEmpty }

    static func save(_ k: String) {
        let clean = k.trimmingCharacters(in: .whitespacesAndNewlines)
        lock.lock()
        store(clean)
        cache = clean
        lock.unlock()
        NotificationCenter.default.post(name: changedNotification, object: nil)
        // Azonnal átmegy az órára is — onnantól az óra a saját netjén,
        // a telefon nélkül kérdezhet (WatchSyncSender.pushMetaKeyNow).
        WatchSyncSender.pushMetaKeyNow()
    }
    static func clear() { save("") }

    /// Keychain → (átállás) régi UserDefaults. A Keychain túléli az app
    /// törlését: friss telepítéskor a régi telepítés kulcsa törlődik.
    private static func loadAndMigrate() -> String {
        let defaults = UserDefaults.standard
        let legacy = defaults.string(forKey: key)?.trimmingCharacters(in: .whitespacesAndNewlines)
        if !defaults.bool(forKey: installedKey) {
            if legacy == nil { KeychainHelper.delete(service: keychainService, account: keychainAccount) }
            defaults.set(true, forKey: installedKey)
        }
        // A nyílt másolat, ha létezik, a frissebb (átállás előtt, vagy egy
        // régebbi build írta vissza) — átköltözik, és a nyílt példány törlődik.
        if let legacy {
            store(legacy)
            return legacy
        }
        if let d = KeychainHelper.load(service: keychainService, account: keychainAccount),
           let s = String(data: d, encoding: .utf8) {
            return s
        }
        return ""
    }

    /// Üres kulcs = törlés. Sikeres Keychain-írás után a nyílt másolat
    /// törlődik; ha a Keychain nem érhető el (aláíratlan Mac), az marad.
    private static func store(_ value: String) {
        if value.isEmpty {
            KeychainHelper.delete(service: keychainService, account: keychainAccount)
            UserDefaults.standard.removeObject(forKey: key)
            return
        }
        let status = KeychainHelper.save(Data(value.utf8), service: keychainService, account: keychainAccount,
                                         accessible: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly)
        if status == errSecSuccess {
            UserDefaults.standard.removeObject(forKey: key)
        } else {
            UserDefaults.standard.set(value, forKey: key)
        }
    }
}

// MARK: - Közös Gemini-tartalék saját kulcs nélkül (worker-proxy)
// A Gemini-kulcs SOHA nem kerül az eszközre: a Summit Cloudflare-worker
// (`/ai/generate`) tartja secretként, és csak érvényes App Check tokennel
// (valódi, módosítatlan app) továbbítja a kérést a Gemini natív
// `generateContent` végpontjára. A modellt is a worker választja
// (`GEMINI_MODEL`), a kliens nem írhatja felül — így egy kiszivárgott
// token sem költheti drágább modellre a közös keretet.
// Korábban a kulcs a mindenki által olvasható `public/ai_fallback`
// Firestore-docból jött, és az eszköz el is tárolta — a régi
// gyorsítótárat a `purgeLegacyCache()` induláskor törli.
enum GeminiFallback {
    @MainActor static var endpoint: URL? {
        guard SummitPushSync.isConfigured else { return nil }
        return URL(string: SummitPushSync.baseURL + "/ai/generate")
    }

    /// A régi appverziók által eltárolt (azóta visszavont) kulcs és modell
    /// törlése. Idempotens, minden indításkor hívható.
    static func purgeLegacyCache() {
        UserDefaults.standard.removeObject(forKey: "summit.geminiFallbackKey.v1")
        UserDefaults.standard.removeObject(forKey: "summit.geminiFallbackModel.v1")
    }

    /// Gemini natív kérés-törzs: rendszerutasítás + egy user-üzenet
    /// (szöveg + JPEG-képek inline), JSON-válaszmóddal.
    static func requestBody(system: String, prompt: String, imageDataURLs: [String]) -> [String: Any] {
        var parts: [[String: Any]] = [["text": prompt]]
        for url in imageDataURLs {
            guard let comma = url.firstIndex(of: ","), url.hasPrefix("data:") else { continue }
            let header = url[url.index(url.startIndex, offsetBy: 5)..<comma]
            let mime = header.split(separator: ";").first.map(String.init) ?? "image/jpeg"
            parts.append(["inlineData": ["mimeType": mime, "data": String(url[url.index(after: comma)...])]])
        }
        return [
            "systemInstruction": ["parts": [["text": system]]],
            "contents": [["role": "user", "parts": parts]],
            "generationConfig": ["temperature": 0.3, "responseMimeType": "application/json"],
        ]
    }

    struct WirePart: Decodable { var text: String? }
    struct WireContent: Decodable { var parts: [WirePart]? }
    struct WireCandidate: Decodable { var content: WireContent? }
    struct WireResp: Decodable { var candidates: [WireCandidate]? }

    /// A válasz első jelöltjének szövege (a részek összefűzve).
    static func content(from data: Data) -> String? {
        guard let resp = try? JSONDecoder().decode(WireResp.self, from: data),
              let parts = resp.candidates?.first?.content?.parts else { return nil }
        let text = parts.compactMap(\.text).joined()
        return text.isEmpty ? nil : text
    }
}

// MARK: - Meta AI kliens (Meta Model API, OpenAI-kompatibilis, multimodális)
// A feltöltött anyagok TELJES tartalmából csinál témánkénti jegyzetet
// (nincs karaktersáv): szöveg + pdf-oldalak képként + fotók.
// Minden téma egy cím + szöveges bejegyzés. A válasz JSON, amit a
// kliens CheatTopic-fává alakít; a user a lapon utólag szerkesztheti.
// Saját Meta-kulcs nélkül a közös, ingyenes Gemini-tartalék dolgozik a
// Summit-workeren át (gyenge!) — saját kulccsal a Meta-végpont.
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
        /// A közös tartalék-proxy elutasította az app-igazolást (App Check)
        /// vagy nincs beállítva a szerveren.
        case fallbackUnavailable
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
            case .fallbackUnavailable: return "A közös AI most nem érhető el — frissítsd az appot, vagy adj meg saját Meta AI-kulcsot."
            }
        }
    }

    /// Témajegyzékek generálása az anyagok szövegéből.
    static func generateTopics(subject: String, title: String, materials: [CheatMaterial]) async throws -> [CheatTopic] {
        // Szolgáltató-választás: saját kulcs → Meta, különben a közös
        // Gemini-tartalék a Summit-workeren át (ha az sem érhető el,
        // nincs generálás).
        let metaKey = MetaAIKeyStore.apiKey
        let useMeta = !metaKey.isEmpty
        let fallbackURL = await GeminiFallback.endpoint
        guard useMeta || fallbackURL != nil else { throw AIError.noKey }
        // TELJES szöveg a lemez-tárból (nincs 15k/24k vágás) — a
        // UserDefaults-beli vágott másolat csak tartalék régi anyagokhoz.
        let corpus = materials.map { CheatStore.fullText(id: $0.id) ?? $0.text }
            .joined(separator: "\n\n").trimmingCharacters(in: .whitespacesAndNewlines)
        // Képek: pdf-oldalak rasterizálva + feltöltött fotók (multimodális).
        let imageURLs = Self.imageDataURLs(for: materials)
        guard !corpus.isEmpty || !imageURLs.isEmpty else { throw AIError.noMaterial }
        let prompt = """
        Tantárgy: \(subject). Témakör: \(title).
        Az alábbi tananyagból készíts tanulható jegyzetet magyarul.
        Bontsd 3-8 témára (pl. életrajz, fő művek, elemzés).
        TARTALOM: semmit ne hagyj ki — ami az anyagban benne van, az
        mind kerüljön bele, annyira szóról szóra, amennyire csak lehet.
        Ne rövidíts, ne foglalj össze, ne hagyj el részleteket. A te dolgod
        CSAK a tagolás: a teljes szöveget tedd áttekinthető, tanulható formába.
        A csatolt KÉPEKEN látható tartalmat (ábrák, képletek, táblázatok,
        szkennelt oldalak) ugyanígy dolgozd bele a jegyzetbe.
        FORMÁZÁS (kötelező, Markdown): a body SOHA nem lehet egybefüggő
        szövegtömb — tagold bekezdésekre, és MINDEN bekezdés, cím és lista
        között pontosan egy üres sor legyen. Használj ### alcímeket
        és - felsorolást, ahol illik. Ne találj ki semmit, csak az anyagban
        szereplő tényeket használd.
        Válaszolj KIZÁRÓLAG érvényes JSON-nal, semmi mással:
        {"topics":[{"title":"...","body":"..."}]}

        TANANYAG:
        \(corpus)
        """
        let system = "Magyar nyelvű tanulójegyzet-készítő vagy. Mindig csak érvényes JSON-t válaszolsz."
        let body: [String: Any]
        if useMeta {
            // Multimodális user-üzenet: szöveg + képek (pdf-oldalak, fotók).
            // Kép nélkül marad a sima string-alak (régi viselkedés).
            var userContent: Any = prompt
            if !imageURLs.isEmpty {
                var parts: [[String: Any]] = [["type": "text", "text": prompt]]
                parts += imageURLs.map { ["type": "image_url", "image_url": ["url": $0]] }
                userContent = parts
            }
            body = [
                "model": Self.model,
                "messages": [
                    ["role": "system", "content": system],
                    ["role": "user", "content": userContent],
                ],
                "temperature": 0.3,
            ]
        } else {
            body = GeminiFallback.requestBody(system: system, prompt: prompt, imageDataURLs: imageURLs)
        }
        guard let httpBody = try? JSONSerialization.data(withJSONObject: body) else { throw AIError.badResponse }
        // Durva plafon: ~20 MB kérés fölött inkább érthető hiba, mint lógás
        // (a worker is ennyit enged át).
        guard httpBody.count < 20_000_000 else {
            throw AIError.network("Az anyag képekkel együtt túl nagy (\(httpBody.count / 1_000_000) MB) — vegyél ki oldalakat, és próbáld újra.")
        }
        var req: URLRequest
        if useMeta {
            req = URLRequest(url: Self.endpoint)
            req.setValue("Bearer \(metaKey)", forHTTPHeaderField: "Authorization")
        } else if let fallbackURL {
            req = URLRequest(url: fallbackURL)
            await SummitAppCheck.attach(to: &req)
        } else {
            throw AIError.noKey
        }
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = httpBody
        req.timeoutInterval = 180
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
        // Worker: 401 = App Check elutasítva, 503 = nincs beállítva a
        // proxy, 413 = túl nagy kérés. Ezek nem a user kulcsának hibái.
        if !useMeta {
            if status == 401 || status == 503 { throw AIError.fallbackUnavailable }
            if status == 413 { throw AIError.network("Az anyag képekkel együtt túl nagy — vegyél ki oldalakat, és próbáld újra.") }
        }
        guard status == 200 else { throw AIError.badStatus(status) }
        let content = useMeta ? Self.chatContent(from: data) : GeminiFallback.content(from: data)
        guard let content, let topics = Self.parseTopics(fromContent: content), !topics.isEmpty else {
            throw AIError.badResponse
        }
        return topics
    }

    // MARK: - Multimodális képek (pdf-oldalak + fotók)

    /// Minden anyaghoz a képi tartalom data-URL-ként: pdf-nél MINDEN
    /// oldal rasterizálva (a modell a teljes pdf-et látja), fotónál az
    /// eredeti kép leskálázva. Üres = tisztán szöveges kérés.
    static func imageDataURLs(for materials: [CheatMaterial]) -> [String] {
        var out: [String] = []
        for m in materials {
            if m.isPDF, let pdf = CheatStore.pdfData(id: m.id), !pdf.isEmpty {
                out += jpegDataURLs(fromPDF: pdf)
            } else if m.isImage, let data = CheatStore.imageData(id: m.id),
                      let url = jpegDataURL(fromImageData: data, maxSide: 1568) {
                out.append(url)
            }
        }
        return out
    }

    /// PDF összes oldala → JPEG data-URL (fehér háttér, max 1536px).
    static func jpegDataURLs(fromPDF data: Data, maxSide: CGFloat = 1536) -> [String] {
        guard let doc = PDFDocument(data: data) else { return [] }
        var out: [String] = []
        for i in 0..<doc.pageCount {
            guard let page = doc.page(at: i) else { continue }
            let box = page.bounds(for: .mediaBox)
            guard box.width > 0, box.height > 0 else { continue }
            let k = min(1, maxSide / max(box.width, box.height))
            let size = CGSize(width: box.width * k, height: box.height * k)
            let renderer = UIGraphicsImageRenderer(size: size)
            let img = renderer.image { ctx in
                UIColor.white.setFill()
                ctx.fill(CGRect(origin: .zero, size: size))
                page.draw(with: .mediaBox, to: ctx.cgContext)
            }
            if let jpg = img.jpegData(compressionQuality: 0.65) {
                out.append("data:image/jpeg;base64,\(jpg.base64EncodedString())")
            }
        }
        return out
    }

    /// Fotó → leskálázott JPEG data-URL.
    static func jpegDataURL(fromImageData data: Data, maxSide: CGFloat = 1568) -> String? {
        guard let ui = UIImage(data: data) else { return nil }
        let s = max(ui.size.width, ui.size.height)
        let img: UIImage
        if s > maxSide, s > 0 {
            let k = maxSide / s
            let ns = CGSize(width: ui.size.width * k, height: ui.size.height * k)
            img = UIGraphicsImageRenderer(size: ns).image { _ in
                ui.draw(in: CGRect(origin: .zero, size: ns))
            }
        } else {
            img = ui
        }
        guard let jpg = img.jpegData(compressionQuality: 0.8) else { return nil }
        return "data:image/jpeg;base64,\(jpg.base64EncodedString())"
    }

    // MARK: - Válaszfejtés

    struct WireTopic: Decodable { var title: String; var body: String }
    struct WireRoot: Decodable { var topics: [WireTopic] }
    struct WireChoiceMsg: Decodable { var content: String? }
    struct WireChoice: Decodable { var message: WireChoiceMsg? }
    struct WireResp: Decodable { var choices: [WireChoice]? }

    /// OpenAI-kompatibilis chat-válasz (Meta) első üzenetének szövege.
    static func chatContent(from data: Data) -> String? {
        guard let resp = try? JSONDecoder().decode(WireResp.self, from: data),
              let content = resp.choices?.first?.message?.content,
              !content.isEmpty else { return nil }
        return content
    }

    static func parseTopics(fromContent content: String) -> [CheatTopic]? {
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
