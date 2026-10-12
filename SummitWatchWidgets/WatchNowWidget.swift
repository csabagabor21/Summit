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
    /// A következő tanítási nap rendkívüliségei (ha ma nincs több óra).
    var note: TimetableWidgetStore.NextDayNote?
    /// A mai nap rendkívüliségei (reggel tanítás előtt).
    var todayInfo: TimetableWidgetStore.NextDayNote?
}

struct WatchNowProvider: TimelineProvider {
    func placeholder(in context: Context) -> WatchNowEntry {
        WatchNowEntry(
            date: Date(), effectiveNow: Date(), lessons: Self.sampleLessons(),
            tasks: nil, accentHex: 0x4A90E2, hasSnapshot: false, note: nil, todayInfo: nil
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
        var note: TimetableWidgetStore.NextDayNote?
        var todayInfo: TimetableWidgetStore.NextDayNote?
        if let data = WatchSharedStore.data(forKey: WatchSharedStore.timetableKey),
           let snap = try? JSONDecoder().decode(TimetableWidgetStore.Snapshot.self, from: data),
           !snap.lessons.isEmpty {
            lessons = snap.lessons
            accent = snap.accentHex == 0 ? 0x4A90E2 : snap.accentHex
            hasSnapshot = true
            note = snap.nextNote
            todayInfo = snap.todayInfo
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
                tasks: nil, accentHex: accent, hasSnapshot: false, note: nil, todayInfo: nil
            )
        }
        return WatchNowEntry(
            date: date, effectiveNow: effective, lessons: lessons, tasks: tasks,
            accentHex: accent, hasSnapshot: hasSnapshot, note: note, todayInfo: todayInfo
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
    /// Az aktuális fázis fix intervalluma az ÉLŐ visszaszámlálóhoz:
    /// Text(timerInterval:) magától tickel (reload nélkül), ezért napi
    /// pár timeline-reload is elég. Nil = nincs mutatnivaló fázis.
    var phase: ClosedRange<Date>? = nil
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
            phase = cur.start...cur.end
            next = filtered.first(where: { $0.start > now })
            previous = filtered.last(where: { $0.end < now })
        } else if let nxt = filtered.first(where: { $0.start > now }) {
            let prev = filtered.last(where: { $0.end < now })
            if let p = prev, nxt.start.timeIntervalSince(p.end) > 0 {
                state = .duringBreak
                let total = nxt.start.timeIntervalSince(p.end)
                progress = total > 0 ? min(1, max(0, now.timeIntervalSince(p.end) / total)) : 0
                remainingText = Self.formatRemaining(Int(ceil(nxt.start.timeIntervalSince(now) / 60)), past: false)
                phase = p.end...nxt.start
            } else if now < filtered.first!.start {
                state = .morning
                let first = filtered.first!
                let cal = Calendar.current
                let morningStart = cal.date(bySettingHour: 7, minute: 0, second: 0, of: now) ?? now
                // Fordított intervallum (pl. 7:00 előtti első óra) crash-elne —
                // ilyenkor nincs élő visszaszámláló, marad a statikus szöveg.
                if morningStart <= first.start { phase = morningStart...first.start }
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
                    if p.end <= nxt.start { phase = p.end...nxt.start }
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

    // MARK: Smart Stack főnézet — cím (tárgy • terem) + számos csík + következő óra
    // Óraszám-sor nincs: az óraszám a csík elején, RAJTA ül (fehér szám),
    // a terem pedig a címben, kis pöttyel. A csík a kiemelőszínt (accent)
    // veszi fel és élő (ProgressView(timerInterval:) — magától tickel),
    // a hátralévő idő élő visszaszámlálóként ("35:00",
    // Text(timerInterval:) — magától tickel) a csík MELLETT
    // (nem külön soron), alatta normál méretű sorban a következő óra.
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
                    if let note = activeNote {
                        noteCard(note)
                    } else if let fl = nextFutureLesson {
                        Text(noteDayUpper(fl.start))
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                        titleRow(fl)
                        Text(shortTime(fl.start))
                            .font(.caption2.weight(.bold).monospacedDigit())
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    } else {
                        Label("Ma nincs több órád", systemImage: "moon.zzz.fill")
                            .font(.headline.weight(.semibold)).lineLimit(1)
                    }
                case .morning:
                    // Reggel tanítás előtt: a mai esemény az első — ha nincs,
                    // a normál "mi fog történni" (első óra + visszaszámláló).
                    if let info = validToday {
                        noteCard(info, dayName: "MA")
                    } else if let n = calc.next {
                        titleRow(n)
                        progressLine(tint: statusTint(n), index: n.index)
                        nextLine(n)
                    }
                case .duringLesson:
                    if let c = calc.current {
                        titleRow(c)
                        progressLine(tint: statusTint(c), index: c.index)
                        if let n = calc.next {
                            nextLine(n)
                        }
                    }
                case .duringBreak:
                    if let n = calc.next {
                        titleRow(n)
                        progressLine(tint: statusTint(n), index: n.index)
                        nextLine(n)
                    }
                }
                attachedLine
            }
            Spacer(minLength: 0)
        }
        // A VStack önmagában csak tartalom-széles és a rendszer középre
        // teszi a kártyában (ezért tűnt középre igazítottnak a
        // "HOLNAP / Matek • A1 / 8:00" blokk) — teljes szélességre
        // feszítve minden szöveges állapot balra igazodik.
        .frame(maxWidth: .infinity, alignment: .leading)
        .multilineTextAlignment(.leading)
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

