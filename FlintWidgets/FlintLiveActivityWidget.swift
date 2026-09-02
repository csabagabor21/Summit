import ActivityKit
import WidgetKit
import SwiftUI

// MARK: - Shared Live Activity UI — Widget Extension target
// Ez a fájl CSAK a Widget Extensionben forduljon — fő appban nem kell.
// A FlintLiveActivityAttributes.swift-et mindkét target fordítja (shared).

@available(iOS 16.2, *)
struct FlintLiveActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: FlintLiveActivityAttributes.self) { context in
            LockScreenView(context: context)
                .activityBackgroundTint(accentColor(context).opacity(0.14))
                .activitySystemActionForegroundColor(accentColor(context))
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    if context.state.phase == "break" {
                        Label("Szünet", systemImage: "cup.and.saucer.fill")
                            .font(.callout.weight(.semibold))
                            .lineLimit(1)
                    } else {
                        Label {
                            Text("\(context.attributes.subject) • \(context.attributes.index). óra")
                                .font(.callout.weight(.semibold))
                                .lineLimit(1)
                        } icon: {
                            Image(systemName: context.attributes.isCancelled ? "xmark.circle.fill" : "graduationcap.fill")
                        }
                    }
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text(remainingShort(context))
                        .font(.callout.monospacedDigit().weight(.semibold))
                        .frame(maxWidth: .infinity, alignment: .trailing)
                        .monospacedDigit()
                }
                DynamicIslandExpandedRegion(.center) {
                    if let nxt = context.state.nextSubject {
                        HStack(spacing: 4) {
                            Image(systemName: "arrow.right.circle.fill")
                            Text("\(nxt) • \(context.state.nextRoom ?? "")").lineLimit(1)
                        }
                        .font(.caption2).foregroundStyle(.secondary)
                    }
                }
                DynamicIslandExpandedRegion(.bottom) {
                    ProgressView(value: progress(start: context.state.lessonStart, end: context.state.lessonEnd))
                        .tint(statusTint(context))
                }
            } compactLeading: {
                Image(systemName: pillSymbol(index: context.attributes.index, cancelled: context.attributes.isCancelled))
                    .foregroundStyle(statusTint(context))
            } compactTrailing: {
                // Fix szélesség: ne ugráljon a pill
                Text(remainingCompact(context))
                    .font(.caption2.monospacedDigit().weight(.semibold))
                    .frame(width: 46)
                    .monospacedDigit()
            } minimal: {
                Image(systemName: pillSymbol(index: context.attributes.index, cancelled: false))
                    .foregroundStyle(accentColor(context))
            }
            .keylineTint(accentColor(context))
        }
    }

    private func progress(start: Date, end: Date) -> Double {
        let total = end.timeIntervalSince(start)
        guard total > 0 else { return 0 }
        let elapsed = Date().timeIntervalSince(start)
        return min(1, max(0, elapsed / total))
    }

    /// Az appban választott accent (Beállítások) — indításkor kapja az activity.
    private func accentColor(_ context: ActivityViewContext<FlintLiveActivityAttributes>) -> Color {
        let hex = context.attributes.accentHex
        return Color(hex: UInt(hex == 0 ? 0xA7DC22 : hex))
    }

    /// Elmarad/Helyettesítés esetén a progress és a pill is átveszi a státuszszínt.
    private func statusTint(_ context: ActivityViewContext<FlintLiveActivityAttributes>) -> Color {
        if context.attributes.isCancelled { return Color.red }
        if context.attributes.isSubstituted { return Color.orange }
        return accentColor(context)
    }

    /// Rövid perces szöveg az expanded nézetbe (renderkori érték).
    private func remainingShort(_ context: ActivityViewContext<FlintLiveActivityAttributes>) -> String {
        let m = max(0, Int(ceil(context.state.lessonEnd.timeIntervalSince(Date()) / 60)))
        return "\(m) perc"
    }

    /// Extra rövid perces szöveg a compact pillbe (renderkori érték).
    private func remainingCompact(_ context: ActivityViewContext<FlintLiveActivityAttributes>) -> String {
        let m = max(0, Int(ceil(context.state.lessonEnd.timeIntervalSince(Date()) / 60)))
        return "\(m)p"
    }

    /// Biztonságos SF Symbol: "10", "-", üres indexre nincs *.circle.fill → üres pill helyett fallback.
    private func pillSymbol(index: String, cancelled: Bool) -> String {
        if cancelled { return "xmark.circle.fill" }
        let t = index.trimmingCharacters(in: .whitespaces)
        if let n = Int(t), (0...9).contains(n) { return "\(n).circle.fill" }
        return "graduationcap.fill"
    }
}

