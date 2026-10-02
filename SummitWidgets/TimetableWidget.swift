import SwiftUI
import WidgetKit

// MARK: - Órarend widget — az app editorial órarend-nézetének Home Screen tükre
// Adat: TimetableWidgetStore snapshot (App Group), egykezességgel a
// TimetableView írja. Mutatott nap: ma, ha még van hátra óra,
// különben a következő órás nap a cache-elt hétből.
struct TimetableWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: TimetableWidgetStore.kind, provider: TimetableWidgetProvider()) { entry in
            TimetableWidgetView(entry: entry)
        }
        .configurationDisplayName("Órarend")
        .description("A mai / következő tanítási nap órái az app órarend-nézetéből.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge, .accessoryCircular, .accessoryRectangular, .accessoryInline])
    }
}

// MARK: - Timeline

struct TimetableWidgetEntry: TimelineEntry {
    var date: Date
    /// Amivel rajzolunk: valós idő, vagy a dev idő-csúszka eltolt ideje.
    var effectiveNow: Date
    var dayLessons: [TimetableWidgetStore.Lesson]
    var dayDate: Date
    var accentHex: Int
    var hasSnapshot: Bool
    /// A következő tanítási nap rendkívüliségei (ha ma nincs több óra).
    var note: TimetableWidgetStore.NextDayNote?
}

struct TimetableWidgetProvider: TimelineProvider {
    func placeholder(in context: Context) -> TimetableWidgetEntry {
        let now = Date()
        return TimetableWidgetEntry(
            date: now, effectiveNow: now, dayLessons: Self.sampleLessons(),
            dayDate: now, accentHex: 0x4A90E2, hasSnapshot: false, note: nil
        )
    }

    func getSnapshot(in context: Context, completion: @escaping (TimetableWidgetEntry) -> Void) {
        completion(makeEntry(at: Date(), preview: context.isPreview))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<TimetableWidgetEntry>) -> Void) {
        let now = Date()
        guard let snap = TimetableWidgetStore.load(), !snap.lessons.isEmpty, !snap.previewActive else {
            // Nincs adat vagy dev idő-csúszka: egy belépő + rendszer-frissítés.
            let entry = makeEntry(at: now, preview: false)
            let refresh = Self.nextRefresh(now: now, effectiveNow: entry.effectiveNow, lessons: entry.dayLessons)
            completion(Timeline(entries: [entry], policy: .after(refresh)))
            return
        }
        // Előre számolt belépők (TimetableWidgetLogic): a widget magától
        // továbbmegy órahatárokon át, késleltetett rendszer-újratöltés
        // mellett is — egy határ már nem egy budgeted reloadba kerül.
        let dates = TimetableWidgetLogic.timelineMoments(now: now, lessons: snap.lessons)
        guard !dates.isEmpty else {
            // Ma már nincs hátra határ (pl. este): egy belépő + éjszakai újratöltés.
            let entry = makeEntry(at: now, preview: false)
            let refresh = Self.nextRefresh(now: now, effectiveNow: entry.effectiveNow, lessons: entry.dayLessons)
            completion(Timeline(entries: [entry], policy: .after(refresh)))
            return
        }
        completion(Timeline(entries: dates.map { makeEntry(at: $0, preview: false) }, policy: .atEnd))
    }

    private func makeEntry(at date: Date, preview: Bool) -> TimetableWidgetEntry {
        let now = date
        guard let snap = TimetableWidgetStore.load(), !snap.lessons.isEmpty else {
            return TimetableWidgetEntry(
                date: now, effectiveNow: now, dayLessons: preview ? Self.sampleLessons() : [],
                dayDate: now, accentHex: 0x4A90E2, hasSnapshot: false, note: nil
            )
        }
        let (day, lessons) = TimetableWidgetLogic.pickDay(now: now, lessons: snap.lessons)
        // Idő-eltolás: a csúszka a mutatott napon belüli időpont —
        // a napválasztás marad valós idejű, az állapot már eltolt.
        let effective: Date
        if snap.previewActive {
            let base = Calendar.current.startOfDay(for: day)
            effective = base.addingTimeInterval(snap.previewMinutes * 60)
        } else {
            effective = now
        }
        return TimetableWidgetEntry(
            date: now, effectiveNow: effective, dayLessons: lessons, dayDate: day,
            accentHex: snap.accentHex == 0 ? 0x4A90E2 : snap.accentHex,
            hasSnapshot: true, note: snap.nextNote
        )
    }

    /// A tiszta logika a TimetableWidgetLogic-ban él (próba is hajtja);
    /// itt csak a preview-minta marad.
    static func pickDay(now: Date, lessons: [TimetableWidgetStore.Lesson]) -> (Date, [TimetableWidgetStore.Lesson]) {
        TimetableWidgetLogic.pickDay(now: now, lessons: lessons)
    }

    static func nextRefresh(now: Date, effectiveNow: Date, lessons: [TimetableWidgetStore.Lesson]) -> Date {
        TimetableWidgetLogic.nextRefresh(now: now, effectiveNow: effectiveNow, lessons: lessons)
    }

    static func sampleLessons() -> [TimetableWidgetStore.Lesson] {
        let cal = Calendar.current
        let morning = cal.date(bySettingHour: 8, minute: 0, second: 0, of: Date()) ?? Date()
        let subjects = [("Matematika", "A.12", "Nagy Éva"), ("Angol nyelv", "B.07", "Kiss Péter"), ("Fizika", "C.21", "Szabó Anna")]
        return subjects.enumerated().map { i, s in
            let start = morning.addingTimeInterval(Double(i) * 3600)
            return TimetableWidgetStore.Lesson(
                id: "sample-\(i)", subject: s.0, room: s.1, teacher: s.2,
                index: "\(i + 1)", start: start, end: start.addingTimeInterval(45 * 60),
                isCancelled: false, isSubstituted: i == 2
            )
        }
    }
}

