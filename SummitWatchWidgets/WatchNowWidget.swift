import SwiftUI
import WidgetKit

// MARK: - "Most" widget az órára — a telefonos MOST-kártya tükre (Smart Stack)
// Ugyanaz a számítás, mint a Főoldal HomeLiveCard → LiveCalc-ja: tartó óra +
// progress + hátralévő idő, szünetben a következő, reggel az első, nap végén
// "Ma nincs több órád". Az óraszámhoz rögzített dolgozat/házi egy-egy sora
// szintén megjelenik (mint a telefonon a kártya alján).
// Adat: a WatchSharedStore App Group-gyorsítótára — a widget extension
// NEM látja az óra app UserDefaults.standard-ját, ezért él minden a
// groupban (a WatchSyncStore ugyanide ír).

struct WatchNowWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: WatchSharedStore.widgetKind, provider: WatchNowProvider()) { entry in
            WatchNowView(entry: entry)
        }
        .configurationDisplayName("Most")
        .description("Az aktuális óra — ugyanaz, mint a telefonos Most-kártya.")
        .supportedFamilies([.accessoryCircular, .accessoryRectangular, .accessoryInline, .accessoryCorner])
    }
}

// MARK: - Timeline

struct WatchNowEntry: TimelineEntry {
    var date: Date
    /// Amivel rajzolunk: valós idő, vagy a dev idő-csúszka eltolt ideje.
    var effectiveNow: Date
    /// A teljes cache-elt hét (a számítás választ napot belőle, mint a telefon).
    var lessons: [TimetableWidgetStore.Lesson]
    var tasks: WatchTasksSnapshot?
    var accentHex: Int
    var hasSnapshot: Bool
}

struct WatchNowProvider: TimelineProvider {
    func placeholder(in context: Context) -> WatchNowEntry {
        WatchNowEntry(
            date: Date(), effectiveNow: Date(), lessons: Self.sampleLessons(),
            tasks: nil, accentHex: 0x4A90E2, hasSnapshot: false
        )
    }

    func getSnapshot(in context: Context, completion: @escaping (WatchNowEntry) -> Void) {
        completion(makeEntry(at: Date(), preview: context.isPreview))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<WatchNowEntry>) -> Void) {
        let now = Date()
        let entry = makeEntry(at: now, preview: false)
        guard entry.hasSnapshot, !entry.lessons.isEmpty else {
            completion(Timeline(entries: [entry], policy: .after(now.addingTimeInterval(30 * 60))))
            return
        }
        // Előre számolt belépők: a Smart Stack magától továbbmegy
        // órahatárokon át (az iOS órarend-widget mintájára).
        let dates = TimetableWidgetLogic.timelineMoments(now: now, lessons: entry.lessons)
        guard !dates.isEmpty else {
            let refresh = TimetableWidgetLogic.nextRefresh(now: now, effectiveNow: entry.effectiveNow, lessons: entry.lessons)
            completion(Timeline(entries: [entry], policy: .after(refresh)))
            return
        }
        completion(Timeline(entries: dates.map { makeEntry(at: $0, preview: false) }, policy: .atEnd))
    }

    private func makeEntry(at date: Date, preview: Bool) -> WatchNowEntry {
        var lessons: [TimetableWidgetStore.Lesson] = []
        var accent = 0x4A90E2
        var hasSnapshot = false
        if let data = WatchSharedStore.data(forKey: WatchSharedStore.timetableKey),
           let snap = try? JSONDecoder().decode(TimetableWidgetStore.Snapshot.self, from: data),
           !snap.lessons.isEmpty {
            lessons = snap.lessons
            accent = snap.accentHex == 0 ? 0x4A90E2 : snap.accentHex
            hasSnapshot = true
        }
        var tasks: WatchTasksSnapshot?
        if let data = WatchSharedStore.data(forKey: WatchSharedStore.tasksKey),
           let snap = try? JSONDecoder().decode(WatchTasksSnapshot.self, from: data) {
            tasks = snap
        }
        // Dev idő-eltolás: ha az iPhone csúszkája aktív, a widget is az
        // eltolt idő szerint rajzol (mint az óra app listái).
        let previewTs = WatchSharedStore.defaults.double(forKey: WatchSharedStore.previewNowKey)
        let effective: Date = previewTs > 0 ? Date(timeIntervalSince1970: previewTs) : date
        if preview {
            return WatchNowEntry(
                date: date, effectiveNow: effective, lessons: Self.sampleLessons(),
                tasks: nil, accentHex: accent, hasSnapshot: false
            )
        }
        return WatchNowEntry(
            date: date, effectiveNow: effective, lessons: lessons, tasks: tasks,
            accentHex: accent, hasSnapshot: hasSnapshot
        )
    }

    static func sampleLessons() -> [TimetableWidgetStore.Lesson] {
        let cal = Calendar.current
        let morning = cal.date(bySettingHour: 8, minute: 0, second: 0, of: Date()) ?? Date()
        let defs = [("Matematika", "A.12", "Nagy Éva"), ("Angol nyelv", "B.07", "Kiss Péter")]
        return defs.enumerated().map { i, s in
            let start = morning.addingTimeInterval(Double(i) * 3600)
            return TimetableWidgetStore.Lesson(
                id: "sample-\(i)", subject: s.0, room: s.1, teacher: s.2,
                index: "\(i + 1)", start: start, end: start.addingTimeInterval(45 * 60),
                isCancelled: false, isSubstituted: false
            )
        }
    }
}

