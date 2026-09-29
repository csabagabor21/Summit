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
}

struct CheatMaterial: Codable, Identifiable, Hashable {
    var id: String
    var name: String
    var text: String
    var addedAt: Date

    init(id: String = UUID().uuidString, name: String, text: String, addedAt: Date = Date()) {
        self.id = id
        self.name = name
        self.text = text
        self.addedAt = addedAt
    }
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
