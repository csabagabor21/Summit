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
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge, .accessoryRectangular])
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
}

struct TimetableWidgetProvider: TimelineProvider {
    func placeholder(in context: Context) -> TimetableWidgetEntry {
        let now = Date()
        return TimetableWidgetEntry(
            date: now, effectiveNow: now, dayLessons: Self.sampleLessons(),
            dayDate: now, accentHex: 0x4A90E2, hasSnapshot: false
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
                dayDate: now, accentHex: 0x4A90E2, hasSnapshot: false
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
            hasSnapshot: true
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

// MARK: - Nézet

// Natív átlátszó liquid glass: nincs saját háttér, a rendszer adja az
// üveget (sötét/világos módban is). Az állapotot CSAK a színek mutatják:
// aktuális = accent, elmarad = piros, helyettesítés = narancs.
private struct TimetableWidgetView: View {
    let entry: TimetableWidgetEntry
    @Environment(\.widgetFamily) private var family

    private var accent: Color { Color(widgetHex: UInt(entry.accentHex)) }
    private var now: Date { entry.effectiveNow }

    private var currentID: String? {
        entry.dayLessons.first(where: { $0.start <= now && $0.end >= now })?.id
    }
    private var nextLesson: TimetableWidgetStore.Lesson? {
        entry.dayLessons.sorted { $0.start < $1.start }.first(where: { $0.start > now })
    }

    var body: some View {
        switch family {
        case .accessoryRectangular:
            accessoryView
        case .systemSmall:
            smallView
        case .systemLarge:
            listView(maxRows: 7)
        default:
            listView(maxRows: 3)
        }
    }

    // MARK: Lock screen — következő óra egy sorban
    private var accessoryView: some View {
        Group {
            if let cur = entry.dayLessons.first(where: { $0.id == currentID }) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("MOST • \(cur.index). ÓRA")
                        .font(.caption2.weight(.bold))
                    Text("\(cur.subject) • \(cur.room)")
                        .font(.headline.weight(.semibold)).lineLimit(1)
                }
            } else if let nxt = nextLesson {
                VStack(alignment: .leading, spacing: 2) {
                    Text("KÖVETKEZŐ • \(nxt.start.formatted(date: .omitted, time: .shortened))")
                        .font(.caption2.weight(.bold))
                    Text("\(nxt.subject) • \(nxt.room)")
                        .font(.headline.weight(.semibold)).lineLimit(1)
                }
            } else {
                Text(dayTitle).font(.headline.weight(.semibold)).lineLimit(1)
            }
        }
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
        dayDate: Date(), accentHex: 0x4A90E2, hasSnapshot: true
    )
}
