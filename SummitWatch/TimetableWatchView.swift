import SwiftUI

// MARK: - Órarend az órán — a telefonos editorial dizájn tükre, kompaktan
// Liquid glass óraszám-kör + badge + tárgy + terem/tanár + idősáv.
// Az aktuális óra kék tintet + vékony progresst kap. Koronával görgethető
// natív lista; napok közt a felső léptetővel lehet mozogni.
struct TimetableWatchView: View {
    @EnvironmentObject var store: WatchSyncStore
    @State private var selectedDay: Date?
    @State private var initializedForSavedAt: Date?

    private var colors: AppColors { .darkRevamped }
    private var accent: Color { Color(hex: UInt(store.accentHex)) }
    private var lessons: [TimetableWidgetStore.Lesson] {
        store.timetable?.lessons.sorted { $0.start < $1.start } ?? []
    }
    private var days: [Date] {
        let cal = Calendar.current
        return Array(Set(lessons.map { cal.startOfDay(for: $0.start) })).sorted()
    }

    var body: some View {
        TimelineView(.periodic(from: Date(), by: 30)) { timeline in
            let now = timeline.date
            Group {
                if lessons.isEmpty {
                    ContentUnavailableView(
                        "Nincs órarend",
                        systemImage: "clock",
                        description: Text("Nyisd meg az Órarendet iPhone-on.")
                    )
                } else {
                    VStack(spacing: 0) {
                        dayPager(days: days, now: now)
                        List {
                            ForEach(dayLessons(now: now), id: \.id) { lesson in
                                WatchLessonRow(
                                    lesson: lesson,
                                    isCurrent: lesson.start <= now && now <= lesson.end,
                                    isLast: lesson.id == dayLessons(now: now).last?.id,
                                    progress: progress(of: lesson, now: now),
                                    accent: accent,
                                    colors: colors
                                )
                                .listRowBackground(Color.clear)
                            }
                        }
                        .listStyle(.plain)
                    }
                }
            }
            .onAppear { smartSelect(now: now) }
            .onChange(of: store.timetable?.savedAt) { smartSelect(now: now) }
        }
        .navigationTitle("Órarend")
    }

    // MARK: - Napválasztás

    private func smartSelect(now: Date) {
        // Telefonnal azonosan: ha a mai órák még tartanak/hátravannak, ma;
        // különben a következő órás nap. Kézi lapozás után nem nyúlunk hozzá.
        if selectedDay != nil, initializedForSavedAt == store.timetable?.savedAt { return }
        let cal = Calendar.current
        let today = cal.startOfDay(for: now)
        if lessons.contains(where: { $0.end > now && cal.isDate($0.start, inSameDayAs: now) }) {
            selectedDay = today
        } else if let next = days.first(where: { $0 > today }) {
            selectedDay = next
        } else {
            selectedDay = days.last ?? today
        }
        initializedForSavedAt = store.timetable?.savedAt
    }

    private func dayLessons(now: Date) -> [TimetableWidgetStore.Lesson] {
        let day = selectedDay ?? Calendar.current.startOfDay(for: now)
        return lessons.filter { Calendar.current.isDate($0.start, inSameDayAs: day) }
    }

    private func progress(of lesson: TimetableWidgetStore.Lesson, now: Date) -> Double {
        guard lesson.start <= now && now <= lesson.end else { return 0 }
        let total = lesson.end.timeIntervalSince(lesson.start)
        guard total > 0 else { return 0 }
        return min(1, max(0, now.timeIntervalSince(lesson.start) / total))
    }

