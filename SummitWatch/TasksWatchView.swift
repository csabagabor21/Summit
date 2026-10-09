import SwiftUI

// MARK: - Feladatok az órán — a telefonos Feladatok tab tömör tükre
// Aktív házik + dolgozatok határidő-sorrendben, két szekcióban.
// Csak olvasható pillantás (pipálás az órán nincs) — koronával
// görgethető natív lista. A kész/lejárt szűrés az iPhone-on történik
// a telefonnal azonos szabállyal (lásd WatchSyncSender.activeTasks).
struct TasksWatchView: View {
    @EnvironmentObject var store: WatchSyncStore

    /// Kinyitott házi-sorok (telefonos NotesView-minta).
    @State private var expandedIDs = Set<String>()

    private var homeworks: [WatchHomework] {
        store.tasks?.homeworks.sorted { $0.deadline < $1.deadline } ?? []
    }
    private var exams: [WatchExam] {
        store.tasks?.exams.sorted { $0.date < $1.date } ?? []
    }

    private func toggleExpanded(_ id: String) {
        withAnimation {
            if expandedIDs.contains(id) { expandedIDs.remove(id) }
            else { expandedIDs.insert(id) }
        }
    }

    /// Melyik órára adták fel a házit: azonos tárgyú, határidő-napi óra
    /// a szinkronizált órarendből (a telefonos HomeworkMatcher.lesson
    /// szabálya). Nincs találat → a dátumszöveg napot mutat óraszám nélkül.
    private func lessonIndex(for hw: WatchHomework) -> String? {
        store.timetable?.lessons.first {
            SubjectMatcher.same($0.subject, hw.subject)
            && Calendar.current.isDate($0.start, inSameDayAs: hw.deadline)
        }?.index
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
                                WatchHomeworkRow(
                                    hw: hw,
                                    lessonIndex: lessonIndex(for: hw),
                                    expanded: expandedIDs.contains(hw.id),
                                    onToggle: { toggleExpanded(hw.id) }
                                )
                            }
                        }
                    }
                    if !exams.isEmpty {
                        Section("Dolgozatok") {
                            ForEach(exams) { ex in
                                WatchExamRow(
                                    ex: ex,
                                    expanded: expandedIDs.contains(ex.id),
                                    onToggle: { toggleExpanded(ex.id) }
                                )
                            }
                        }
                    }
                }
                .listStyle(.plain)
                // Sor lenyitása = választás: a legfinomabb tick. Más
                // az órán nincs — a csukló erősít, a success is sok.
                .sensoryFeedback(.selection, trigger: expandedIDs)
                .refreshable { await store.requestSyncNow() }
            }
        }
        .navigationTitle("Feladatok")
    }
}

// MARK: - Házi-sor — becsukva csak tárgy + határidő, a fejléc
// koppintására nyílik a teljes szöveg (a telefonos Feladatok-tab mintájára).
private struct WatchHomeworkRow: View {
    let hw: WatchHomework
    /// Melyik órára adták fel ("1") — a szülő oldja fel az órarendből.
    let lessonIndex: String?
    let expanded: Bool
    let onToggle: () -> Void

    /// A szinkron üres cím helyett "(nincs leírás)"-t küld — az nem
    /// kinyitható tartalom, ezért ahhoz nincs nyíl és lenyíló szöveg sem.
    private var hasText: Bool { !hw.title.isEmpty && hw.title != "(nincs leírás)" }

