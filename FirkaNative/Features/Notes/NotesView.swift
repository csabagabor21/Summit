import SwiftUI

struct NotesView: View {
    @EnvironmentObject var theme: ThemeStore
    @EnvironmentObject var session: SessionStore
    @EnvironmentObject var kreta: KretaClient
    @EnvironmentObject var completed: CompletedStore
    @ObservedObject private var watchAvailability = WatchAvailability.shared
    /// A házik / dolgozatok / órák / hiányzások a közös gyorstárból (KretaStore)
    /// indulnak: tabra lépéskor azonnal látszik a mentett lista, a
    /// frissítés a háttérben íródik be.
    @State private var homeworks: [HomeworkItem]
    @State private var exams: [ExamItem]
    /// Saját (kézzel felvett) tételek — a KRÉTA-listákkal összefésülve jelennek meg.
    @State private var customTasks: [CustomTask] = []
    /// Saját tétel ID → hányadik tanóra (a házi-sorok óraszám-pilljéhez).
    @State private var customPeriods: [String: Int] = [:]
    /// Létező tantárgyak (Jegyek-tab köre): a sheet csak ezekből enged választani.
    @State private var subjects: [String] = []
    @State private var showingAdd = false
    @State private var showingWatch = false
    /// Óraválasztó a felvételhez: a pluszra előbb az órarend jön (nem naptár),
    /// a kiválasztott óra töltődik elő a felvevő lapon.
    @State private var showingPicker = false
    @State private var pendingLesson: LessonItem?
    @State private var openAddAfterPicker = false
    /// Az óraválasztó saját órái: a házi-ablak órái + a következő 4 hét
    /// (különben jövő heti óra nem volt, házi nélkül pedig egy sem).
    @State private var pickerLessons: [LessonItem] = []
    @State private var pickerLoading = false
    /// Órarendi órák az óraszám-pillekhez (a csatolmány-lehúzás mellékterméke).
    @State private var lessons: [LessonItem]
    /// Hiányzások a dolgozat-pótláshoz (ugyanabban a körben jön, mint a többi).
    @State private var absences: [AbsenceItem]
    /// Dolgozat-pótlás kapcsoló/elvetés — újraszámolja a kijelzett dátumokat.
    @State private var rolloverTick = 0
    /// Percenkénti újraértékelés: az órához tűzött dolgozat az óra végén
    /// magától átkerül a Dolgozatokból a Készbe (frissítés nélkül is).
    @State private var nowTick = Date()
    /// Csak akkor igaz, ha még semmilyen (mentett) házi/dolgozat-adat nincs.
    @State private var isLoading: Bool
    @State private var filter: Int // 0 = Feladatok, 1 = Dolgozatok, 2 = Kész

    /// Főoldali "Összes dolgozat" deeplink: 1-gyel nyitva egyből a
    /// Dolgozatok szegmens jön (a tab és az értesítés-koppintás marad 0).
    init(initialFilter: Int = 0) {
        _filter = State(initialValue: initialFilter)
        let snap = Self.storeSnapshot()
        _homeworks = State(initialValue: snap.homeworks)
        _exams = State(initialValue: snap.exams)
        _lessons = State(initialValue: snap.lessons)
        _absences = State(initialValue: snap.absences)
        _isLoading = State(initialValue: !snap.known)
    }

    /// A gyorstár állapota (hálózat nélkül): házik a már ismert órarendi
    /// és részlet-csatolmányokkal, dolgozatok, hiányzások, az ablak órái.
    private struct StoreSnapshot {
        var homeworks: [HomeworkItem]
        var exams: [ExamItem]
        var lessons: [LessonItem]
        var absences: [AbsenceItem]
        var known: Bool
    }

    private static func storeSnapshot() -> StoreSnapshot {
        let store = KretaStore.shared
        let hwList: [HomeworkItem]? = store.value(.homework)
        let exList: [ExamItem]? = store.value(.exams)
        let abs: [AbsenceItem] = store.value(.absences) ?? []
        let hw = hwList ?? [], ex = exList ?? []
        var lessons: [LessonItem] = []
        var merged = hw
        if let window = lessonWindow(homeworks: hw, exams: ex, absences: abs) {
            lessons = store.availableLessons(from: window.from, to: window.to)
            if !lessons.isEmpty { merged = HomeworkLessonAttachments.merged(hw, lessons: lessons) }
        }
        merged = store.applyingCachedHomeworkDetails(merged)
        return StoreSnapshot(homeworks: merged, exams: ex, lessons: lessons, absences: abs,
                             known: hwList != nil || exList != nil)
    }

