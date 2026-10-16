import SwiftUI
import WidgetKit

// MARK: - Vakáció widget — „még X tanítási nap a nyárig"
//
// Adat: VacationCountdown.Info (App Group), az app írja a 0. hétről
// (TimetableView → KRÉTA NaptariNapok, most → aug. 31.).
// Nyáron átvált: „X nap az iskolakezdésig". Adat nélkül üres kártya.
struct VacationWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: VacationWidgetStore.kind, provider: VacationWidgetProvider()) { entry in
            VacationWidgetView(entry: entry)
        }
        .configurationDisplayName("Vakáció")
        .description("Hátralévő tanítási napok a nyári szünetig.")
        .supportedFamilies([.systemSmall, .accessoryCircular, .accessoryRectangular, .accessoryInline])
    }
}

private enum VacationWidgetStore {
    static let kind = "VacationWidget"
}

struct VacationWidgetEntry: TimelineEntry {
    var date: Date
    var info: VacationCountdown.Info?
}

struct VacationWidgetProvider: TimelineProvider {
    func placeholder(in context: Context) -> VacationWidgetEntry {
        VacationWidgetEntry(date: Date(), info: VacationCountdown.Info(
            state: .countdown, daysLeft: 23,
            targetDate: Date().addingTimeInterval(23 * 86400), computedAt: Date()))
    }

    func getSnapshot(in context: Context, completion: @escaping (VacationWidgetEntry) -> Void) {
        completion(VacationWidgetEntry(date: Date(), info: VacationCountdown.load()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<VacationWidgetEntry>) -> Void) {
        let now = Date()
        let entry = VacationWidgetEntry(date: now, info: VacationCountdown.load())
        // Napi frissítés is elég (a szám csak éjfélkor változik);
        // az app úgyis újratölt publikáláskor.
        let midnight = Calendar.current.startOfDay(for: now.addingTimeInterval(86400))
        completion(Timeline(entries: [entry], policy: .after(midnight)))
    }
}

private struct VacationWidgetView: View {
    let entry: VacationWidgetEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        switch family {
        case .accessoryInline:
            Text(inlineText).lineLimit(1)
        case .accessoryCircular:
            circularView
        case .accessoryRectangular:
            rectangularView
        default:
            smallView
        }
    }

    private var isSummer: Bool { entry.info?.state == .summer }

    private var headline: String {
        guard let info = entry.info else { return "–" }
        return "\(info.daysLeft)"
    }

    private var subline: String {
        guard entry.info != nil else { return "Nyisd meg az appot" }
        return isSummer ? "nap az iskolakezdésig" : "tanítási nap a nyárig"
    }

    private var inlineText: String {
        guard let info = entry.info else { return "Vakáció" }
        return isSummer
            ? "Nyári szünet (\(info.daysLeft) nap)"
            : "\(info.daysLeft) tanítási nap a nyárig"
    }

    private var smallView: some View {
        VStack(alignment: .leading, spacing: 2) {
            Spacer(minLength: 0)
            Image(systemName: isSummer ? "sun.max.fill" : "airplane.departure")
                .font(.title3.weight(.semibold))
                .foregroundStyle(.orange)
            Text(headline)
                .font(.system(size: 44, weight: .bold, design: .rounded))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text(subline)
                .font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                .lineLimit(2)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .containerBackground(for: .widget) {
            LinearGradient(
                colors: [.orange.opacity(0.22), .white.opacity(0.03)],
                startPoint: .top, endPoint: .bottom
            )
        }
    }

    private var rectangularView: some View {
        VStack(alignment: .leading, spacing: 2) {
            Spacer(minLength: 0)
            Label(
                isSummer ? "Nyári szünet (\(headline) nap)" : "\(headline) tanítási nap a nyárig",
                systemImage: isSummer ? "sun.max.fill" : "airplane.departure"
            )
            .font(.headline.weight(.semibold)).lineLimit(1)
            Text(entry.info.map { shortDate($0.targetDate) } ?? "Nyisd meg az appot")
                .font(.caption2).foregroundStyle(.secondary).lineLimit(1)
            Spacer(minLength: 0)
        }
        .containerBackground(for: .widget) {
            LinearGradient(
                colors: [.orange.opacity(0.16), .white.opacity(0.03)],
                startPoint: .top, endPoint: .bottom
            )
        }
    }

    private var circularView: some View {
        VStack(spacing: 1) {
            Image(systemName: isSummer ? "sun.max.fill" : "airplane.departure")
                .font(.caption.weight(.semibold))
            Text(entry.info.map { "\($0.daysLeft)" } ?? "–")
                .font(.title3.weight(.bold).monospacedDigit())
        }
    }

    private func shortDate(_ d: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "hu_HU")
        f.dateFormat = "MMM d."
        return "Cél: \(f.string(from: d))"
    }
}

#Preview(as: .systemSmall) {
    VacationWidget()
} timeline: {
    VacationWidgetEntry(date: Date(), info: VacationCountdown.Info(
        state: .countdown, daysLeft: 23,
        targetDate: Date().addingTimeInterval(23 * 86400), computedAt: Date()))
}
