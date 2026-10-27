import SwiftUI

/// Bemutató, Feladatok-lépés: a valódi Feladatok tab (`NotesView`) tartalma
/// — ugyanaz a szegmens-választó (`SkinSegmented`), napcím (`NotesDayHeader`),
/// házi- és dolgozat-sor (`NotesHomeworkRow`, `NotesExamRow`), ugyanazokkal
/// a lista-módosítókkal, a `DemoData` házijaival és dolgozataival.
///
/// Mozgás: a sorok egyenként érkeznek, egy ütem múlva az első házi magától
/// kipipálódik (a sor saját pipa-animációja + `taskToggled` haptika), egy
/// pillanatig zölden marad, majd a valódi tabhoz hasonlóan kikerül a Készbe;
/// utána a szegmens a Dolgozatokra vált és vissza. Bármilyen user-érintésre
/// (pipa, lenyitás, szegmens) a koreográfia leáll, és a képernyő úgy
/// viselkedik, mint az igazi.
///
/// A pipa CSAK helyi állapot: a bemutató a valódi `CompletedStore`-ba (ami
/// szinkronizál) nem ír.
struct OnboardingTasksStep: View {
    @EnvironmentObject var theme: ThemeStore
    @Environment(\.colorScheme) var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.horizontalSizeClass) private var hSize

    private let homeworks: [HomeworkItem]
    private let exams: [ExamItem]
    /// Demo órák a házi-sorok óraszám-pilljéhez (mint a tabon az órarendi órák).
    private let lessons: [LessonItem]

    @State private var filter = 0 // 0 = Feladatok, 1 = Dolgozatok, 2 = Kész
    /// Helyben kipipált házik / dolgozatok (a `CompletedStore` helyett).
    @State private var doneIDs: Set<String> = []
    @State private var readyIDs: Set<String> = []
    /// A bemutató által épp kipipált házi: egy ütemig még a Feladatokban
    /// marad zölden, hogy a pipa látsszon, mielőtt a Készbe kerül.
    @State private var lingeringIDs: Set<String> = []
    @State private var expandedIDs: Set<String> = []
    /// Hány házi-sor jelent már meg a belépő kaszkádban.
    @State private var revealed = 0
    /// A user hozzányúlt — a koreográfia innentől nem lép közbe.
    @State private var userTookOver = false

    init() {
        let demo = Self.demoItems()
        homeworks = demo.homeworks
        exams = demo.exams
        lessons = demo.lessons
    }

    private var colors: AppColors { theme.colors(for: scheme) }
    private var isPad: Bool { hSize == .regular }

    var body: some View {
        List {
            Section {
                // Mint a tabon: a setter csak user-koppintásra fut (haptika);
                // a bemutató szegmensváltása néma.
                SkinSegmented(selection: Binding(
                    get: { filter },
                    set: {
                        if $0 != filter { SummitHaptics.selection(); takeOver() }
                        filter = $0
                    }
                ), options: [
                    SkinOption(value: 0, title: "Feladatok"), SkinOption(value: 1, title: "Dolgozatok"), SkinOption(value: 2, title: "Kész"),
                ])
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 4, trailing: 16))
                .listRowSeparator(.hidden)
                .animation(SummitMotion.gentle, value: filter)
                .summitEntrance()
            }

            if currentIsEmpty {
                Section {
                    SkinEmptyState(
                        title: filter == 1 ? "Nincs dolgozat" : filter == 2 ? "Nincs kész feladat" : "Nincs feladat",
                        systemImage: filter == 1 ? "doc.text" : "checklist",
                        description: Text(filter == 1 ? "Nincs bejelentett számonkérés" : filter == 2 ? "A kipipált feladatok ide kerülnek" : "Minden kész")
                    )
                        .frame(maxWidth: .infinity, minHeight: 220)
                        .padding(.vertical, 16)
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                        .listRowInsets(EdgeInsets(top: 24, leading: 16, bottom: 24, trailing: 16))
                        .transition(.opacity.combined(with: .scale(scale: 0.98)))
                }
            } else {
                // Napra bontott szekciók — mint a tabon.
                Group {
                    if filter == 1 {
                        ForEach(groupByDay(exams, date: { $0.date }), id: \.day) { g in
                            Section {
                                ForEach(g.items, id: \.id) { exam in examRow(exam) }
                            } header: {
                                NotesDayHeader(day: g.day, count: g.items.count)
                            }
                        }
                    } else if filter == 2 {
                        ForEach(groupByDay(doneHomeworks, date: { $0.deadline }, descending: true), id: \.day) { g in
                            Section {
                                ForEach(g.items, id: \.id) { hw in homeworkRow(hw) }
                            } header: {
                                NotesDayHeader(day: g.day, count: g.items.count)
                            }
                        }
                    } else {
                        ForEach(groupByDay(revealedHomeworks, date: { $0.deadline }), id: \.day) { g in
                            Section {
                                ForEach(g.items, id: \.id) { hw in homeworkRow(hw) }
                            } header: {
                                NotesDayHeader(day: g.day, count: g.items.count)
                            }
                        }
                    }
                }
                .id(filter)
                .transition(.opacity)
            }
        }
        .listStyle(.insetGrouped)
        .frame(maxWidth: isPad ? MacSupport.contentWidth(ipad: 1280, mac: 1150) : .infinity)
        .padding(.horizontal, MacSupport.sidePadding)
        .frame(maxWidth: .infinity)
        .summitListChrome(colors: colors)
        .animation(SummitMotion.gentle, value: currentIsEmpty)
        .animation(SummitMotion.gentle, value: filter)
        .tint(colors.accent)
        .task { await choreography() }
    }

    // MARK: - Sorok (a tab közös sor-nézetei, helyi állapottal)

    private func homeworkRow(_ hw: HomeworkItem) -> some View {
        let expanded = expandedIDs.contains(hw.id)
        return NotesHomeworkRow(
            hw: hw,
            done: doneIDs.contains(hw.id) || hw.isDone,
            expanded: expanded,
            lessonIndexText: HomeworkMatcher.lesson(for: hw, in: lessons).map { "\($0.index). óra" },
            onToggleDone: { toggleDone(hw.id) },
            onToggleExpanded: { toggleExpanded(hw.id, expanded: expanded) }
        )
    }

    private func examRow(_ exam: ExamItem) -> some View {
        let expanded = expandedIDs.contains(exam.id)
        return NotesExamRow(
            exam: exam,
            ready: readyIDs.contains(exam.id),
            expanded: expanded,
            onToggleReady: {
                takeOver()
                if readyIDs.contains(exam.id) { readyIDs.remove(exam.id) } else { readyIDs.insert(exam.id) }
            },
            onToggleExpanded: { toggleExpanded(exam.id, expanded: expanded) }
        )
    }

    /// User-pipa: mint a tabon, azonnal a Készbe (vagy vissza) kerül.
    /// A sor maga hívja `SummitMotion.snappy` animációban, haptikával.
    private func toggleDone(_ id: String) {
        takeOver()
        if doneIDs.contains(id) { doneIDs.remove(id) } else { doneIDs.insert(id) }
    }

    private func toggleExpanded(_ id: String, expanded: Bool) {
        takeOver()
        // Chevron-sor lenyitása = választás: finom tick (mint a tabon).
        SummitHaptics.selection()
        withAnimation(SummitMotion.snappy) {
            if expanded { expandedIDs.remove(id) } else { expandedIDs.insert(id) }
        }
    }

    // MARK: - Listák

    /// Élő házik határidő szerint (a kipipált a Készbe kerül — kivéve az
    /// épp a bemutató által kipipáltat, ami egy ütemig még itt látszik).
    private var liveHomeworks: [HomeworkItem] {
        homeworks
            .filter { !doneIDs.contains($0.id) || lingeringIDs.contains($0.id) }
            .sorted { $0.deadline < $1.deadline }
    }

    /// A belépő kaszkád: csak az eddig megjelent sorok (a kezdeti sorrendben).
    private var revealedHomeworks: [HomeworkItem] {
        let shown = Set(revealOrder.prefix(revealed))
        return liveHomeworks.filter { shown.contains($0.id) }
    }

    private var revealOrder: [String] {
        homeworks.sorted { $0.deadline < $1.deadline }.map(\.id)
    }

    private var doneHomeworks: [HomeworkItem] {
        homeworks.filter { doneIDs.contains($0.id) && !lingeringIDs.contains($0.id) }
    }

    /// Az üres állapot a teljes listán dől el, nem a kaszkád állásán —
    /// különben a belépéskor egy pillanatra „Nincs feladat" villanna.
    private var currentIsEmpty: Bool {
        if filter == 1 { return exams.isEmpty }
        if filter == 2 { return doneHomeworks.isEmpty }
        return liveHomeworks.isEmpty
    }

    /// Napra bontás — a tab `groupByDay`-ével azonos szabály (a Kész csökkenő).
    private func groupByDay<T>(_ items: [T], date: (T) -> Date, descending: Bool = false) -> [(day: Date, items: [T])] {
        let cal = Calendar.current
        let grouped = Dictionary(grouping: items) { cal.startOfDay(for: date($0)) }
        let days = descending ? grouped.keys.sorted(by: >) : grouped.keys.sorted()
        return days.map { day in
            let items = grouped[day]!.sorted { descending ? date($0) > date($1) : date($0) < date($1) }
            return (day: day, items: items)
        }
    }

    // MARK: - Koreográfia

    /// Első érintés: a kaszkád azonnal kész, a lebegő pipa a helyére kerül,
    /// a bemutató többet nem nyúl a képernyőhöz.
    private func takeOver() {
        guard !userTookOver else { return }
        userTookOver = true
        revealed = revealOrder.count
        lingeringIDs.removeAll()
    }

    /// Reduce Motion mellett rugó helyett rövid áttűnés.
    private func motion(_ animation: Animation) -> Animation {
        reduceMotion ? .easeInOut(duration: 0.2) : animation
    }

    /// Várakozás; hamis, ha közben a lépés eltűnt vagy a user átvette.
    private func pause(_ seconds: Double) async -> Bool {
        try? await Task.sleep(for: .seconds(seconds))
        return !Task.isCancelled && !userTookOver
    }

    private func choreography() async {
        let order = revealOrder
        // 1) Belépő kaszkád: a sorok egyenként (Reduce Motion: egyszerre).
        if reduceMotion {
            revealed = order.count
        } else {
            guard await pause(0.25) else { return }
            for i in order.indices {
                withAnimation(SummitMotion.gentle) { revealed = i + 1 }
                guard await pause(0.09) else { return }
            }
        }
        // 2) Az első házi magától kipipálódik — a sor saját pipa-animációja.
        guard await pause(1.0), let first = order.first else { return }
        SummitHaptics.taskToggled(markedDone: true)
        withAnimation(motion(SummitMotion.snappy)) {
            doneIDs.insert(first)
            lingeringIDs.insert(first)
        }
        // 3) Egy ütem múlva a Készbe kerül, mint a tabon.
        guard await pause(0.9) else { return }
        withAnimation(motion(SummitMotion.snappy)) { _ = lingeringIDs.remove(first) }
        // 4) Dolgozatok, majd vissza a Feladatokra.
        guard await pause(1.4) else { return }
        withAnimation(motion(SummitMotion.gentle)) { filter = 1 }
        guard await pause(2.6) else { return }
        withAnimation(motion(SummitMotion.gentle)) { filter = 0 }
    }

    // MARK: - Demo adatok

    /// `DemoData` házik és dolgozatok. A demo a hét hétfőjéhez horgonyoz —
    /// a bemutatóban a napok megtartott távolsággal előre tolódnak (a házik
    /// mától, a dolgozatok holnaptól), hogy egyik se legyen már lejárt.
    private static func demoItems() -> (homeworks: [HomeworkItem], exams: [ExamItem], lessons: [LessonItem]) {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let tomorrow = cal.date(byAdding: .day, value: 1, to: today) ?? today
        let hw = DemoData.homeworks()
        let ex = DemoData.exams()

        func shift(earliest: Date?, to target: Date) -> Int {
            guard let earliest else { return 0 }
            return max(0, cal.dateComponents([.day], from: cal.startOfDay(for: earliest), to: target).day ?? 0)
        }
        let hwDays = shift(earliest: hw.map(\.deadline).min(), to: today)
        let exDays = shift(earliest: ex.map(\.date).min(), to: tomorrow)
        func moved(_ d: Date, _ days: Int) -> Date { cal.date(byAdding: .day, value: days, to: d) ?? d }

        let homeworks = hw.map {
            HomeworkItem(id: $0.id, subject: $0.subject, title: $0.title, deadline: moved($0.deadline, hwDays),
                         teacher: $0.teacher, isDone: $0.isDone, attachments: $0.attachments)
        }
        let exams = ex.map {
            ExamItem(id: $0.id, subject: $0.subject, date: moved($0.date, exDays), mode: $0.mode,
                     description: $0.description, teacher: $0.teacher, lessonIndex: $0.lessonIndex,
                     announcedDate: $0.announcedDate, groupName: $0.groupName, attachments: $0.attachments)
        }
        let lessons = DemoData.lessons(from: today, to: cal.date(byAdding: .day, value: 10, to: today) ?? today)
        return (homeworks, exams, lessons)
    }
}