// MARK: - MOST-számítás — a telefonos LiveCalc portja
// Szándékosan ugyanazok az állapotok és szövegek, mint a HomeView-ban:
// tartó óra + progress + "X perc van hátra", szünet + "X perc múlva
// kezdődik", reggel + "Jó reggelt!", nap végén "Ma nincs több órád".
// Különbség: a felmentés-levágás itt nincs (a felmentés-lista nem utazik
// az órára — az óra app listái sem vágják, így a kettő egyezik).
struct WatchNowCalc {
    enum State { case empty, morning, duringLesson, duringBreak }
    var state: State = .empty
    var current: TimetableWidgetStore.Lesson?
    var next: TimetableWidgetStore.Lesson?
    var previous: TimetableWidgetStore.Lesson?
    var progress: Double = 0
    var remainingText: String = ""
    /// A tartó/következő órához rögzített dolgozat (mint a telefonon).
    var exam: WatchExam?
    /// Ugyanarra az órára eső házi (mint a telefonon).
    var homework: WatchHomework?

    private static func todayLessons(_ lessons: [TimetableWidgetStore.Lesson], now: Date) -> [TimetableWidgetStore.Lesson] {
        let cal = Calendar.current
        return lessons.filter { cal.isDate($0.start, inSameDayAs: now) || cal.isDate($0.end, inSameDayAs: now) }
            .filter { !$0.subject.trimmingCharacters(in: .whitespaces).isEmpty }
            .sorted { $0.start < $1.start }
    }

    private static func formatRemaining(_ minutes: Int, past: Bool) -> String {
        if minutes <= 0 { return past ? "Vége" : "Kezdődik" }
        return past ? "\(minutes) perc van hátra" : "\(minutes) perc múlva kezdődik"
    }

    /// Dolgozat–óra csatolás az ExamMatcher telefonos szabályával, az órai
    /// WatchExam-alakra: óraszámra tűzött csak a saját órájára, különben az
    /// óraszám nélküli aznapi, végül az egyetlen aznapi azonos tárgyú.
    private static func exam(for lesson: TimetableWidgetStore.Lesson, in exams: [WatchExam], calendar: Calendar = .current) -> WatchExam? {
        let sameDay = exams.filter {
            SubjectMatcher.same($0.subject, lesson.subject)
            && calendar.isDate($0.date, inSameDayAs: lesson.start)
        }
        if let pinned = sameDay.first(where: { $0.lessonIndex != nil && Int(lesson.index) == $0.lessonIndex }) {
            return pinned
        }
        if let unpinned = sameDay.first(where: { $0.lessonIndex == nil }) {
            return unpinned
        }
        if sameDay.count == 1 { return sameDay[0] }
        if Int(lesson.index) == nil { return sameDay.first }
        return nil
    }