    /// Gyorstár → kijelzett állapot (store-változáskor, hálózat nélkül).
    private func syncFromStore() {
        let snap = Self.storeSnapshot()
        guard snap.known else { return }
        if homeworks != snap.homeworks { homeworks = snap.homeworks }
        if exams != snap.exams { exams = snap.exams }
        if lessons != snap.lessons { lessons = snap.lessons }
        if absences != snap.absences { absences = snap.absences }
        isLoading = false
    }
    @State private var expandedIDs: Set<String> = []
    @State private var flashedID: String?
    @State private var flashPulse = false
    @State private var scrollProxy: ScrollViewProxy?
    private let switchToTasks = Notification.Name("summit.switchToTasks")
    @Environment(\.colorScheme) var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.horizontalSizeClass) private var hSize
    private var isPad: Bool { hSize == .regular }
    /// Széles elrendezés (iPad / Mac): a Watch ilyenkor sidebar-tab,
    /// nem toolbar-gomb (lásd MainTabView.watchTabVisible).
    private var isWide: Bool { isPad || MacSupport.isMac }
    var colors: AppColors { theme.colors(for: scheme) }

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
            List {
                Section {
                    // Egyedi binding: a setter CSAK user-koppintásra fut —
                    // a deeplink/Handoff szegmensugrás néma marad.
                    SkinSegmented(selection: Binding(
                        get: { filter },
                        set: { if $0 != filter { SummitHaptics.selection() }; filter = $0 }
                    ), options: [
                        SkinOption(value: 0, title: "Feladatok"), SkinOption(value: 1, title: "Dolgozatok"), SkinOption(value: 2, title: "Kész"),
                    ])
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 4, trailing: 16))
                    .listRowSeparator(.hidden)
                    .animation(SummitMotion.gentle, value: filter)
                }

                if isLoading {
                    ForEach(0..<3, id: \.self) { _ in
                        HStack { Text("Betöltés…").redacted(reason: .placeholder) }
                            .summitRowSurface(colors: colors)
                            .voxelRowChrome()
                    }
                } else if currentIsEmpty {
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
                    // Napra bontott szekciók — nem ömlesztett lista.
                    Group {
                        if filter == 1 {
                            ForEach(examDayGroups, id: \.day) { g in
                                Section {
                                    ForEach(g.items, id: \.id) { exam in
                                        examRow(exam, isFlash: flashedID == exam.id,
                                                rolled: resolvedExams.rolledIDs.contains(exam.id),
                                                originalDate: resolvedExams.originalDates[exam.id])
                                    }
                                } header: {
                                    dayHeader(day: g.day, count: g.items.count)
                                }
                            }
                        } else if filter == 2 {
                            ForEach(doneDayGroups, id: \.day) { g in
                                Section {
                                    ForEach(g.items) { entry in
                                        switch entry {
                                        case .homework(let hw):
                                            homeworkRow(hw, isFlash: flashedID == hw.id)
                                        case .exam(let exam):
                                            examRow(exam, isFlash: flashedID == exam.id,
                                                    rolled: resolvedExams.rolledIDs.contains(exam.id),
                                                    originalDate: resolvedExams.originalDates[exam.id])
                                        }
                                    }
                                } header: {
                                    dayHeader(day: g.day, count: g.items.count)
                                }
                            }
                        } else {
                            ForEach(homeworkDayGroups, id: \.day) { g in
                                Section {
                                    ForEach(g.items, id: \.id) { hw in
                                        homeworkRow(hw, isFlash: flashedID == hw.id)
                                    }
                                } header: {
                                    dayHeader(day: g.day, count: g.items.count)
                                }
                            }
                        }
                    }
                    .id(filter)
                    .transition(.opacity)
                }
            }
            .listStyle(.insetGrouped)
            .frame(maxWidth: isPad ? MacSupport.contentWidth(ipad: 1000, mac: 1150) : .infinity)
            .padding(.horizontal, MacSupport.sidePadding)
            .frame(maxWidth: .infinity)
            .summitListChrome(colors: colors)
            .animation(SummitMotion.gentle, value: currentIsEmpty)
            .animation(SummitMotion.gentle, value: filter)
            .navigationTitle("Feladatok")
            .navigationBarTitleDisplayMode(.large)
            .summitToolbarBackground()
            .toolbar {
                // Watch-belépő a + gombbal szemben, a másik oldalt —
                // CSAK iPhone-on (compact): iPad-en és Mac-en a Watch
                // saját sidebar-tabot kap (lásd MainTabView), itt nem kell.
                // Sheetben nyílik a saját X-ével — pusholva a beágyazott
                // NavigationStack miatt nem lenne látható visszaút.
                if watchAvailability.showTab && !isWide {
                    SkinToolbarItem(placement: .topBarLeading) {
                        Button { showingWatch = true } label: {
                            SkinIcon("applewatch")
                        }
                        .accessibilityLabel("Watch")
                    }
                }
                SkinToolbarItem(placement: .topBarTrailing) {
                    Button { openLessonPicker() } label: {
                        SkinIcon("plus")
                    }
                    .accessibilityLabel(filter == 1 ? "Saját dolgozat hozzáadása" : "Saját feladat hozzáadása")
                }
            }
            // 1) Óraválasztó (órarend szerint, nem naptár szerint).
            .sheet(isPresented: $showingPicker, onDismiss: openAddIfNeeded) {
                LessonPickerSheet(
                    lessons: pickerLessons,
                    isLoading: pickerLoading,
                    onPick: { lesson in
                        pendingLesson = lesson
                        openAddAfterPicker = true
                        showingPicker = false
                    },
                    onSkip: {
                        pendingLesson = nil
                        openAddAfterPicker = true
                        showingPicker = false
                    }
                )
            }
            // 2) Felvevő lap — óraválasztás után előtöltve, különben naptárral.
            .sheet(isPresented: $showingAdd) {
                AddCustomTaskSheet(
                    kind: filter == 1 ? .exam : .homework,
                    subjects: addSubjects,
                    onSave: { reloadCustom(); pendingLesson = nil },
                    prefillSubject: pendingLesson?.subject,
                    prefillDay: pendingLesson?.start,
                    prefillPeriod: pendingLesson.flatMap { Int($0.index) }
                )
            }
            // 3) Watch-jegyzetek — saját X-szel csukható (nincs tab-sáv).
            .sheet(isPresented: $showingWatch) {
                CheatView(showCloseButton: true)
            }
            .onReceive(NotificationCenter.default.publisher(for: CustomTasksStore.changedNotification)) { _ in
                reloadCustom()
            }
            // Dolgozat-pótlás kapcsoló/elvetés — a kijelzett dátumok újraszámolódnak.
            .onReceive(NotificationCenter.default.publisher(for: ExamRollover.changedNotification)) { _ in
                rolloverTick += 1
            }
            // Percenkénti jel: az óra végén lejárt dolgozat magától átkerül
            // a Készbe (a lejárt-határ a nowTick-től függ).
            .onReceive(Timer.publish(every: 60, on: .main, in: .common).autoconnect()) { nowTick = $0 }
            .task { await load() }
            // Közös gyorstár: a háttérben (bárhonnan) beérkező házi / dolgozat /
            // hiányzás azonnal beíródik, a body maga nem függ a store-tól.
            .background {
                KretaStoreWatcher(kinds: [.homework, .exams, .absences]) { syncFromStore() }
            }
            .refreshable {
                await load(force: true)
                SummitHaptics.light()
            }
            // Órarend-pillből érkezve a megfelelő szegmensre ugrik + kiemeli a sort
            .onReceive(NotificationCenter.default.publisher(for: switchToTasks)) { notif in
                // Direkt kézbesítés nyert a Handoff-pendinggel szemben.
                HandoffCenter.shared.pendingTasks = nil
                let wantsExams = (notif.userInfo?["segment"] as? String) == "exams"
                let fid = notif.userInfo?["flash"] as? String
                // A szegmens oda nyílik, ahol a tétel ténylegesen van: a
                // lejárt / kipipált tétel a Készben él („hw-"/„ex-" előtagú
                // sor-azonosítóval) — különben semmi nem villant fel.
                var segment = wantsExams ? 1 : 0
                var scrollID = fid
                if let fid {
                    let live = wantsExams ? filteredExams.contains { $0.id == fid }
                                          : filteredHomeworks.contains { $0.id == fid }
                    let doneID = (wantsExams ? "ex-" : "hw-") + fid
                    if !live, doneEntries.contains(where: { $0.id == doneID }) {
                        segment = 2
                        scrollID = doneID
                    }
                }
                filter = segment
                if let fid, let scrollID {
                    // Tabváltás után fusson, hogy a sorok már legyenek
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { flash(id: fid, scrollTo: scrollID) }
                } else {
                    flashedID = nil; flashPulse = false
                }
            }
            .onAppear { scrollProxy = proxy }
            // Continuity-folytatás: a küldő szegmense + villanó sora
            // (a direkt értesítés a cover-animáció alatt elveszhet — a
            // pending ilyenkor ment meg). Utána a saját állapotot hirdetjük.
            .onAppear {
                // Óra-párosítás az app futása alatt is változhat — a
                // Watch-gomb láthatósága ettől függ.
                watchAvailability.refresh()
                if let p = HandoffCenter.shared.takeTasks() {
                    filter = p.segment
                    if let fid = p.flash {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { flash(id: fid) }
                    }
                }
                HandoffCenter.shared.setTasksPosition(segment: filter)
            }
            .onChange(of: filter) { _, seg in
                HandoffCenter.shared.setTasksPosition(segment: seg)
            }
            }
        }
        .tint(colors.accent)
    }

    /// Kiemelőszínű flash + odagörgetés az órarendből átjött feladathoz/dolgozathoz.
    /// `scrollTo`: a List-sor azonosítója, ha eltér a tételétől (Kész: előtagos).
    private func flash(id: String, scrollTo: String? = nil) {
        withAnimation { flashedID = id }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            withAnimation(.easeInOut(duration: 0.45).repeatCount(3, autoreverses: true)) { flashPulse = true }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                withAnimation { scrollProxy?.scrollTo(scrollTo ?? id, anchor: .center) }
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.2) {
            withAnimation { flashedID = nil; flashPulse = false }
        }
    }

    // Élő házi: kipipált és lejárt nem jelenik meg (a Készbe kerül),
    // Home-on a kipipált zölden marad
    var filteredHomeworks: [HomeworkItem] {
        (homeworks + CustomTasksStore.homeworkItems(from: customTasks))
            .filter { !completed.isHomeworkDone($0.id) && !HomeworkExpiry.isExpired($0) }
            .sorted { $0.deadline < $1.deadline }
    }
    /// Kész szegmens: kipipált + lejárt házi és lejárt dolgozat, időrendben.
    /// A kipipálás innen vissza is vonható; a lejárt csak történet.
    enum DoneEntry: Identifiable {
        case homework(HomeworkItem)
        case exam(ExamItem)
        var id: String {
            switch self {
            case .homework(let hw): return "hw-" + hw.id
            case .exam(let ex): return "ex-" + ex.id
            }
        }
        var date: Date {
            switch self {
            case .homework(let hw): return hw.deadline
            case .exam(let ex): return ex.date
            }
        }
    }
    var doneEntries: [DoneEntry] {
        let today = Calendar.current.startOfDay(for: Date())
        // A dolgozat-történet nem nőhet végtelenre: az elmúlt 30 nap lejártjai
        // (a házi-lista amúgy is -30 napos ablakból jön).
        let examCutoff = Calendar.current.date(byAdding: .day, value: -30, to: today)!
        var out: [DoneEntry] = (homeworks + CustomTasksStore.homeworkItems(from: customTasks))
            .filter { completed.isHomeworkDone($0.id) || $0.isDone || HomeworkExpiry.isExpired($0) }
            .map { .homework($0) }
        out += resolvedExams.items
            .filter { ExamExpiry.isExpired($0, now: nowTick, lessons: lessons) && $0.date >= examCutoff }
            .map { .exam($0) }
        // Legújabb legfelül (nem a legrégebbi) — a Kész egy történet,
        // a friss pipa érdekli a usert, nem a hónapos.
        return out.sorted { $0.date > $1.date }
    }
    /// Dolgozatok átütemezéssel: ha a dolgozat napján hiányoztál, a
    /// következő olyan órán jelenik meg (piros háttérrel) — swipe-pal elvethető.
    private var resolvedExams: (items: [ExamItem], rolledIDs: Set<String>, originalDates: [String: Date]) {
        _ = rolloverTick
        return ExamRollover.displayItems(
            exams: exams + CustomTasksStore.examItems(from: customTasks),
            absences: absences, lessons: lessons)
    }
    // Élő dolgozat: csak a még nem lejárt — a lejárt a Készbe kerül.
    // A határ a KIJELZETT (pótolt) dátumon dől el; az órához tűzött aznapi
    // dolgozat az óra végén jár le (nem éjfélkor).
    var filteredExams: [ExamItem] {
        resolvedExams.items
            .filter { !ExamExpiry.isExpired($0, now: nowTick, lessons: lessons) }
            .sorted { $0.date < $1.date }
    }
    // MARK: - Napra bontás (Feladatok, Dolgozatok, Kész — mindhárom)
    // A Kész csökkenő (legújabb nap és napon belül a legújabb tétel legfelül),
    // az élő listák növekvő maradnak.
    private func groupByDay<T>(_ items: [T], date: (T) -> Date, descending: Bool = false) -> [(day: Date, items: [T])] {
        let cal = Calendar.current
        let grouped = Dictionary(grouping: items) { cal.startOfDay(for: date($0)) }
        let days = descending ? grouped.keys.sorted(by: >) : grouped.keys.sorted()
        return days.map { day in
            let items = grouped[day]!.sorted { descending ? date($0) > date($1) : date($0) < date($1) }
            return (day: day, items: items)
        }
    }
    var homeworkDayGroups: [(day: Date, items: [HomeworkItem])] {
        groupByDay(filteredHomeworks) { $0.deadline }
    }
    var examDayGroups: [(day: Date, items: [ExamItem])] {
        groupByDay(filteredExams) { $0.date }
    }
    var doneDayGroups: [(day: Date, items: [DoneEntry])] {
        groupByDay(doneEntries, date: { $0.date }, descending: true)
    }
    /// Napcím: Ma / Holnap / Tegnap, különben "szept. 22., hétfő" + darabszám.
    /// Neonban HUD-szekciófejléc (a mai nap sárga, a többi HUD-vörös,
    /// a darabszám `// 03 DB` kód).
    private func dayHeader(day: Date, count: Int) -> some View {
        let cal = Calendar.current
        let title: String
        if cal.isDateInToday(day) { title = "Ma" }
        else if cal.isDateInTomorrow(day) { title = "Holnap" }
        else if cal.isDateInYesterday(day) { title = "Tegnap" }
        else {
            let f = DateFormatter(); f.locale = Locale(identifier: "hu_HU"); f.dateFormat = "MMM d., EEEE"
            title = f.string(from: day).capitalized
        }
        return dayHeaderLabel(title: title, count: count, isToday: cal.isDateInToday(day))
    }
    @ViewBuilder
    private func dayHeaderLabel(title: String, count: Int, isToday: Bool) -> some View {
        if theme.isNeon {
            NeonSectionHeader(title, code: String(format: "%02d db", count),
                            accent: isToday ? NeonTheme.yellow : NeonTheme.red)
                .accessibilityLabel("\(title), \(count) db")
        } else {
            Text("\(title) • \(count) db").skinSecondaryOnSky()
        }
    }
    private var currentIsEmpty: Bool {
        if filter == 1 { return filteredExams.isEmpty }
        if filter == 2 { return doneEntries.isEmpty }
        return filteredHomeworks.isEmpty
    }
    // Magyar dátum — az eszköz nyelve angol is lehet, a KRÉTA-dátum éjfélkor időpont nélkül
    private func huDate(_ d: Date) -> String {
        let f = DateFormatter(); f.locale = Locale(identifier: "hu_HU"); f.dateFormat = "yyyy. MMM d."
        return f.string(from: d)
    }
    private func huDateTime(_ d: Date) -> String {
        let c = Calendar.current.dateComponents([.hour, .minute], from: d)
        if c.hour == 0 && c.minute == 0 { return huDate(d) }
        let f = DateFormatter(); f.locale = Locale(identifier: "hu_HU"); f.dateFormat = "yyyy. MMM d. HH:mm"
        return f.string(from: d)
    }
    /// Házipill: nem a dátum (az a szekciófejlécben van), hanem hogy
    /// hányadik órára van feladva. Saját tételnél a felvételkor választott
    /// tanóra nyer (tárgy + határidő-nap illesztéssel csak a KRÉTA-tételek).
    private func lessonIndexText(for hw: HomeworkItem) -> String? {
        if let p = customPeriods[hw.id] { return "\(p). óra" }
        guard let lesson = HomeworkMatcher.lesson(for: hw, in: lessons) else { return nil }
        return "\(lesson.index). óra"
    }

    /// A felvevő lap tantárgy-listája: az óraválasztott tárgy akkor is
    /// választható, ha épp nincs a KRÉTA-univerzumban.
    private var addSubjects: [String] {
        guard let s = pendingLesson?.subject, !subjects.contains(s) else { return subjects }
        return [s] + subjects
    }

    /// Az óraválasztó nyitása: azonnal a már ismert órákkal (házi-ablak +
    /// gyorstárban lévő következő 4 hét), a hiányzó hetek a háttérben
    /// töltődnek be (a heti gyorstár szabályai szerint).
    private func openLessonPicker() {
        pendingLesson = nil
        let range = pickerRange
        pickerLessons = mergedPickerLessons(KretaStore.shared.availableLessons(from: range.from, to: range.to))
        showingPicker = true
        guard let user = session.selectedUser else { return }
        let iss = user.instituteCode.isEmpty ? (JWT.instituteCode(from: user.accessToken) ?? "") : user.instituteCode
        guard !iss.isEmpty else { return }
        pickerLoading = true
        Task {
            let fetched = await kreta.fetchTimetable(iss: iss, from: range.from, to: range.to)
            pickerLessons = mergedPickerLessons(fetched)
            pickerLoading = false
        }
    }

    private var pickerRange: (from: Date, to: Date) {
        let today = Calendar.current.startOfDay(for: Date())
        return (today, Calendar.current.date(byAdding: .day, value: 28, to: today) ?? today)
    }

    /// A házi-ablak órái + a kapott órák, azonosító szerint egyszer, időrendben.
    private func mergedPickerLessons(_ extra: [LessonItem]) -> [LessonItem] {
        var seen = Set<String>()
        return (pickerLessons + lessons + extra)
            .filter { seen.insert($0.id).inserted }
            .sorted { $0.start < $1.start }
    }

    /// Óraválasztó bezárása után (választással vagy "Naptár szerint"-tel)
    /// nyílik a felvevő lap — kézi becsukásnál nem.
    private func openAddIfNeeded() {
        if openAddAfterPicker {
            openAddAfterPicker = false
            showingAdd = true
        }
    }

    /// Saját tételek újratöltése az óraszám-térképpel együtt.
    private func reloadCustom() {
        let all = CustomTasksStore.load()
        customTasks = all
        customPeriods = Dictionary(uniqueKeysWithValues: all.compactMap { t in
            t.lessonIndex.map { (t.id, $0) }
        })
    }
    /// Részletező dátumsor: időpont (ha van) + hányadik óra
    private func examDateLine(_ exam: ExamItem) -> String {
        if let n = exam.lessonIndex { return "\(huDateTime(exam.date)) (\(n). óra)" }
        return huDateTime(exam.date)
    }
    /// Kész sor halvány arca: Summitban rendszer-zöld, Neonban HUD-türkiz.
    private var doneFill: Color {
        theme.isNeon ? NeonTheme.green.opacity(0.10) : Color.green.opacity(scheme == .dark ? 0.10 : 0.07)
    }

    private func toggleExpanded(_ id: String, expanded: Bool) {
        // Chevron-sor lenyitása = választás: finom tick (csak user-tapból hívódik).
        SummitHaptics.selection()
        withAnimation(SummitMotion.snappy) {
            if expanded { expandedIDs.remove(id) } else { expandedIDs.insert(id) }
        }
    }

    /// Az órarendből átjött tétel villanó kerete / háttere: Summitban lekerekített,
    /// Voxelben pixel-lépcsős alakzat.
    @ViewBuilder
    private func flashStroke(_ isFlash: Bool) -> some View {
        let color = colors.accent.opacity(isFlash ? (flashPulse ? 0.95 : 0.22) : 0)
        let width: CGFloat = isFlash ? 2.2 : 0
        if VoxelTheme.isActive {
            VoxelPixelShape(steps: 1).strokeBorder(color, lineWidth: isFlash ? VoxelTheme.px : 0).allowsHitTesting(false)
        } else if NeonTheme.isActive {
            cpFlashShape.strokeBorder(NeonTheme.yellow.opacity(isFlash ? (flashPulse || reduceMotion ? 1 : 0.35) : 0), lineWidth: isFlash ? 1.5 : 0)
                .padding(cpFlashOutset).allowsHitTesting(false)
        } else {
            RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(color, lineWidth: width)
                .allowsHitTesting(false)
        }
    }

    /// Neon flash-alakzat: a sor HUD-paneljével (NeonRowBackground)
    /// egybeeső levágott sarkú keret — a sor-tartalomtól a panel széléig
    /// (alap sor-margó) kifelé tolva.
    private var cpFlashShape: NeonChamferShape { NeonChamferShape(cut: 10, corners: .diagonal) }
    private var cpFlashOutset: EdgeInsets { EdgeInsets(top: -11, leading: -16, bottom: -11, trailing: -16) }

    @ViewBuilder
    private func flashFill(_ isFlash: Bool) -> some View {
        let color = colors.accent.opacity(isFlash ? (flashPulse ? 0.16 : 0.04) : 0)
        if VoxelTheme.isActive {
            VoxelPixelShape(steps: 1).fill(color)
        } else if NeonTheme.isActive {
            cpFlashShape.fill(NeonTheme.yellow.opacity(isFlash ? (flashPulse || reduceMotion ? 0.12 : 0.04) : 0))
                .padding(cpFlashOutset).allowsHitTesting(false)
        } else {
            RoundedRectangle(cornerRadius: 12, style: .continuous).fill(color)
        }
    }

    /// Kész-pipa: Summitban / Voxelben a megszokott kör-ikon,
    /// Neonban levágott sarkú HUD-jelölőnégyzet (sárga keret, készen
    /// sárga kitöltés fekete pipával).
    @ViewBuilder
    private func checkGlyph(_ on: Bool) -> some View {
        if NeonTheme.isActive {
            let box = NeonChamferShape(cut: 5, corners: .diagonal)
            box.fill(on ? NeonTheme.yellow : NeonTheme.panel)
                .overlay(box.strokeBorder(NeonTheme.yellow.opacity(on ? 1 : 0.6), lineWidth: 1))
                .overlay {
                    if on {
                        Image(systemName: "checkmark")
                            .font(.system(size: 12, weight: .heavy))
                            .foregroundStyle(Color.black)
                    }
                }
                .frame(width: 22, height: 22)
                .frame(width: 30, height: 30)
                .contentShape(Rectangle())
        } else {
            SkinIcon(on ? "checkmark.circle.fill" : "circle", size: 30)
                .font(.system(size: 22))
                .foregroundStyle(on ? Color.green : .secondary)
        }
    }

    /// Sor-háttér: Neonban HUD-panel az állapot színű kerettel (kész =
    /// türkiz, pótló = vörös, egyébként a skin alap HUD-vöröse); máshol a
    /// megszokott `skinRowBackground`.
    @ViewBuilder
    private func taskRowBackground(_ fill: Color, accent: Color = NeonTheme.red) -> some View {
        if NeonTheme.isActive {
            NeonRowBackground(accent: accent, fill: fill)
        } else {
            VoxelTheme.skinRowBackground(fill)
        }
    }

    @ViewBuilder
    private func homeworkRow(_ hw: HomeworkItem, isFlash: Bool = false) -> some View {
        let done = completed.isHomeworkDone(hw.id) || hw.isDone
        let expanded = expandedIDs.contains(hw.id)
        HStack(alignment: .top, spacing: 10) {
            Button {
                // Készre pipa = ünnepelt kimenet (success), levétel = könnyű
                // koppanás. KRÉTA-kész tételnél nincs állapotváltás — ott néma.
                SummitHaptics.taskToggled(markedDone: !done)
                withAnimation(SummitMotion.snappy) { completed.toggleHomework(hw.id) }
            } label: {
                checkGlyph(done)
            }
            .buttonStyle(.skinPlain)
            // KRÉTA-ban kész tétel: a pipa nem vehető le (eddig némán
            // billentette a helyi állapotot, látható változás nélkül).
            .disabled(hw.isDone)
            .accessibilityLabel(done ? "Kész" : "Készre jelölés")
            .padding(.top, 2)
            VStack(alignment: .leading, spacing: 6) {
                // Csak a fejléc és az előnézet nyit-csuk — a kinyitott
                // részletező blokkban a gombok önállóan működnek
                HStack { Text(hw.subject).skinFont(.subheadline, weight: .semibold); if CustomTasksStore.isCustomId(hw.id) { Text("Saját").cpTag().skinFont(.caption2, weight: .bold).foregroundStyle(colors.accent).padding(.horizontal, 8).padding(.vertical, 4).skinPill(fill: colors.accent.opacity(0.12)) }; Spacer(); if !hw.attachments.isEmpty { HStack(spacing: 3) { SkinIcon("paperclip"); if hw.attachments.count > 1 { Text("\(hw.attachments.count)") } }.skinFont(.caption2, weight: .semibold).foregroundStyle(.secondary).accessibilityLabel("\(hw.attachments.count) csatolmány") }; if let idx = lessonIndexText(for: hw) { Text(idx).cpTag().skinFont(.caption2).foregroundStyle(.secondary).padding(.horizontal, 8).padding(.vertical, 4).skinPill(fill: Color.primary.opacity(0.06)) } }
                    .contentShape(Rectangle())
                    .onTapGesture { toggleExpanded(hw.id, expanded: expanded) }
                if expanded {
                    // Teljes szöveg KRÉTA-formázással (félkövér, listák, linkek),
                    // nyers HTML-tagek nélkül
                    Text(HomeworkHTML.formatted(hw.title))
                        .skinFont(.callout)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    // Határidő: saját tételnél a választott tanóra + nap
                    // (nincs falióra-idő), KRÉTA-tételnél a megszokott időpont.
                    if let p = customPeriods[hw.id] {
                        SkinLabel("\(p). óra • \(huDate(hw.deadline))", systemImage: "clock")
                            .skinFont(.caption).foregroundStyle(.secondary)
                    } else {
                        SkinLabel(hw.deadline.formatted(date: .abbreviated, time: .shortened), systemImage: "clock")
                            .skinFont(.caption).foregroundStyle(.secondary)
                    }
                    if !hw.teacher.isEmpty {
                        SkinLabel(hw.teacher, systemImage: "person.fill")
                            .skinFont(.caption).foregroundStyle(.secondary)
                    }
                    // Órarend-ugrás (a csatolmány-blokk fölött), majd a fájlok.
                    Button {
                        NotificationCenter.default.post(name: Notification.Name("summit.switchToTimetable"), object: nil, userInfo: ["subject": hw.subject, "deadline": hw.deadline.timeIntervalSince1970, "hwId": hw.id])
                    } label: {
                        SkinLabel("Mutatás az órarendben", systemImage: "calendar")
                            .skinFont(.caption, weight: .semibold)
                            .skinOutlinePill(colors.accent)
                    }
                    .voxelButtonOrPlain()
                    // Csatolt fájlok (PDF, kép…) — koppintásra QuickLook.
                    AttachmentsBlock(attachments: hw.attachments, ownerId: hw.id)
                } else {
                    Text(hw.plainTitle.isEmpty ? "(nincs leírás)" : hw.plainTitle)
                        .skinFont(.callout).foregroundStyle(.secondary).lineLimit(3)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                        .onTapGesture { toggleExpanded(hw.id, expanded: expanded) }
                }
            }
            Spacer(minLength: 0)
            Button { toggleExpanded(hw.id, expanded: expanded) } label: {
                SkinIcon(expanded ? "chevron.up" : "chevron.down")
                    .skinFont(.caption, weight: .semibold)
                    .foregroundStyle(.tertiary)
                    .padding(.top, 6)
            }
            .buttonStyle(.skinPlain)
        }
        .listRowBackground(taskRowBackground(done ? doneFill : colors.surface, accent: done ? NeonTheme.green : NeonTheme.red))
        .listRowInsets(VoxelTheme.rowInsets(nil))
        .overlay(flashStroke(isFlash))
        .background(flashFill(isFlash))
        .transition(.asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity), removal: .move(edge: .leading).combined(with: .opacity)))
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            if CustomTasksStore.isCustomId(hw.id) {
                Button(role: .destructive) {
                    // Saját feladat törlése: semleges commit-koppanás.
                    SummitHaptics.light()
                    CustomTasksStore.remove(id: hw.id)
                } label: {
                    SkinLabel("Törlés", systemImage: "trash")
                }
            }
        }
    }

    @ViewBuilder
    private func examRow(_ exam: ExamItem, isFlash: Bool = false, rolled: Bool = false, originalDate: Date? = nil) -> some View {
        let expanded = expandedIDs.contains(exam.id)
        // Kipipálható (ready vagy-e), de a listában marad — nem tűnik el, mint a házi
        let ready = completed.isExamDone(exam.id)
        HStack(alignment: .top, spacing: 10) {
            Button {
                // Mint a házi-pipa: készre → success, vissza → light.
                SummitHaptics.taskToggled(markedDone: !ready)
                withAnimation(SummitMotion.snappy) { completed.toggleExam(exam.id) }
            } label: {
                checkGlyph(ready)
            }
            .buttonStyle(.skinPlain)
            .padding(.top, 2)
            VStack(alignment: .leading, spacing: 6) {
                HStack { Text(exam.subject).skinFont(.subheadline, weight: .semibold); if CustomTasksStore.isCustomId(exam.id) { Text("Saját").cpTag().skinFont(.caption2, weight: .bold).foregroundStyle(colors.accent).padding(.horizontal, 8).padding(.vertical, 4).skinPill(fill: colors.accent.opacity(0.12)) }; Spacer(); if rolled { Text("Pótló").cpTag().skinFont(.caption2, weight: .bold).foregroundStyle(theme.isNeon ? NeonTheme.red : .red).padding(.horizontal, 8).padding(.vertical, 4).skinPill(fill: (theme.isNeon ? NeonTheme.red : Color.red).opacity(0.12)) }; if let n = exam.lessonIndex { Text("\(n). óra").cpTag().skinFont(.caption2).foregroundStyle(.secondary).padding(.horizontal, 8).padding(.vertical, 4).skinPill(fill: (theme.isNeon ? NeonTheme.yellow : Color.orange).opacity(0.14)) } }
                    .contentShape(Rectangle())
                    .onTapGesture { toggleExpanded(exam.id, expanded: expanded) }
                if expanded {
                    Text(exam.mode)
                        .skinFont(.callout, weight: .semibold)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    if !exam.plainDescription.isEmpty {
                        Text(exam.plainDescription)
                            .skinFont(.callout).foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    if !exam.teacher.isEmpty {
                        SkinLabel(exam.teacher, systemImage: "person.fill")
                            .skinFont(.caption).foregroundStyle(.secondary)
                    }
                    // Dátum időponttal (éjfélkor csak dátum) + hányadik óra — a hivatalos
                    // app is írja: "2026. szeptember 15., kedd (1. óra)"
                    SkinLabel(examDateLine(exam), systemImage: "clock")
                        .skinFont(.caption).foregroundStyle(.secondary)
                    // Pótló dolgozatnál az eredeti nap is látszik
                    if rolled, let orig = originalDate {
                        SkinLabel("Eredeti: \(huDate(orig))", systemImage: "calendar.badge.exclamationmark")
                            .skinFont(.caption, weight: .medium).foregroundStyle(.red)
                    }
                    if let announced = exam.announcedDate {
                        SkinLabel("Bejelentve: \(huDate(announced))", systemImage: "megaphone")
                            .skinFont(.caption).foregroundStyle(.secondary)
                    }
                    if !exam.groupName.isEmpty {
                        SkinLabel(exam.groupName, systemImage: "person.2.fill")
                            .skinFont(.caption).foregroundStyle(.secondary)
                    }
                    Button {
                        NotificationCenter.default.post(name: Notification.Name("summit.switchToTimetable"), object: nil, userInfo: ["subject": exam.subject, "deadline": exam.date.timeIntervalSince1970])
                    } label: {
                        SkinLabel("Mutatás az órarendben", systemImage: "calendar")
                            .skinFont(.caption, weight: .semibold)
                            .skinOutlinePill(colors.accent)
                    }
                    .voxelButtonOrPlain()
                    AttachmentsBlock(attachments: exam.attachments, ownerId: exam.id)
                } else {
                    Text(exam.plainDescription.isEmpty ? exam.mode : "\(exam.mode) • \(exam.plainDescription)")
                        .skinFont(.callout).foregroundStyle(.secondary).lineLimit(2)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                        .onTapGesture { toggleExpanded(exam.id, expanded: expanded) }
                }
            }
            Spacer(minLength: 0)
            Button { toggleExpanded(exam.id, expanded: expanded) } label: {
                SkinIcon(expanded ? "chevron.up" : "chevron.down")
                    .skinFont(.caption, weight: .semibold)
                    .foregroundStyle(.tertiary)
                    .padding(.top, 6)
            }
            .buttonStyle(.skinPlain)
        }
        // Pótló dolgozat piros háttere (mint a kipipált zöld, csak piros) —
        // a kész (zöld) állapot nyer, ha mindkettő igaz.
        .listRowBackground(taskRowBackground(ready ? doneFill : rolled ? (theme.isNeon ? NeonTheme.red.opacity(0.16) : Color.red.opacity(scheme == .dark ? 0.16 : 0.10)) : colors.surface,
                                             accent: ready ? NeonTheme.green : NeonTheme.red))
        .listRowInsets(VoxelTheme.rowInsets(nil))
        .overlay(flashStroke(isFlash))
        .background(flashFill(isFlash))
        .transition(.asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity), removal: .move(edge: .leading).combined(with: .opacity)))
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            // Pótló átütemezés elvetése — az eredeti dátum marad
            if rolled {
                Button {
                    SummitHaptics.light()
                    ExamRollover.dismiss(exam.id)
                } label: {
                    SkinLabel("Elvetés", systemImage: "xmark")
                }
                .tint(.orange)
            }
            if CustomTasksStore.isCustomId(exam.id) {
                Button(role: .destructive) {
                    SummitHaptics.light()
                    CustomTasksStore.remove(id: exam.id)
                } label: {
                    SkinLabel("Törlés", systemImage: "trash")
                }
            }
        }
    }

    /// Tabváltáskor a `.task` újra lefut — friss gyorstár-találatnál ez
    /// hálózat nélkül tér vissza. A mentett lista már látszik (init), a
    /// frissítés a háttérben íródik be: előbb a lista, utána (külön) az
    /// órarendi és részlet-csatolmányok — a lista nem vár a heti órarendekre.
    /// Lehúzás (`force`) tényleges frissítés.
    func load(force: Bool = false) async {
        // Saját tételek helyből jönnek — hálózati hibától függetlenül vannak.
        reloadCustom()
        // Egy adatsáv: demo usert is a KretaClient szolgálja ki helyből.
        guard let user = session.selectedUser else { isLoading = false; return }
        KretaStore.shared.activate(user)
        let iss=user.instituteCode.isEmpty ? (JWT.instituteCode(from: user.accessToken) ?? "") : user.instituteCode
        async let hw = kreta.fetchHomework(iss: iss, force: force)
        async let ex = kreta.fetchExams(iss: iss, force: force)
        async let ab = kreta.fetchAbsences(iss: iss, force: force)
        async let subj = kreta.fetchAllSubjectNames(iss: iss, force: force)
        async let gr = kreta.fetchGrades(iss: iss, force: force)
        let (hwR, exR, abR, subjR, grR) = await (hw, ex, ab, subj, gr)
        // A lista a gyorstárból (benne a most beérkezett friss adattal);
        // totális fetch-hiba esetén a legutóbbi mentett lista marad.
        syncFromStore()
        isLoading = false
        // Tantárgy-univerzum a hozzáadó sheetnek: a Jegyek-tab köre
        // (hálózati tárgyak + cache + jegyekből látott tárgyak).
        let cached = UserDefaults.standard.stringArray(forKey: KretaClient.cachedSubjectsKey) ?? []
        subjects = Array(Set(subjR).union(cached).union(grR.map(\.subject))).sorted()
        if !hwR.isEmpty || !exR.isEmpty {
            let (mergedHW, fetchedLessons) = await lessonAttachments(hwR, exams: exR, kreta: kreta, iss: iss, absences: abR, force: force)
            if !mergedHW.isEmpty { homeworks = mergedHW }
            if !fetchedLessons.isEmpty { lessons = fetchedLessons }
        }
        // Apple Watch: az aktív feladatok mennek az órára is (csak sikeres
        // lehúzáskor — totális hiba esetén az órai lista változatlan marad).
        if !hwR.isEmpty || !exR.isEmpty {
            let active = WatchSyncSender.activeTasks(
                homeworks: homeworks, custom: customTasks, exams: exams,
                lessons: lessons, completed: completed
            )
            WatchSyncSender.pushTasks(homeworks: active.hw, exams: active.ex)
        }
    }

    /// A csatolmány-/pótló-kereséshez szükséges órarend-ablak: a házi-lista
    /// −35 napja + a határidők (+2 nap); dolgozat napján lévő hiányzásnál a
    /// 62 napos pótló-horizont. Nil, ha nincs mit nézni.
    private static func lessonWindow(homeworks: [HomeworkItem], exams: [ExamItem], absences: [AbsenceItem]) -> (from: Date, to: Date)? {
        guard !homeworks.isEmpty || !exams.isEmpty else { return nil }
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        // A dolgozat-dátumok is tágítják az ablakot: a pótló-óra kereséséhez
        // a jövőbeli órák is kellenek, nem csak a házi-határidők.
        let deadlines = homeworks.map(\.deadline) + exams.map(\.date)
        // Hiányzás a dolgozat napján → a tétel ELŐRE (akár 60 nappal) vetítődik:
        // ilyenkor az ablaknak a pótolt nap óráit is le kell fednie, különben
        // az órarendes lejárt-határ (ExamExpiry) nem talál órát, és a dolgozat
        // az óra után is a Dolgozatokban ragad.
        let absenceDays = Set(absences.map { cal.startOfDay(for: $0.date) })
        let hasOverlap = exams.contains { absenceDays.contains(cal.startOfDay(for: $0.date)) }
        let horizon: Date
        if hasOverlap, let far = cal.date(byAdding: .day, value: 62, to: today) {
            horizon = far
        } else {
            horizon = cal.date(byAdding: .day, value: 2, to: cal.startOfDay(for: max(deadlines.max() ?? today, today))) ?? today
        }
        guard let from = cal.date(byAdding: .day, value: -35, to: today), horizon > from else { return nil }
        // Max ~3,5 hónap — a listaablak, a tipikus határidők és átfedéskor a
        // 60 napos pótló-horizont is belefér.
        let cap = cal.date(byAdding: .day, value: 15 * 7, to: from) ?? horizon
        return (from, min(horizon, cap))
    }

    /// Firka-minta: a KRÉTA a fájlokat az órarendi elemre teszi
    /// (`OrarendElemek[].Csatolmanyok`), a házi-payloadban gyakran semmi
    /// sincs. A fájl a FELADÁS hetének óráján is lehet (HaziFeladatUid-kapocs),
    /// nem csak a határidő napján — ezért a teljes listaablakot (-35 nap)
    /// plusz a határidőket nézzük át. A hetek a közös heti gyorstárból jönnek
    /// (a lezárt múlt hét nem megy újra hálózatra, a többi a frissesség-
    /// szabály szerint), így tabra lépésenként nem fut le 15 órarend-kérés.
    /// Üres/sikertelen órarendnél a házi-lista változatlanul marad.
    private func lessonAttachments(_ hwR: [HomeworkItem], exams exR: [ExamItem], kreta: KretaClient, iss: String, absences abR: [AbsenceItem], force: Bool = false) async -> ([HomeworkItem], [LessonItem]) {
        guard let window = Self.lessonWindow(homeworks: hwR, exams: exR, absences: abR) else { return (hwR, []) }
        let lessons = await kreta.fetchTimetable(iss: iss, from: window.from, to: window.to, force: force)
        // Ami órarendből sem jött meg (vagy üres volt az órarend),
        // annak a részlet-végpont adhat fájlt.
        if lessons.isEmpty { return (await kreta.fetchHomeworkDetails(hwR, iss: iss), []) }
        let merged = HomeworkLessonAttachments.merged(hwR, lessons: lessons)
        let hits = merged.filter { !$0.attachments.isEmpty }.count
        kreta.diag("feladat-csatolmány: \(hits)/\(hwR.count) házihoz van fájl (\(lessons.count) óra átnézve)")
        return (await kreta.fetchHomeworkDetails(merged, iss: iss), lessons)
    }
}

