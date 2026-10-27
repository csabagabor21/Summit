import SwiftUI

/// Bemutató — Órarend lépés. KIZÁRÓLAG az igazi Órarend képernyő elemei:
/// a közös hét-sáv (`TimetableWeekBar`), a nap-fejléc (`TimetableDayHeader`)
/// és a valódi órasor (`TimetableRow` — üveg óraszám, terem-kocka, házi- és
/// dolgozat-pill, folyamatjelző), ugyanazokkal a lista-modifierekkel, mint
/// a `TimetableView`. Az adat a `DemoData` hete (bejelentkezés nincs, se
/// store-töltés, se hálózat).
///
/// Mozgás (Reduce Motion mellett mind kimarad, a végállapot azonnal áll):
/// a hét-sáv korongja a szomszéd napról a mai napra csúszik (ugyanaz a
/// napváltás, mint a sáv koppintásakor), utána a nap órái egyenként
/// beúsznak, végül a folyó óra csíkja a kezdetéről a „mostig" kúszik, a
/// hátralévő perc visszaszámol. Utána a valódi képernyő 15 mp-es ütemében
/// él tovább. A sáv és a napváltó swipe valódi: napot és hetet is lapoz.
struct OnboardingTimetableStep: View {
    @EnvironmentObject var theme: ThemeStore
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.horizontalSizeClass) private var hSize
    private var isPad: Bool { hSize == .regular }

    /// A bemutatott nap (hétköznap-tag, 2 = hétfő): ma; hétvégén a péntek —
    /// a demo házik és dolgozatok ehhez a héthez horgonyoznak.
    private let targetDay: Int
    /// A folyó óra kezdete és a szimulált „most" (a 2. óra derekán).
    private let currentStart: Date
    private let liveNow: Date

    @State private var weekOffset = 0
    @State private var selectedDay: Int
    @State private var userHasNavigated = false
    @State private var week: OnboardingDemoWeek
    /// A szimulált idő — a sorok ehhez mérik a „most"-ot és a csíkot.
    @State private var now: Date
    /// Hány sor látszik már a nap idővonalán (belépő kaszkád).
    @State private var revealed = 0

    init() {
        let cal = Calendar.current
        let today = Date()
        let wd = cal.component(.weekday, from: today)
        let target = (2...6).contains(wd) ? wd : 6
        let w = OnboardingDemoWeek.make(offset: 0, featuredDay: target)
        let monday = KretaWeek.monday(for: today)
        let day = cal.date(byAdding: .day, value: target - 2, to: monday) ?? monday
        let todays = w.lessons.filter { cal.isDate($0.start, inSameDayAs: day) }.sorted { $0.start < $1.start }
        let current = todays.count > 1 ? todays[1] : todays.first
        let start = current?.start ?? day
        let mid = current.map { $0.start.addingTimeInterval($0.end.timeIntervalSince($0.start) * 0.6) } ?? day
        targetDay = target
        currentStart = start
        liveNow = mid
        // A belépő a szomszéd napról indul, a korong onnan csúszik a mai napra.
        // Reduce Motion mellett már az első képkocka a végállapot (az
        // environment itt még nem olvasható, ezért a rendszer-kapcsoló).
        let still = UIAccessibility.isReduceMotionEnabled
        _selectedDay = State(initialValue: still ? target : (target == 2 ? 3 : target - 1))
        _week = State(initialValue: w)
        _now = State(initialValue: still ? mid : start)
        _revealed = State(initialValue: still ? .max : 0)
    }

    private var colors: AppColors { theme.colors(for: scheme) }
    private var monday: Date { KretaWeek.adding(weeks: weekOffset, to: KretaWeek.monday(for: Date())) }
    private var selectedDate: Date? {
        Calendar.current.date(byAdding: .day, value: selectedDay - 2, to: monday)
    }
    /// A kiválasztott nap órái (nap-pontos szűrés, mint a valódi képernyőn).
    private var filtered: [LessonItem] {
        guard let d = selectedDate else { return [] }
        return week.lessons.filter { Calendar.current.isDate($0.start, inSameDayAs: d) }.sorted { $0.start < $1.start }
    }

    var body: some View {
        let items = filtered
        List {
            // MARK: Nap-fejléc — ugyanaz a sor-beállítás, mint az Órarendben
            Section {
                TimetableDayHeader(title: selectedDate.map(TimetableView.dayTitle(of:)) ?? "",
                                   summaryItems: items.isEmpty ? nil : ExemptedStore.trimmingTrailingExempted(items),
                                   glitchKey: "\(weekOffset)-\(selectedDay)")
                    .contentShape(Rectangle())
                    .simultaneousGesture(daySwipeGesture)
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                    .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 2, trailing: 16))
                    .summitEntrance(delay: 0.15)
            }

            // MARK: Idővonal — a valódi órasorok
            Section {
                VStack(spacing: 0) {
                    ForEach(Array(items.enumerated()), id: \.element.id) { idx, lesson in
                        let cur = isCurrent(lesson)
                        let ex = exam(for: lesson)
                        TimetableRow(
                            lesson: lesson,
                            isCurrent: cur,
                            isLast: idx == items.count - 1,
                            colors: colors,
                            scheme: scheme,
                            progress: cur ? progress(for: lesson) : 0,
                            effectiveNow: now,
                            hasAssignment: homework(for: lesson) != nil || ex != nil,
                            homework: homework(for: lesson),
                            exam: ex,
                            examRolled: ex.map { week.derived.rolledIDs.contains($0.id) } ?? false
                        )
                        .padding(.vertical, 5)
                        // Belépő kaszkád: fade + 10 pt emelkedés (Reduce Motion: csak fade).
                        .opacity(idx < revealed ? 1 : 0)
                        .offset(y: idx < revealed || reduceMotion ? 0 : 10)
                    }
                }
                .simultaneousGesture(daySwipeGesture)
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
                .listRowInsets(EdgeInsets(top: 4, leading: 8, bottom: 4, trailing: 12))
            }
            .id("\(weekOffset)-\(selectedDay)")
        }
        .listStyle(.insetGrouped)
        .listSectionSpacing(.compact)
        .safeAreaBar(edge: .top, spacing: 0) {
            weekBar
                .summitEntrance(delay: 0.05)
        }
        .scrollEdgeEffectStyle(.soft, for: .top)
        .frame(maxWidth: isPad ? MacSupport.contentWidth(ipad: 1280, mac: 1150) : .infinity)
        .padding(.horizontal, MacSupport.sidePadding)
        .frame(maxWidth: .infinity)
        .summitListChrome(colors: colors)
        // Mint az Órarendben: a nagy cím a sávban, a hét-sáv alatta nem ugrál.
        .toolbarTitleDisplayMode(.inlineLarge)
        .tint(colors.accent)
        .task { await runIntro() }
    }

    // MARK: Hét-sáv — a valódi komponens, a bemutató állapotával
    private var weekBar: some View {
        TimetableWeekBar(
            weekOffset: weekOffset,
            selectedDay: selectedDay,
            userHasNavigated: userHasNavigated,
            lessons: week.lessons,
            weekKnown: true,
            examDays: week.derived.examDays,
            colors: colors,
            onSelectDay: { tag in
                userHasNavigated = true
                revealed = .max
                withAnimation(SummitMotion.page) { selectedDay = tag }
            },
            onPageWeek: { pageWeek($0) },
            onToday: {
                SummitHaptics.selection()
                revealed = .max
                userHasNavigated = false
                withAnimation(SummitMotion.page) {
                    setWeek(0)
                    selectedDay = targetDay
                }
            }
        )
    }

    // MARK: Párosítás — a valódi képernyő szabályai (TimetableDerived)
    private func homework(for lesson: LessonItem) -> HomeworkItem? {
        week.derived.lessonIDs.contains(lesson.id) ? week.derived.homeworkByLesson[lesson.id] : nil
    }
    private func exam(for lesson: LessonItem) -> ExamItem? {
        week.derived.lessonIDs.contains(lesson.id) ? week.derived.examByLesson[lesson.id] : nil
    }
    private func isCurrent(_ l: LessonItem) -> Bool { l.start <= now && l.end >= now }
    private func progress(for l: LessonItem) -> Double {
        let t = l.end.timeIntervalSince(l.start)
        return t > 0 ? min(1, max(0, now.timeIntervalSince(l.start) / t)) : 0
    }

    // MARK: Lapozás — az Órarend lapozó-logikája a demo héttel
    private func setWeek(_ offset: Int) {
        guard offset != weekOffset else { return }
        weekOffset = offset
        week = OnboardingDemoWeek.make(offset: offset, featuredDay: targetDay)
    }

    /// Hétlapozás (chevron és a sáv swipe-ja) — mint a `pageWeek`.
    private func pageWeek(_ delta: Int) {
        let target = weekOffset + delta
        guard (-8...8).contains(target) else { return }
        userHasNavigated = true
        revealed = .max
        SummitHaptics.selection()
        withAnimation(SummitMotion.page) { setWeek(target) }
    }

    /// Nap/hét-váltó swipe a napi tartalmon — ugyanaz a szigorú vízszintes
    /// zár (64 pt + kétszeres vízszintes túlsúly), mint az Órarendben.
    private var daySwipeGesture: some Gesture {
        DragGesture(minimumDistance: 32, coordinateSpace: .local)
            .onEnded { value in
                let dx = value.translation.width
                let dy = value.translation.height
                guard abs(dx) > 64, abs(dx) > 2 * abs(dy) else { return }
                let beforeWeek = weekOffset, beforeDay = selectedDay
                revealed = .max
                withAnimation(SummitMotion.page) {
                    if dx < 0 {
                        if selectedDay < 6 {
                            selectedDay += 1
                        } else if weekOffset < 8 {
                            // péntekről → következő hét hétfő
                            setWeek(weekOffset + 1); selectedDay = 2
                        }
                    } else {
                        if selectedDay > 2 {
                            selectedDay -= 1
                        } else if weekOffset > -8 {
                            // hétfőről → előző hét péntek
                            setWeek(weekOffset - 1); selectedDay = 6
                        }
                    }
                }
                if weekOffset != beforeWeek || selectedDay != beforeDay {
                    userHasNavigated = true
                    SummitHaptics.selection()
                }
            }
    }

    // MARK: Belépő koreográfia
    private func runIntro() async {
        if reduceMotion {
            selectedDay = targetDay
            revealed = .max
            now = liveNow
        } else {
            // 1) A korong a mai napra csúszik — mint egy nap-koppintás.
            guard await pause(0.55) else { return }
            if !userHasNavigated {
                SummitHaptics.selection()
                withAnimation(SummitMotion.page) { selectedDay = targetDay }
            }
            // 2) A nap órái egyenként beúsznak.
            guard await pause(0.25) else { return }
            for i in 1...max(1, filtered.count) {
                withAnimation(SummitMotion.gentle) { revealed = max(revealed, i) }
                guard await pause(0.07) else { return }
            }
            revealed = .max
            // 3) A folyó óra csíkja a kezdetéről a „mostig" kúszik.
            guard await pause(0.2) else { return }
            let steps = 10
            let span = liveNow.timeIntervalSince(currentStart)
            for s in 1...steps {
                withAnimation(SummitMotion.progress) {
                    now = currentStart.addingTimeInterval(span * Double(s) / Double(steps))
                }
                guard await pause(0.11) else { return }
            }
        }
        // Utána a valódi képernyő ütemében él tovább (15 mp-es lépés).
        while await pause(15) {
            withAnimation(SummitMotion.progress) { now = now.addingTimeInterval(15) }
        }
    }

    /// Megszakítható várakozás: hamis, ha a lépés eltűnt (a task leállt).
    private func pause(_ seconds: Double) async -> Bool {
        do { try await Task.sleep(for: .seconds(seconds)); return true } catch { return false }
    }
}