    @ViewBuilder
    private func dayPager(days: [Date], now: Date) -> some View {
        let cal = Calendar.current
        let day = selectedDay ?? cal.startOfDay(for: now)
        let idx = days.firstIndex(of: day)
        HStack(spacing: 2) {
            Button {
                if let i = idx, i > 0 { selectedDay = days[i - 1] }
            } label: {
                Image(systemName: "chevron.left")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(idx == nil || idx == 0 ? .tertiary : .primary)
                    .frame(width: 28, height: 22)
            }
            .buttonStyle(.plain)
            .disabled(idx == nil || idx == 0)
            Spacer(minLength: 0)
            Button {
                selectedDay = cal.startOfDay(for: now)
                initializedForSavedAt = store.timetable?.savedAt
            } label: {
                Text(dayTitle(day, now: now))
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(cal.isDate(day, inSameDayAs: now) ? accent : .primary)
                    .lineLimit(1)
            }
            .buttonStyle(.plain)
            Spacer(minLength: 0)
            Button {
                if let i = idx, i + 1 < days.count { selectedDay = days[i + 1] }
            } label: {
                Image(systemName: "chevron.right")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(idx == nil || idx == days.count - 1 ? .tertiary : .primary)
                    .frame(width: 28, height: 22)
            }
            .buttonStyle(.plain)
            .disabled(idx == nil || idx == days.count - 1)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
    }

    private func dayTitle(_ day: Date, now: Date) -> String {
        let cal = Calendar.current
        if cal.isDate(day, inSameDayAs: now) { return "Ma" }
        if let tomorrow = cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: now)),
           cal.isDate(day, inSameDayAs: tomorrow) { return "Holnap" }
        let fmt = DateFormatter()
        fmt.locale = Locale(identifier: "hu_HU")
        fmt.dateFormat = "EEEE"
        let name = fmt.string(from: day)
        return name.prefix(1).uppercased() + name.dropFirst()
    }
}

// MARK: - Órasor — TimetableRow (telefon) kompakt tükre
private struct WatchLessonRow: View {
    let lesson: TimetableWidgetStore.Lesson
    let isCurrent: Bool
    let isLast: Bool
    let progress: Double
    let accent: Color
    let colors: AppColors
    @Environment(\.colorScheme) var scheme

    private var ringTint: Color? {
        if lesson.isCancelled { return .red }
        if lesson.isSubstituted { return .orange }
        if isCurrent { return .blue }
        return nil
    }
    private var numberColor: Color {
        ringTint ?? .white
    }
    private var badgeLabel: String? { lesson.isCancelled ? "Elmarad" : (lesson.isSubstituted ? "Helyettesítés" : nil) }
    private var badgeColor: Color { lesson.isCancelled ? .red : .orange }

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            // LEFT — glass óraszám-kör (mint a telefonon)
            Text(lesson.index)
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(numberColor)
                .frame(width: 28, height: 28)
                .background {
                    Circle()
                        .fill(Color.clear)
                        .glassEffect(
                            .regular.tint((ringTint ?? .white).opacity(isCurrent ? 0.18 : 0.08)).interactive(),
                            in: .circle
                        )
                }
                .padding(.top, 2)

            // CENTER — editorial tartalom (kompakt: meta egy sorban)
            VStack(alignment: .leading, spacing: 2) {
                if let lbl = badgeLabel {
                    Text(lbl.uppercased())
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 5).padding(.vertical, 1.5)
                        .background(Capsule().fill(badgeColor))
                }
                Text(lesson.subject)
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundStyle(lesson.isCancelled ? .secondary : .primary)
                    .strikethrough(lesson.isCancelled, color: .secondary)
                    .lineLimit(2)
                HStack(spacing: 4) {
                    if !lesson.room.isEmpty {
                        Text(lesson.room)
                            .font(.caption2.weight(.bold).monospacedDigit())
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 5).padding(.vertical, 2)
                            .background(
                                RoundedRectangle(cornerRadius: 5, style: .continuous)
                                    .fill(Color.primary.opacity(0.08))
                            )
                            .lineLimit(1)
                    }
                    if !lesson.teacher.isEmpty {
                        Text(lesson.teacher)
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    Text(timeRange)
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                        .layoutPriority(1)
                }
                if isCurrent {
                    ProgressView(value: progress)
                        .tint(.blue)
                        .padding(.top, 1)
                }
            }
        }
        .padding(.vertical, 3)
    }

    private var timeRange: String {
        let fmt = DateFormatter()
        fmt.locale = Locale(identifier: "hu_HU")
        fmt.dateFormat = "H:mm"
        return "\(fmt.string(from: lesson.start))–\(fmt.string(from: lesson.end))"
    }
}