    var body: some View {
        HStack(alignment: .top, spacing: 9) {
            Image(systemName: "circle")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .padding(.top, 2)
            VStack(alignment: .leading, spacing: 2) {
                // Valódi gomb (nem onTapGesture): az AssistiveTouch-kézmozdulatok
                // (csippentés = következő, ököl = kiválasztás), a rendszer
                // Double Tap és a VoiceOver csak fókuszálható vezérlőre tud
                // ráállni — puszta tap-gesztusra nem.
                Button {
                    if hasText { onToggle() }
                } label: {
                    HStack(spacing: 5) {
                        Text(hw.subject)
                            .font(.subheadline.weight(.semibold))
                            .lineLimit(1)
                        if hw.isCustom {
                            Text("SAJÁT")
                                .font(.caption2.weight(.bold))
                                .foregroundStyle(.blue)
                        }
                        Spacer(minLength: 2)
                        if hasText {
                            Image(systemName: expanded ? "chevron.up" : "chevron.down")
                                .font(.caption2.weight(.bold))
                                .foregroundStyle(.tertiary)
                        }
                    }
                }
                .buttonStyle(.plain)
                .disabled(!hasText)
                .accessibilityHint(hasText ? (expanded ? "Becsukja a részleteket." : "Kinyitja a részleteket.") : "")
                if expanded && hasText {
                    Text(hw.title)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Text(Self.dueText(hw.deadline, lessonIndex: lessonIndex))
                    .font(.caption2.weight(.medium).monospacedDigit())
                    .foregroundStyle(dueColor(hw.deadline))
                    .lineLimit(1)
            }
        }
        .padding(.vertical, 3)
    }

    /// Határidő-sor: ha tudjuk, melyik órára adták fel, a nap + óraszám
    /// ("Péntek 1. óra"). Az éjféli dátum-határidőkre a "Ma 0:00-ig"
    /// értelmetlen volt — éjfélkor nincs időpont, csak a nap. Valós
    /// (nem éjféli) időpontnál marad a megszokott "-ig" alak.
    static func dueText(_ date: Date, lessonIndex: String?) -> String {
        let cal = Calendar.current
        let idx = (lessonIndex ?? "").isEmpty ? nil : lessonIndex
        let day: String
        if cal.isDateInToday(date) { day = "Ma" }
        else if cal.isDateInTomorrow(date) { day = "Holnap" }
        else if idx != nil { day = Self.weekdayFmt.string(from: date).capitalized }
        else { day = Self.dayFmt.string(from: date) }
        if let i = idx { return "\(day) \(i). óra" }
        if cal.startOfDay(for: date) == date { return day }
        return "\(day) \(Self.timeFmt.string(from: date))-ig"
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
    private static let weekdayFmt: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "hu_HU")
        f.dateFormat = "EEEE"
        return f
    }()
}

// MARK: - Dolgozat-sor
// MARK: - Dolgozat-sor — ugyanúgy lenyitható, mint a házi:
// becsukva tárgy + pillek + határidő, koppintásra a megnevezés és a leírás.
private struct WatchExamRow: View {
    let ex: WatchExam
    let expanded: Bool
    let onToggle: () -> Void

    private var hasText: Bool { !ex.mode.isEmpty || !ex.details.isEmpty }

    var body: some View {
        HStack(alignment: .top, spacing: 9) {
            Image(systemName: "pencil.and.list.clipboard")
                .font(.subheadline)
                .foregroundStyle(.orange)
                .padding(.top, 2)
            VStack(alignment: .leading, spacing: 2) {
                // Valódi gomb (nem onTapGesture): a kézmozdulatok és a
                // VoiceOver csak fókuszálható vezérlőre tud ráállni.
                Button {
                    if hasText { onToggle() }
                } label: {
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
                        Spacer(minLength: 2)
                        if hasText {
                            Image(systemName: expanded ? "chevron.up" : "chevron.down")
                                .font(.caption2.weight(.bold))
                                .foregroundStyle(.tertiary)
                        }
                    }
                }
                .buttonStyle(.plain)
                .disabled(!hasText)
                .accessibilityHint(hasText ? (expanded ? "Becsukja a részleteket." : "Kinyitja a részleteket.") : "")
                if expanded && hasText {
                    if !ex.mode.isEmpty {
                        Text(ex.mode)
                            .font(.caption.weight(.medium))
                    }
                    if !ex.details.isEmpty {
                        Text(ex.details)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Text(WatchHomeworkRow.dueText(ex.date, lessonIndex: ex.lessonIndex.map { "\($0)" }))
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(.vertical, 3)
    }
}
