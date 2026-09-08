import ActivityKit
import WidgetKit
import SwiftUI

// MARK: - Widget Extension Live Activity UI
// FONTOS: Ezt a fájlt a Widget Extension target-be kell tenni!
// Lépések (egyszeri, 2 perc Xcode-ban):
//   1) File > New > Target > Widget Extension → név: SummitWidgets
//      → pipáld: "Include Live Activity" (generál egy WidgetBundle-t)
//      → deployment target: iOS 16.1 (nem 16.0!)
//   2) A generált SummitWidgetsBundle.swift-ben regisztráld:
//        @main struct SummitWidgetsBundle: WidgetBundle {
//            var body: some Widget { SummitLiveActivityWidget() }
//        }
//   3) Ez a fájl + SummitLiveActivityAttributes.swift legyen MINDKÉT target tagja:
//      File Inspector → Target Membership → Summit + SummitWidgets bepipálva.
//   4) Info.plist kulcs már a project.yml-ben: NSSupportsLiveActivities = YES.
//      Widget extension Info.plist-jében is ugyanez kell (Xcode automatikusan teszi).
//
// Amíg nincs Widget Extension, a Manager elindítja az activityt, de
// a rendszer nem tud UI-t rajzolni — ezért kell a Bundle. Addig is a
// kód fordítható és a Settings toggle + Manager már működik.
//
// Design szabály (WWDC23):
// - Lock Screen: 14pt margin, kompakt magasság, staleDate-t a Manager adja.
// - Dynamic Island: compact (leading/trailing) + expanded (center/bottom).
// - Watch: .supplementalActivityFamilies([.small]) opcionális.

@available(iOS 16.2, *)
struct SummitLiveActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: SummitLiveActivityAttributes.self) { context in
            // MARK: Lock Screen / Banner
            LockScreenView(context: context)
                .activityBackgroundTint(Color(hex: UInt(context.attributes.accentHex)).opacity(0.12))
                .activitySystemActionForegroundColor(Color(hex: UInt(context.attributes.accentHex)))
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Label(context.state.subject, systemImage: context.state.isCancelled ? "xmark.circle.fill" : "graduationcap.fill")
                        .font(.caption.weight(.semibold))
                        .lineLimit(1)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    // Visszaszámláló — a rendszer magától frissíti (nincs FrequentUpdates kell)
                    Text(timerInterval: context.state.lessonStart...context.state.lessonEnd, countsDown: true)
                        .font(.caption2.monospacedDigit().weight(.semibold))
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }
                DynamicIslandExpandedRegion(.center) {
                    if let nxt = context.state.nextSubject {
                        Text("Köv: \(nxt) • \(context.state.nextRoom ?? "")")
                            .font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                    }
                }
                DynamicIslandExpandedRegion(.bottom) {
                    ProgressView(value: progress(start: context.state.lessonStart, end: context.state.lessonEnd))
                        .tint(Color(hex: UInt(context.attributes.accentHex)))
                }
            } compactLeading: {
                Image(systemName: context.state.isCancelled ? "xmark.circle.fill" : "\(context.state.index).circle.fill")
                    .foregroundStyle(Color(hex: UInt(context.attributes.accentHex)))
            } compactTrailing: {
                Text(timerInterval: context.state.lessonStart...context.state.lessonEnd, countsDown: true)
                    .font(.caption2.monospacedDigit())
                    .frame(width: 46)
            } minimal: {
                Image(systemName: "\(context.state.index).circle.fill")
                    .foregroundStyle(Color(hex: UInt(context.attributes.accentHex)))
            }
            .keylineTint(Color(hex: UInt(context.attributes.accentHex)))
        }
    }

    private func progress(start: Date, end: Date) -> Double {
        let total = end.timeIntervalSince(start)
        guard total > 0 else { return 0 }
        let elapsed = Date().timeIntervalSince(start)
        return min(1, max(0, elapsed / total))
    }
}

@available(iOS 16.2, *)
private struct LockScreenView: View {
    let context: ActivityViewContext<SummitLiveActivityAttributes>

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle().fill(Color(hex: UInt(context.attributes.accentHex)).opacity(0.16))
                    .frame(width: 42, height: 42)
                Text(context.state.index)
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundStyle(Color(hex: UInt(context.attributes.accentHex)))
            }
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(context.state.subject).font(.subheadline.weight(.semibold)).lineLimit(1)
                    if context.state.isCancelled {
                        Text("Elmarad").font(.caption2.weight(.bold)).foregroundStyle(.white).padding(.horizontal, 6).padding(.vertical, 2).background(Capsule().fill(Color.red))
                    } else if context.state.isSubstituted {
                        Text("Helyettesítés").font(.caption2.weight(.bold)).foregroundStyle(.white).padding(.horizontal, 6).padding(.vertical, 2).background(Capsule().fill(Color.orange))
                    }
                }
                HStack(spacing: 6) {
                    Text(context.state.room).font(.caption2.weight(.bold)).foregroundStyle(.secondary)
                    Text("•").foregroundStyle(.tertiary)
                    Text(context.state.teacher).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                }
                if let nxt = context.state.nextSubject {
                    Text("Köv: \(nxt) • \(context.state.nextRoom ?? "")")
                        .font(.caption2).foregroundStyle(.tertiary).lineLimit(1)
                }
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 4) {
                // Óra visszaszámláló — a Lock Screen a staleDate-ig frissíti magát
                Text(timerInterval: context.state.lessonStart...context.state.lessonEnd, countsDown: true)
                    .font(.system(size: 14, weight: .semibold, design: .rounded).monospacedDigit())
                ProgressView(value: progress(start: context.state.lessonStart, end: context.state.lessonEnd))
                    .tint(Color(hex: UInt(context.attributes.accentHex)))
                    .frame(width: 72)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private func progress(start: Date, end: Date) -> Double {
        let total = end.timeIntervalSince(start)
        guard total > 0 else { return 0 }
        let elapsed = Date().timeIntervalSince(start)
        return min(1, max(0, elapsed / total))
    }
}

// Fallback iOS 16.1 (ActivityConfiguration ott még nem 16.2) — iOS 16.1-en a DynamicIsland üres nem engedett, ezért külön.
@available(iOS 16.1, *)
struct SummitLiveActivityWidgetLegacy: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: SummitLiveActivityAttributes.self) { context in
            LockScreenView(context: context)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) { Text(context.state.subject).font(.caption2) }
                DynamicIslandExpandedRegion(.trailing) { Text(timerInterval: context.state.lessonStart...context.state.lessonEnd, countsDown: true).font(.caption2.monospacedDigit()) }
            } compactLeading: {
                Text(context.state.index).font(.caption2.weight(.bold))
            } compactTrailing: {
                Text(timerInterval: context.state.lessonStart...context.state.lessonEnd, countsDown: true).font(.caption2.monospacedDigit())
            } minimal: {
                Text(context.state.index).font(.caption2.weight(.bold))
            }
        }
    }
}