// MARK: - MOST-számítás — az órai WatchNowCalc iPhone-portja
// Ugyanazok az állapotok és szövegek: tartó óra + progress + "X perc van
// hátra", szünet + "X perc múlva kezdődik", reggel az első, nap végén
// "Ma nincs több órád". Plusz egy iPhone-saját állapot: a provider olykor
// jövőbeli napot választ (holnap listája a home screenen) — ilyenkor nincs
// élő fázis, a csík mellett a nap + időpont áll ("Holnap • 8:00").
// Feladat-részletek (dolgozat/házi címe) az iPhone-snapshotban nincsenek,
// csak a hasAssignment-flag — azt az attachedLine használja.
private struct PhoneNowCalc {
    enum State { case empty, morning, upcoming, duringLesson, duringBreak }
    var state: State = .empty
    var current: TimetableWidgetStore.Lesson?
    var next: TimetableWidgetStore.Lesson?
    var previous: TimetableWidgetStore.Lesson?
    var progress: Double = 0
    var remainingText: String = ""
    /// Az aktuális fázis fix intervalluma az ÉLŐ visszaszámlálóhoz.
    /// Nil = nincs mutatnivaló fázis (pl. jövőbeli nap).
    var phase: ClosedRange<Date>? = nil

    private static func formatRemaining(_ minutes: Int, past: Bool) -> String {
        if minutes <= 0 { return past ? "Vége" : "Kezdődik" }
        return past ? "\(minutes) perc van hátra" : "\(minutes) perc múlva kezdődik"
    }

    init(lessons: [TimetableWidgetStore.Lesson], now: Date, calendar: Calendar = .current) {
        let filtered = lessons
            .filter { !$0.subject.trimmingCharacters(in: .whitespaces).isEmpty }
            .sorted { $0.start < $1.start }
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
                if p.end <= nxt.start { phase = p.end...nxt.start }
            } else if now < filtered.first!.start {
                let first = filtered.first!
                if calendar.isDate(first.start, inSameDayAs: now) {
                    state = .morning
                    let morningStart = calendar.date(bySettingHour: 7, minute: 0, second: 0, of: now) ?? now
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
                    // Jövőbeli nap (pl. holnapi lista): statikus nap + időpont.
                    state = .upcoming
                    let label: String
                    if calendar.isDateInTomorrow(first.start) {
                        label = "Holnap"
                    } else {
                        let f = DateFormatter(); f.locale = Locale(identifier: "hu_HU"); f.dateFormat = "EEEE"
                        label = f.string(from: first.start).capitalized
                    }
                    remainingText = "\(label) • \(first.start.formatted(date: .omitted, time: .shortened))"
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
    }
}

// MARK: - Nézet

// Natív átlátszó liquid glass: nincs saját háttér, a rendszer adja az
// üveget (sötét/világos módban is). Az állapotot CSAK a színek mutatják:
// aktuális = accent, elmarad = piros, helyettesítés = narancs.
private struct TimetableWidgetView: View {
    let entry: TimetableWidgetEntry
    @Environment(\.widgetFamily) private var family

    private var accent: Color { Color(widgetHex: UInt(entry.accentHex)) }
    private var now: Date { entry.effectiveNow }
    private var nowCalc: PhoneNowCalc {
        PhoneNowCalc(lessons: entry.dayLessons, now: entry.effectiveNow)
    }

    private var currentID: String? {
        entry.dayLessons.first(where: { $0.start <= now && $0.end >= now })?.id
    }
    private var nextLesson: TimetableWidgetStore.Lesson? {
        entry.dayLessons.sorted { $0.start < $1.start }.first(where: { $0.start > now })
    }

    var body: some View {
        switch family {
        case .accessoryCircular:
            circularView
        case .accessoryRectangular:
            accessoryView
        case .accessoryInline:
            inlineView
        case .systemSmall:
            smallView
        case .systemLarge:
            listView(maxRows: 7)
        default:
            listView(maxRows: 3)
        }
    }