    init(lessons: [TimetableWidgetStore.Lesson], tasks: WatchTasksSnapshot?, now: Date) {
        let filtered = Self.todayLessons(lessons, now: now)
        guard !filtered.isEmpty else { return }
        if let cur = filtered.first(where: { $0.start <= now && $0.end >= now }) {
            state = .duringLesson; current = cur
            let total = cur.end.timeIntervalSince(cur.start)
            progress = total > 0 ? min(1, max(0, now.timeIntervalSince(cur.start) / total)) : 0
            remainingText = Self.formatRemaining(Int(ceil(cur.end.timeIntervalSince(now) / 60)), past: true)
            next = filtered.first(where: { $0.start > now })
            previous = filtered.last(where: { $0.end < now })
        } else if let nxt = filtered.first(where: { $0.start > now }) {
            let prev = filtered.last(where: { $0.end < now })
            if let p = prev, nxt.start.timeIntervalSince(p.end) > 0 {
                state = .duringBreak
                let total = nxt.start.timeIntervalSince(p.end)
                progress = total > 0 ? min(1, max(0, now.timeIntervalSince(p.end) / total)) : 0
                remainingText = Self.formatRemaining(Int(ceil(nxt.start.timeIntervalSince(now) / 60)), past: false)
            } else if now < filtered.first!.start {
                state = .morning
                let first = filtered.first!
                let cal = Calendar.current
                let morningStart = cal.date(bySettingHour: 7, minute: 0, second: 0, of: now) ?? now
                let total = first.start.timeIntervalSince(morningStart)
                if total > 0, now >= morningStart {
                    progress = min(1, max(0, now.timeIntervalSince(morningStart) / total))
                }
                let rem = Int(ceil(first.start.timeIntervalSince(now) / 60))
                if rem > 180 {
                    state = .empty
                    remainingText = ""
                } else {
                    remainingText = Self.formatRemaining(rem, past: false)
                }
            } else {
                state = .duringBreak
                if let p = prev {
                    let total = nxt.start.timeIntervalSince(p.end)
                    progress = total > 0 ? min(1, max(0, now.timeIntervalSince(p.end) / total)) : 0
                    remainingText = Self.formatRemaining(Int(ceil(nxt.start.timeIntervalSince(now) / 60)), past: false)
                }
            }
            next = nxt; previous = prev
        } else {
            state = .empty
        }
        // Rögzített infó a kártya aljára (mint a telefonon): a tartó órára,
        // különben a következőre vonatkozik.
        if let anchor = current ?? next, let t = tasks {
            exam = Self.exam(for: anchor, in: t.exams)
            homework = t.homeworks.first {
                SubjectMatcher.same($0.subject, anchor.subject)
                && Calendar.current.isDate($0.deadline, inSameDayAs: anchor.start)
            }
        }
    }
}

// MARK: - Nézet

private struct WatchNowView: View {
    let entry: WatchNowEntry
    @Environment(\.widgetFamily) private var family

    private var accent: Color { Color(nowHex: UInt(entry.accentHex)) }
    private var calc: WatchNowCalc {
        WatchNowCalc(lessons: entry.lessons, tasks: entry.tasks, now: entry.effectiveNow)
    }

    var body: some View {
        switch family {
        case .accessoryRectangular:
            rectangularView
        case .accessoryCircular:
            circularView
        case .accessoryCorner:
            cornerView
        default:
            inlineView
        }
    }

