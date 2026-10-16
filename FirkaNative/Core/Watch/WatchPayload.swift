import Foundation

// MARK: - Watch payload — shared iPhone ↔ Apple Watch
// WatchConnectivity applicationContext-ben utazik (iPhone tolja, az óra csak
// olvas — ezért az órán nincs bejelentkezés). Token, név, OM, e-mail SOHA:
// csak óracím, terem, tanár, időpont, jegyérték és kerekítési küszöbök.
// Az órarendi szelethez a widget snapshotját használjuk újra
// (TimetableWidgetStore.Snapshot — szintén shared fájl, mindkét target
// fordítja). Ez a fájl csak Foundationt importál, Catalyst-barát.
/// Közös tár az óra app és a Smart Stack-widget között.
/// watchOS-en a widget extension NEM látja az app UserDefaults.standard-ját,
/// ezért a gyorsítótár App Groupban él. Azonosítója megegyezik az iOS-es
/// csoportéval (group.hu.flint.summit), de platformonként külön konténer —
/// az iOS widget-cache és az órai cache nem keveredik.
/// Mindkét watch-target fordítja (lásd project.yml).
enum WatchSharedStore {
    static let appGroupID = "group.hu.flint.summit"
    /// A Smart Stack-widget kind-ja (timeline-újratöltéshez is ez kell).
    static let widgetKind = "WatchNowWidget"

    static let timetableKey = "watch.cache.timetable.v1"
    static let gradesKey = "watch.cache.grades.v1"
    static let tasksKey = "watch.cache.tasks.v1"
    static let cheatKey = "watch.cache.cheat.v1"
    static let schoolEventsKey = "watch.cache.schoolevents.v1"
    /// Fejlesztői idő-előnézet (unix idő, Double). Csak akkor van jelen, ha
    /// az iPhone-on az Idő-eltolás csúszka aktív.
    static let previewNowKey = "watch.cache.previewNow.v1"

    static var defaults: UserDefaults {
        UserDefaults(suiteName: appGroupID) ?? .standard
    }

    /// Olvasás group-első, régi standard-második: a group előtti build
    /// gyorsítótára átköltözik, így a widget már az első szinkron előtt is
    /// látja a legutóbbi adatot.
    static func data(forKey key: String) -> Data? {
        if let d = defaults.data(forKey: key) { return d }
        if defaults !== UserDefaults.standard,
           let d = UserDefaults.standard.data(forKey: key) {
            defaults.set(d, forKey: key)
            return d
        }
        return nil
    }

    static func set(_ data: Data, forKey key: String) {
        defaults.set(data, forKey: key)
    }
}

enum WatchPayloadKey {
    static let timetable = "watch.timetable.v1"
    static let grades = "watch.grades.v1"
    static let tasks = "watch.tasks.v1"
    /// Tanulójegyzet-lapok az órára (Jegyzet tab).
    static let cheat = "watch.cheat.v1"
    /// Iskolai események (tannaptár) az órarend tetejére.
    static let schoolEvents = "watch.schoolevents.v1"
    /// Óra → iPhone szinkronkérés (megnyitáskor, ha az órai adat avult
    /// vagy hiányzik). Mindkét irány ugyanazt a kulcs-szótárat használja.
    static let request = "watch.requestSync.v1"
    /// Fejlesztői idő-előnézet pillanata (unix idő, Double). Csak akkor
    /// van jelen, ha az iPhone-on az Idő-eltolás csúszka aktív — ilyenkor
    /// az óra is az eltolt idő szerint rajzol (aktuális óra + progress).
    static let previewNow = "watch.previewNow.v1"
}

/// Fejlesztői idő-előnézet (Beállítások → Fejlesztői → Idő-eltolás)
/// órára szánt pillanata: ha aktív, a mai nap ennyi perckor "járunk".
/// CSAK helyi WatchConnectivity-n utazik — a felhős SummitSync-be,
/// a widget-cache-be és a Live Activity-tervbe sosem kerül (a dev
/// flag nem szinkronizálható, csak a párosított óra tükrezi).
enum WatchPreviewClock {
    static func overrideNow() -> Date? {
        let d = UserDefaults.standard
        guard d.bool(forKey: "developer.enabled"),
              d.bool(forKey: "home.demoPreviewActive") else { return nil }
        let mins = d.double(forKey: "home.demoPreviewMinutes")
        let base = Calendar.current.startOfDay(for: Date())
        return base.addingTimeInterval(mins * 60)
    }
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

// MARK: - Tanulójegyzet-lap az órára — a CheatSheet hordozható kivonata
// Dolgozat → témák: egy téma egy jegyzet (cím + szöveg), mélyebb
// szint nincs. A feltöltött nyers anyagok NEM utaznak (nagyok) —
// csak a kész (AI- vagy kézi) jegyzet-törzsek, vágva (az
// applicationContext nagy méretnél eldobná a teljes contextet).
struct WatchCheatTopic: Codable, Hashable, Identifiable {
    var id: String
    var title: String
    var body: String
}

struct WatchCheatSheet: Codable, Hashable, Identifiable {
    var id: String
    var subject: String
    var title: String
    var date: Date?
}

/// Jegyzet-snapshot: lapok + témáik az órára.
struct WatchCheatSnapshot: Codable {
    var savedAt: Date
    var accentHex: Int
    var sheets: [WatchCheatSheet]
    var topics: [String: [WatchCheatTopic]]