    // MARK: Lock screen — "Most" kártya 3 sorban
    // A téglalap-slot kb. 160×76 pt: egy státusz-fejléc + egy cím + egy
    // info-sor fér el kényelmesen. A "→ következő óra" sor csak óra alatt
    // jelenik meg, ahol tényleg más óra jön: szünetben/reggel a mutatott
    // óra MAGA a következő, ott a duplikált cím (tárgy + "→ tárgy") volt
    // a fura. Különbség az órához
    // képest: az iPhone-snapshot csak egy hasAssignment-flaget hordoz
    // (dolgozat/házi részletei nélkül), ezért a kártya alján összevont
    // "Számonkérés" sor áll a két részletes órai sor helyett.
    private var accessoryView: some View {
        VStack(alignment: .leading, spacing: 2) {
            Spacer(minLength: 0)
            if !entry.hasSnapshot && entry.dayLessons.isEmpty {
                Text("Nyisd meg az appot")
                    .font(.headline.weight(.semibold)).lineLimit(1)
                Text("Az órarend az app megnyitása után érkezik.")
                    .font(.caption2).foregroundStyle(.secondary).lineLimit(1)
            } else {
                switch nowCalc.state {
                case .empty:
                    if let note = activeNote {
                        noteCard(note)
                    } else {
                        Label("Ma nincs több órád", systemImage: "moon.zzz.fill")
                            .font(.headline.weight(.semibold)).lineLimit(1)
                    }
                case .duringLesson:
                    if let c = nowCalc.current {
                        subjectLine(c)
                        progressLine(tint: statusTint(c))
                        if let n = nowCalc.next, n.id != c.id {
                            nextLine(n)
                        }
                    }
                case .duringBreak:
                    if let n = nowCalc.next {
                        statusHeader("SZÜNET")
                        subjectLine(n)
                        progressLine(tint: statusTint(n))
                    }
                case .morning:
                    if let n = nowCalc.next {
                        statusHeader("ELSŐ ÓRA")
                        subjectLine(n)
                        progressLine(tint: statusTint(n))
                    }
                case .upcoming:
                    if let note = activeNote {
                        noteCard(note)
                    } else if let n = nowCalc.next {
                        statusHeader(dayLabel(n.start).uppercased())
                        subjectLine(n)
                        staticLine(nowCalc.remainingText)
                    }
                }
                attachedLine
            }
            Spacer(minLength: 0)
        }
        .containerBackground(for: .widget) {
            LinearGradient(
                colors: [.white.opacity(0.16), .white.opacity(0.03)],
                startPoint: .top, endPoint: .bottom
            )
        }
    }

    /// Státusz-fejléc kiskapitálissal: MOST / SZÜNET / ELSŐ ÓRA / HOLNAP.
    private func statusHeader(_ s: String) -> some View {
        Text(s)
            .font(.caption2.weight(.bold)).tracking(0.8)
            .foregroundStyle(.secondary).lineLimit(1)
    }

    /// Cím-sor: tárgy + kis pötty + terem.
    private func subjectLine(_ l: TimetableWidgetStore.Lesson) -> some View {
        HStack(spacing: 4) {
            Text(l.subject)
                .font(.headline.weight(.bold)).lineLimit(1)
                .truncationMode(.tail)
            Text("•").foregroundStyle(.tertiary).font(.caption2)
            Text(l.room.isEmpty ? l.teacher : l.room)
                .font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
        }
    }

    /// Statikus info-sor élő fázis nélkül (jövőbeli nap: "Holnap • 8:00").
    private func staticLine(_ s: String) -> some View {
        Text(s)
            .font(.caption2.weight(.bold).monospacedDigit())
            .foregroundStyle(.secondary).lineLimit(1)
    }

    // MARK: Következő napi kártya — ha ma nincs több óra
    // 1 tétel = teljes kártya (cím + alcím), több = summary at-a-glance.

    /// Még érvényes jegyzet: a napja ma vagy később van.
    private var validNote: TimetableWidgetStore.NextDayNote? {
        guard let note = entry.note, note.totalCount > 0 || note.noSchoolName != nil else { return nil }
        let cal = Calendar.current
        guard cal.startOfDay(for: note.day) >= cal.startOfDay(for: entry.effectiveNow) else { return nil }
        return note
    }