/// Óraválasztó a saját feladat felvételéhez: a pluszra nem naptár jön,
/// hanem az órarend — a koppintott óra tárgya, napja és óraszáma töltődik
/// elő a felvevő lapon. A "Naptár szerint" úttal marad a kézi dátumozás.
struct LessonPickerSheet: View {
    let lessons: [LessonItem]
    /// A következő hetek órái még töltődnek.
    var isLoading: Bool = false
    let onPick: (LessonItem) -> Void
    let onSkip: () -> Void
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var theme: ThemeStore
    @Environment(\.colorScheme) var scheme
    var colors: AppColors { theme.colors(for: scheme) }
    @State private var day: Date

    init(lessons: [LessonItem], isLoading: Bool = false, onPick: @escaping (LessonItem) -> Void, onSkip: @escaping () -> Void) {
        self.lessons = lessons
        self.isLoading = isLoading
        self.onPick = onPick
        self.onSkip = onSkip
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let ds = Array(Set(lessons.map { cal.startOfDay(for: $0.start) })).sorted()
        if let first = ds.first, let last = ds.last {
            _day = State(initialValue: min(max(today, first), last))
        } else {
            _day = State(initialValue: today)
        }
    }

    private var days: [Date] {
        let cal = Calendar.current
        return Array(Set(lessons.map { cal.startOfDay(for: $0.start) })).sorted()
    }