    enum CodingKeys: String, CodingKey {
        case savedAt, accentHex, sheets, topics
    }
    init(savedAt: Date, accentHex: Int, sheets: [WatchCheatSheet], topics: [String: [WatchCheatTopic]]) {
        self.savedAt = savedAt; self.accentHex = accentHex
        self.sheets = sheets; self.topics = topics
    }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        savedAt = try c.decodeIfPresent(Date.self, forKey: .savedAt) ?? Date.distantPast
        accentHex = try c.decodeIfPresent(Int.self, forKey: .accentHex) ?? 0x4A90E2
        sheets = try c.decodeIfPresent([WatchCheatSheet].self, forKey: .sheets) ?? []
        topics = try c.decodeIfPresent([String: [WatchCheatTopic]].self, forKey: .topics) ?? [:]
    }
}

// MARK: - Iskolai esemény az órára — a SchoolEvent hordozható kivonata
// A telefonos kártya-alcím szabállyal (idő • hely / Egész nap).
struct WatchSchoolEvent: Codable, Hashable, Identifiable {
    var day: String
    var title: String
    var location: String
    var allDay: Bool
    var start: String
    var end: String

    var id: String { "\(day)|\(start)|\(end)|\(title)|\(location)" }

    var subtitle: String {
        var parts: [String] = []
        if !allDay, !start.isEmpty {
            parts.append(end.isEmpty ? start : "\(start) – \(end)")
        } else if location.isEmpty {
            parts.append("Egész nap")
        }
        if !location.isEmpty { parts.append(location) }
        return parts.joined(separator: " • ")
    }
}

/// Esemény-snapshot: az adott hét tannaptára + mutatás-kapcsoló.
struct WatchSchoolEventsSnapshot: Codable {
    var savedAt: Date
    var visible: Bool
    var events: [WatchSchoolEvent]

    enum CodingKeys: String, CodingKey {
        case savedAt, visible, events
    }
    init(savedAt: Date, visible: Bool, events: [WatchSchoolEvent]) {
        self.savedAt = savedAt; self.visible = visible; self.events = events
    }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        savedAt = try c.decodeIfPresent(Date.self, forKey: .savedAt) ?? Date.distantPast
        visible = try c.decodeIfPresent(Bool.self, forKey: .visible) ?? true
        events = try c.decodeIfPresent([WatchSchoolEvent].self, forKey: .events) ?? []
    }
}

// MARK: - Markdown-bekezdésekre vágás (jegyzet-nézet, óra)
// Az órai Text Markdown-bekezdéstávolsága nem ad látható lukat, ezért a
// jegyzet-nézet bekezdésenként külön Textet rajzol fix térközzel.
// Üres sorok mentén vág; ami maradék szimpla sortörés, az bekezdésen
// belüli szoros törés marad.
func splitMarkdownParagraphs(_ s: String) -> [String] {
    s.components(separatedBy: "\n")
        .map { $0.trimmingCharacters(in: .whitespaces) }
        .split(separator: "", omittingEmptySubsequences: false)
        .map { $0.joined(separator: "\n") }
        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        .filter { !$0.isEmpty }
}

// MARK: - Évközi-szűrés a telefonnal azonosan (GradesView.isEvkozi)
enum WatchGradeFilter {
    static func isEvkozi(_ g: WatchGrade) -> Bool {
        let t = g.type.lowercased()
        return t.contains("evkozi") || t.contains("évközi") || (!t.contains("felevi") && !t.contains("félévi") && !t.contains("év végi") && !t.contains("evvegi") && !t.contains("évvégi"))
    }
    static func evkozi(_ grades: [WatchGrade]) -> [WatchGrade] {
        grades.filter { $0.value != 0 && isEvkozi($0) }
    }
    static func groupedEvkozi(_ grades: [WatchGrade]) -> [String: [WatchGrade]] {
        Dictionary(grouping: evkozi(grades), by: { $0.subject })
    }
}
