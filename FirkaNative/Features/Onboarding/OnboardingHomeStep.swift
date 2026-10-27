import SwiftUI

/// Bemutató, 1. lépés: a Főoldal teteje — KIZÁRÓLAG a valódi Főoldal
/// elemeiből (`HomeGreetingHeader`, `HomeLiveCard`, `HomeAssignmentRow`,
/// `HomeSeeAllLink`, iPaden `PadExamRow` / `PadHomeworkRow`), a beépített
/// `DemoData`-val. A mozgás csak koreográfia: a sorok egymás után
/// kerülnek a listába, utána a MOST-kártyán percenként telik az idő (a
/// valódi csík kúszik, a visszaszámláló pörög). Reduce Motion mellett
/// azonnal a végállapot látszik.
struct OnboardingHomeStep: View {
    @EnvironmentObject var theme: ThemeStore
    @Environment(\.colorScheme) private var scheme
    @Environment(\.horizontalSizeClass) private var hSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Neon: az üdvözlés egyszeri glitch-rángása (mint a Főoldalon).
    @State private var greetingGlitch = 0
    /// Hány elem került már be a belépő koreográfiából (0 = csak az üdvözlés).
    @State private var revealed = 0
    /// A MOST-kártya mű-ideje: percek a mai nap elejétől.
    @State private var minute = Self.startMinute
    /// Helyben kipipált demo-tételek — a valódi `CompletedStore`-ba a
    /// bemutató nem ír (a demo-ID-k ne kerüljenek a user pipái közé).
    @State private var doneExams: Set<String> = []
    @State private var doneHomeworks: Set<String> = []

    /// 9:16 → 9:31: a 2. óra (Angol, 9:00–9:45) közepe, csatolt házival.
    private static let startMinute = 9 * 60 + 16
    private static let endMinute = 9 * 60 + 31

    private let lessons: [LessonItem]
    private let exams: [ExamItem]
    private let homeworks: [HomeworkItem]

    init() {
        let lessons = DemoData.lessonsToday()
        let shift = Self.daysSinceMonday()
        let cal = Calendar.current
        func moved(_ d: Date) -> Date { cal.date(byAdding: .day, value: shift, to: d) ?? d }
        // A demo-hét (hétfőtől) a mai napra tolva: a házik és dolgozatok
        // hétvégén is élnek, és a mai órákhoz csatolódnak, mint hétfőn.
        let demoNow = Self.date(minute: Self.endMinute)
        self.lessons = lessons
        self.exams = DemoData.exams()
            .map { ExamItem(id: $0.id, subject: $0.subject, date: moved($0.date), mode: $0.mode, description: $0.description, teacher: $0.teacher) }
            .filter { !ExamExpiry.isExpired($0, now: demoNow, lessons: lessons) }
        self.homeworks = DemoData.homeworks()
            .map { HomeworkItem(id: $0.id, subject: $0.subject, title: $0.title, deadline: moved($0.deadline), teacher: $0.teacher, isDone: false, attachments: $0.attachments) }
            .filter { !HomeworkExpiry.isExpired($0, now: demoNow) }
    }

    private var colors: AppColors { theme.colors(for: scheme) }
    private var isPad: Bool { hSize == .regular }

    // MARK: - Koreográfia sorrendje

    /// 1 = MOST-kártya, utána iPhone-on a dolgozat-sorok + link, majd a
    /// házi-sorok + link; iPaden a kétoszlopos szekció egyben.
    private var examBase: Int { 2 }
    private var homeworkBase: Int { examBase + examRows.count + 1 }
    private var revealTotal: Int { isPad ? 2 : homeworkBase + homeworkRows.count }

    /// Az `index`-től induló, `count` hosszú csoportból mennyi látszik már.
    private func shown(from index: Int, of count: Int) -> Int {
        max(0, min(count, revealed - index + 1))
    }

    private var examRows: [ExamItem] { Array(exams.sorted { $0.date < $1.date }.prefix(3)) }
    /// Mint a Főoldalon: csak az élő, kipipálatlan házik.
    private var liveHomeworks: [HomeworkItem] {
        homeworks.filter { !doneHomeworks.contains($0.id) }.sorted { $0.deadline < $1.deadline }
    }
    private var homeworkRows: [HomeworkItem] { Array(liveHomeworks.prefix(3)) }

