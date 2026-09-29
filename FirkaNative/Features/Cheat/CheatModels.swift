import Foundation

// MARK: - SummitCheat modellek (tanulójegyzetek dolgozatonként)
// Egy "lap" (CheatSheet) egy dolgozathoz / témakörhöz tartozik
// (pl. "Babits Mihály"): feltöltött anyagok + azokból készült
// (Meta AI-val generált vagy kézzel írt) témánkénti jegyzetek.
// A témán belül altémák vannak (pl. "Életrajza", "Novellái") —
// az óra a dolgozat → téma → altéma úton mutatja őket.

struct CheatSubtopic: Codable, Identifiable, Hashable {
    var id: String
    var title: String
    var body: String

    init(id: String = UUID().uuidString, title: String, body: String = "") {
        self.id = id
        self.title = title
        self.body = body
    }
}

struct CheatTopic: Codable, Identifiable, Hashable {
    var id: String
    var title: String
    var subtopics: [CheatSubtopic]

    init(id: String = UUID().uuidString, title: String, subtopics: [CheatSubtopic] = []) {
        self.id = id
        self.title = title
        self.subtopics = subtopics
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