    /// Aktív jegyzet: üres állapotban bármely érvényes jövőbeli jegyzet
    /// mehet, holnapi nézetben csak az arra a napra szóló — különben egy
    /// távoli jegyzet (pl. keddi esemény) eltakarná a közelebbi órát
    /// (pl. hétfő 8:00).
    private var activeNote: TimetableWidgetStore.NextDayNote? {
        guard let note = validNote else { return nil }
        switch nowCalc.state {
        case .empty:
            return note
        case .upcoming:
            return Calendar.current.isDate(note.day, inSameDayAs: entry.dayDate) ? note : nil
        default:
            return nil
        }
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
    private func noteCard(_ n: TimetableWidgetStore.NextDayNote) -> some View {
        if let ns = n.noSchoolName {
            HStack(spacing: 4) {
                Image(systemName: "house.fill")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.secondary)
                Text(dayLabel(n.day).uppercased())
                    .font(.caption2.weight(.bold)).tracking(0.8)
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
                Text(dayLabel(n.day).uppercased())
                    .font(.caption2.weight(.bold)).tracking(0.8)
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
                Text(dayLabel(n.day).uppercased())
                    .font(.caption2.weight(.bold)).tracking(0.8)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Text(noteSummary(n))
                .font(.headline.weight(.bold)).lineLimit(1)
                .minimumScaleFactor(0.8)
        }
    }

    /// Következő óra egy sorban: nyíl + terem + pötty + tárgy. Csak óra
    /// alatt jelenik meg, ahol a következő tényleg MÁS óra (nincs duplikált
    /// cím, mint a szünetes "tárgy + → tárgy" volt).
    private func nextLine(_ n: TimetableWidgetStore.Lesson) -> some View {
        HStack(spacing: 4) {
            Image(systemName: "arrow.right.circle.fill")
                .font(.caption2.weight(.bold))
                .foregroundStyle(.secondary)
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
    }

    /// Rövid vékony accent-csík, MELLETTE az élő visszaszámláló
    /// ("27:54", másodpercenként tickel, reload nélkül). Óraszám sehol.
    private func progressLine(tint: Color) -> some View {
        HStack(spacing: 6) {
            ProgressView(value: nowCalc.progress)
                .tint(tint)
                .frame(width: 100)
            countdownText
                .font(.caption2.weight(.bold).monospacedDigit())
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }

    /// Számonkérés-jelzés a kártya alján, az órai dolgozat/házi sorok helyén.
    @ViewBuilder
    private var attachedLine: some View {
        if let anchor = nowCalc.current ?? nowCalc.next, anchor.hasAssignment {
            Label("Számonkérés ehhez az órához", systemImage: "exclamationmark.triangle.fill")
                .font(.caption2.weight(.semibold)).foregroundStyle(.orange).lineLimit(1)
        }
    }

    // MARK: Kör — progress-gyűrű + hátralévő idő (mint az órán)
    @ViewBuilder
    private var circularView: some View {
        switch nowCalc.state {
        case .duringLesson:
            if let c = nowCalc.current {
                Gauge(value: nowCalc.progress) {
                    Text(c.index).font(.caption2.weight(.bold).monospacedDigit())
                } currentValueLabel: {
                    countdownText.font(.caption2.weight(.bold).monospacedDigit())
                }
                .gaugeStyle(.accessoryCircular)
                .tint(statusColor(c))
            }
        case .duringBreak, .morning, .upcoming:
            if let n = nowCalc.next {
                Gauge(value: nowCalc.progress) {
                    Text(n.index).font(.caption2.weight(.bold).monospacedDigit())
                } currentValueLabel: {
                    countdownText.font(.caption2.weight(.bold).monospacedDigit())
                }
                .gaugeStyle(.accessoryCircular)
                .tint(statusColor(n))
            }
        case .empty:
            if let note = activeNote {
                Image(systemName: note.totalCount == 1 ? noteIcon(note.items.first?.kind ?? "") : "bell.badge.fill")
            } else {
                Image(systemName: "moon.zzz.fill")
            }
        }
    }

    // MARK: Egysoros — a zárképernyő óra fölötti sávjába (mint az órán)
    private var inlineView: some View {
        inlineBody.lineLimit(1)
    }

    @ViewBuilder
    private var inlineBody: some View {
        if let phase = nowCalc.phase, !isPreviewShift,
           entry.hasSnapshot, !entry.dayLessons.isEmpty,
           nowCalc.state == .duringLesson, let c = nowCalc.current {
            Text("Most: \(c.subject) • ") + Text(timerInterval: phase, countsDown: true)
        } else {
            Text(inlineText)
        }
    }

    /// Egysoros jegyzet-szöveg ("Holnap: Matek" / "Holnap: 2 dolgozat").
    private func noteLine(_ n: TimetableWidgetStore.NextDayNote) -> String {
        let day = dayLabel(n.day)
        if let ns = n.noSchoolName {
            if n.totalCount == 0 { return "\(day): \(ns)" }
            let rest = n.totalCount == 1
                ? (n.items.first.map(noteItemLine) ?? "")
                : noteSummary(n)
            return "\(day): \(ns) • \(rest)"
        }
        if n.totalCount == 1, let item = n.items.first {
            return "\(day): \(item.title)"
        }
        return "\(day): \(noteSummary(n))"
    }

    private var inlineText: String {
        guard entry.hasSnapshot, !entry.dayLessons.isEmpty else { return "Most: nyisd meg az appot" }
        switch nowCalc.state {
        case .empty:
            if let note = activeNote { return noteLine(note) }
            return "Ma nincs több órád"
        case .morning:
            if let n = nowCalc.next { return "Első: \(n.subject) • \(shortTime(n.start))" }
            return "Ma nincs több órád"
        case .upcoming:
            if let note = activeNote { return noteLine(note) }
            if let n = nowCalc.next { return "\(dayLabel(n.start)): \(n.subject) • \(shortTime(n.start))" }
            return "Ma nincs több órád"
        case .duringLesson:
            if let c = nowCalc.current { return "Most: \(c.subject) • \(nowCalc.remainingText)" }
            return "Ma nincs több órád"
        case .duringBreak:
            if let n = nowCalc.next { return "Szünet • \(n.subject) \(shortTime(n.start))" }
            return "Ma nincs több órád"
        }
    }

    /// Élő visszaszámláló ("35:00"): a rendszer magától újrarajzolja,
    /// timeline-reload nélkül. Fázis nélkül a statikus szöveg marad.
    @ViewBuilder
    private var countdownText: some View {
        if let phase = nowCalc.phase, !isPreviewShift {
            Text(timerInterval: phase, countsDown: true)
        } else {
            Text(shortRemaining)
        }
    }

    private var shortRemaining: String {
        // "42 perc van hátra" → "42 p"; dátumos ("Holnap • 8:00") marad.
        let parts = nowCalc.remainingText.split(separator: " ")
        if let first = parts.first, Int(first) != nil { return "\(first) p" }
        return nowCalc.remainingText
    }

    /// Dev idő-csúszka aktív? Ilyenkor az élő timer rossz értéket mutatna,
    /// ezért statikus marad.
    private var isPreviewShift: Bool {
        abs(entry.effectiveNow.timeIntervalSince(entry.date)) > 60
    }

    /// "Holnap" / napnév a jövőbeli naphoz ("Hétfő"), ma nincs használva.
    private func dayLabel(_ d: Date) -> String {
        let cal = Calendar.current
        if cal.isDateInTomorrow(d) { return "Holnap" }
        let f = DateFormatter(); f.locale = Locale(identifier: "hu_HU"); f.dateFormat = "EEEE"
        return f.string(from: d).capitalized
    }

    private func shortTime(_ d: Date) -> String {
        d.formatted(date: .omitted, time: .shortened)
    }

    private func statusTint(_ l: TimetableWidgetStore.Lesson) -> Color {
        if l.isCancelled { return .red }
        if l.isSubstituted { return .orange }
        return accent
    }

    // MARK: Small — csak a lényeg: státusz színnel, tárgy, idő
    private var smallView: some View {
        VStack(alignment: .leading, spacing: 2) {
            if let h = dayHeader {
                Text(h).font(.caption.weight(.medium))
                    .foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 0)
            if entry.dayLessons.isEmpty {
                emptyView
            } else if let cur = entry.dayLessons.first(where: { $0.id == currentID }) {
                Text("Most • \(remainingMinutes(cur))").font(.caption.weight(.semibold)).foregroundStyle(statusColor(cur))
                Text(cur.subject).font(.title3.weight(.bold)).lineLimit(2).minimumScaleFactor(0.8)
                Text("\(cur.index). óra • \(cur.room) • \(timeRange(cur))")
                    .font(.footnote.monospacedDigit()).foregroundStyle(.secondary).lineLimit(1)
            } else if let nxt = nextLesson {
                Text("Következő • \(nxt.start.formatted(date: .omitted, time: .shortened))")
                    .font(.caption.weight(.semibold)).foregroundStyle(statusColor(nxt))
                Text(nxt.subject).font(.title3.weight(.bold)).lineLimit(2).minimumScaleFactor(0.8)
                Text("\(nxt.index). óra • \(nxt.room) • \(timeRange(nxt))")
                    .font(.footnote.monospacedDigit()).foregroundStyle(.secondary).lineLimit(1)
            } else {
                Text("Mára vége").font(.title3.weight(.bold))
            }
            Spacer(minLength: 0)
        }
        // Külső margó nincs: iOS 17+ óta a WidgetKit magától teszi a tartalom
        // köré a szabványos, mind a 4 oldalon egyforma margót (mint az Apple
        // Időjárás-widgeten) — a kézi padding duplázna, és a lista túl magas
        // lesz, ezért vágódik le felül.
    }

    // MARK: Medium / Large — kompakt editorial lista: visszafogott fejléc,
    // karcsú sorok (szám + tárgy + meta), az aktuális óra halvány
    // accent-hátteret kap — így nem egyforma súlyú minden sor.
    private func listView(maxRows: Int) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            if let h = dayHeader {
                Text(h).font(.caption2.weight(.bold)).tracking(0.6)
                    .foregroundStyle(.secondary).lineLimit(1)
                    .padding(.bottom, 6)
            }
            if entry.dayLessons.isEmpty {
                emptyView.padding(.top, 4)
            } else {
                // Ablakos lista: legfelül a tartó (vagy a következő) óra,
                // alatta a rákövetkezők — az 5. óra alatt az 5–6–7. látszik.
                let vis = TimetableWidgetLogic.window(lessons: entry.dayLessons, now: now, maxRows: maxRows)
                VStack(alignment: .leading, spacing: 4) {
                    if vis.earlier > 0 {
                        Text("↑ \(vis.earlier) korábbi óra")
                            .font(.caption2).foregroundStyle(.tertiary)
                            .padding(.horizontal, 8)
                    }
                    ForEach(vis.rows, id: \.id) { l in
                        row(l)
                    }
                    if vis.later > 0 {
                        Text("+\(vis.later) további óra")
                            .font(.caption2).foregroundStyle(.tertiary)
                            .padding(.horizontal, 8)
                            .padding(.top, 2)
                    }
                }
            }
            Spacer(minLength: 0)
        }
        // Külső margó nincs (lásd smallView): a rendszer-margó az egyforma.
    }

    private func row(_ l: TimetableWidgetStore.Lesson) -> some View {
        HStack(spacing: 10) {
            Text(l.index)
                .font(.callout.weight(.bold).monospacedDigit())
                .foregroundStyle(numberColor(l))
                .frame(width: 20, alignment: .trailing)
            VStack(alignment: .leading, spacing: 1) {
                Text(l.subject)
                    .font(.subheadline.weight(.semibold))
                    .strikethrough(l.isCancelled, color: .secondary)
                    .foregroundStyle(subjectColor(l))
                    .lineLimit(1)
                Text("\(l.room) • \(timeRange(l))")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 4)
            if l.isCancelled {
                Text("elmarad").font(.caption2.weight(.semibold)).foregroundStyle(.red)
            } else if l.isSubstituted {
                Text("helyettesítés").font(.caption2.weight(.semibold)).foregroundStyle(.orange)
            } else if isCurrent(l) {
                Text(remainingMinutes(l)).font(.caption2.weight(.semibold).monospacedDigit())
                    .foregroundStyle(accent)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background {
            if isCurrent(l) {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(accent.opacity(0.14))
            }
        }
    }

    private func subjectColor(_ l: TimetableWidgetStore.Lesson) -> Color {
        if l.isCancelled { return .secondary }
        if isCurrent(l) { return accent }
        return .primary
    }

    private var emptyView: some View {
        VStack(alignment: .leading, spacing: 4) {
            Image(systemName: entry.hasSnapshot ? "moon.zzz.fill" : "calendar.badge.exclamationmark")
                .font(.title3).foregroundStyle(.secondary)
            Text(entry.hasSnapshot ? "Nincs óra" : "Nyisd meg az appot")
                .font(.system(size: 15, weight: .bold, design: .rounded))
            Text(entry.hasSnapshot ? "Pihenőnap — tölts egy kávét." : "Az órarend az első Órarend-megnyitás után jelenik meg.")
                .font(.caption2.weight(.medium)).foregroundStyle(.secondary).lineLimit(2)
        }
    }

    // MARK: Segédek — az app TimetableRow prioritásával
    private var dayTitle: String {
        let f = DateFormatter(); f.locale = Locale(identifier: "hu_HU"); f.dateFormat = "EEEE"
        return f.string(from: entry.dayDate).capitalized
    }
    /// Fejléc-nap "ÓRAREND" nélkül: holnap → "HOLNAP", távolabbi nap → a nap
    /// neve, ma → nil (nincs fejlécsor). Adat nélkül "ÓRAREND".
    private var dayHeader: String? {
        if !entry.hasSnapshot && entry.dayLessons.isEmpty { return "ÓRAREND" }
        let cal = Calendar.current
        if cal.isDateInToday(entry.dayDate) { return nil }
        if cal.isDateInTomorrow(entry.dayDate) { return "HOLNAP" }
        return dayTitle.uppercased()
    }
    private var dayCountLine: String {
        "\(entry.dayLessons.count) óra • \(dayTitle)"
    }
    private func isCurrent(_ l: TimetableWidgetStore.Lesson) -> Bool { l.id == currentID }
    private func progress(of l: TimetableWidgetStore.Lesson) -> Double {
        let t = l.end.timeIntervalSince(l.start)
        guard t > 0 else { return 0 }
        return min(1, max(0, now.timeIntervalSince(l.start) / t))
    }
    private func timeRange(_ l: TimetableWidgetStore.Lesson) -> String {
        "\(l.start.formatted(date: .omitted, time: .shortened))–\(l.end.formatted(date: .omitted, time: .shortened))"
    }
    private func remainingMinutes(_ l: TimetableWidgetStore.Lesson) -> String {
        let rem = Int(ceil(l.end.timeIntervalSince(now) / 60))
        return rem <= 0 ? "Vége" : "\(rem) p"
    }
    private func statusColor(_ l: TimetableWidgetStore.Lesson) -> Color {
        if l.isCancelled { return .red }
        if l.isSubstituted { return .orange }
        if isCurrent(l) { return accent }
        return .gray
    }
    private func numberColor(_ l: TimetableWidgetStore.Lesson) -> Color {
        if l.isCancelled { return .red }
        if l.isSubstituted { return .orange }
        if isCurrent(l) { return .white }
        return .primary
    }
}

// MARK: - Self-contained hex — nem függ az AppColors.swift-től
private extension Color {
    init(widgetHex: UInt, alpha: Double = 1.0) {
        let r = Double((widgetHex >> 16) & 0xFF) / 255.0
        let g = Double((widgetHex >> 8) & 0xFF) / 255.0
        let b = Double(widgetHex & 0xFF) / 255.0
        self.init(.sRGB, red: r, green: g, blue: b, opacity: alpha)
    }
}

#Preview(as: .systemMedium) {
    TimetableWidget()
} timeline: {
    TimetableWidgetEntry(
        date: Date(), effectiveNow: Date(), dayLessons: TimetableWidgetProvider.sampleLessons(),
        dayDate: Date(), accentHex: 0x4A90E2, hasSnapshot: true, note: nil
    )
}

// MARK: - Mai nap widget — általános napi infó az aktuális óra helyett
// Lock screenre: ha van mai iskolai esemény, azt mutatja; különben a mai
// dolgozatokat; különben a hátralévő órákat ("Még 3 órád van"). Óra alatt
// sem az aktuális órát írja — ez a Most-kártya kistestvére, nem ikre.
// Adat: ugyanaz a snapshot (mai lecke-lista + todayInfo + nextNote).
struct SchoolDayWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: TimetableWidgetStore.dayKind, provider: SchoolDayProvider()) { entry in
            SchoolDayView(entry: entry)
        }
        .configurationDisplayName("Mai nap")
        .description("Mai események, dolgozatok és hátralévő órák — nem az aktuális óra.")
        .supportedFamilies([.accessoryCircular, .accessoryRectangular, .accessoryInline])
    }
}