    // MARK: - Nézet

    var body: some View {
        List {
            Section {
                HomeGreetingHeader(greeting: greeting, firstName: firstName, glitch: $greetingGlitch) {
                    // Bejelentkezés előtt nincs frissítés-állapot (üresjárat).
                    EmptyView()
                }
            }

            if revealed >= 1 {
                HomeLiveCard(lessons: lessons, exams: exams, homeworks: homeworks, overrideNow: Self.date(minute: minute))
            }

            if isPad {
                if revealed >= 2 { padSection }
            } else {
                examSection
                homeworkSection
            }
        }
        .listStyle(.insetGrouped)
        .voxelDefaultFont()
        .frame(maxWidth: isPad ? MacSupport.contentWidth(ipad: 1280, mac: 1150) : .infinity)
        .padding(.horizontal, MacSupport.sidePadding)
        .frame(maxWidth: .infinity)
        .summitListChrome(colors: colors)
        .task { await play() }
    }

    // MARK: - iPhone-szekciók (a Főoldal sorai)

    @ViewBuilder
    private var examSection: some View {
        let visible = shown(from: examBase, of: examRows.count)
        if visible > 0 {
            Section {
                ForEach(examRows.prefix(visible)) { e in
                    // Ugyanaz az óra-csatolás, mint a Főoldalon (csak határidő-napi óra).
                    let lesson = HomeworkMatcher.lesson(
                        for: HomeworkItem(id: e.id, subject: e.subject, title: "", deadline: e.date, teacher: "", isDone: false),
                        in: lessons
                    )
                    HomeAssignmentRow(
                        subject: e.subject,
                        detail: e.plainDescription.isEmpty ? e.mode : "\(e.mode) • \(e.plainDescription)",
                        date: e.date,
                        lesson: lesson,
                        lessonIndexFallback: e.lessonIndex,
                        done: doneExams.contains(e.id),
                        colors: colors,
                        scheme: scheme,
                        onToggle: { toggleExam(e.id) },
                        onTap: {}
                    )
                }
                if revealed >= examBase + examRows.count {
                    HomeSeeAllLink(title: "Összes dolgozat (\(exams.count))") {}
                        .voxelListRow(fill: colors.surface)
                }
            } header: { homeSectionHeader("Közelgő dolgozatok", code: "EXM_\(String(format: "%02d", exams.count))") }
        }
    }

    @ViewBuilder
    private var homeworkSection: some View {
        let visible = shown(from: homeworkBase, of: homeworkRows.count)
        if visible > 0 {
            Section {
                ForEach(homeworkRows.prefix(visible)) { h in
                    HomeAssignmentRow(
                        subject: h.subject,
                        detail: h.plainTitle.isEmpty ? "(nincs leírás)" : h.plainTitle,
                        date: h.deadline,
                        lesson: HomeworkMatcher.lesson(for: h, in: lessons),
                        lessonIndexFallback: nil,
                        done: doneHomeworks.contains(h.id),
                        colors: colors,
                        scheme: scheme,
                        onToggle: { toggleHomework(h.id) },
                        onTap: {}
                    )
                }
                if revealed >= homeworkBase + homeworkRows.count {
                    HomeSeeAllLink(title: "Összes feladat (\(liveHomeworks.count))") {}
                        .voxelListRow(fill: colors.surface)
                }
            } header: { homeSectionHeader("Közelgő feladatok", code: "TSK_\(String(format: "%02d", liveHomeworks.count))") }
        }
    }

    // MARK: - iPad: a Főoldal kétoszlopos szekciója

