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
                .containerBackground(for: .widget) {
                    LinearGradient(
                        colors: [Color(white: 0.12), Color(white: 0.05)],
                        startPoint: .topLeading, endPoint: .bottomTrailing
                    )
                }
        }
        .configurationDisplayName("Órarend")
        .description("A mai / következő tanítási nap órái az app órarend-nézetéből.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge, .accessoryRectangular])
        .contentMarginsDisabled()
    }
}

// MARK: - Timeline

struct TimetableWidgetEntry: TimelineEntry {
    var date: Date
    var dayLessons: [TimetableWidgetStore.Lesson]
    var dayDate: Date
    var accentHex: Int
    var hasSnapshot: Bool
}

struct TimetableWidgetProvider: TimelineProvider {
    func placeholder(in context: Context) -> TimetableWidgetEntry {
        TimetableWidgetEntry(
            date: Date(), dayLessons: Self.sampleLessons(),
            dayDate: Date(), accentHex: 0x4A90E2, hasSnapshot: false
        )
    }

    func getSnapshot(in context: Context, completion: @escaping (TimetableWidgetEntry) -> Void) {
        completion(makeEntry(preview: context.isPreview))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<TimetableWidgetEntry>) -> Void) {
        let entry = makeEntry(preview: false)
        let refresh = Self.nextRefresh(after: entry.date, lessons: entry.dayLessons)
        completion(Timeline(entries: [entry], policy: .after(refresh)))
    }

    private func makeEntry(preview: Bool) -> TimetableWidgetEntry {
        let now = Date()
        guard let snap = TimetableWidgetStore.load(), !snap.lessons.isEmpty else {
            return TimetableWidgetEntry(
                date: now, dayLessons: preview ? Self.sampleLessons() : [],
                dayDate: now, accentHex: 0x4A90E2, hasSnapshot: false
            )
        }
        let (day, lessons) = Self.pickDay(now: now, lessons: snap.lessons)
        return TimetableWidgetEntry(
            date: now, dayLessons: lessons, dayDate: day,
            accentHex: snap.accentHex == 0 ? 0x4A90E2 : snap.accentHex,
            hasSnapshot: true
        )
    }

    /// Ma, ha van még hátra / tartó óra — különben a következő órás nap.
    static func pickDay(now: Date, lessons: [TimetableWidgetStore.Lesson]) -> (Date, [TimetableWidgetStore.Lesson]) {
        let cal = Calendar.current
        let todays = lessons.filter { cal.isDate($0.start, inSameDayAs: now) }.sorted { $0.start < $1.start }
        if todays.contains(where: { $0.end > now }) {
            return (cal.startOfDay(for: now), todays)
        }
        let upcoming = lessons.filter { $0.start > now }.sorted { $0.start < $1.start }
        if let first = upcoming.first {
            let day = cal.startOfDay(for: first.start)
            return (day, lessons.filter { cal.isDate($0.start, inSameDayAs: day) }.sorted { $0.start < $1.start })
        }
        return (cal.startOfDay(for: now), todays)
    }

    /// Következő órakezdés / óravég, de legkésőbb +8 óra (WidgetKit büdzsé).
    static func nextRefresh(after now: Date, lessons: [TimetableWidgetStore.Lesson]) -> Date {
        let bounds = lessons.flatMap { [$0.start, $0.end] }.filter { $0 > now }.sorted()
        let cap = now.addingTimeInterval(8 * 3600)
        if let next = bounds.first { return min(next.addingTimeInterval(60), cap) }
        return cap
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

private struct TimetableWidgetView: View {
    let entry: TimetableWidgetEntry
    @Environment(\.widgetFamily) private var family

    private var accent: Color { Color(widgetHex: UInt(entry.accentHex)) }
    private var now: Date { entry.date }

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

    // MARK: Small — MOST / KÖVETKEZŐ hero
    private var smallView: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(headerLine).font(.caption2.weight(.bold)).tracking(0.8)
                .foregroundStyle(.secondary).lineLimit(1)
            Spacer(minLength: 0)
            if entry.dayLessons.isEmpty {
                emptyView
            } else if let cur = entry.dayLessons.first(where: { $0.id == currentID }) {
                heroLesson(cur, label: "MOST • \(cur.index). ÓRA")
                ProgressView(value: progress(of: cur)).tint(statusColor(cur))
            } else if let nxt = nextLesson {
                heroLesson(nxt, label: "KÖVETKEZŐ • \(nxt.start.formatted(date: .omitted, time: .shortened))")
                Text(dayCountLine).font(.caption2.weight(.medium)).foregroundStyle(.tertiary)
            } else {
                Text("Mára vége").font(.system(.title3, design: .rounded).weight(.bold))
                Text(dayCountLine).font(.caption2.weight(.medium)).foregroundStyle(.tertiary)
            }
            Spacer(minLength: 0)
        }
        .padding(14)
    }

    private func heroLesson(_ l: TimetableWidgetStore.Lesson, label: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label).font(.caption2.weight(.bold)).tracking(0.6)
                .foregroundStyle(statusColor(l)).lineLimit(1)
            Text(l.subject).font(.system(size: 19, weight: .bold, design: .rounded))
                .lineLimit(2).minimumScaleFactor(0.8)
            HStack(spacing: 5) {
                Text(l.room).font(.caption2.weight(.bold).monospacedDigit())
                    .padding(.horizontal, 6).padding(.vertical, 3)
                    .background(RoundedRectangle(cornerRadius: 5).fill(.white.opacity(0.14)))
                    .lineLimit(1)
                Text(timeRange(l)).font(.caption2.weight(.semibold).monospacedDigit())
                    .foregroundStyle(.secondary).lineLimit(1)
            }
        }
    }

    // MARK: Medium / Large — spine lista, mint az appban
    private func listView(maxRows: Int) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .lastTextBaseline) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(headerLine).font(.caption2.weight(.bold)).tracking(0.8)
                        .foregroundStyle(.secondary).lineLimit(1)
                    Text("\(entry.dayLessons.count) óra")
                        .font(.system(size: 20, weight: .bold, design: .rounded)).monospacedDigit()
                }
                Spacer(minLength: 6)
                if let first = entry.dayLessons.first, let last = entry.dayLessons.last {
                    Text("\(first.start.formatted(date: .omitted, time: .shortened)) – \(last.end.formatted(date: .omitted, time: .shortened))")
                        .font(.caption2.weight(.semibold).monospacedDigit())
                        .foregroundStyle(.secondary).lineLimit(1)
                }
            }
            .padding(.bottom, 8)
            if entry.dayLessons.isEmpty {
                emptyView.padding(.top, 4)
            } else {
                ForEach(Array(entry.dayLessons.prefix(maxRows).enumerated()), id: \.element.id) { idx, l in
                    row(l, isLast: idx == min(maxRows, entry.dayLessons.count) - 1)
                }
                if entry.dayLessons.count > maxRows {
                    Text("+\(entry.dayLessons.count - maxRows) további óra")
                        .font(.caption2.weight(.semibold)).foregroundStyle(.tertiary)
                        .padding(.top, 4)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(14)
    }

    private func row(_ l: TimetableWidgetStore.Lesson, isLast: Bool) -> some View {
        HStack(alignment: .top, spacing: 8) {
            VStack(spacing: 0) {
                Text(l.index)
                    .font(.system(size: 12, weight: .bold, design: .rounded)).monospacedDigit()
                    .foregroundStyle(numberColor(l))
                    .frame(width: 26, height: 26)
                    .background(Circle().fill(statusColor(l).opacity(isCurrent(l) ? 0.28 : 0.14)))
                if !isLast {
                    Rectangle().fill(.white.opacity(0.12)).frame(width: 1.2, height: 8)
                        .padding(.vertical, 1)
                }
            }
            .frame(width: 26)
            VStack(alignment: .leading, spacing: 1) {
                Text(l.subject)
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .strikethrough(l.isCancelled, color: .secondary)
                    .foregroundStyle(l.isCancelled ? .secondary : .primary)
                    .lineLimit(1)
                HStack(spacing: 4) {
                    Text(l.room).font(.caption2.weight(.bold).monospacedDigit())
                        .foregroundStyle(.secondary).lineLimit(1)
                    Text("•").font(.caption2).foregroundStyle(.tertiary)
                    Text(timeRange(l)).font(.caption2.weight(.medium).monospacedDigit())
                        .foregroundStyle(isCurrent(l) ? statusColor(l) : .secondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 4)
            if l.isCancelled {
                badge("Elmarad", .red)
            } else if l.isSubstituted {
                badge("Hely.", .orange)
            } else if isCurrent(l) {
                badge(remainingMinutes(l), accent)
            }
        }
        .padding(.vertical, 2)
    }

    private func badge(_ text: String, _ color: Color) -> some View {
        Text(text.uppercased()).font(.caption2.weight(.bold))
            .foregroundStyle(.white).padding(.horizontal, 6).padding(.vertical, 3)
            .background(Capsule().fill(color)).lineLimit(1)
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
    private var headerLine: String {
        if !entry.hasSnapshot && entry.dayLessons.isEmpty { return "ÓRAREND" }
        let cal = Calendar.current
        let prefix = cal.isDateInToday(entry.dayDate) ? "MA" : dayTitle.uppercased()
        return "ÓRAREND • \(prefix)"
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
        date: Date(), dayLessons: TimetableWidgetProvider.sampleLessons(),
        dayDate: Date(), accentHex: 0x4A90E2, hasSnapshot: true
    )
}