struct SchoolDayEntry: TimelineEntry {
    var date: Date
    var effectiveNow: Date
    var todayLessons: [TimetableWidgetStore.Lesson]
    /// Mai rendkívüliségek (esemény-első sorrendben).
    var info: TimetableWidgetStore.NextDayNote?
    /// Tartalék nap végére (mint a Most-widget jegyzete).
    var next: TimetableWidgetStore.NextDayNote?
    var accentHex: Int
    var hasSnapshot: Bool
}

struct SchoolDayProvider: TimelineProvider {
    func placeholder(in context: Context) -> SchoolDayEntry {
        let now = Date()
        return SchoolDayEntry(
            date: now, effectiveNow: now, todayLessons: TimetableWidgetProvider.sampleLessons(),
            info: nil, next: nil, accentHex: 0x4A90E2, hasSnapshot: false
        )
    }

    func getSnapshot(in context: Context, completion: @escaping (SchoolDayEntry) -> Void) {
        completion(makeEntry(at: Date(), preview: context.isPreview))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<SchoolDayEntry>) -> Void) {
        let now = Date()
        guard let snap = TimetableWidgetStore.load(), !snap.lessons.isEmpty, !snap.previewActive else {
            let entry = makeEntry(at: now, preview: false)
            let refresh = TimetableWidgetLogic.nextRefresh(now: now, effectiveNow: entry.effectiveNow, lessons: entry.todayLessons)
            completion(Timeline(entries: [entry], policy: .after(refresh)))
            return
        }
        let dates = TimetableWidgetLogic.timelineMoments(now: now, lessons: snap.lessons)
        guard !dates.isEmpty else {
            let entry = makeEntry(at: now, preview: false)
            let refresh = TimetableWidgetLogic.nextRefresh(now: now, effectiveNow: entry.effectiveNow, lessons: snap.lessons)
            completion(Timeline(entries: [entry], policy: .after(refresh)))
            return
        }
        completion(Timeline(entries: dates.map { makeEntry(at: $0, preview: false) }, policy: .atEnd))
    }

    private func makeEntry(at date: Date, preview: Bool) -> SchoolDayEntry {
        let now = date
        guard let snap = TimetableWidgetStore.load(), !snap.lessons.isEmpty else {
            return SchoolDayEntry(
                date: now, effectiveNow: now,
                todayLessons: preview ? TimetableWidgetProvider.sampleLessons() : [],
                info: nil, next: nil, accentHex: 0x4A90E2, hasSnapshot: false
            )
        }
        let effective: Date
        if snap.previewActive {
            let base = Calendar.current.startOfDay(for: now)
            effective = base.addingTimeInterval(snap.previewMinutes * 60)
        } else {
            effective = now
        }
        let cal = Calendar.current
        let today = snap.lessons
            .filter { cal.isDate($0.start, inSameDayAs: effective) }
            .filter { !$0.subject.trimmingCharacters(in: .whitespaces).isEmpty }
            .sorted { $0.start < $1.start }
        return SchoolDayEntry(
            date: now, effectiveNow: effective, todayLessons: today,
            info: snap.todayInfo, next: snap.nextNote,
            accentHex: snap.accentHex == 0 ? 0x4A90E2 : snap.accentHex,
            hasSnapshot: true
        )
    }
}

