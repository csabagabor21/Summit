import Foundation

// MARK: - Watch payload — shared iPhone ↔ Apple Watch
// WatchConnectivity applicationContext-ben utazik (iPhone tolja, az óra csak
// olvas — ezért az órán nincs bejelentkezés). Token, név, OM, e-mail SOHA:
// csak óracím, terem, tanár, időpont, jegyérték és kerekítési küszöbök.
// Az órarendi szelethez a widget snapshotját használjuk újra
// (TimetableWidgetStore.Snapshot — szintén shared fájl, mindkét target
// fordítja). Ez a fájl csak Foundationt importál, Catalyst-barát.
enum WatchPayloadKey {
    static let timetable = "watch.timetable.v1"
    static let grades = "watch.grades.v1"
    static let tasks = "watch.tasks.v1"
    /// Óra → iPhone szinkronkérés (megnyitáskor, ha az órai adat avult
    /// vagy hiányzik). Mindkét irány ugyanazt a kulcs-szótárat használja.
    static let request = "watch.requestSync.v1"
}

/// Jegy az órára — a GradeItem hordozható kivonata (lásd GradesView).
struct WatchGrade: Codable, Hashable, Identifiable {
    var id: String
    var subject: String
    var value: Int
    var valueText: String
    var date: Date
    var teacher: String
    var type: String
    var weight: Int
    var topic: String
}

/// Jegy-snapshot: tárgyak + jegyek + tantárgyi kerekítési küszöbök, hogy az
/// óra ugyanazt a kerekített értéket mutassa, mint a telefon (GradingLogic).
struct WatchGradesSnapshot: Codable {
    var savedAt: Date
    var accentHex: Int
    var subjects: [String]
    var grades: [WatchGrade]
    var thresholds: [String: Double]

    enum CodingKeys: String, CodingKey {
        case savedAt, accentHex, subjects, grades, thresholds
    }
    init(savedAt: Date, accentHex: Int, subjects: [String], grades: [WatchGrade], thresholds: [String: Double]) {
        self.savedAt = savedAt; self.accentHex = accentHex
        self.subjects = subjects; self.grades = grades; self.thresholds = thresholds
    }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        savedAt = try c.decodeIfPresent(Date.self, forKey: .savedAt) ?? Date.distantPast
        accentHex = try c.decodeIfPresent(Int.self, forKey: .accentHex) ?? 0x4A90E2
        subjects = try c.decodeIfPresent([String].self, forKey: .subjects) ?? []
        grades = try c.decodeIfPresent([WatchGrade].self, forKey: .grades) ?? []
        thresholds = try c.decodeIfPresent([String: Double].self, forKey: .thresholds) ?? [:]
    }
}

/// Házi feladat az órára — a HomeworkItem hordozható kivonata (lásd
/// NotesView). Csak az aktívak utaznak (nem kész, nem lejárt) — a
/// szűrés az iPhone-on történik a telefonnal azonos szabállyal.
struct WatchHomework: Codable, Hashable, Identifiable {
    var id: String
    var subject: String
    var title: String
    var deadline: Date
    var teacher: String
    var isCustom: Bool
}

/// Dolgozat az órára — az ExamItem hordozható kivonata. Csak az aktívak
/// utaznak (ExamExpiry-szabály az iPhone-on).
struct WatchExam: Codable, Hashable, Identifiable {
    var id: String
    var subject: String
    var mode: String
    var details: String
    var date: Date
    var lessonIndex: Int?
    var isCustom: Bool
}

/// Feladat-snapshot: aktív házik + dolgozatok határidő-sorrendben.
struct WatchTasksSnapshot: Codable {
    var savedAt: Date
    var accentHex: Int
    var homeworks: [WatchHomework]
    var exams: [WatchExam]

    enum CodingKeys: String, CodingKey {
        case savedAt, accentHex, homeworks, exams
    }
    init(savedAt: Date, accentHex: Int, homeworks: [WatchHomework], exams: [WatchExam]) {
        self.savedAt = savedAt; self.accentHex = accentHex
        self.homeworks = homeworks; self.exams = exams
    }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        savedAt = try c.decodeIfPresent(Date.self, forKey: .savedAt) ?? Date.distantPast
        accentHex = try c.decodeIfPresent(Int.self, forKey: .accentHex) ?? 0x4A90E2
        homeworks = try c.decodeIfPresent([WatchHomework].self, forKey: .homeworks) ?? []
        exams = try c.decodeIfPresent([WatchExam].self, forKey: .exams) ?? []
    }
}

// MARK: - Évközi-szűrés a telefonnal azonosan (GradesView.isEvkozi)
enum WatchGradeFilter {
    static func isEvkozi(_ g: WatchGrade) -> Bool {
        let t = g.type.lowercased()
        return t.contains("evkozi") || (!t.contains("felevi") && !t.contains("félévi") && !t.contains("év végi") && !t.contains("evvegi") && !t.contains("évvégi"))
    }
    static func evkozi(_ grades: [WatchGrade]) -> [WatchGrade] {
        grades.filter { $0.value != 0 && isEvkozi($0) }
    }
    static func groupedEvkozi(_ grades: [WatchGrade]) -> [String: [WatchGrade]] {
        Dictionary(grouping: evkozi(grades), by: { $0.subject })
    }
}