    // MARK: Smart Stack főnézet — kompakt: cím + csík melletti "35p" + következő óra
    // A csík a kiemelőszínt (accent) veszi fel, a hátralévő idő rövid
    // "35p" alakban a csík MELLETT ül (nem külön soron), alatta pedig egy
    // sorban a következő óra — így minden elfér zsúfoltság nélkül.
    private var rectangularView: some View {
        VStack(alignment: .leading, spacing: 3) {
            // Két egyforma spacer középre rendezi a blokkot: alul-felül
            // ugyanakkora padding adódik, bármekkora a kártya (a lekerekített
            // sarkokhoz is arányosan igazodik). Szűk helyen 0-ra csuklanak.
            Spacer(minLength: 0)
            if !entry.hasSnapshot && entry.lessons.isEmpty {
                Text("Nyisd meg az appot")
                    .font(.headline.weight(.semibold)).lineLimit(1)
                Text("Az órarend iPhone-ról érkezik.")
                    .font(.caption2).foregroundStyle(.secondary).lineLimit(1)
            } else {
                switch calc.state {
                case .empty:
                    Label("Ma nincs több órád", systemImage: "moon.zzz.fill")
                        .font(.headline.weight(.semibold)).lineLimit(1)
                case .morning:
                    if let n = calc.next {
                        Text(n.subject)
                            .font(.headline.weight(.bold)).lineLimit(1)
                        lessonLine(n, showTime: n.start)
                        progressLine(tint: statusTint(n))
                        nextLine(n)
                    }
                case .duringLesson:
                    if let c = calc.current {
                        Text(c.subject)
                            .font(.headline.weight(.bold)).lineLimit(1)
                        lessonLine(c, showTime: nil)
                        progressLine(tint: statusTint(c))
                        if let n = calc.next {
                            nextLine(n)
                        }
                    }
                case .duringBreak:
                    if let n = calc.next {
                        Text(n.subject)
                            .font(.headline.weight(.bold)).lineLimit(1)
                        lessonLine(n, showTime: n.start)
                        progressLine(tint: statusTint(n))
                        nextLine(n)
                    }
                }
                attachedLine
            }
            Spacer(minLength: 0)
        }
        // Mért aszimmetria kompenzálása: a rendszer tartalom-margója felül
        // ~12-13px, alul ~2-3px (saját szimulátor-mérés) — a -5 felhozza a
        // blokkot, így alul-felül egyforma a padding. Rövid állapotokban
        // (1-2 sor) a spacerek középre rendeznek, ott ez hatástalan.
        .padding(.top, -5)
        // Smart Stack-háttér: a rendszer a harmadik féltől származó
        // kártyák alá átlátszatlan feketét tesz (saját mérés: 6 háttér-
        // variáns kipróbálva szimulátoron + pixel-analízis — a clear,
        // a material, a .glassEffect és az AccessoryWidgetBackground is
        // feketét ad, csak a lapos szín él). A Now Playing világos üvege
        // rendszer-privilegium, nem publikus API. A HIG is egyedi hátteret
        // javasol (mint a Stocks piros/zöldje) — ezért ez a finom semleges
        // fény-átmenet imitálja az üveg csillogását.
        .containerBackground(for: .widget) {
            LinearGradient(
                colors: [.white.opacity(0.16), .white.opacity(0.03)],
                startPoint: .top, endPoint: .bottom
            )
        }
    }

    private func lessonLine(_ l: TimetableWidgetStore.Lesson, showTime: Date?) -> some View {
        HStack(spacing: 4) {
            Text("\(l.index). óra")
                .font(.caption2.weight(.bold).monospacedDigit())
            Text("•").foregroundStyle(.tertiary).font(.caption2)
            Text(l.room.isEmpty ? l.teacher : l.room)
                .font(.caption2).foregroundStyle(.secondary).lineLimit(1)
            Spacer(minLength: 2)
            if let t = showTime {
                Text(shortTime(t)).font(.caption2.monospacedDigit()).foregroundStyle(.secondary)
            }
        }
    }

    /// Accent-csík + mellette a rövid "35p" — egy soron, külön
    /// "X perc van hátra" sor nélkül.
    private func progressLine(tint: Color) -> some View {
        HStack(spacing: 6) {
            ProgressView(value: calc.progress)
                .tint(tint)
            Text(shortRemaining)
                .font(.caption2.weight(.bold).monospacedDigit())
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }

    /// Következő óra egy sorban: nyíl + terem, utána a tárgy, ha elfér.
    /// Időpont és "Következő" felirat nincs — a fenti sorokból úgyis
    /// látszik, melyik óra tart épp. Szándékosan kisebb (10pt) alárendelt
    /// sor, hogy a Smart Stack-kártyán biztosan elférjen. A terem sosem
    /// nyomódik össze, a tárgy vágódik (`tail`), ha szűk a hely.
    private func nextLine(_ n: TimetableWidgetStore.Lesson) -> some View {
        HStack(spacing: 4) {
            Image(systemName: "arrow.right.circle.fill")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(.secondary)
                // Optikai igazítás: a kerek ikonnak nincs sík bal éle, mint
                // a "Matek" M-betűjének — enélkül a sor beljebbnek látszana.
                // Offset (nem padding), hogy a layout-távok ne változzanak.
                .offset(x: -2)
            let room = n.room.isEmpty ? n.teacher : n.room
            if !room.isEmpty {
                Text(room)
                    .font(.system(size: 10, weight: .bold).monospacedDigit())
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
            }
            Text(n.subject)
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.tail)
        }
    }