private struct SchoolDayView: View {
    let entry: SchoolDayEntry
    @Environment(\.widgetFamily) private var family

    private var now: Date { entry.effectiveNow }
    private var remaining: [TimetableWidgetStore.Lesson] {
        entry.todayLessons.filter { $0.end > now }.sorted { $0.start < $1.start }
    }
    private var current: TimetableWidgetStore.Lesson? {
        remaining.first(where: { $0.start <= now && $0.end >= now })
    }
    private var next: TimetableWidgetStore.Lesson? {
        entry.todayLessons.sorted { $0.start < $1.start }.first(where: { $0.start > now })
    }

    /// Mai infó, ha tényleg mára szól (publikálás óta nem fordult a nap).
    private var validInfo: TimetableWidgetStore.NextDayNote? {
        guard let info = entry.info, info.totalCount > 0 || info.noSchoolName != nil else { return nil }
        let cal = Calendar.current
        guard cal.isDate(info.day, inSameDayAs: now) else { return nil }
        return info
    }

    /// Tartalék-jegyzet nap végére (mint a Most-widgetnél).
    private var validNext: TimetableWidgetStore.NextDayNote? {
        guard let note = entry.next, note.totalCount > 0 || note.noSchoolName != nil else { return nil }
        let cal = Calendar.current
        guard cal.startOfDay(for: note.day) >= cal.startOfDay(for: now) else { return nil }
        return note
    }