    private var dayLessons: [LessonItem] {
        lessons.filter { Calendar.current.isDate($0.start, inSameDayAs: day) }
            .sorted { $0.start < $1.start }
    }

    var body: some View {
        NavigationStack {
            List {
                if days.isEmpty && isLoading {
                    HStack(spacing: 10) {
                        SkinProgress()
                        Text("Órarend betöltése…").skinFont(.subheadline).foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, minHeight: 120)
                    .listRowBackground(Color.clear)
                } else if days.isEmpty {
                    SkinEmptyState(
                        title: "Nincs betöltött óra",
                        systemImage: "calendar.badge.exclamationmark",
                        description: Text("Húzd le a Feladatok tabot a frissítéshez, vagy vidd fel naptár szerint.")
                    )
                } else {
                    Section("Nap") {
                        DatePicker("Nap", selection: $day, in: days.first!...days.last!, displayedComponents: .date)
                            .datePickerStyle(.graphical)
                            .labelsHidden()
                    }
                    .voxelListRowComfy(fill: colors.surface)
                    Section("Órák") {
                        if dayLessons.isEmpty {
                            Text("Ezen a napon nincs óra.").foregroundStyle(.secondary)
                        } else {
                            ForEach(dayLessons) { lesson in
                                Button { onPick(lesson) } label: {
                                    HStack(spacing: 10) {
                                        Text(lesson.index)
                                            .cpOnly { $0.font(NeonTheme.mono(size: 14, relativeTo: .subheadline)).foregroundStyle(NeonTheme.yellow) }
                                            .skinFont(.subheadline, weight: .bold).monospacedDigit()
                                            .frame(width: 28, height: 28)
                                            .background {
                                                if VoxelTheme.isActive { VoxelInventorySlot() }
                                                else if NeonTheme.isActive {
                                                    NeonChamferShape(cut: 6, corners: .diagonal).fill(NeonTheme.yellow.opacity(0.10))
                                                        .overlay(NeonChamferShape(cut: 6, corners: .diagonal).strokeBorder(NeonTheme.yellow.opacity(0.7), lineWidth: 1))
                                                }
                                                else { Circle().fill(Color.primary.opacity(0.08)) }
                                            }
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(lesson.subject)
                                                .skinFont(.subheadline, weight: .semibold)
                                                .foregroundStyle(.primary)
                                            Text("\(lesson.start.formatted(date: .omitted, time: .shortened)) • \(lesson.room)")
                                                .skinFont(.caption)
                                                .foregroundStyle(.secondary)
                                        }
                                        Spacer()
                                        SkinIcon("chevron.right")
                                            .skinFont(.caption2, weight: .semibold)
                                            .foregroundStyle(.tertiary)
                                    }
                                    // `.plain` gombban csak a rajzolt pixelek
                                    // koppinthatók: a Spacer-rész enélkül halott.
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.skinPlain)
                            }
                        }
                    }
                    .voxelListRowComfy(fill: colors.surface)
                }
                Section {
                    Button("Naptár szerint viszem fel") { onSkip() }
                        .voxelInlineButton()
                }
                .voxelListRowComfy(fill: colors.surface)
            }
            .skinFormChrome()
            .onChange(of: days) { _, new in
                // A háttérben beérkező jövő heti órák: ha a választott nap
                // már elmúlt (a házi-ablak régi óráiból jött), a legközelebbi
                // tanítási napra ugrik.
                let today = Calendar.current.startOfDay(for: Date())
                if day < today, let next = new.first(where: { $0 >= today }) { day = next }
            }
            .navigationTitle("Melyik órához?")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                SkinToolbarItem(placement: .cancellationAction) {
                    Button("Mégse") { dismiss() }
                }
            }
        }
    }
}