    /// Rögzített dolgozat/házi egy-egy sora — mint a telefonos kártya alján.
    @ViewBuilder
    private var attachedLine: some View {
        if let e = calc.exam {
            let desc = e.details.isEmpty ? e.mode : "\(e.mode): \(e.details)"
            Label(desc, systemImage: "exclamationmark.triangle.fill")
                .font(.caption2.weight(.semibold)).foregroundStyle(.orange).lineLimit(1)
        }
        if let h = calc.homework {
            Label(h.title, systemImage: "checklist")
                .font(.caption2).foregroundStyle(.secondary).lineLimit(1)
        }
    }

    // MARK: Kör — progress-gyűrű + hátralévő idő
    @ViewBuilder
    private var circularView: some View {
        switch calc.state {
        case .duringLesson:
            if let c = calc.current {
                Gauge(value: calc.progress) {
                    Text(c.index).font(.caption2.weight(.bold).monospacedDigit())
                } currentValueLabel: {
                    Text(shortRemaining).font(.caption2.weight(.bold).monospacedDigit())
                }
                .gaugeStyle(.accessoryCircular)
                .tint(statusTint(c))
            }
        case .duringBreak, .morning:
            if let n = calc.next {
                Gauge(value: calc.progress) {
                    Text(n.index).font(.caption2.weight(.bold).monospacedDigit())
                } currentValueLabel: {
                    Text(shortRemaining).font(.caption2.weight(.bold).monospacedDigit())
                }
                .gaugeStyle(.accessoryCircular)
                .tint(statusTint(n))
            }
        case .empty:
            Image(systemName: "moon.zzz.fill")
        }
    }

    // MARK: Egy sor a Smart Stack tetejére / sarki nézet
    private var inlineView: some View {
        Text(inlineText).lineLimit(1)
    }

    private var cornerView: some View {
        Text(cornerText)
            .font(.caption2.weight(.bold).monospacedDigit())
            .lineLimit(1)
            .minimumScaleFactor(0.7)
    }

    private var inlineText: String {
        guard entry.hasSnapshot, !entry.lessons.isEmpty else { return "Most: nyisd meg az appot" }
        switch calc.state {
        case .empty:
            return "Ma nincs több órád"
        case .morning:
            if let n = calc.next { return "Első: \(n.subject) • \(shortTime(n.start))" }
            return "Ma nincs több órád"
        case .duringLesson:
            if let c = calc.current { return "Most: \(c.subject) • \(calc.remainingText)" }
            return "Ma nincs több órád"
        case .duringBreak:
            if let n = calc.next { return "Szünet • \(n.subject) \(shortTime(n.start))" }
            return "Ma nincs több órád"
        }
    }

    private var cornerText: String {
        switch calc.state {
        case .duringLesson, .duringBreak, .morning:
            return shortRemaining
        case .empty:
            return "Vége"
        }
    }

    private var shortRemaining: String {
        // "42 perc van hátra" → "42 p"; "8 perc múlva kezdődik" → "8 p".
        let parts = calc.remainingText.split(separator: " ")
        if let first = parts.first, Int(first) != nil { return "\(first) p" }
        return calc.remainingText
    }

    private func statusTint(_ l: TimetableWidgetStore.Lesson) -> Color {
        if l.isCancelled { return .red }
        if l.isSubstituted { return .orange }
        return accent
    }

    private func shortTime(_ d: Date) -> String {
        d.formatted(date: .omitted, time: .shortened)
    }
}

// MARK: - Self-contained hex — nem függ az AppColors.swift-től
private extension Color {
    init(nowHex: UInt, alpha: Double = 1.0) {
        let r = Double((nowHex >> 16) & 0xFF) / 255.0
        let g = Double((nowHex >> 8) & 0xFF) / 255.0
        let b = Double(nowHex & 0xFF) / 255.0
        self.init(.sRGB, red: r, green: g, blue: b, opacity: alpha)
    }
}

#Preview(as: .accessoryRectangular) {
    WatchNowWidget()
} timeline: {
    WatchNowEntry(
        date: Date(), effectiveNow: Date(), lessons: WatchNowProvider.sampleLessons(),
        tasks: nil, accentHex: 0x4A90E2, hasSnapshot: true
    )
}