/// A bemutató hete: a `DemoData` csempézett órarendje + a valódi párosítás
/// (`TimetableDerived`: házi, dolgozat pótlással, dolgozatos napok).
private struct OnboardingDemoWeek {
    let lessons: [LessonItem]
    let derived: TimetableDerived

    /// A kiemelt (bemutatott) napon, ha a demo-sablon ott nem jelöl
    /// elmaradást/helyettesítést (csak hétfőn jelöl), a hétfői minta kerül
    /// rá helyben: a 3. óra elmarad, a 4. helyettesítés — így a valódi sor
    /// a saját színezésével mutatja mindkettőt.
    static func make(offset: Int, featuredDay: Int) -> OnboardingDemoWeek {
        let cal = Calendar.current
        let monday = KretaWeek.adding(weeks: offset, to: KretaWeek.monday(for: Date()))
        var lessons = DemoData.lessons(from: monday, to: KretaWeek.end(of: monday))
        if offset == 0, let day = cal.date(byAdding: .day, value: featuredDay - 2, to: monday) {
            let idxs = lessons.indices
                .filter { cal.isDate(lessons[$0].start, inSameDayAs: day) }
                .sorted { lessons[$0].start < lessons[$1].start }
            let marked = idxs.contains { lessons[$0].isCancelled || lessons[$0].isSubstituted }
            if !marked, idxs.count >= 4 {
                let c = lessons[idxs[2]]
                lessons[idxs[2]] = LessonItem(id: c.id, subject: c.subject, room: c.room, start: c.start, end: c.end,
                                              teacher: c.teacher, index: c.index, isSubstituted: false,
                                              isCancelled: true, originalTeacher: c.teacher)
                let s = lessons[idxs[3]]
                lessons[idxs[3]] = LessonItem(id: s.id, subject: s.subject, room: s.room, start: s.start, end: s.end,
                                              teacher: "Helyettes Tanár", index: s.index, isSubstituted: true,
                                              isCancelled: false, originalTeacher: s.teacher)
            }
        }
        let derived = TimetableDerived.make(lessons: lessons, homeworks: DemoData.homeworks(),
                                            exams: DemoData.exams(), absences: DemoData.absences())
        return OnboardingDemoWeek(lessons: lessons, derived: derived)
    }
}