/// Saját feladat / dolgozat felvétele: típus, tantárgy (CSAK a meglévő,
/// Jegyeknél is látható tárgyakból), megnevezés, naptár-nap + aznapi óra.
/// Óraválasztóból nyitva az óra előtöltődik (tárgy + nap + óraszám).
struct AddCustomTaskSheet: View {
    let kind: CustomTaskKind
    let subjects: [String]
    let onSave: () -> Void
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var theme: ThemeStore
    @Environment(\.colorScheme) var scheme
    var colors: AppColors { theme.colors(for: scheme) }
    @State private var selectedKind: CustomTaskKind
    @State private var subject = ""
    @State private var title = ""
    @State private var day: Date
    /// Hányadik tanóra aznap (1., 2., 3. …) — nem falióra-időpont.
    @State private var period: Int

    /// Igaz, ha óraválasztóból nyitottuk: a tárgy + nap + óraszám a
    /// kiválasztott órából jön, ezért a felvevő lapon már nem kérdezzük
    /// újra — csak összefoglalóként mutatjuk.
    private let isLessonBound: Bool

    init(kind: CustomTaskKind, subjects: [String], onSave: @escaping () -> Void,
         prefillSubject: String? = nil, prefillDay: Date? = nil, prefillPeriod: Int? = nil) {
        self.kind = kind
        self.subjects = subjects
        self.onSave = onSave
        let trimmedSubject = prefillSubject?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let validPeriod = prefillPeriod.flatMap { (1...15).contains($0) ? $0 : nil }
        self.isLessonBound = !trimmedSubject.isEmpty && prefillDay != nil && validPeriod != nil
        _selectedKind = State(initialValue: kind)
        _day = State(initialValue: prefillDay.map { Calendar.current.startOfDay(for: $0) } ?? Calendar.current.startOfDay(for: Date()))
        if let p = prefillSubject, !p.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            _subject = State(initialValue: p)
        } else if let first = subjects.first {
            _subject = State(initialValue: first)
        }
        _period = State(initialValue: prefillPeriod.flatMap { (1...15).contains($0) ? $0 : nil } ?? 1)
    }

    /// Óraválasztóból jött összefoglaló dátuma (magyar formátum).
    private var lessonBoundDateText: String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "hu_HU")
        f.dateFormat = "MMM d., EEEE"
        return f.string(from: day).capitalized
    }

    private var isExam: Bool { selectedKind == .exam }
    private var canSave: Bool {
        !subject.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        && !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    SkinSegmented(selection: $selectedKind, options: [
                        SkinOption(value: CustomTaskKind.homework, title: "Feladat"),
                        SkinOption(value: CustomTaskKind.exam, title: "Dolgozat"),
                    ])
                    .padding(.horizontal, theme.isVoxel || theme.isNeon ? 16 : 0)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))
                }
                if isLessonBound {
                    Section("Óra") {
                        SkinLabel("\(subject) • \(lessonBoundDateText) • \(period). óra", systemImage: "calendar")
                            .skinFont(.callout)
                    }
                    .voxelListRowComfy(fill: colors.surface)
                } else {
                    Section("Tantárgy") {
                        if subjects.isEmpty {
                            Text("Még nincs tantárgy — húzd le a Jegyek tabot.")
                                .skinFont(.callout).foregroundStyle(.secondary)
                        } else {
                            SkinMenuPicker(
                                title: "Tantárgy",
                                selection: $subject,
                                options: subjects.map { SkinOption(value: $0, title: $0) }
                            )
                        }
                    }
                    .voxelListRowComfy(fill: colors.surface)
                }
                Section(isExam ? "Megnevezés" : "Leírás") {
                    TextField(isExam ? "Pl. Témazáró – Egyenletek" : "Pl. 5-ös fejezet vázlat",
                              text: $title,
                              prompt: skinPrompt(isExam ? "Pl. Témazáró – Egyenletek" : "Pl. 5-ös fejezet vázlat"),
                              axis: .vertical)
                        .voxelInput()
                }
                .voxelListRowComfy(fill: colors.surface)
                if !isLessonBound {
                    Section("Nap") {
                        DatePicker("Nap", selection: $day,
                                   in: Calendar.current.startOfDay(for: Date())...Date.distantFuture,
                                   displayedComponents: .date)
                        .datePickerStyle(.graphical)
                        .labelsHidden()
                    }
                    .voxelListRowComfy(fill: colors.surface)
                    Section(isExam ? "Hányadik órában" : "Hányadik órára") {
                        SkinStepper(title: "\(period). óra", value: $period, range: 1...15)
                    }
                    .voxelListRowComfy(fill: colors.surface)
                }
            }
            .skinFormChrome()
            .navigationTitle(isExam ? "Saját dolgozat" : "Saját feladat")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                SkinToolbarItem(placement: .cancellationAction) {
                    Button("Mégse") { dismiss() }
                }
                SkinToolbarItem(placement: .confirmationAction) {
                    Button("Mentés") {
                        // A nap éjféli kezdete + választott tanóra-sorszám.
                        let date = Calendar.current.startOfDay(for: day)
                        CustomTasksStore.add(kind: selectedKind, subject: subject,
                                             title: title, date: date, lessonIndex: period)
                        onSave()
                        dismiss()
                    }
                    .disabled(!canSave || subjects.isEmpty)
                }
            }
        }
    }
}

