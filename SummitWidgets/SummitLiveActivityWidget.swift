import ActivityKit
import WidgetKit
import SwiftUI

// MARK: - Shared Live Activity UI — Widget Extension target
// Ez a fájl CSAK a Widget Extensionben forduljon — fő appban nem kell.
// A SummitLiveActivityAttributes.swift-et mindkét target fordítja (shared).
//
// "Napi egy activity" modell: az attributes napfix (dayKey + accent),
// az AKTUÁLIS óra minden adata a state-ben él — innen olvasunk.
// A state a hátralévő napi tervet (plan) is hordozza, így a widget már
// előre mutatja a következő órákat; az élő timerInterval visszaszámlálók
// app-ébresztés nélkül tickelnek a nap végéig (staleDate = dayEnd).

@available(iOS 16.2, *)
struct SummitLiveActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: SummitLiveActivityAttributes.self) { context in
            // Átlátszó liquid glass háttér (mint a zenelejátszó): a .clear
            // engedi, hogy a rendszer rajzolja az áttetsző üveg-hátteret.
            // Bármilyen színes tint lapos, nem üveg hatást adna iOS 26-ban.
            // (Az accent csak a tartalomban — progress, badge, ikon — él.)
            LockScreenView(context: context)
                .activityBackgroundTint(.clear)
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
                            Text("\(context.state.subject) • \(context.state.index). óra")
                                .font(.callout.weight(.semibold))
                                .lineLimit(1)
                        } icon: {
                            Image(systemName: context.state.isCancelled ? "xmark.circle.fill" : "graduationcap.fill")
                        }
                    }
                }
                DynamicIslandExpandedRegion(.trailing) {
                    // ÉLŐ timer: a rendszer másodpercenként frissíti, app-ébresztés nélkül.
                    // (A statikus Date()-alapú szöveg beragadt, mert a Widgetet csak
                    // app-update rajzolja újra — ez okozta a "lagging behind"-ot.)
                    // Center: a trailing régióban a jobbra tolás optikailag
                    // félrecsúszik a leading címhez képest.
                    Text(timerInterval: context.state.lessonStart...context.state.lessonEnd, countsDown: true)
                        .font(.callout.monospacedDigit().weight(.semibold))
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity, alignment: .center)
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
                    // ÉLŐ progress: a rendszer animálja, app-update nélkül —
                    // mint a Maps navigációs sávja. (A Date()-alapú fix érték
                    // két update között beragadt volna.)
                    // Irány fázis-függő: óra közben TÖLTŐDIK (balról jobbra),
                    // szünetben ÜRÜL (jobbról balra) — a hátralévő szünet fogy.
                    ProgressView(timerInterval: context.state.lessonStart...context.state.lessonEnd, countsDown: context.state.phase == "break")
                        .tint(statusTint(context))
                }
            } compactLeading: {
                Image(systemName: pillSymbol(index: context.state.index, cancelled: context.state.isCancelled))
                    .foregroundStyle(statusTint(context))
            } compactTrailing: {
                // ÉLŐ timer a pillben is — mm:ss-hez szélesebb fix keret kell, hogy ne ugráljon
                Text(timerInterval: context.state.lessonStart...context.state.lessonEnd, countsDown: true)
                    .font(.caption2.monospacedDigit().weight(.semibold))
                    .frame(width: 58)
                    .monospacedDigit()
            } minimal: {
                Image(systemName: pillSymbol(index: context.state.index, cancelled: false))
                    .foregroundStyle(accentColor(context))
            }
            .keylineTint(accentColor(context))
        }
    }

    /// Az appban választott accent (Beállítások) — indításkor kapja az activity.
    private func accentColor(_ context: ActivityViewContext<SummitLiveActivityAttributes>) -> Color {
        let hex = context.attributes.accentHex
        return Color(hex: UInt(hex == 0 ? 0x4A90E2 : hex))
    }

    /// Elmarad/Helyettesítés esetén a progress és a pill is átveszi a státuszszínt.
    private func statusTint(_ context: ActivityViewContext<SummitLiveActivityAttributes>) -> Color {
        if context.state.isCancelled { return Color.red }
        if context.state.isSubstituted { return Color.orange }
        return accentColor(context)
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
    let context: ActivityViewContext<SummitLiveActivityAttributes>
    private var accent: Color {
        let hex = context.attributes.accentHex
        return Color(hex: UInt(hex == 0 ? 0x4A90E2 : hex))
    }

    private var isBreak: Bool { context.state.phase == "break" }
    private var title: String {
        if isBreak { return context.state.nextSubject ?? "Szünet" }
        return context.state.subject
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Státusz — mint a MOST-kártya capsule-je
            if context.state.isCancelled {
                Text("Elmarad")
                    .font(.caption2.weight(.bold)).foregroundStyle(.white)
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .background(Capsule().fill(Color.red))
            } else if context.state.isSubstituted {
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
                Text(context.state.room)
                    .font(.caption2.weight(.bold).monospacedDigit())
                    .foregroundStyle(.white)
                    .padding(.horizontal, 7).padding(.vertical, 4)
                    .background(RoundedRectangle(cornerRadius: 6).fill(accent))
                    .lineLimit(1)
                Text("\(context.state.index). óra")
                    .font(.caption.weight(.semibold).monospacedDigit())
                    .foregroundStyle(.secondary)
                Text("•").foregroundStyle(.tertiary)
                Text(context.state.teacher)
                    .font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
            }
            // Full szélességű ÉLŐ progress — a rendszer animálja,
            // app-update nélkül (mint a Maps navigációs sávja).
            // Irány fázis-függő: óra közben töltődik, szünetben ürül.
            ProgressView(timerInterval: context.state.lessonStart...context.state.lessonEnd, countsDown: isBreak)
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
                // ÉLŐ timer a Lock Screenen is — a rendszer tickeli, nem kell app-update.
                HStack(spacing: 4) {
                    Text(isBreak ? "kezdődik" : "hátra")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.tertiary)
                    Text(timerInterval: context.state.lessonStart...context.state.lessonEnd, countsDown: true)
                        .font(.caption.weight(.semibold).monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private var statusTint: Color {
        if context.state.isCancelled { return Color.red }
        if context.state.isSubstituted { return Color.orange }
        return accent
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
