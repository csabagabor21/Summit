import SwiftUI

struct NotesView: View {
    @EnvironmentObject var theme: ThemeStore
    @EnvironmentObject var session: SessionStore
    @EnvironmentObject var kreta: KretaClient
    @EnvironmentObject var completed: CompletedStore
    @ObservedObject private var watchAvailability = WatchAvailability.shared
    @State private var homeworks: [HomeworkItem] = []
    @State private var exams: [ExamItem] = []
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
    /// Órarendi órák az óraszám-pillekhez (a csatolmány-lehúzás mellékterméke).
    @State private var lessons: [LessonItem] = []
    /// Hiányzások a dolgozat-pótláshoz (ugyanabban a körben jön, mint a többi).
    @State private var absences: [AbsenceItem] = []
    /// Dolgozat-pótlás kapcsoló/elvetés — újraszámolja a kijelzett dátumokat.
    @State private var rolloverTick = 0
    /// Percenkénti újraértékelés: az órához tűzött dolgozat az óra végén
    /// magától átkerül a Dolgozatokból a Készbe (frissítés nélkül is).
    @State private var nowTick = Date()
    @State private var isLoading = true
    @State private var filter: Int // 0 = Feladatok, 1 = Dolgozatok, 2 = Kész

    /// Főoldali "Összes dolgozat" deeplink: 1-gyel nyitva egyből a
    /// Dolgozatok szegmens jön (a tab és az értesítés-koppintás marad 0).
    init(initialFilter: Int = 0) {
        _filter = State(initialValue: initialFilter)
    }
    @State private var expandedIDs: Set<String> = []
    @State private var flashedID: String?
    @State private var flashPulse = false
    @State private var scrollProxy: ScrollViewProxy?
    private let switchToTasks = Notification.Name("summit.switchToTasks")
    @Environment(\.colorScheme) var scheme
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
                            .mcRowChrome()
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
                    Button { pendingLesson = nil; showingPicker = true } label: {
                        SkinIcon("plus")
                    }
                    .accessibilityLabel(filter == 1 ? "Saját dolgozat hozzáadása" : "Saját feladat hozzáadása")
                }
            }
            // 1) Óraválasztó (órarend szerint, nem naptár szerint).
            .sheet(isPresented: $showingPicker, onDismiss: openAddIfNeeded) {
                LessonPickerSheet(
                    lessons: lessons,
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
            .refreshable {
                await load(force: true)
                SummitHaptics.light()
            }
            // Órarend-pillből érkezve a megfelelő szegmensre ugrik + kiemeli a sort
            .onReceive(NotificationCenter.default.publisher(for: switchToTasks)) { notif in
                // Direkt kézbesítés nyert a Handoff-pendinggel szemben.
                HandoffCenter.shared.pendingTasks = nil
                if (notif.userInfo?["segment"] as? String) == "exams" {
                    filter = 1
                } else {
                    filter = 0
                }
                if let fid = notif.userInfo?["flash"] as? String {
                    // Tabváltás után fusson, hogy a sorok már legyenek
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { flash(id: fid) }
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
    private func flash(id: String) {
        withAnimation { flashedID = id }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            withAnimation(.easeInOut(duration: 0.45).repeatCount(3, autoreverses: true)) { flashPulse = true }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                withAnimation { scrollProxy?.scrollTo(id, anchor: .center) }
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
        return Text("\(title) • \(count) db")
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
    private func toggleExpanded(_ id: String, expanded: Bool) {
        // Chevron-sor lenyitása = választás: finom tick (csak user-tapból hívódik).
        SummitHaptics.selection()
        withAnimation(SummitMotion.snappy) {
            if expanded { expandedIDs.remove(id) } else { expandedIDs.insert(id) }
        }
    }

    /// Az órarendből átjött tétel villanó kerete / háttere: Summitban lekerekített,
    /// Minecraftban pixel-lépcsős alakzat.
    @ViewBuilder
    private func flashStroke(_ isFlash: Bool) -> some View {
        let color = colors.accent.opacity(isFlash ? (flashPulse ? 0.95 : 0.22) : 0)
        let width: CGFloat = isFlash ? 2.2 : 0
        if MinecraftTheme.isActive {
            McPixelShape(steps: 1).strokeBorder(color, lineWidth: isFlash ? MinecraftTheme.px : 0).allowsHitTesting(false)
        } else {
            RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(color, lineWidth: width)
        }
    }

    @ViewBuilder
    private func flashFill(_ isFlash: Bool) -> some View {
        let color = colors.accent.opacity(isFlash ? (flashPulse ? 0.16 : 0.04) : 0)
        if MinecraftTheme.isActive {
            McPixelShape(steps: 1).fill(color)
        } else {
            RoundedRectangle(cornerRadius: 12, style: .continuous).fill(color)
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
                if !hw.isDone { SummitHaptics.taskToggled(markedDone: !done) }
                withAnimation(SummitMotion.snappy) { completed.toggleHomework(hw.id) }
            } label: {
                SkinIcon(done ? "checkmark.circle.fill" : "circle", size: 30)
                    .font(.system(size: 22))
                    .foregroundStyle(done ? Color.green : .secondary)
            }
            .buttonStyle(.plain)
            .padding(.top, 2)
            VStack(alignment: .leading, spacing: 6) {
                // Csak a fejléc és az előnézet nyit-csuk — a kinyitott
                // részletező blokkban a gombok önállóan működnek
                HStack { Text(hw.subject).skinFont(.subheadline, weight: .semibold); if CustomTasksStore.isCustomId(hw.id) { Text("Saját").skinFont(.caption2, weight: .bold).foregroundStyle(colors.accent).padding(.horizontal, 8).padding(.vertical, 4).skinPill(fill: colors.accent.opacity(0.12)) }; Spacer(); if !hw.attachments.isEmpty { HStack(spacing: 3) { SkinIcon("paperclip"); if hw.attachments.count > 1 { Text("\(hw.attachments.count)") } }.skinFont(.caption2, weight: .semibold).foregroundStyle(.secondary).accessibilityLabel("\(hw.attachments.count) csatolmány") }; if let idx = lessonIndexText(for: hw) { Text(idx).skinFont(.caption2).foregroundStyle(.secondary).padding(.horizontal, 8).padding(.vertical, 4).skinPill(fill: Color.primary.opacity(0.06)) } }
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
                    .mcButtonOrPlain()
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
            .buttonStyle(.plain)
        }
        .listRowBackground(MinecraftTheme.skinRowBackground(done ? Color.green.opacity(scheme == .dark ? 0.10 : 0.07) : colors.surface))
        .listRowInsets(MinecraftTheme.rowInsets(nil))
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
                SkinIcon(ready ? "checkmark.circle.fill" : "circle", size: 30)
                    .font(.system(size: 22))
                    .foregroundStyle(ready ? Color.green : .secondary)
            }
            .buttonStyle(.plain)
            .padding(.top, 2)
            VStack(alignment: .leading, spacing: 6) {
                HStack { Text(exam.subject).skinFont(.subheadline, weight: .semibold); if CustomTasksStore.isCustomId(exam.id) { Text("Saját").skinFont(.caption2, weight: .bold).foregroundStyle(colors.accent).padding(.horizontal, 8).padding(.vertical, 4).skinPill(fill: colors.accent.opacity(0.12)) }; Spacer(); if rolled { Text("Pótló").skinFont(.caption2, weight: .bold).foregroundStyle(.red).padding(.horizontal, 8).padding(.vertical, 4).skinPill(fill: Color.red.opacity(0.12)) }; if let n = exam.lessonIndex { Text("\(n). óra").skinFont(.caption2).foregroundStyle(.secondary).padding(.horizontal, 8).padding(.vertical, 4).skinPill(fill: Color.orange.opacity(0.14)) } }
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
                    .mcButtonOrPlain()
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
            .buttonStyle(.plain)
        }
        // Pótló dolgozat piros háttere (mint a kipipált zöld, csak piros) —
        // a kész (zöld) állapot nyer, ha mindkettő igaz.
        .listRowBackground(MinecraftTheme.skinRowBackground(ready ? Color.green.opacity(scheme == .dark ? 0.10 : 0.07) : rolled ? Color.red.opacity(scheme == .dark ? 0.16 : 0.10) : colors.surface))
        .listRowInsets(MinecraftTheme.rowInsets(nil))
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
    /// hálózat nélkül tér vissza (a 15 hetes órarend-ablak is tárolt).
    /// A váz csak üres listánál jön; egyébként a régi tételek maradnak,
    /// és az új adat dinamikusan beíródik. Lehúzás (`force`) tényleges frissítés.
    func load(force: Bool = false) async {
        // Saját tételek helyből jönnek — hálózati hibától függetlenül vannak.
        reloadCustom()
        // Egy adatsáv: demo usert is a KretaClient szolgálja ki helyből.
        guard let user = session.selectedUser else { isLoading = false; return }
        let hadData = !(homeworks.isEmpty && exams.isEmpty)
        if !hadData { isLoading = true }
        let iss=user.instituteCode.isEmpty ? (JWT.instituteCode(from: user.accessToken) ?? "") : user.instituteCode
        let prevHW = homeworks, prevEx = exams, prevAb = absences
        async let hw = kreta.fetchHomework(iss: iss, force: force)
        async let ex = kreta.fetchExams(iss: iss, force: force)
        async let ab = kreta.fetchAbsences(iss: iss, force: force)
        async let subj = kreta.fetchAllSubjectNames(iss: iss, force: force)
        async let gr = kreta.fetchGrades(iss: iss, force: force)
        let (hwR, exR, abR, subjR, grR) = await (hw, ex, ab, subj, gr)
        // Totális fetch-hiba (lejárt token, offline): a legutóbbi lista marad,
        // nem ürül ki a Feladatok tab egy sikertelen refresh-től.
        if hwR.isEmpty && exR.isEmpty && hadData {
            homeworks = prevHW; exams = prevEx; absences = prevAb
        } else {
            let (mergedHW, fetchedLessons) = await lessonAttachments(hwR, exams: exR, kreta: kreta, iss: iss, absences: abR, force: force)
            homeworks = mergedHW; exams = exR; lessons = fetchedLessons
            absences = abR
        }
        // Tantárgy-univerzum a hozzáadó sheetnek: a Jegyek-tab köre
        // (hálózati tárgyak + cache + jegyekből látott tárgyak).
        let cached = UserDefaults.standard.stringArray(forKey: "firka.cachedSubjects.v1") ?? []
        subjects = Array(Set(subjR).union(cached).union(grR.map(\.subject))).sorted()
        // Apple Watch: az aktív feladatok mennek az órára is (csak sikeres
        // lehúzáskor — totális hiba esetén az órai lista változatlan marad).
        if !hwR.isEmpty || !exR.isEmpty {
            let active = WatchSyncSender.activeTasks(
                homeworks: homeworks, custom: customTasks, exams: exams,
                lessons: lessons, completed: completed
            )
            WatchSyncSender.pushTasks(homeworks: active.hw, exams: active.ex)
        }
        isLoading=false
    }

    /// Firka-minta: a KRÉTA a fájlokat az órarendi elemre teszi
    /// (`OrarendElemek[].Csatolmanyok`), a házi-payloadban gyakran semmi
    /// sincs. A fájl a FELADÁS hetének óráján is lehet (HaziFeladatUid-kapocs),
    /// nem csak a határidő napján — ezért a teljes listaablakot (-35 nap)
    /// plusz a határidőket nézzük át, heti darabokban, párhuzamosan.
    /// Üres/sikertelen órarendnél a házi-lista változatlanul marad.
    private func lessonAttachments(_ hwR: [HomeworkItem], exams exR: [ExamItem], kreta: KretaClient, iss: String, absences abR: [AbsenceItem], force: Bool = false) async -> ([HomeworkItem], [LessonItem]) {
        guard !hwR.isEmpty || !exR.isEmpty else { return (hwR, []) }
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        // A dolgozat-dátumok is tágítják az ablakot: a pótló-óra kereséséhez
        // a jövőbeli órák is kellenek, nem csak a házi-határidők.
        let deadlines = hwR.map(\.deadline) + exR.map(\.date)
        // Hiányzás a dolgozat napján → a tétel ELŐRE (akár 60 nappal) vetítődik:
        // ilyenkor az ablaknak a pótolt nap óráit is le kell fednie, különben
        // az órarendes lejárt-határ (ExamExpiry) nem talál órát, és a dolgozat
        // az óra után is a Dolgozatokban ragad.
        let absenceDays = Set(abR.map { cal.startOfDay(for: $0.date) })
        let hasOverlap = exR.contains { absenceDays.contains(cal.startOfDay(for: $0.date)) }
        let horizon: Date
        if hasOverlap, let far = cal.date(byAdding: .day, value: 62, to: today) {
            horizon = far
        } else {
            horizon = cal.date(byAdding: .day, value: 2, to: cal.startOfDay(for: max(deadlines.max() ?? today, today))) ?? today
        }
        guard let from = cal.date(byAdding: .day, value: -35, to: today),
              horizon > from else { return (hwR, []) }
        let to = horizon
        // Heti darabolás (nagy ablakra az órarend-végpont megbízhatatlan),
        // max ~3,5 hónap — a listaablak, a tipikus határidők és átfedéskor
        // a 60 napos pótló-horizont is belefér.
        var chunks: [(Date, Date)] = []
        var cur = from
        while cur < to && chunks.count < 15 {
            let end = min(cal.date(byAdding: .day, value: 7, to: cur)!, to)
            chunks.append((cur, end))
            cur = end
        }
        let lessons: [LessonItem] = await withTaskGroup(of: [LessonItem].self) { group in
            for (s, e) in chunks {
                group.addTask { await kreta.fetchTimetable(iss: iss, from: s, to: e, force: force) }
            }
            var out: [LessonItem] = []
            for await part in group { out.append(contentsOf: part) }
            return out
        }
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
    let onPick: (LessonItem) -> Void
    let onSkip: () -> Void
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var theme: ThemeStore
    @Environment(\.colorScheme) var scheme
    var colors: AppColors { theme.colors(for: scheme) }
    @State private var day: Date

    init(lessons: [LessonItem], onPick: @escaping (LessonItem) -> Void, onSkip: @escaping () -> Void) {
        self.lessons = lessons
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
                if days.isEmpty {
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
                    .mcListRowComfy(fill: colors.surface)
                    Section("Órák") {
                        if dayLessons.isEmpty {
                            Text("Ezen a napon nincs óra.").foregroundStyle(.secondary)
                        } else {
                            ForEach(dayLessons) { lesson in
                                Button { onPick(lesson) } label: {
                                    HStack(spacing: 10) {
                                        Text(lesson.index)
                                            .skinFont(.subheadline, weight: .bold).monospacedDigit()
                                            .frame(width: 28, height: 28)
                                            .background {
                                                if MinecraftTheme.isActive { McInventorySlot() }
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
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    .mcListRowComfy(fill: colors.surface)
                }
                Section {
                    Button("Naptár szerint viszem fel") { onSkip() }
                        .mcInlineButton()
                }
                .mcListRowComfy(fill: colors.surface)
            }
            .skinFormChrome()
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
                    .padding(.horizontal, theme.isMinecraft ? 16 : 0)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))
                }
                if isLessonBound {
                    Section("Óra") {
                        SkinLabel("\(subject) • \(lessonBoundDateText) • \(period). óra", systemImage: "calendar")
                            .skinFont(.callout)
                    }
                    .mcListRowComfy(fill: colors.surface)
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
                    .mcListRowComfy(fill: colors.surface)
                }
                Section(isExam ? "Megnevezés" : "Leírás") {
                    TextField(isExam ? "Pl. Témazáró – Egyenletek" : "Pl. 5-ös fejezet vázlat",
                              text: $title,
                              prompt: skinPrompt(isExam ? "Pl. Témazáró – Egyenletek" : "Pl. 5-ös fejezet vázlat"),
                              axis: .vertical)
                        .mcInput()
                }
                .mcListRowComfy(fill: colors.surface)
                if !isLessonBound {
                    Section("Nap") {
                        DatePicker("Nap", selection: $day,
                                   in: Calendar.current.startOfDay(for: Date())...Date.distantFuture,
                                   displayedComponents: .date)
                        .datePickerStyle(.graphical)
                        .labelsHidden()
                    }
                    .mcListRowComfy(fill: colors.surface)
                    Section(isExam ? "Hányadik órában" : "Hányadik órára") {
                        SkinStepper(title: "\(period). óra", value: $period, range: 1...15)
                    }
                    .mcListRowComfy(fill: colors.surface)
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
            // Minecraft-skin: Monocraft ugyanazzal a Dynamic Type skálával
            // (a pixelbetűnek nincs félkövér/dőlt változata, a jelölés így
            // csak az aláhúzásból / linkből látszik).
            let mcFont = MinecraftTheme.isActive
                ? UIFont(name: MinecraftFontLoader.familyName, size: s.heading ? 15 : 14).map {
                    UIFontMetrics(forTextStyle: s.heading ? .headline : .body).scaledFont(for: $0)
                } : nil
            var traits: UIFontDescriptor.SymbolicTraits = []
            if s.bold { traits.insert(.traitBold) }
            if s.italic { traits.insert(.traitItalic) }
            if mcFont == nil, !traits.isEmpty, let d = font.fontDescriptor.withSymbolicTraits(traits) {
                font = UIFont(descriptor: d, size: 0)
            }
            c.font = mcFont ?? font
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
