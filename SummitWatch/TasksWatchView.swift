import SwiftUI

// MARK: - Feladatok az órán — a telefonos Feladatok tab tömör tükre
// Aktív házik + dolgozatok határidő-sorrendben, két szekcióban.
// Csak olvasható pillantás (pipálás az órán nincs) — koronával
// görgethető natív lista. A kész/lejárt szűrés az iPhone-on történik
// a telefonnal azonos szabállyal (lásd WatchSyncSender.activeTasks).
struct TasksWatchView: View {
    @EnvironmentObject var store: WatchSyncStore

    private var homeworks: [WatchHomework] {
        store.tasks?.homeworks.sorted { $0.deadline < $1.deadline } ?? []
    }
    private var exams: [WatchExam] {
        store.tasks?.exams.sorted { $0.date < $1.date } ?? []
    }

    var body: some View {
        Group {
            if homeworks.isEmpty && exams.isEmpty {
                ContentUnavailableView(
                    "Nincs feladat",
                    systemImage: "checklist",
                    description: Text("Nyisd meg a Feladatokat iPhone-on.")
                )
            } else {
                List {
                    if let err = store.lastSyncError {
                        Section {
                            Text(err)
                                .font(.caption2)
                                .foregroundStyle(.orange)
                        }
                    }
                    if !homeworks.isEmpty {
                        Section("Házik") {
                            ForEach(homeworks) { hw in
                                WatchHomeworkRow(hw: hw)
                            }
                        }
                    }
                    if !exams.isEmpty {
                        Section("Dolgozatok") {
                            ForEach(exams) { ex in
                                WatchExamRow(ex: ex)
                            }
                        }
                    }
                }
                .listStyle(.plain)
                .refreshable { await store.requestSyncNow() }
            }
        }
        .navigationTitle("Feladatok")
    }
}

// MARK: - Házi-sor
private struct WatchHomeworkRow: View {
    let hw: WatchHomework

    var body: some View {
        HStack(alignment: .top, spacing: 9) {
            Image(systemName: "circle")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .padding(.top, 2)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 5) {
                    Text(hw.subject)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                    if hw.isCustom {
                        Text("SAJÁT")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(.blue)
                    }
                }
                if !hw.title.isEmpty {
                    Text(hw.title)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(3)
                }
                Text(Self.dueText(hw.deadline))
                    .font(.caption2.weight(.medium).monospacedDigit())
                    .foregroundStyle(dueColor(hw.deadline))
                    .lineLimit(1)
            }
        }
        .padding(.vertical, 3)
    }

    static func dueText(_ date: Date) -> String {
        let cal = Calendar.current
        let time = Self.timeFmt.string(from: date)
        if cal.isDateInToday(date) { return "Ma \(time)-ig" }
        if cal.isDateInTomorrow(date) { return "Holnap \(time)-ig" }
        return "\(Self.dayFmt.string(from: date)) \(time)-ig"
    }

    private func dueColor(_ date: Date) -> Color {
        let cal = Calendar.current
        if cal.isDate(date, inSameDayAs: Date()) || date < Date() { return .orange }
        if cal.isDateInTomorrow(date) { return .yellow }
        return .secondary
    }

    private static let timeFmt: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "hu_HU")
        f.dateFormat = "H:mm"
        return f
    }()
    private static let dayFmt: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "hu_HU")
        f.dateFormat = "MMM d."
        return f
    }()
}

// MARK: - Dolgozat-sor
private struct WatchExamRow: View {
    let ex: WatchExam

    var body: some View {
        HStack(alignment: .top, spacing: 9) {
            Image(systemName: "pencil.and.list.clipboard")
                .font(.subheadline)
                .foregroundStyle(.orange)
                .padding(.top, 2)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 5) {
                    Text(ex.subject)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                    if ex.isCustom {
                        Text("SAJÁT")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(.blue)
                    }
                    if let n = ex.lessonIndex {
                        Text("\(n). óra")
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(.secondary)
                    }
                }
                if !ex.mode.isEmpty {
                    Text(ex.mode)
                        .font(.caption.weight(.medium))
                        .lineLimit(1)
                }
                if !ex.details.isEmpty {
                    Text(ex.details)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                Text(WatchHomeworkRow.dueText(ex.date))
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(.vertical, 3)
    }
}
