import Foundation

// MARK: - SummitCheat modellek (tanulójegyzetek dolgozatonként)
// Egy "lap" (CheatSheet) egy dolgozathoz / témakörhöz tartozik
// (pl. "Babits Mihály"): feltöltött anyagok + azokból készült
// (Meta AI-val generált vagy kézzel írt) jegyzetek, témánként
// egy-egy bejegyzéssel (cím + szöveg). Nincs mélyebb szint: a
// témalista elemei maguk a jegyzetek — koppintásra a szöveg nyílik.
// Az óra a dolgozat → téma úton mutatja őket.
struct CheatTopic: Codable, Identifiable, Hashable {
    var id: String
    var title: String
    var body: String

    init(id: String = UUID().uuidString, title: String, body: String = "") {
        self.id = id
        self.title = title
        self.body = body
    }

    enum CodingKeys: String, CodingKey {
        case id, title, body, subtopics
    }

    /// Régi (kétszintű) tárolás átköltöztetése: ha a `body` még nincs
    /// meg, az altémákat `## Alcím` fejlécekkel összefűzve vesszük át —
    /// a user meglévő jegyzetei (pl. "Baby", "Retell") nem vesznek el.
    struct LegacySub: Decodable {
        var title: String
        var body: String
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(String.self, forKey: .id) ?? UUID().uuidString
        title = try c.decodeIfPresent(String.self, forKey: .title) ?? ""
        if let b = try c.decodeIfPresent(String.self, forKey: .body), !b.isEmpty {
            body = b
        } else {
            let subs = (try? c.decodeIfPresent([LegacySub].self, forKey: .subtopics)) ?? []
            body = subs.map { "## \($0.title)\n\($0.body)" }.joined(separator: "\n\n")
        }
    }