@available(iOS 16.2, *)
private struct LockScreenView: View {
    let context: ActivityViewContext<FlintLiveActivityAttributes>
    private var accent: Color {
        let hex = context.attributes.accentHex
        return Color(hex: UInt(hex == 0 ? 0xA7DC22 : hex))
    }

    private var isBreak: Bool { context.state.phase == "break" }
    private var title: String {
        if isBreak { return context.state.nextSubject ?? "Szünet" }
        return context.attributes.subject
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Státusz — mint a MOST-kártya capsule-je
            if context.attributes.isCancelled {
                Text("Elmarad")
                    .font(.caption2.weight(.bold)).foregroundStyle(.white)
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .background(Capsule().fill(Color.red))
            } else if context.attributes.isSubstituted {
                Text("Helyettesítés")
                    .font(.caption2.weight(.bold)).foregroundStyle(.white)
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .background(Capsule().fill(Color.orange))
            } else if isBreak {
                Text("SZÜNET")
                    .font(.caption2.weight(.bold))
                    .tracking(1.1)
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
            }
            // Nagy cím — mint a MOST-kártya
            Text(title)
                .font(.system(size: 26, weight: .bold, design: .rounded))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .truncationMode(.tail)
            // Meta sor: room badge + "N. óra • tanár"
            HStack(spacing: 6) {
                Text(context.attributes.room)
                    .font(.caption2.weight(.bold).monospacedDigit())
                    .foregroundStyle(.white)
                    .padding(.horizontal, 7).padding(.vertical, 4)
                    .background(RoundedRectangle(cornerRadius: 6).fill(accent))
                    .lineLimit(1)
                Text("\(context.attributes.index). óra")
                    .font(.caption.weight(.semibold).monospacedDigit())
                    .foregroundStyle(.secondary)
                Text("•").foregroundStyle(.tertiary)
                Text(context.attributes.teacher)
                    .font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
            }
            // Full szélességű progress — mint a MOST-kártya
            ProgressView(value: progress(start: context.state.lessonStart, end: context.state.lessonEnd))
                .tint(isBreak ? accent : statusTint)
            // Alsó sor: következő óra nyíllal + fennmaradó percek
            HStack(spacing: 6) {
                if !isBreak, let nxt = context.state.nextSubject {
                    Image(systemName: "arrow.right.circle.fill")
                        .font(.caption).foregroundStyle(.secondary)
                    Text("\(nxt) • \(context.state.nextRoom ?? "")")
                        .font(.caption.weight(.medium)).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer()
                Text(remainingText)
                    .font(.caption.weight(.semibold).monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private var statusTint: Color {
        if context.attributes.isCancelled { return Color.red }
        if context.attributes.isSubstituted { return Color.orange }
        return accent
    }

    /// Fennmaradó idő percekben — mint a MOST-kártya "X perc van hátra".
    /// Statikus (renderkori) érték: az activity csak app-eseményekre frissül,
    /// a rendszer-élő timerInterval másodperces formátuma nem kérhető perc-only módban.
    private var remainingText: String {
        let m = max(0, Int(ceil(context.state.lessonEnd.timeIntervalSince(Date()) / 60)))
        if isBreak {
            return m <= 0 ? "Kezdődik" : "\(m) perc múlva kezdődik"
        }
        return m <= 0 ? "Vége" : "\(m) perc van hátra"
    }

    private func progress(start: Date, end: Date) -> Double {
        let total = end.timeIntervalSince(start)
        guard total > 0 else { return 0 }
        let elapsed = Date().timeIntervalSince(start)
        return min(1, max(0, elapsed / total))
    }
}

// MARK: - Self-contained Color hex — ne függjön az AppColors.swift-től (extension target minimal)
private extension Color {
    init(hex: UInt, alpha: Double = 1.0) {
        let r = Double((hex >> 16) & 0xFF) / 255.0
        let g = Double((hex >> 8) & 0xFF) / 255.0
        let b = Double(hex & 0xFF) / 255.0
        self.init(.sRGB, red: r, green: g, blue: b, opacity: alpha)
    }
}