    private var padSection: some View {
        Section {
            HStack(alignment: .top, spacing: 16) {
                VStack(alignment: .leading, spacing: 10) {
                    SkinLabel("Közelgő dolgozatok", systemImage: "pencil.and.list.clipboard").voxelSectionHeader()
                    ForEach(examRows, id: \.id) { e in
                        PadExamRow(exam: e, done: doneExams.contains(e.id), colors: colors, scheme: scheme) {
                            toggleExam(e.id)
                        }
                    }
                    Button("Összes dolgozat (\(exams.count))") {}
                        .skinFont(.caption, weight: .semibold)
                        .foregroundStyle(colors.accent)
                        .buttonStyle(.skinPlain)
                }.frame(maxWidth: .infinity, alignment: .topLeading)
                VStack(alignment: .leading, spacing: 10) {
                    SkinLabel("Közelgő feladatok", systemImage: "checklist").voxelSectionHeader()
                    ForEach(homeworkRows, id: \.id) { h in
                        PadHomeworkRow(homework: h, done: doneHomeworks.contains(h.id), colors: colors, scheme: scheme) {
                            toggleHomework(h.id)
                        }
                    }
                    Button("Összes feladat (\(liveHomeworks.count))") {}
                        .skinFont(.caption, weight: .semibold)
                        .foregroundStyle(colors.accent)
                        .buttonStyle(.skinPlain)
                }.frame(maxWidth: .infinity, alignment: .topLeading)
            }.padding(.vertical, 4)
        }
        .listRowBackground(Color.clear).listRowSeparator(.hidden).listRowInsets(EdgeInsets(top: 8, leading: 4, bottom: 8, trailing: 4))
    }

    // MARK: - Pipák (helyben, a Főoldal visszajelzésével)

    private func toggleExam(_ id: String) {
        SummitHaptics.taskToggled(markedDone: !doneExams.contains(id))
        withAnimation(SummitMotion.snappy) {
            if doneExams.contains(id) { doneExams.remove(id) } else { doneExams.insert(id) }
        }
    }

    private func toggleHomework(_ id: String) {
        SummitHaptics.taskToggled(markedDone: !doneHomeworks.contains(id))
        withAnimation(SummitMotion.snappy) {
            if doneHomeworks.contains(id) { doneHomeworks.remove(id) } else { doneHomeworks.insert(id) }
        }
    }

    // MARK: - Animáció

    /// Belépés: a MOST-kártya, majd a sorok egyenként kerülnek a listába
    /// (a List saját beszúró animációjával), utána a kártyán percenként
    /// telik az idő. A lépés eltűnésekor a `.task` megszakad.
    private func play() async {
        if reduceMotion {
            revealed = revealTotal
            minute = Self.endMinute
            return
        }
        try? await Task.sleep(for: .milliseconds(250))
        for step in 1...revealTotal {
            guard !Task.isCancelled else { return }
            withAnimation(SummitMotion.gentle) { revealed = step }
            try? await Task.sleep(for: .milliseconds(step == 1 ? 320 : 110))
        }
        try? await Task.sleep(for: .milliseconds(600))
        while minute < Self.endMinute {
            guard !Task.isCancelled else { return }
            withAnimation(SummitMotion.progress) { minute += 1 }
            try? await Task.sleep(for: .milliseconds(420))
        }
    }

    // MARK: - Segédek

    /// Napszak szerinti köszönés — a Főoldal (`HomeViewModel.greeting`) szabálya.
    private var greeting: String {
        let h = Calendar.current.component(.hour, from: Date())
        if h >= 18 { return "Jó estét" }
        if h >= 12 { return "Jó napot" }
        if h >= 4 { return "Jó reggelt" }
        return "Jó estét"
    }

    /// A demo-fiók keresztneve („Demo Diák" → „Diák"), mint a Főoldal üdvözlésében.
    private var firstName: String {
        let name = AppUser.demo.name
        return name.split(separator: " ").last.map(String.init) ?? name
    }

    /// A mai nap adott perce (a demo-órarend is a mai napra épül).
    private static func date(minute: Int) -> Date {
        let cal = Calendar.current
        return cal.date(byAdding: .minute, value: minute, to: cal.startOfDay(for: Date())) ?? Date()
    }

    /// Hány nap telt el a hét hétfője óta (a `DemoData` hétfőhöz horgonyoz).
    private static func daysSinceMonday() -> Int {
        let weekday = Calendar.current.component(.weekday, from: Date())
        return weekday == 1 ? 6 : weekday - 2
    }
}