    var body: some View {
        switch family {
        case .accessoryCircular:
            circularView
        case .accessoryInline:
            Text(inlineText).lineLimit(1)
        default:
            rectangularView
        }
    }

    // MARK: Téglalap — esemény > dolgozat > hátralévő órák

    private var rectangularView: some View {
        VStack(alignment: .leading, spacing: 2) {
            Spacer(minLength: 0)
            if !entry.hasSnapshot && entry.todayLessons.isEmpty && validInfo == nil {
                Text("Nyisd meg az appot")
                    .font(.headline.weight(.semibold)).lineLimit(1)
                Text("A napi infó az app megnyitása után érkezik.")
                    .font(.caption2).foregroundStyle(.secondary).lineLimit(1)
            } else if !remaining.isEmpty {
                if let info = validInfo {
                    dayCard(info, dayName: "MA")
                } else {
                    statusHeader("MA")
                    Text(remainingText)
                        .font(.headline.weight(.bold)).lineLimit(1)
                    Text(subLine)
                        .font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                }
            } else if !entry.todayLessons.isEmpty {
                // Tanítás véget ért: már a holnap számít, a mai infó csak tartalék.
                if let note = validNext {
                    dayCard(note, dayName: dayLabel(note.day).uppercased())
                } else if let info = validInfo {
                    dayCard(info, dayName: "MA")
                } else {
                    Label("Mára vége", systemImage: "moon.zzz.fill")
                        .font(.headline.weight(.semibold)).lineLimit(1)
                }
            } else if let info = validInfo {
                dayCard(info, dayName: "MA")
            } else if let note = validNext {
                dayCard(note, dayName: dayLabel(note.day).uppercased())
            } else {
                Label("Ma nincs tanítás", systemImage: "calendar.badge.clock")
                    .font(.headline.weight(.semibold)).lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .containerBackground(for: .widget) {
            LinearGradient(
                colors: [.white.opacity(0.16), .white.opacity(0.03)],
                startPoint: .top, endPoint: .bottom
            )
        }
    }

    /// 1 tétel = teljes kártya, több = summary ("2 dolgozat").
    @ViewBuilder
    private func dayCard(_ n: TimetableWidgetStore.NextDayNote, dayName: String) -> some View {
        if let ns = n.noSchoolName {
            HStack(spacing: 4) {
                Image(systemName: "house.fill")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.secondary)
                Text(dayName)
                    .font(.caption2.weight(.bold)).tracking(0.8)
                    .foregroundStyle(.secondary).lineLimit(1)
            }
            Text(ns)
                .font(.headline.weight(.bold)).lineLimit(1)
                .minimumScaleFactor(0.8)
            if n.totalCount == 1, let item = n.items.first {
                Text(dayItemLine(item))
                    .font(.caption2).foregroundStyle(.secondary).lineLimit(1)
            } else if n.totalCount > 1 {
                Text(daySummary(n))
                    .font(.caption2).foregroundStyle(.secondary).lineLimit(1)
            }
        } else if n.totalCount == 1, let item = n.items.first {
            HStack(spacing: 4) {
                Image(systemName: noteIcon(item.kind))
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(item.kind == "cancelled" ? .red : .orange)
                Text(dayName)
                    .font(.caption2.weight(.bold)).tracking(0.8)
                    .foregroundStyle(.secondary).lineLimit(1)
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
                Text(dayName)
                    .font(.caption2.weight(.bold)).tracking(0.8)
                    .foregroundStyle(.secondary).lineLimit(1)
            }
            Text(daySummary(n))
                .font(.headline.weight(.bold)).lineLimit(1)
                .minimumScaleFactor(0.8)
        }
    }

    private var remainingText: String {
        let c = remaining.count
        return c == 1 ? "Még 1 órád van" : "Még \(c) órád van"
    }

    private var subLine: String {
        if let cur = current {
            return "Most: \(cur.subject)"
        }
        if let nxt = next {
            return "Kövi: \(nxt.subject) • \(shortTime(nxt.start))"
        }
        return ""
    }

    private func statusHeader(_ s: String) -> some View {
        Text(s)
            .font(.caption2.weight(.bold)).tracking(0.8)
            .foregroundStyle(.secondary).lineLimit(1)
    }

    // MARK: Kör + egysoros

    @ViewBuilder
    private var circularView: some View {
        if !remaining.isEmpty {
            if validInfo != nil {
                Image(systemName: "calendar.badge.exclamationmark")
            } else {
                Text("\(remaining.count)")
                    .font(.title3.weight(.bold).monospacedDigit())
            }
        } else if validNext != nil {
            Image(systemName: "bell.badge.fill")
        } else {
            Image(systemName: "moon.zzz.fill")
        }
    }

    private var inlineText: String {
        guard entry.hasSnapshot || validInfo != nil else { return "Nyisd meg az appot" }
        if !remaining.isEmpty {
            if let info = validInfo { return todayLine(info) }
            return remainingText
        }
        if !entry.todayLessons.isEmpty {
            if let note = validNext { return nextInlineLine(note) }
            if let info = validInfo { return todayLine(info) }
            return "Mára vége"
        }
        if let info = validInfo { return todayLine(info) }
        if let note = validNext { return nextInlineLine(note) }
        return "Ma nincs tanítás"
    }

    private func todayLine(_ info: TimetableWidgetStore.NextDayNote) -> String {
        if info.totalCount == 1, let item = info.items.first {
            return "Ma: \(dayItemLine(item))"
        }
        return "Ma: \(daySummary(info))"
    }

    private func nextInlineLine(_ note: TimetableWidgetStore.NextDayNote) -> String {
        let day = dayLabel(note.day)
        if let ns = note.noSchoolName {
            if note.totalCount == 0 { return "\(day): \(ns)" }
            let rest = note.totalCount == 1
                ? (note.items.first.map(dayItemLine) ?? "")
                : daySummary(note)
            return "\(day): \(ns) • \(rest)"
        }
        if note.totalCount == 1, let item = note.items.first {
            return "\(day): \(item.title)"
        }
        return "\(day): \(daySummary(note))"
    }

    // MARK: Segédek (önállóak — a Most-nézet privátjai nem látszanak ide)

    private func dayItemLine(_ item: TimetableWidgetStore.NextDayItem) -> String {
        item.subtitle.isEmpty ? item.title : "\(item.title) • \(item.subtitle)"
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

    private func daySummary(_ n: TimetableWidgetStore.NextDayNote) -> String {
        var parts: [String] = []
        if n.examCount > 0 { parts.append("\(n.examCount) dolgozat") }
        if n.cancelledCount > 0 { parts.append("\(n.cancelledCount) elmaradó óra") }
        if n.substitutedCount > 0 { parts.append("\(n.substitutedCount) helyettesítés") }
        if n.eventCount > 0 { parts.append("\(n.eventCount) esemény") }
        return parts.joined(separator: " • ")
    }

    private func dayLabel(_ d: Date) -> String {
        let cal = Calendar.current
        if cal.isDateInTomorrow(d) { return "Holnap" }
        let f = DateFormatter(); f.locale = Locale(identifier: "hu_HU"); f.dateFormat = "EEEE"
        return f.string(from: d).capitalized
    }

    private func shortTime(_ d: Date) -> String {
        d.formatted(date: .omitted, time: .shortened)
    }
}

#Preview(as: .accessoryRectangular) {
    SchoolDayWidget()
} timeline: {
    SchoolDayEntry(
        date: Date(), effectiveNow: Date(),
        todayLessons: TimetableWidgetProvider.sampleLessons(),
        info: TimetableWidgetStore.NextDayNote(
            day: Date(), items: [TimetableWidgetStore.NextDayItem(kind: "event", title: "Kirándulás", subtitle: "Egész nap • Városliget")],
            examCount: 0, cancelledCount: 0, substitutedCount: 0, eventCount: 1
        ),
        next: nil, accentHex: 0x4A90E2, hasSnapshot: true
    )
}
