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
    /// A "Mai nap" lock screen widget kind-ja.
    static let dayKind = "SchoolDayWidget"

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
        /// Telefonos státusz-port: felmentett tárgy (zöld) — az iPhone
        /// az ExemptedStore-ból tölti push-kor.
        var isExempted: Bool = false
        /// Telefonos státusz-port: aznapi házi/dolgozat (szürke háttér) —
        /// az iPhone a HomeworkMatcher/ExamMatcher szabállyal tölti.
        var hasAssignment: Bool = false

        // Régi snapshotokban még nincs isExempted/hasAssignment kulcs —
        // decodeIfPresent, különben egy frissítés után az első push-ig
        // üres lenne az óra és a widget.
        enum CodingKeys: String, CodingKey {
            case id, subject, room, teacher, index, start, end
            case isCancelled, isSubstituted, isExempted, hasAssignment
        }
        init(id: String, subject: String, room: String, teacher: String, index: String, start: Date, end: Date, isCancelled: Bool, isSubstituted: Bool, isExempted: Bool = false, hasAssignment: Bool = false) {
            self.id = id; self.subject = subject; self.room = room
            self.teacher = teacher; self.index = index
            self.start = start; self.end = end
            self.isCancelled = isCancelled; self.isSubstituted = isSubstituted
            self.isExempted = isExempted; self.hasAssignment = hasAssignment
        }
        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            id = try c.decode(String.self, forKey: .id)
            subject = try c.decode(String.self, forKey: .subject)
            room = try c.decodeIfPresent(String.self, forKey: .room) ?? ""
            teacher = try c.decodeIfPresent(String.self, forKey: .teacher) ?? ""
            index = try c.decodeIfPresent(String.self, forKey: .index) ?? ""
            start = try c.decode(Date.self, forKey: .start)
            end = try c.decode(Date.self, forKey: .end)
            isCancelled = try c.decodeIfPresent(Bool.self, forKey: .isCancelled) ?? false
            isSubstituted = try c.decodeIfPresent(Bool.self, forKey: .isSubstituted) ?? false
            isExempted = try c.decodeIfPresent(Bool.self, forKey: .isExempted) ?? false
            hasAssignment = try c.decodeIfPresent(Bool.self, forKey: .hasAssignment) ?? false
        }
    }

    /// "Ha ma nincs több óra" kártya: a következő tanítási nap
    /// rendkívüliségei prioritás-sorrendben — esemény > dolgozat >
    /// elmaradó óra > helyettesítés. A fő app számolja, a
    /// widgetek csak mutatják, ha a napja még nem múlt el. 1 tétel =
    /// teljes kártya (cím + alcím), több tétel = summary ("2 dolgozat •
    /// 1 helyettesítés") at-a-glance. Részletes listák nem utaznak,
    /// csak ez a kivonat + darabszámok.
    struct NextDayItem: Codable {
        /// "exam" | "cancelled" | "substituted" | "event".
        var kind: String
        /// Dolgozat tárgya / óra tárgya / esemény címe.
        var title: String
        /// Dolgozat módja / "3. óra elmarad" / esemény alcíme.
        var subtitle: String
    }

    /// Tanítás nélküli hétköznap (tanév rendje, KRÉTA NaptariNapok) —
    /// az órarend ilyet nem ír (nincs órája), a widget viszont kiírja
    /// ("Hétfő / Tanítás nélküli munkanap").
    struct NoSchoolDay: Codable {
        /// Nap eleje.
        var day: Date
        /// Típusnév a KRÉTÁ-tól ("Tanítás nélküli munkanap").
        var name: String
    }

    struct NextDayNote: Codable {
        /// A következő tanítási nap (nap eleje).
        var day: Date
        /// Max 3 tétel, prioritás-sorrendben (a summaryhez elég).
        var items: [NextDayItem]
        /// Darabszámok aznap — a summary ezekből épül ("2 dolgozat •
        /// 1 helyettesítés"). Több lehet, mint items.
        var examCount: Int
        var cancelledCount: Int
        var substitutedCount: Int
        var eventCount: Int
        /// Ha a nap órák nélkül is jelölt (tanítás nélküli): a típusnév
        /// a kártya címe, az események az alcímbe kerülnek.
        var noSchoolName: String? = nil

        var totalCount: Int { examCount + cancelledCount + substitutedCount + eventCount }
    }

    struct Snapshot: Codable {
        var savedAt: Date
        var accentHex: Int
        /// A betöltött hét órái, időrendben (a widget választ napot belőle).
        var lessons: [Lesson]
        /// Dev idő-eltolás csúszka (Beállítások → Fejlesztői): ha aktív,
        /// a widget is az eltolt idő szerint rajzol.
        var previewActive: Bool = false
        var previewMinutes: Double = 540
        var nextNote: NextDayNote? = nil
        /// A mai nap rendkívüliségei (ugyanaz a típus, day = ma) — a
        /// "Mai nap" widgetnek.
        var todayInfo: NextDayNote? = nil

        // Régi snapshotokban még nincs preview/note-kulcs —
        // decodeIfPresent, különben egy frissítés után az első
        // appnyitásig üres lenne a widget.
        enum CodingKeys: String, CodingKey {
            case savedAt, accentHex, lessons, previewActive, previewMinutes, nextNote, todayInfo
        }
        init(savedAt: Date, accentHex: Int, lessons: [Lesson], previewActive: Bool = false, previewMinutes: Double = 540, nextNote: NextDayNote? = nil, todayInfo: NextDayNote? = nil) {
            self.savedAt = savedAt; self.accentHex = accentHex; self.lessons = lessons
            self.previewActive = previewActive; self.previewMinutes = previewMinutes
            self.nextNote = nextNote; self.todayInfo = todayInfo
        }
        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            savedAt = try c.decode(Date.self, forKey: .savedAt)
            accentHex = try c.decode(Int.self, forKey: .accentHex)
            lessons = try c.decode([Lesson].self, forKey: .lessons)
            previewActive = try c.decodeIfPresent(Bool.self, forKey: .previewActive) ?? false
            previewMinutes = try c.decodeIfPresent(Double.self, forKey: .previewMinutes) ?? 540
            nextNote = try c.decodeIfPresent(NextDayNote.self, forKey: .nextNote)
            todayInfo = try c.decodeIfPresent(NextDayNote.self, forKey: .todayInfo)
        }
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

    /// Jövőbeli órák beolvasztása: a múlt kidobva, újak duplikálás nélkül.
    /// Snapshot nélkül is létrehoz (van benne valós adat) — üreset sosem ír.
    @discardableResult
    static func mergeFuture(lessons: [Lesson], accentHex: Int, now: Date, calendar: Calendar = .current) -> Bool {
        let today = calendar.startOfDay(for: now)
        let base = load()
        var existing = base?.lessons ?? []
        existing.removeAll { $0.end < today }
        var ids = Set(existing.map(\.id))
        for l in lessons where ids.insert(l.id).inserted { existing.append(l) }
        existing.sort { $0.start < $1.start }
        guard !existing.isEmpty else { return false }
        save(Snapshot(
            savedAt: Date(), accentHex: accentHex, lessons: existing,
            previewActive: base?.previewActive ?? false,
            previewMinutes: base?.previewMinutes ?? 540
        ))
        return true
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
