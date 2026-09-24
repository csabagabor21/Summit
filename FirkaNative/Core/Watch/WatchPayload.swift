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