    /// Cím-sor: tárgy + kis pötty + terem (az óraszám-sor helyett —
    /// az óraszám a csíkon ül). A terem sosem nyomódik össze,
    /// a tárgy vágódik (`tail`), ha szűk a hely.
    private func titleRow(_ l: TimetableWidgetStore.Lesson) -> some View {
        HStack(spacing: 4) {
            Text(l.subject)
                .font(.headline.weight(.bold)).lineLimit(1)
                .truncationMode(.tail)
            Text("•").foregroundStyle(.tertiary).font(.caption2)
            Text(l.room.isEmpty ? l.teacher : l.room)
                .font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Accent-csík + RAJTA az óraszám (fehér szám a csík elején, mint eddig)
    /// + mellette az élő visszaszámláló ("35:00", másodpercenként tickel,
    /// reload nélkül) — egy soron, külön "X perc van hátra" sor nélkül.
    /// A csík maga is élő: a fázis intervallumára kötött ProgressView a
    /// visszaszámlálóval együtt, másodpercenként tickel. Két részlet
    /// számít: a countsDown: true ÜRÍTENÉ a csíkot (visszafelé menne),
    /// ezért false — így töltődik előre, mint a régi statikus érték; és
    /// az alapértelmezett dátum-címkét üres nézetekkel nyomjuk el,
    /// különben a csík maga is kirakna egy második számlálót a saját
    /// visszaszámlálónk mellé.
    private func progressLine(tint: Color, index: String) -> some View {
        HStack(spacing: 6) {
            liveBar(tint: tint, index: index)
            countdownText
                .font(.caption2.weight(.bold).monospacedDigit())
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Élő csík (fázisra kötve, timeline-reload nélkül tickel) vagy
    /// statikus pillanatnyi érték preview-eltolásnál és fázis nélkül.
    private func liveBar(tint: Color, index: String) -> some View {
        Group {
            if let phase = calc.phase, !isPreviewShift {
                ProgressView(
                    timerInterval: phase,
                    countsDown: false,
                    label: { EmptyView() },
                    currentValueLabel: { EmptyView() }
                )
            } else {
                ProgressView(value: calc.progress)
            }
        }
        .tint(tint)
        // A HStack-ben a visszaszámláló-szöveg elvinné a helyet, a csík
        // csak az ideális szélességét kapná (rövid maradna) — ezért
        // kihúzzuk a teljes szabad szélességre (mint a régi képen).
        .frame(maxWidth: .infinity)
        .overlay(alignment: .leading) {
            if !index.isEmpty {
                Text("\(index).")
                    .font(.system(size: 11, weight: .bold).monospacedDigit())
                    .foregroundStyle(.white)
                    .padding(.leading, 6)
            }
        }
    }

    /// Következő óra egy sorban: nyíl + terem + pötty + tárgy
    /// ("→ B2 • Angol"). Időpont és "Következő" felirat nincs — a fenti
    /// sorokból úgyis látszik, melyik óra tart épp. A terem sosem nyomódik
    /// össze, a tárgy vágódik (`tail`), ha szűk a hely.
    private func nextLine(_ n: TimetableWidgetStore.Lesson) -> some View {
        HStack(spacing: 4) {
            Image(systemName: "arrow.right.circle.fill")
                .font(.caption2.weight(.bold))
                .foregroundStyle(.secondary)
                // Optikai igazítás: a kerek ikonnak nincs sík bal éle, mint
                // a "Matek" M-betűjének — enélkül a sor beljebbnek látszana.
                // Offset (nem padding), hogy a layout-távok ne változzanak.
                .offset(x: -2)
            let room = n.room.isEmpty ? n.teacher : n.room
            if !room.isEmpty {
                Text(room)
                    .font(.caption2.weight(.bold).monospacedDigit())
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
                Text("•").foregroundStyle(.tertiary).font(.caption2)
            }
            Text(n.subject)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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

    // MARK: Következő napi kártya — ha ma nincs több óra
    // 1 tétel = teljes kártya (cím + alcím), több = summary at-a-glance
    // ("2 dolgozat • 1 helyettesítés"). Lejárt napra nem mutat semmit.

    /// Még érvényes jegyzet: a napja ma vagy később van.
    private var validNote: TimetableWidgetStore.NextDayNote? {
        guard let note = entry.note, note.totalCount > 0 || note.noSchoolName != nil else { return nil }
        let cal = Calendar.current
        guard cal.startOfDay(for: note.day) >= cal.startOfDay(for: entry.effectiveNow) else { return nil }
        return note
    }

    /// Legközelebbi jövőbeli óra a teljes hétből (az üres állapothoz).
    private var nextFutureLesson: TimetableWidgetStore.Lesson? {
        entry.lessons
            .filter { $0.start > entry.effectiveNow && !$0.subject.trimmingCharacters(in: .whitespaces).isEmpty }
            .sorted { $0.start < $1.start }
            .first
    }

    /// Aktív jegyzet: csak akkor mutatjuk, ha a jegyzet napja egybeesik
    /// a legközelebbi jövőbeli óra napjával — különben a jegyzet (pl.
    /// keddi esemény) eltakarná a közelebbi órát (pl. hétfő 8:00).
    /// Ha nincs ismert jövőbeli óra, a jegyzet mehet (nincs mit takarni).
    private var activeNote: TimetableWidgetStore.NextDayNote? {
        guard let note = validNote else { return nil }
        guard let fl = nextFutureLesson else { return note }
        return Calendar.current.isDate(note.day, inSameDayAs: fl.start) ? note : nil
    }

    /// Mai infó reggelre: csak ha tényleg mára szól.
    private var validToday: TimetableWidgetStore.NextDayNote? {
        guard let info = entry.todayInfo,
              info.totalCount > 0 || info.noSchoolName != nil else { return nil }
        guard Calendar.current.isDate(info.day, inSameDayAs: entry.effectiveNow) else { return nil }
        return info
    }

    private func noteIcon(_ kind: String) -> String {
        switch kind {
        case "exam": return "doc.text.fill"
        case "cancelled": return "xmark.circle.fill"
        case "substituted": return "person.2.fill"
        case "event": return "calendar.badge.clock"
        default: return "bell.badge.fill"
        }
    }

    /// "HOLNAP" / napnév nagybetűvel a kártya fejlécébe.
    private func noteDayUpper(_ d: Date) -> String {
        let cal = Calendar.current
        if cal.isDateInTomorrow(d) { return "HOLNAP" }
        let f = DateFormatter(); f.locale = Locale(identifier: "hu_HU"); f.dateFormat = "EEEE"
        return f.string(from: d).uppercased()
    }

    /// "Holnap" / napnév az egysorosokba.
    private func noteDayShort(_ d: Date) -> String {
        let cal = Calendar.current
        if cal.isDateInTomorrow(d) { return "Holnap" }
        let f = DateFormatter(); f.locale = Locale(identifier: "hu_HU"); f.dateFormat = "EEEE"
        return f.string(from: d).capitalized
    }

    /// Summary több tételre: "2 dolgozat • 1 helyettesítés".
    private func noteSummary(_ n: TimetableWidgetStore.NextDayNote) -> String {
        var parts: [String] = []
        if n.examCount > 0 { parts.append("\(n.examCount) dolgozat") }
        if n.cancelledCount > 0 { parts.append("\(n.cancelledCount) elmaradó óra") }
        if n.substitutedCount > 0 { parts.append("\(n.substitutedCount) helyettesítés") }
        if n.eventCount > 0 { parts.append("\(n.eventCount) esemény") }
        return parts.joined(separator: " • ")
    }

    /// Egy tétel alcím-sora: "Fogadóóra • 17:00 – 19:00".
    private func noteItemLine(_ item: TimetableWidgetStore.NextDayItem) -> String {
        item.subtitle.isEmpty ? item.title : "\(item.title) • \(item.subtitle)"
    }

    @ViewBuilder
    private func noteCard(_ n: TimetableWidgetStore.NextDayNote, dayName: String? = nil) -> some View {
        let header = dayName ?? noteDayUpper(n.day)
        if let ns = n.noSchoolName {
            HStack(spacing: 4) {
                Image(systemName: "house.fill")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.secondary)
                Text(header)
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Text(ns)
                .font(.headline.weight(.bold)).lineLimit(1)
                .minimumScaleFactor(0.8)
            if n.totalCount == 1, let item = n.items.first {
                Text(noteItemLine(item))
                    .font(.caption2).foregroundStyle(.secondary).lineLimit(1)
            } else if n.totalCount > 1 {
                Text(noteSummary(n))
                    .font(.caption2).foregroundStyle(.secondary).lineLimit(1)
            }
        } else if n.totalCount == 1, let item = n.items.first {
            HStack(spacing: 4) {
                Image(systemName: noteIcon(item.kind))
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(item.kind == "cancelled" ? .red : .orange)
                Text(header)
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Text(item.title)
                .font(.headline.weight(.bold)).lineLimit(1)
                .truncationMode(.tail)
            if !item.subtitle.isEmpty {
                Text(item.subtitle)
                    .font(.caption2).foregroundStyle(.secondary).lineLimit(1)
            }
        } else {
            HStack(spacing: 4) {
                Image(systemName: "bell.badge.fill")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.orange)
                Text(header)
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Text(noteSummary(n))
                .font(.headline.weight(.bold)).lineLimit(1)
                .minimumScaleFactor(0.8)
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
                    countdownText.font(.caption2.weight(.bold).monospacedDigit())
                }
                .gaugeStyle(.accessoryCircular)
                .tint(statusTint(c))
            }
        case .duringBreak, .morning:
            if calc.state == .morning, let info = validToday {
                Image(systemName: info.totalCount == 1 ? noteIcon(info.items.first?.kind ?? "") : "bell.badge.fill")
            } else if let n = calc.next {
                Gauge(value: calc.progress) {
                    Text(n.index).font(.caption2.weight(.bold).monospacedDigit())
                } currentValueLabel: {
                    countdownText.font(.caption2.weight(.bold).monospacedDigit())
                }
                .gaugeStyle(.accessoryCircular)
                .tint(statusTint(n))
            }
        case .empty:
            if let note = activeNote {
                Image(systemName: note.totalCount == 1 ? noteIcon(note.items.first?.kind ?? "") : "bell.badge.fill")
            } else if nextFutureLesson != nil {
                Image(systemName: "calendar")
            } else {
                Image(systemName: "moon.zzz.fill")
            }
        }
    }

    // MARK: Egy sor a Smart Stack tetejére / sarki nézet
    private var inlineView: some View {
        inlineBody.lineLimit(1)
    }

    /// Óra alatt a mondat vége is él ("Most: Matek • 35:00"); máshol
    /// (időpontot mutató reggel/szünet, nap vége) marad a statikus szöveg.
    @ViewBuilder
    private var inlineBody: some View {
        if let phase = calc.phase, !isPreviewShift,
           entry.hasSnapshot, !entry.lessons.isEmpty,
           calc.state == .duringLesson, let c = calc.current {
            Text("Most: \(c.subject) • ") + Text(timerInterval: phase, countsDown: true)
        } else {
            Text(inlineText)
        }
    }

    // MARK: Sarok-komplikáció — tantárgy + óraszám + élő visszaszámláló
    // A sima "15 p" helyett kontextus is van: "MAT 2. • 12:34" (óra alatt),
    // "→ ANG 04:12" (szünetben/reggel, nyíl = következőre vár),
    // "VÉGE" nap végén. Az élő timer magától tickel, reload nélkül.
    private var cornerView: some View {
        cornerBody
            .font(.caption2.weight(.bold).monospacedDigit())
            .lineLimit(1)
            .minimumScaleFactor(0.6)
    }

    @ViewBuilder
    private var cornerBody: some View {
        if !entry.hasSnapshot || entry.lessons.isEmpty {
            Text("SUMMIT")
        } else if let phase = calc.phase, !isPreviewShift {
            switch calc.state {
            case .duringLesson:
                Text("\(cornerTitle) • ") + Text(timerInterval: phase, countsDown: true)
            case .duringBreak, .morning:
                Text("→ \(cornerAbbr) ") + Text(timerInterval: phase, countsDown: true)
            case .empty:
                Text("VÉGE")
            }
        } else {
            Text(cornerText)
        }
    }

    private var inlineText: String {
        guard entry.hasSnapshot, !entry.lessons.isEmpty else { return "Most: nyisd meg az appot" }
        switch calc.state {
        case .empty:
            if let note = activeNote {
                let day = noteDayShort(note.day)
                if let ns = note.noSchoolName {
                    if note.totalCount == 0 { return "\(day): \(ns)" }
                    let rest = note.totalCount == 1
                        ? (note.items.first.map(noteItemLine) ?? "")
                        : noteSummary(note)
                    return "\(day): \(ns) • \(rest)"
                }
                if note.totalCount == 1, let item = note.items.first {
                    return "\(day): \(item.title)"
                }
                return "\(day): \(noteSummary(note))"
            }
            if let fl = nextFutureLesson {
                return "\(noteDayShort(fl.start)): \(fl.subject) • \(shortTime(fl.start))"
            }
            return "Ma nincs több órád"
        case .morning:
            if let info = validToday {
                if info.totalCount == 1, let item = info.items.first {
                    return "Ma: \(item.title)"
                }
                return "Ma: \(noteSummary(info))"
            }
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
        guard entry.hasSnapshot, !entry.lessons.isEmpty else { return "SUMMIT" }
        switch calc.state {
        case .duringLesson:
            return "\(cornerTitle) • \(shortRemaining)"
        case .duringBreak:
            return "→ \(cornerAbbr) \(shortRemaining)"
        case .morning:
            if let info = validToday {
                if info.totalCount == 1, let kind = info.items.first?.kind {
                    return "\(kind == "event" ? "🎟" : "📝") Ma"
                }
                return "🔔 Ma"
            }
            return "→ \(cornerAbbr) \(shortRemaining)"
        case .empty:
            if let note = activeNote {
                let icon = note.noSchoolName != nil ? "🏫" : "🔔"
                return "\(icon) \(noteDayShort(note.day))"
            }
            if let fl = nextFutureLesson {
                return "→ \(noteDayShort(fl.start)) \(shortTime(fl.start))"
            }
            return "VÉGE"
        }
    }

    /// Sarokba való 3 betűs tantárgy-rövidítés: "Matematika" → "MAT",
    /// "Angol nyelv" → "ANG". A tartó / következő óra tárgyából.
    private var cornerAbbr: String {
        let subject = (calc.current ?? calc.next)?.subject ?? ""
        let first = subject.split(separator: " ").first.map(String.init) ?? ""
        let letters = first.filter { $0.isLetter }
        guard !letters.isEmpty else { return "ÓRA" }
        return String(letters.prefix(3)).uppercased()
    }

    /// "MAT 2." vagy óraszám nélkül csak "MAT" — dupla szóköz nélkül.
    private var cornerTitle: String {
        let idx = (calc.current ?? calc.next)?.index ?? ""
        return idx.isEmpty ? cornerAbbr : "\(cornerAbbr) \(idx)."
    }

    private var shortRemaining: String {
        // "42 perc van hátra" → "42 p"; "8 perc múlva kezdődik" → "8 p".
        let parts = calc.remainingText.split(separator: " ")
        if let first = parts.first, Int(first) != nil { return "\(first) p" }
        return calc.remainingText
    }

    /// Dev idő-csúszka aktív? Ilyenkor az élő timer rossz értéket mutatna
    /// (valós időben tickelne az eltolt fázisra), ezért statikus marad.
    /// A galéria-placeholder mikroszekundumos eltérését nem nézzük annak.
    private var isPreviewShift: Bool {
        abs(entry.effectiveNow.timeIntervalSince(entry.date)) > 1
    }

    /// Élő visszaszámláló ("35:00", másodpercenként tickel): a rendszer
    /// magától újrarajzolja, timeline-reload nélkül. Preview-eltolásnál
    /// és fázis nélkül a régi statikus "35 p" marad.
    @ViewBuilder
    private var countdownText: some View {
        if let phase = calc.phase, !isPreviewShift {
            Text(timerInterval: phase, countsDown: true)
        } else {
            Text(shortRemaining)
        }
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
        tasks: nil, accentHex: 0x4A90E2, hasSnapshot: true, note: nil, todayInfo: nil
    )
}