    /// Kódoláskor csak az élő mezők mennek (a `subtopics` kizárólag a
    /// régi tárolás beolvasásához létezik a kulcsok között).
    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(title, forKey: .title)
        try c.encode(body, forKey: .body)
    }

    // MARK: - Törzsszöveg-normalizálás (AI-fegyelmezés)
    // A gyenge modellek néha egybefüggő faltömböt adnak vissza (nincs
    // üres sor, néhol a szóköz is lemarad: "címmel.A", "fordítás1913-ban"
    // — lásd watch-screenshot). Ezt javítjuk, nem a modellt fegyelmezzük:
    // a meglévő Markdown-szerkezetet (üres sorok, címsorok, listák)
    // sosem bántjuk, csak a hosszú, sortörés nélküli tömböket tördeljük
    // mondathatáronként bekezdésekre. FIXPONT (idempotens): load() és
    // cap() is hívja, az újrafuttatás ugyanazt adja.
    static func normalizedBody(_ s: String) -> String {
        var t = s.replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        // Lelmaradt szóközök: írásjel + nagybetű/szám ("címmel.A"),
        // illetve szó + évszám/szám ("fordítás1913-ban"). A vegyjeleket
        // (H2O, B2) nem bántjuk — csak 3-4 jegyű számot választunk le.
        t = Self.replacing(t, pattern: "([.!?:;])([A-ZÁÉÍÓÖŐÚÜŰ0-9])", with: "$1 $2")
        t = Self.replacing(t, pattern: "([a-záéíóöőúüű])(\\d{3,4})", with: "$1 $2")
        // 3+ sortörés → 1 üres sor, magányos sortörés → üres sor.
        // (A modell gyakran szimpla \n-ekkel tördel — a Markdown azt
        // egybefolyatja, csak az üres sor ad valódi bekezdésnyi lukat.)
        t = Self.replacing(t, pattern: "\n{3,}", with: "\n\n")
        t = Self.replacing(t, pattern: "(?<!\n)\n(?!\n)", with: "\n\n")
        t = t.trimmingCharacters(in: .whitespacesAndNewlines)
        var out: [String] = []
        for block in t.components(separatedBy: "\n\n") {
            let b = block.trimmingCharacters(in: .whitespacesAndNewlines)
            if b.isEmpty { continue }
            if !b.contains("\n"), b.count > 350, !Self.isMarkdownLine(b) {
                out.append(contentsOf: Self.paragraphs(from: b))
            } else {
                out.append(b)
            }
        }
        return out.joined(separator: "\n\n")
    }

    /// Markdown-szerkezetű sor (címsor, lista, idézet): tördelni tilos.
    private static func isMarkdownLine(_ s: String) -> Bool {
        let t = s.trimmingCharacters(in: .whitespaces)
        if t.hasPrefix("#") || t.hasPrefix(">") || t.hasPrefix("- ") ||
            t.hasPrefix("* ") || t.hasPrefix("+ ") { return true }
        if t.range(of: #"^\d+[.)]\s"#, options: .regularExpression) != nil { return true }
        return false
    }

    /// Hosszú tömb → max ~300 karakteres bekezdések mondathatárokon.
    private static func paragraphs(from block: String) -> [String] {
        let sentences = Self.split(block,
            pattern: #"(?<=[.!?…])\s+(?=[A-ZÁÉÍÓÖŐÚÜŰ"„(\d])"#)
        guard sentences.count > 1 else { return [block] }
        var paras: [String] = []
        var cur = ""
        for s in sentences {
            if cur.isEmpty { cur = s }
            else if cur.count + 1 + s.count <= 300 { cur += " " + s }
            else { paras.append(cur); cur = s }
        }
        if !cur.isEmpty { paras.append(cur) }
        return paras.isEmpty ? [block] : paras
    }

    private static func replacing(_ s: String, pattern: String, with template: String) -> String {
        guard let re = try? NSRegularExpression(pattern: pattern) else { return s }
        return re.stringByReplacingMatches(in: s, range: NSRange(s.startIndex..., in: s), withTemplate: template)
    }

    private static func split(_ s: String, pattern: String) -> [String] {
        guard let re = try? NSRegularExpression(pattern: pattern) else { return [s] }
        let range = NSRange(s.startIndex..., in: s)
        var out: [String] = []
        var last = s.startIndex
        for m in re.matches(in: s, range: range) {
            guard let r = Range(m.range, in: s) else { continue }
            out.append(String(s[last..<r.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines))
            last = r.upperBound
        }
        out.append(String(s[last...]).trimmingCharacters(in: .whitespacesAndNewlines))
        return out.filter { !$0.isEmpty }
    }
}

struct CheatMaterial: Codable, Identifiable, Hashable {
    var id: String
    var name: String
    var text: String
    var addedAt: Date
    /// Forrásfajta: "pdf" / "image" / nil (txt, md és régi adatok).
    /// Hiányzó kulcs = régi tárolás = sima szöveg — a dekódolás nem törik.
    var kind: String?

    init(id: String = UUID().uuidString, name: String, text: String, addedAt: Date = Date(), kind: String? = nil) {
        self.id = id
        self.name = name
        self.text = text
        self.addedAt = addedAt
        self.kind = kind
    }

    var isPDF: Bool { kind == "pdf" }
    var isImage: Bool { kind == "image" }
}

struct CheatSheet: Codable, Identifiable, Hashable {
    var id: String
    /// Kapcsolt dolgozat KRÉTA/custom ID-ja (opcionális — lehet
    /// dolgozat nélküli, csak tárgyhoz kötött gyűjtő is).
    var examId: String?
    var subject: String
    /// Megnevezés (pl. "Babits Mihály", "Témazáró – Egyenletek").
    var title: String
    var date: Date?
    var materials: [CheatMaterial]
    var topics: [CheatTopic]
    var updatedAt: Date

    init(id: String = UUID().uuidString, examId: String? = nil, subject: String,
         title: String, date: Date? = nil, materials: [CheatMaterial] = [],
         topics: [CheatTopic] = [], updatedAt: Date = Date()) {
        self.id = id
        self.examId = examId
        self.subject = subject
        self.title = title
        self.date = date
        self.materials = materials
        self.topics = topics
        self.updatedAt = updatedAt
    }
}