/// KRÉTA házi-szöveg (HTML) formázott megjelenítése: félkövér/dőlt,
/// aláhúzott/áthúzott, listák, linkek megmaradnak, nyers tagek nem látszanak.
/// Szándékosan NEM az NSAttributedString HTML-importjával: az WebKitet használ
/// és SwiftUI body-ból hívva AttributeGraph-crash-t (SIGABRT) okozott.
/// Ez kézi szegmens-építés (HomeworkRich) + Dynamic Type-barát preferred font,
/// színek nélkül — világos/sötét módban is a rendszer szövegszínével jelenik meg.
enum HomeworkHTML {
    static func formatted(_ html: String) -> AttributedString {
        let segs = HomeworkRich.segments(from: html)
        guard !segs.isEmpty else {
            let p = HomeworkPlain.text(from: html)
            return AttributedString(p.isEmpty ? "(nincs leírás)" : p)
        }
        var out = AttributedString()
        for s in segs {
            var c = AttributeContainer()
            var font = UIFont.preferredFont(forTextStyle: s.heading ? .headline : .body)
            // Voxel-skin: Monocraft ugyanazzal a Dynamic Type skálával
            // (a pixelbetűnek nincs félkövér/dőlt változata, a jelölés így
            // csak az aláhúzásból / linkből látszik).
            let voxelFont = VoxelTheme.isActive
                ? UIFont(name: VoxelFontLoader.familyName, size: s.heading ? 15 : 14).map {
                    UIFontMetrics(forTextStyle: s.heading ? .headline : .body).scaledFont(for: $0)
                } : nil
            // Neon-skin: Rajdhani (a skin folyószöveg-betűje) ugyanazzal
            // a Dynamic Type skálával; félkövér / címsor = Bold, egyébként
            // SemiBold (dőlt változat nincs — a dőlt jelölés ott nem látszik).
            let cpFont: UIFont? = voxelFont == nil && NeonTheme.isActive ? {
                NeonFontLoader.registerOnce()
                let name = (s.heading || s.bold) ? NeonFontLoader.displayBold : NeonFontLoader.displaySemiBold
                return UIFont(name: name, size: s.heading ? 19 : 17).map {
                    UIFontMetrics(forTextStyle: s.heading ? .headline : .body).scaledFont(for: $0)
                }
            }() : nil
            var traits: UIFontDescriptor.SymbolicTraits = []
            if s.bold { traits.insert(.traitBold) }
            if s.italic { traits.insert(.traitItalic) }
            if voxelFont == nil, cpFont == nil, !traits.isEmpty, let d = font.fontDescriptor.withSymbolicTraits(traits) {
                font = UIFont(descriptor: d, size: 0)
            }
            c.font = voxelFont ?? cpFont ?? font
            if s.underline { c.underlineStyle = NSUnderlineStyle.single }
            if s.strike { c.strikethroughStyle = NSUnderlineStyle.single }
            if let l = s.link { c.link = l }
            var part = AttributedString(s.text)
            part.mergeAttributes(c)
            out += part
        }
        return out
    }
}

// MARK: - Neon-segédek (csak ebben a fájlban)

private extension View {
    /// Csak Neon-skinben alkalmazott módosítás; Summitban és
    /// Voxelben a nézet érintetlen marad.
    @ViewBuilder
    func cpOnly<V: View>(_ transform: (Self) -> V) -> some View {
        if NeonTheme.isActive { transform(self) } else { self }
    }

    /// Apró címke (Saját / Pótló / óraszám) Neonban egyenközű,
    /// nagybetűs HUD-kód. A `skinFont` ELÉ kell tenni (a belső betű nyer).
    func cpTag() -> some View {
        cpOnly { $0.font(NeonTheme.mono(size: 10, relativeTo: .caption2)).textCase(.uppercase).tracking(0.8) }
    }
}
