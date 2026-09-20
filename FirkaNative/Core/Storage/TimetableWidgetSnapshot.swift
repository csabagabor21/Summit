import Foundation

// MARK: - Órarend widget snapshot — shared app ↔ Widget Extension
// Egykezesség: CSAK a TimetableView írja (load() végén), a widget csak olvas.
// App Group nélkül az extension nem látná a fő app UserDefaults-át,
// ezért a heti órarend kivonata ide kerül JSON-ben. Token, név, OM, e-mail
// SOHA: csak óracím, terem, tanár, időpont és az accentHex.
// Mindkét target fordítja (lásd project.yml SummitWidgets sources + pbxproj).
enum TimetableWidgetStore {
    static let appGroupID = "group.hu.flint.summit"
    static let snapshotKey = "widget.timetable.snapshot.v1"
    /// WidgetKit kind — mindkét target innen olvassa (nincs shared framework).
    static let kind = "TimetableWidget"

    struct Lesson: Codable, Hashable {
        var id: String
        var subject: String
        var room: String
        var teacher: String
        var index: String
        var start: Date
        var end: Date
        var isCancelled: Bool
        var isSubstituted: Bool
    }

    struct Snapshot: Codable {
        var savedAt: Date
        var accentHex: Int
        /// A betöltött hét órái, időrendben (a widget választ napot belőle).
        var lessons: [Lesson]
    }

    private static var defaults: UserDefaults? {
        UserDefaults(suiteName: appGroupID)
    }

    static func save(_ snapshot: Snapshot) {
        guard let defaults,
              let data = try? JSONEncoder().encode(snapshot) else { return }
        defaults.set(data, forKey: snapshotKey)
    }

    static func load() -> Snapshot? {
        guard let defaults,
              let data = defaults.data(forKey: snapshotKey),
              let snap = try? JSONDecoder().decode(Snapshot.self, from: data) else { return nil }
        return snap
    }

    /// Egy nap óráinak cseréje a snapshotban (háttér-ébresztés: csak a mai
    /// napot húzza le, a hét többi napja marad). Nincs snapshot → false.
    @discardableResult
    static func mergeDay(lessons: [Lesson], day: Date, accentHex: Int, calendar: Calendar = .current) -> Bool {
        guard var snap = load() else { return false }
        snap.lessons.removeAll { calendar.isDate($0.start, inSameDayAs: day) }
        snap.lessons.append(contentsOf: lessons)
        snap.lessons.sort { $0.start < $1.start }
        snap.accentHex = accentHex
        snap.savedAt = Date()
        save(snap)
        return true
    }
}
