import SwiftUI

// MARK: - Editorial Timetable — liquid glass számozás + spine timeline
// - Baloldalt: minden óra 1,2,3... liquid glass körben (az üveg a szám háttere)
// - Editorial tipó: nagy rounded subject, tracked label, finom progress, spine vonal
// - Current óra kiemelve: accent tinted glass + élő progress
// - Elmarad / helyettesítés: tinted surface + capsule badge
struct TimetableView: View {
    @EnvironmentObject var theme: ThemeStore
    @EnvironmentObject var session: SessionStore
    @EnvironmentObject var kreta: KretaClient
    @State private var lessons: [LessonItem] = []
    // Üres initial: a demo-értékek valós módban az első load előtt is belekacsintottak a UI-ba.
    @State private var homeworks: [HomeworkItem] = []
    @State private var exams: [ExamItem] = []
    @State private var selectedDay: Int = Calendar.current.component(.weekday, from: Date())
    @State private var weekOffset: Int = 0 // 0 = ez a hét, -1 = múlt hét, +1 = jövő hét
    // Kézi navigálás (hét/nap lapozás) után az okos ugrás nem dobhat vissza —
    // csak a "Ma" gomb és az első betöltés ugorhat a következő tanítási napra.
    @State private var userHasNavigated = false
    @State private var isLoading = true
    @State private var loadError: String? = nil
    @State private var flashedLessonID: String?
    @State private var suppressAutoJumpUntil = Date.distantPast // házi-deeplink alatt nincs okos ugrás
    @State private var flashPulse = false
    @State private var scrollProxy: ScrollViewProxy?
    @State private var exemptedTick = 0
    // Iskolai események (tannaptár): a Beállításokban importált ICS,
    // SummitSync-kel jön át a többi eszközről is.
    @State private var schoolEvents: [SchoolEvent] = SchoolEventsStore.load()
    /// Hiányzások a dolgozat-pótláshoz (egyszer húzzuk, a hétlapozás
    /// újrahasznosítja; pull-to-refresh nullázza).
    @State private var cachedAbsences: [AbsenceItem]?
    /// Dolgozat-pótlás kapcsoló/elvetés — újraszámolja a kijelzett dátumokat.
    @State private var rolloverTick = 0
    @AppStorage("schoolevents.show.v1") private var schoolEventsVisible = true
    private let switchToTimetable = Notification.Name("summit.switchToTimetable")
    @Environment(\.colorScheme) var scheme
    @Environment(\.horizontalSizeClass) private var hSize
    private var isPad: Bool { hSize == .regular }
    var colors: AppColors { theme.colors(for: scheme) }
    let days = ["Hétfő","Kedd","Szerda","Csütörtök","Péntek"]
    private let dayTags = Array(2...6)
    @AppStorage("home.demoPreviewActive") private var isPreviewActive = false
    @AppStorage("home.demoPreviewMinutes") private var previewMinutes: Double = 540
    @AppStorage("developer.enabled") private var devMode = false
    private func mondayOfWeek(offset: Int) -> Date {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let weekday = cal.component(.weekday, from: today)
        let mondayOffset = (weekday == 1 ? -6 : 2 - weekday)
        let baseMonday = cal.date(byAdding: .day, value: mondayOffset, to: today)!
        return cal.date(byAdding: .day, value: offset * 7, to: baseMonday)!
    }
    private var currentMonday: Date { mondayOfWeek(offset: weekOffset) }
    /// Naptári nap → (weekOffset, hétköznap-tag) a 0. hét hétfőjéhez képest.
    private func offsetAndTag(for day: Date) -> (weekOffset: Int, weekday: Int) {
        let cal = Calendar.current
        let base = mondayOfWeek(offset: 0)
        let diff = cal.dateComponents([.day], from: base, to: cal.startOfDay(for: day)).day ?? 0
        let wd = cal.component(.weekday, from: day)
        guard wd >= 2 && wd <= 6 else { return (0, 2) }
        return (Int(floor(Double(diff) / 7.0)), wd)
    }
    /// Ha a mai utolsó óra már véget ért (vagy hétvége van), a következő tanítási
    /// (órával rendelkező) nap weekOffset/hétköznap párját adja vissza.
    private func smartDayTarget(now: Date, items: [LessonItem]) -> (weekOffset: Int, weekday: Int) {
        let cal = Calendar.current
        let weekday = cal.component(.weekday, from: now)
        let isWeekend = (weekday == 1 || weekday == 7)
        if !isWeekend {
            let todays = items.filter { cal.isDate($0.start, inSameDayAs: now) }
            if let lastEnd = todays.map(\.end).max() {
                if now < lastEnd { return (0, weekday) } // még tart / hátravan a mai tanítás
            } else if items.isEmpty {
                return (0, weekday) // még nincs adat — naptár szerint ma
            }
            // Mai órák lementek (vagy ma nincs óra, de van cache): első órás nap előre
            for i in 1...14 {
                guard let day = cal.date(byAdding: .day, value: i, to: now) else { continue }
                let wd = cal.component(.weekday, from: day)
                guard wd >= 2 && wd <= 6 else { continue }
                if items.contains(where: { cal.isDate($0.start, inSameDayAs: day) }) {
                    return offsetAndTag(for: day)
                }
            }
        }
        // Hétvége, vagy a cache-ben nincs előrébb óra (pl. a jövő hét még nincs
        // lehúzva): naptár szerinti következő hétköznap.
        for i in 1...7 {
            guard let day = cal.date(byAdding: .day, value: i, to: now) else { continue }
            let wd = cal.component(.weekday, from: day)
            if wd >= 2 && wd <= 6 { return offsetAndTag(for: day) }
        }
        return isWeekend ? (1, 2) : (0, weekday)
    }
    /// Tabra lépéskor / betöltés után a következő tanítási napra ugrik, ha kell.
    /// Igazat ad vissza, ha napot (vagy hetet) váltott.
    @discardableResult
    private func applySmartDay(now: Date = Date()) -> Bool {
        guard now > suppressAutoJumpUntil else { return false }
        let t = smartDayTarget(now: now, items: lessons)
        guard t.weekOffset != weekOffset || t.weekday != selectedDay else { return false }
        weekOffset = t.weekOffset
        selectedDay = t.weekday
        return true
    }
    /// "Ma" gomb / hétnév-tap: vissza a 0. hétre, majd a load() végi okos
    /// ugrás (userHasNavigated == false) finomít a következő tanítási napra
    /// (hétvége / nap vége → kövi tanítási nap). Direkt a cache-ből nem
    /// számolunk, mert az még a régi hetet mutathatná.
    private func goToSmartToday() {
        suppressAutoJumpUntil = .distantPast
        withAnimation(SummitMotion.page) { weekOffset = 0 }
        userHasNavigated = false
        Task { await load() }
    }

    /// Tabra lépéskor MINDIG a mai napra áll (a kézi lapozás nem marad meg
    /// tabváltáson át). A load() végi okos ugrás finomít a következő
    /// tanítási napra (hétvége / nap vége). Házi-deeplink alatt nem nyúl
    /// semmihez — a jumpToLesson intézi a pozíciót.
    private func enterTimetable() {
        guard !isLoading else { return }
        guard Date() > suppressAutoJumpUntil else { return }
        let wd = Calendar.current.component(.weekday, from: Date())
        withAnimation(SummitMotion.page) {
            weekOffset = 0
            selectedDay = min(6, max(2, wd))
            userHasNavigated = false
        }
        Task { await load() }
    }

    /// Deeplink-cél hét/nap a határidőből (a lapozó ±8 hetéhez igazítva).
    /// Hétvégi határidő → péntek (a házi órája jellemzően ott van).
    private func deeplinkTarget(for deadline: Date) -> (weekOffset: Int, weekday: Int) {
        let cal = Calendar.current
        let base = mondayOfWeek(offset: 0)
        let diff = cal.dateComponents([.day], from: base, to: cal.startOfDay(for: deadline)).day ?? 0
        let off = max(-8, min(8, Int(floor(Double(diff) / 7.0))))
        var wd = cal.component(.weekday, from: deadline)
        if wd < 2 || wd > 6 { wd = 6 }
        return (off, wd)
    }

    /// "Mutatás az órarendben" ugrás: a határidő hetére lapoz (ha kell),
    /// megvárja a töltést, és CSAK a betöltött órák közt keres — korábban
    /// a régi hét rossz órája villant fel, és oda sem görgetett.
    /// Illesztés: 1) HaziFeladatUid-kapocs, 2) tárgy+nap, 3) tárgy.
    private func jumpToLesson(subject: String, deadline: Date, hwId: String? = nil) async {
        let cal = Calendar.current
        let target = deeplinkTarget(for: deadline)
        // Deeplink alatt nincs okos ugrás, és a tabra lépés se írja felül.
        suppressAutoJumpUntil = Date().addingTimeInterval(10)
        userHasNavigated = true
        if target.weekOffset != weekOffset {
            withAnimation(SummitMotion.page) { weekOffset = target.weekOffset }
            await load()
        } else if lessons.isEmpty {
            await load()
        }
        var match: LessonItem?
        if let hwId { match = lessons.first(where: { $0.haziFeladatUid == hwId }) }
        if match == nil {
            match = lessons.first(where: { SubjectMatcher.same($0.subject, subject) && cal.isDate($0.start, inSameDayAs: deadline) })
        }
        if match == nil { match = lessons.first(where: { SubjectMatcher.same($0.subject, subject) }) }
        // A napot a ténylegesen megtalált órához igazítjuk (ne a hétvégi
        // határidő napjához), különben üres napra állna.
        let day = match.map { cal.component(.weekday, from: $0.start) } ?? target.weekday
        withAnimation(SummitMotion.page) {
            selectedDay = day
            flashedLessonID = match?.id
            flashPulse = false
        }
        guard let m = match else { return }
        // A sorok kirajzolódnak, aztán odagörgetünk és villogtatunk.
        try? await Task.sleep(nanoseconds: 350_000_000)
        withAnimation(SummitMotion.page) {
            scrollProxy?.scrollTo(m.id, anchor: .center)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            withAnimation(.easeInOut(duration: 0.45).repeatCount(3, autoreverses: true)) { flashPulse = true }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.2) {
            withAnimation { flashedLessonID = nil; flashPulse = false }
        }
    }
    private var currentWeekRangeText: String {
        let cal = Calendar.current
        let monday = currentMonday
        let friday = cal.date(byAdding: .day, value: 4, to: monday)!
        let df: DateFormatter = { let f = DateFormatter(); f.locale = Locale(identifier: "hu_HU"); f.dateFormat = "MMM d."; return f }()
        return "\(df.string(from: monday)) – \(df.string(from: friday))"
    }
    private var weekTitle: String {
        if weekOffset == 0 { return "Ez a hét" }
        if weekOffset == -1 { return "Múlt hét" }
        if weekOffset == 1 { return "Jövő hét" }
        if weekOffset < 0 { return "\(abs(weekOffset)) héttel ezelőtt" }
        return "\(weekOffset) hét múlva"
    }
    private var previewDate: Date {
        let cal = Calendar.current
        let monday = currentMonday
        let dayOffset = max(0, min(4, selectedDay - 2)) // 0..4
        let dayBase = cal.date(byAdding: .day, value: dayOffset, to: monday)!
        return dayBase.addingTimeInterval(previewMinutes * 60)
    }
    private var overrideNow: Date? { isPreviewActive && devMode ? previewDate : nil }

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
            List {
                // MARK: Week pager — előre/hátra a hetekben
                Section {
                    HStack(spacing: 0) {
                        Button {
                            userHasNavigated = true
                            withAnimation(SummitMotion.page) { weekOffset -= 1 }
                            Task { await load() }
                        } label: {
                            Image(systemName: "chevron.left")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(.secondary)
                                .frame(width: 36, height: 32)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .disabled(weekOffset <= -8)

                        Spacer(minLength: 8)

                        VStack(spacing: 2) {
                            Text(weekTitle)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.primary)
                                .contentTransition(.numericText())
                            Text(currentWeekRangeText)
                                .font(.caption2.weight(.medium).monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                        .animation(SummitMotion.page, value: weekOffset)
                        .onTapGesture {
                            guard weekOffset != 0 else { return }
                            goToSmartToday()
                        }

                        Spacer(minLength: 8)

                        Button {
                            userHasNavigated = true
                            withAnimation(SummitMotion.page) { weekOffset += 1 }
                            Task { await load() }
                        } label: {
                            Image(systemName: "chevron.right")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(.secondary)
                                .frame(width: 36, height: 32)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .disabled(weekOffset >= 8)

                        // "Ma" gomb: nem csak hetet lapozva, hanem napot
                        // ellapozva is előjön (a nap-picker és a swipe is
                        // userHasNavigated-et állít; a gomb azt nullázza).
                        if weekOffset != 0 || userHasNavigated {
                            Button("Ma") { goToSmartToday() }
                            .font(.caption.weight(.semibold))
                            .tint(colors.accent)
                            .padding(.leading, 8)
                        }
                    }
                    .padding(.vertical, 2)
                    .listRowBackground(colors.surface)
                    .listRowInsets(EdgeInsets(top: 6, leading: 12, bottom: 6, trailing: 12))
                }

                // Frissítési hiba: ne haljon meg némán az órarend sem.
                if let err = loadError, !kreta.sessionExpired {
                    Section {
                        Label(err, systemImage: "wifi.exclamationmark")
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(.orange)
                            .fixedSize(horizontal: false, vertical: true)
                            .listRowBackground(Color.orange.opacity(scheme == .dark ? 0.12 : 0.08))
                            .listRowInsets(EdgeInsets(top: 10, leading: 16, bottom: 10, trailing: 16))
                            .listRowSeparator(.hidden)
                    }
                }

                // MARK: Day picker — ugyanaz az inset mint Notes/Home
                Section {
                    Picker("Nap", selection: $selectedDay) {
                        ForEach(2...6, id: \.self) { d in Text(days[d-2]).tag(d) }
                    }
                    .pickerStyle(.segmented)
                    .onChange(of: selectedDay) { _, _ in userHasNavigated = true }
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 6, trailing: 16))
                    .listRowSeparator(.hidden)
                    .animation(SummitMotion.page, value: selectedDay)
                }

                // Az idő-eltolás csúszka a Fejlesztői módban él — itt csak az
                // eltolt idő szerint rajzolunk, ha aktív (overrideNow).
                if isLoading {
                    Section {
                        ForEach(0..<5, id: \.self) { _ in
                            HStack(spacing: 14) {
                                Circle().fill(Color.primary.opacity(0.08)).frame(width: 38, height: 38)
                                VStack(alignment: .leading, spacing: 6) {
                                    RoundedRectangle(cornerRadius: 6).fill(Color.primary.opacity(0.08)).frame(height: 14).frame(maxWidth: 140)
                                    RoundedRectangle(cornerRadius: 6).fill(Color.primary.opacity(0.06)).frame(height: 10).frame(maxWidth: 90)
                                }
                                Spacer()
                            }
                            .padding(.vertical, 10)
                            .redacted(reason: .placeholder)
                            .listRowBackground(colors.surface)
                            .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
                        }
                    }
                } else if filtered.isEmpty {
                    // Óra nélküli napon is látszik a tannaptár (pl. tanítás
                    // nélküli munkanap programja) — az üres-állapot alatta marad.
                    if !dayEvents.isEmpty {
                        Section {
                            schoolEventCards
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                            .listRowInsets(EdgeInsets(top: 4, leading: 8, bottom: 4, trailing: 12))
                        }
                    }
                    Section {
                        ContentUnavailableView("Nincs óra", systemImage: "moon.zzz.fill", description: Text("Pihenőnap — nincs rögzített óra erre a napra."))
                            .frame(maxWidth: .infinity, minHeight: 220)
                            .padding(.vertical, 16)
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                            .listRowInsets(EdgeInsets(top: 24, leading: 16, bottom: 24, trailing: 16))
                    }
                } else {
                    // MARK: Day meta — editorial header (mint Grades "ÖSSZÁTLAG" stílus)
                    // Az óraszám és az idősáv a záró felmentett órák nélkül értendő
                    // (7 órából az utolsó felmentett → "6 óra", a 6. végéig).
                    Section {
                        HStack(alignment: .lastTextBaseline, spacing: 12) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(dayLabel(for: selectedDay).uppercased())
                                    .font(.caption2.weight(.bold))
                                    .foregroundStyle(.secondary)
                                    .tracking(1.1)
                                HStack(alignment: .firstTextBaseline, spacing: 6) {
                                    Text("\(effectiveFiltered.count)")
                                        .font(.system(size: 30, weight: .bold, design: .rounded))
                                        .monospacedDigit()
                                    Text(effectiveFiltered.count == 1 ? "óra" : "óra")
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundStyle(.secondary)
                                }
                            }
                            Spacer()
                            VStack(alignment: .trailing, spacing: 2) {
                                Text("IDŐSÁV")
                                    .font(.caption2.weight(.bold))
                                    .foregroundStyle(.secondary)
                                    .tracking(1.0)
                                if let first = effectiveFiltered.first, let last = effectiveFiltered.last {
                                    Text("\(first.start.formatted(date: .omitted, time: .shortened)) – \(last.end.formatted(date: .omitted, time: .shortened))")
                                        .font(.caption.weight(.semibold).monospacedDigit())
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                        .padding(.vertical, 2)
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                        .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 2, trailing: 16))
                    }

                    // MARK: Timeline — liquid glass körök + spine (egy list row)
                    // GlassEffectContainer nélkül: a konténer az üveg-passzt a számok
                    // fölé rántaná, a számok szellemként látszanának az üveg mögött.
                    // Az iskolai események 0. óraként, full-width kártyákon
                    // állnak a timeline fölött (számozott kör nélkül).
                    Section {
                        VStack(spacing: 0) {
                            if !dayEvents.isEmpty {
                                schoolEventCards
                                .padding(.bottom, 10)
                            }
                            timelineContent
                        }
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                        .listRowInsets(EdgeInsets(top: 4, leading: 8, bottom: 4, trailing: 12))
                    }
                    .id("\(weekOffset)-\(selectedDay)")
                    .transition(.asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity), removal: .move(edge: .leading).combined(with: .opacity)))
                }
            }
            .listStyle(.insetGrouped)
            .frame(maxWidth: isPad ? MacSupport.contentWidth(ipad: 1000, mac: 1150) : .infinity)
            .frame(maxWidth: .infinity)
            .scrollContentBackground(.hidden)
            .background(colors.background)
            .simultaneousGesture(
                DragGesture(minimumDistance: 24, coordinateSpace: .local)
                    .onEnded { value in
                        let dx = value.translation.width
                        let dy = value.translation.height
                        guard abs(dx) > abs(dy), abs(dx) > 52 else { return }
                        userHasNavigated = true
                        withAnimation(SummitMotion.page) {
                            if dx < 0 {
                                if let idx = dayTags.firstIndex(of: selectedDay), idx < dayTags.count - 1 {
                                    selectedDay = dayTags[idx + 1]
                                } else if weekOffset < 8 {
                                    // péntekről → következő hét hétfő
                                    weekOffset += 1; selectedDay = 2
                                    Task { await load() }
                                }
                            } else if dx > 0 {
                                if let idx = dayTags.firstIndex(of: selectedDay), idx > 0 {
                                    selectedDay = dayTags[idx - 1]
                                } else if weekOffset > -8 {
                                    // hétfőről → előző hét péntek
                                    weekOffset -= 1; selectedDay = 6
                                    Task { await load() }
                                }
                            }
                        }
                    }
            )
            .animation(SummitMotion.page, value: selectedDay)
            .animation(SummitMotion.page, value: weekOffset)
            .refreshable {
                // Lehúzáskor a hiányzások is frissen jönnek (a pótláshoz).
                cachedAbsences = nil
                await load()
            }
            // Máshol (Feladatok tab, másik eszköz sync-kel) felvett/törölt
            // saját tétel az órarenden is azonnal látszódjon.
            .onReceive(NotificationCenter.default.publisher(for: CustomTasksStore.changedNotification)) { _ in
                mergeCustomTasks()
            }
            // Dolgozat-pótlás kapcsoló/elvetés — a kijelzett dátumok újraszámolódnak.
            .onReceive(NotificationCenter.default.publisher(for: ExamRollover.changedNotification)) { _ in
                rolloverTick += 1
            }
            // Dev idő-csúszka: a widget is kövesse az eltolt időt —
            // ehhez elég újrapublikálni (hálózat nem kell hozzá).
            .onChange(of: previewMinutes) { _, _ in publishWidgetSnapshot() }
            .onChange(of: isPreviewActive) { _, _ in publishWidgetSnapshot() }
            .navigationTitle("Órarend")
            .navigationBarTitleDisplayMode(.large)
            .toolbarBackground(.visible, for: .navigationBar)
            .task {
                if UserDefaults.standard.object(forKey: "home.demoPreviewMinutes") == nil {
                    let c = Calendar.current
                    let h = c.component(.hour, from: Date())
                    let m = c.component(.minute, from: Date())
                    previewMinutes = Double(max(420, min(960, h*60+m)))
                }
                await load()
            }
            .onAppear {
                scrollProxy = proxy
                // Másik eszközről szinkronizált tannaptár is itt érkezik meg.
                schoolEvents = SchoolEventsStore.load()
                // Tabra lépéskor mindig a mai nap (első betöltés alatt a
                // load() intézi az okos ugrást — az enterTimetable olyankor
                // korán visszatér).
                enterTimetable()
            }
            // Live Activity sync EGYKEZES: csak a HomeView írja (ugyanaz az AppStorage kulcs!).
            // Két író (Home + Timetable eltérő nap locked lessons-szel) egymást ütötte:
            // csúszkánál az egyik indított, a másik endAll-ozott → villogó/blank Island.
            .onReceive(NotificationCenter.default.publisher(for: ExemptedStore.changedNotification)) { _ in exemptedTick += 1 }
            .onReceive(NotificationCenter.default.publisher(for: SchoolEventsStore.changedNotification)) { _ in schoolEvents = SchoolEventsStore.load() }
            .id(exemptedTick)
            .onReceive(NotificationCenter.default.publisher(for: switchToTimetable)) { notif in
                guard let info = notif.userInfo,
                      let subject = info["subject"] as? String,
                      let deadlineTS = info["deadline"] as? Double else { return }
                let deadline = Date(timeIntervalSince1970: deadlineTS)
                let hwId = info["hwId"] as? String
                Task { await jumpToLesson(subject: subject, deadline: deadline, hwId: hwId) }
            }
            }
        }
        .tint(colors.accent)
    }

    private func homework(for lesson: LessonItem) -> HomeworkItem? {
        // Szigorúan határidő-napra csatolunk — dátum nélküli fallback nélkül,
        // különben egy házi minden órára ráíródna (HomeworkMatcher)
        HomeworkMatcher.homework(for: lesson, in: homeworks)
    }
    /// Dolgozatok átütemezéssel: a hiányzás napján lévő dolgozat a
    /// következő olyan órán jelenik meg (piros háttérrel) — a csatolás a
    /// kijelzett dátumon történik, az eredeti napról eltűnik.
    private var displayExams: [ExamItem] {
        _ = rolloverTick
        return ExamRollover.displayItems(exams: exams, absences: cachedAbsences ?? [], lessons: lessons).items
    }
    private var rolledExamIDs: Set<String> {
        _ = rolloverTick
        return ExamRollover.displayItems(exams: exams, absences: cachedAbsences ?? [], lessons: lessons).rolledIDs
    }
    private func exam(for lesson: LessonItem) -> ExamItem? {
        // Óraszámos dolgozat csak a saját órájára kerül (ExamMatcher),
        // óraszám nélkül marad a nap-alapú csatolás.
        ExamMatcher.exam(for: lesson, in: displayExams)
    }
    private func hasAssignment(for lesson: LessonItem) -> Bool {
        let cal = Calendar.current
        let sameDayHW = homeworks.contains { SubjectMatcher.same($0.subject, lesson.subject) && cal.isDate($0.deadline, inSameDayAs: lesson.start) }
        // Óraszámos dolgozat csak a saját óráját színezi (ExamMatcher)
        let sameDayExam = exam(for: lesson) != nil
        if sameDayHW || sameDayExam { return true }
        // Kanonikus fallback: ha van bármilyen hw/ex ugyanarra a tárgyra, jelezzük
        let anyHW = homeworks.contains { SubjectMatcher.same($0.subject, lesson.subject) }
        let anyEx = displayExams.contains { SubjectMatcher.same($0.subject, lesson.subject) }
        // Csak akkor fehér, ha nincs elmarad/helyettesítés és van csatolt feladat
        if anyHW || anyEx {
            // Ne legyen túl agresszív: csak akkor, ha az adott napi leckék között tényleg kevés hw van
            // Itt visszafogjuk — sameDay prioritás, de ha van legalább 1 hw a tárgyra, mutassuk
            // mert demo-ban Matek/Angol különben nem látszana
            return false // konzervatív: csak sameDay számít fehér háttérnek
        }
        if homework(for: lesson) != nil { return true }
        return false
    }

    @ViewBuilder
    private var timelineContent: some View {
        Group {
            if let fixed = overrideNow {
                // Demo pörgetés — fixed időre számol, TimelineView nélkül
                ForEach(Array(filtered.enumerated()), id: \.element.id) { idx, lesson in
                    let cur = isCurrent(lesson, now: fixed)
                    let isLast = idx == filtered.count - 1
                    let isFlash = flashedLessonID == lesson.id
                    TimetableRow(
                        lesson: lesson,
                        isCurrent: cur,
                        isLast: isLast,
                        colors: colors,
                        scheme: scheme,
                        progress: cur ? progress(for: lesson, now: fixed) : 0,
                        effectiveNow: fixed,
                        hasAssignment: hasAssignment(for: lesson),
                        homework: homework(for: lesson),
                        exam: exam(for: lesson),
                        isFlashing: isFlash,
                        flashPulse: flashPulse,
                        examRolled: exam(for: lesson).map { rolledExamIDs.contains($0.id) } ?? false
                    )
                    .id(lesson.id)
                    .padding(.vertical, 5)
                    .transition(.asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity), removal: .move(edge: .leading).combined(with: .opacity)))
                }
            } else {
                // Élő — 15s-enként frissülő TimelineView, hogy a menő progress magától is mozogjon
                TimelineView(.periodic(from: .now, by: 15)) { context in
                    let now = context.date
                    ForEach(Array(filtered.enumerated()), id: \.element.id) { idx, lesson in
                        let cur = isCurrent(lesson, now: now)
                        let isLast = idx == filtered.count - 1
                        let isFlash = flashedLessonID == lesson.id
                        TimetableRow(
                            lesson: lesson,
                            isCurrent: cur,
                            isLast: isLast,
                            colors: colors,
                            scheme: scheme,
                            progress: cur ? progress(for: lesson, now: now) : 0,
                            effectiveNow: now,
                            hasAssignment: hasAssignment(for: lesson),
                            homework: homework(for: lesson),
                            exam: exam(for: lesson),
                            isFlashing: isFlash,
                            flashPulse: flashPulse,
                            examRolled: exam(for: lesson).map { rolledExamIDs.contains($0.id) } ?? false
                        )
                        .id(lesson.id)
                        .padding(.vertical, 5)
                        .transition(.asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity), removal: .move(edge: .leading).combined(with: .opacity)))
                    }
                }
            }
        }
    }

    /// 0. óra-sáv: full-width eseménykártyák (a számozott kör sávját
    /// is kitöltik — ott kezdődnek, ahol a kör, és ott végződnek, ahol
    /// az órakártya).
    @ViewBuilder
    private var schoolEventCards: some View {
        VStack(spacing: 8) {
            ForEach(dayEvents) { event in
                SchoolEventCard(event: event, colors: colors, scheme: scheme)
            }
        }
    }

    private func dayLabel(for tag: Int) -> String {
        guard let i = dayTags.firstIndex(of: tag) else { return "" }
        return days[i]
    }

    var filtered: [LessonItem] {
        guard !lessons.isEmpty else { return [] }
        // Nap-pontos szűrés (nem csak hétköznap): ha a lessons-ben két hét anyaga
        // vagy duplikált KRÉTA-sorok vannak, a hétfő nem duplázódhat 14-re.
        let cal = Calendar.current
        guard let dayDate = selectedDate else { return [] }
        return lessons.filter { cal.isDate($0.start, inSameDayAs: dayDate) }.sorted { $0.start < $1.start }
    }
    /// A nap érdemi órái: a záró felmentett órák nem számítanak bele az
    /// óraszámba és az idősávba sem (mint a Live Activity-ben) — a sorok
    /// persze továbbra is látszanak, zöld "Felmentett" jelöléssel.
    var effectiveFiltered: [LessonItem] { ExemptedStore.trimmingTrailingExempted(filtered) }
    /// A kiválasztott nap dátuma (az eseménykártyák nap-szűréséhez is).
    private var selectedDate: Date? {
        let cal = Calendar.current
        guard let dayIdx = dayTags.firstIndex(of: selectedDay) else { return nil }
        return cal.date(byAdding: .day, value: dayIdx, to: currentMonday)
    }
    /// Az adott nap iskolai eseményei — 0. óraként, full-width kártyákon.
    private var dayEvents: [SchoolEvent] {
        guard schoolEventsVisible, let d = selectedDate else { return [] }
        return SchoolEventsStore.events(on: d, from: schoolEvents)
    }
    /// KRÉTA néha ugyanazt az órát kétszer adja (pl. csoportbontás) — tárgy+időpont kulccsal irtjuk.
    private func deduped(_ items: [LessonItem]) -> [LessonItem] {
        var seen = Set<String>()
        return items.filter { seen.insert("\($0.subject)|\($0.start.timeIntervalSince1970)|\($0.end.timeIntervalSince1970)").inserted }
    }
    func isCurrent(_ l: LessonItem, now: Date) -> Bool { l.start<=now && l.end>=now }
    func progress(for l: LessonItem, now: Date) -> Double { let t=l.end.timeIntervalSince(l.start); return t>0 ? min(1,max(0,now.timeIntervalSince(l.start)/t)) : 0 }
    // legacy overloadok — ha nem adsz now-t, effectiveNow-t használja (preview vagy élő)
    func isCurrent(_ l: LessonItem) -> Bool { isCurrent(l, now: overrideNow ?? Date()) }
    func progress(for l: LessonItem) -> Double { progress(for: l, now: overrideNow ?? Date()) }

    func load() async {
        let entryOffset = weekOffset
        // Egy adatsáv: demo usert is a KretaClient szolgálja ki helyből
        // (a kért hétre csempézett órarenddel) — nincs külön demo-ág.
        // A házik/dolgozatok abszolút dátumosak, mint élesben: másik hétre
        // lapozva csak az órarend látszik (ahogy egy valós usernél is).
        guard let user = session.selectedUser else { isLoading = false; return }
        isLoading = true
        let iss = user.instituteCode.isEmpty ? (JWT.instituteCode(from: user.accessToken) ?? "") : user.instituteCode
        if iss.isEmpty || iss == "unknown" {
            lessons = []; homeworks = []; exams = []
            loadError = "Hiányzó intézményi kód — jelentkezz be újra."
            if entryOffset == 0, !userHasNavigated { applySmartDay() }
            isLoading = false
            return
        }
        // Totális fetch-hiba (lejárt token, offline) ellen: ha minden üresen
        // jön vissza, de volt adatunk ÉS még mindig ugyanazt a hetet nézzük,
        // a régit tartjuk meg — különben egy sikertelen refresh kiürítené a napot.
        let prevLessons = lessons, prevHW = homeworks, prevEx = exams
        let hadData = !(prevLessons.isEmpty && prevHW.isEmpty && prevEx.isEmpty)
        await fetchWeek()
        // Okos nap csak a 0. hétről indulva ÉS csak ha a user nem lapozott
        // kézzel: ha az utolsó mai óra lement / hétvége van, a következő
        // tanítási napra ugrunk — ha az másik hét, annak az adata is kell.
        if entryOffset == 0, !userHasNavigated, applySmartDay(), weekOffset != entryOffset {
            await fetchWeek()
        }
        // A hibaág a KRÉTA-adatokon dönt (a saját tételek helyből mindig
        // megvannak, azok nem takarhatják el a sikertelen lehúzást).
        let kretaEmpty = lessons.isEmpty
            && homeworks.allSatisfy { CustomTasksStore.isCustomId($0.id) }
            && exams.allSatisfy { CustomTasksStore.isCustomId($0.id) }
        if kretaEmpty {
            if hadData && weekOffset == entryOffset {
                lessons = prevLessons; homeworks = prevHW; exams = prevEx
                mergeCustomTasks()
                loadError = kreta.sessionExpired
                    ? "A KRÉTA-munkamenet lejárt — jelentkezz be újra."
                    : "Nem sikerült frissíteni — a legutóbbi adatokat mutatjuk."
            } else if !hadData {
                loadError = kreta.sessionExpired
                    ? "A KRÉTA-munkamenet lejárt — jelentkezz be újra."
                    : "Nem érkezett adat a KRÉTÁ-tól — ellenőrizd a kapcsolatot vagy jelentkezz be újra."
            } else {
                loadError = nil
            }
        } else {
            loadError = nil
        }
        publishWidgetSnapshot()
        isLoading = false
    }

    /// Widget-egykezesség: a heti snapshot csak innen íródik az App Groupba.
    /// A widget ebből rajzolja a mai / következő tanítási napot.
    /// (A mapping + reload a TimetableWidgetPublish-ban; a BG-ébresztés
    /// ugyanoda mergeli a mai napot.)
    private func publishWidgetSnapshot() {
        TimetableWidgetPublish.publishWeek(lessons)
        // Apple Watch: ugyanez a heti anyag megy az órára is.
        WatchSyncSender.pushTimetable(lessons)
    }

    /// Saját tételek bekeverése a KRÉTA-listákba (mindig a store-ból,
    /// duplázás nélkül) — így a Feladatok tabon felvett saját házi/dolgozat
    /// az órarend megfelelő óráján is megjelenik (tárgy + nap egyezéssel,
    /// dolgozatnál óraszám-tűzéssel).
    private func mergeCustomTasks() {
        let custom = CustomTasksStore.load()
        homeworks = homeworks.filter { !CustomTasksStore.isCustomId($0.id) }
            + CustomTasksStore.homeworkItems(from: custom)
        exams = exams.filter { !CustomTasksStore.isCustomId($0.id) }
            + CustomTasksStore.examItems(from: custom)
    }

    /// Az aktuális weekOffset hetének lehúzása (KRÉTA: hétfő–vasárnap).
    private func fetchWeek() async {
        guard let user = session.selectedUser else { return }
        let iss = user.instituteCode.isEmpty ? (JWT.instituteCode(from: user.accessToken) ?? "") : user.instituteCode
        guard !iss.isEmpty, iss != "unknown" else { lessons = []; homeworks = []; exams = []; return }
        let monday = currentMonday
        let start = monday
        let end = Calendar.current.date(byAdding: .day, value: 7, to: monday)! // vasárnap 00:00 = teljes hét
        async let tt = kreta.fetchTimetable(iss: iss, from: start, to: end)
        async let hw = kreta.fetchHomework(iss: iss)
        async let ex = kreta.fetchExams(iss: iss)
        let (ttR, hwR, exR) = await (tt, hw, ex)
        lessons = deduped(ttR)
        homeworks = hwR
        exams = exR
        // Hiányzások a dolgozat-pótláshoz: hetet lapozva nem húzzuk újra.
        if cachedAbsences == nil {
            cachedAbsences = await kreta.fetchAbsences(iss: iss)
        }
        mergeCustomTasks()
    }
}

// MARK: - 0. óra — full-width iskolai esemény (számozott kör nélkül)
private struct SchoolEventCard: View {
    let event: SchoolEvent
    let colors: AppColors
    let scheme: ColorScheme

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "calendar.badge.clock")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(colors.accent)
                .padding(.top, 3)
            VStack(alignment: .leading, spacing: 3) {
                Text("ISKOLAI ESEMÉNY")
                    .font(.caption2.weight(.bold))
                    .tracking(0.6)
                    .foregroundStyle(.secondary)
                Text(event.title)
                    .font(.system(size: 17, weight: .semibold, design: .rounded))
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)
                if !event.subtitle.isEmpty {
                    Text(event.subtitle)
                        .font(.caption.weight(.medium).monospacedDigit())
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
            Spacer(minLength: 8)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(colors.accent.opacity(scheme == .dark ? 0.14 : 0.08))
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .strokeBorder(colors.accent.opacity(scheme == .dark ? 0.30 : 0.22), lineWidth: 1)
                )
                .shadow(color: colors.shadow.opacity(scheme == .dark ? 0.20 : 0.06), radius: 8, y: 3)
        )
    }
}

// MARK: - Single editorial row — liquid glass óraszám színezi az állapotot (tick nélkül)
private struct TimetableRow: View {
    let lesson: LessonItem
    let isCurrent: Bool
    let isLast: Bool
    let colors: AppColors
    let scheme: ColorScheme
    let progress: Double
    var effectiveNow: Date = Date()
    var hasAssignment: Bool = false
    var homework: HomeworkItem? = nil
    var exam: ExamItem? = nil
    var isFlashing: Bool = false
    var flashPulse: Bool = false
    /// Hiányzás miatt átütemezett (pótló) dolgozat — piros a pill háttere.
    var examRolled: Bool = false

    private var isCancelled: Bool { lesson.isCancelled }
    private var isSubstituted: Bool { lesson.isSubstituted }
    private var isExempted: Bool { ExemptedStore.isExempted(lesson.subject) }
    private var isPast: Bool { lesson.end < effectiveNow && !isCurrent }

    // Prioritás: felmentett (zöld) > elmarad > helyettesítés > most (kék) > feladat/dolgozat (fehér) > múlt/jövő = neutrális
    private var ringTint: Color? {
        if isExempted { return Color.green }
        if isCancelled { return Color.red }
        if isSubstituted { return Color.orange }
        if isCurrent { return Color.blue }
        if hasAssignment { return Color.white }
        return nil
    }
    private var isTintedGlass: Bool { ringTint != nil }
    private var rowBackground: Color {
        if isExempted { return Color.green.opacity(scheme == .dark ? 0.16 : 0.10) }
        if isCancelled { return Color.red.opacity(scheme == .dark ? 0.16 : 0.10) }
        if isSubstituted { return Color.orange.opacity(scheme == .dark ? 0.16 : 0.10) }
        if isCurrent { return Color.blue.opacity(scheme == .dark ? 0.16 : 0.10) }
        // Light módban a fehér sor beleolvadt a kártyába — ott inverz szürke
        if hasAssignment { return scheme == .dark ? Color.white.opacity(0.22) : Color.black.opacity(0.07) }
        return colors.surface
    }
    private var numberColor: Color {
        if isExempted { return Color.green }
        if isCancelled { return Color.red }
        if isSubstituted { return Color.orange }
        if isCurrent { return Color.blue }
        if hasAssignment { return scheme == .dark ? Color.white : Color.black }
        return scheme == .dark ? Color.white : Color.black
    }
    private var badgeLabel: String? {
        if isExempted { return "Felmentett" }
        return lesson.substitutionLabel
    }
    private var badgeColor: Color {
        if isExempted { return Color.green }
        if isCancelled { return Color.red }
        return Color.orange
    }

    var body: some View {
        HStack(alignment: .top, spacing: 6) {
            // LEFT — liquid glass number + spine. Az üveg a szám HÁTTERE (mint a
            // gyári glass-gomboknál): testvér-ZStackben az üveg-passz a számot takarná.
            VStack(spacing: 0) {
                Text(lesson.index)
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(numberColor)
                    .contentTransition(.numericText())
                    .allowsHitTesting(false)
                    .frame(width: 38, height: 38)
                    .background {
                        Group {
                            if #available(iOS 26.0, *) {
                                Circle()
                                    .fill(Color.clear)
                                    .glassEffect(
                                        isTintedGlass
                                            ? .regular.tint((ringTint ?? colors.accent).opacity(scheme == .dark ? (hasAssignment ? 0.22 : isCurrent ? 0.18 : 0.12) : (hasAssignment ? 0.18 : isCurrent ? 0.14 : 0.09))).interactive()
                                            : .regular.tint(Color.white.opacity(scheme == .dark ? 0.06 : 0.04)).interactive(),
                                        in: .circle
                                    )
                            } else {
                                Circle()
                                    .fill(isTintedGlass ? (ringTint ?? colors.accent).opacity(scheme == .dark ? 0.10 : 0.08) : Color.primary.opacity(scheme == .dark ? 0.08 : 0.07))
                                    .overlay(Circle().fill(.ultraThinMaterial).opacity(isTintedGlass ? 0.35 : 0.82))
                            }
                        }
                    }
                    .shadow(color: (ringTint ?? Color.clear).opacity(isTintedGlass ? (scheme == .dark ? 0.14 : 0.08) : 0), radius: 6, y: 2)

                // Spine — vékony editorial vonal a következő körig
                if !isLast {
                    Rectangle()
                        .fill(Color.primary.opacity(scheme == .dark ? 0.09 : 0.07))
                        .frame(width: 1.2)
                        .frame(height: 22)
                        .padding(.top, 6)
                        .padding(.bottom, 2)
                }
            }
            .frame(width: 38)
            .padding(.top, 2)

            // CENTER CARD — editorial content
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .top, spacing: 10) {
                    VStack(alignment: .leading, spacing: 4) {
                        // Badge row — felmentett is zöld, elmarad piros, helyettesítés narancs
                        if let lbl = badgeLabel {
                            Text(lbl.uppercased())
                                .font(.caption2.weight(.bold))
                                .tracking(0.5)
                                .foregroundStyle(.white)
                                .padding(.horizontal, 7).padding(.vertical, 3.5)
                                .background(Capsule().fill(badgeColor))
                        }

                        Text(lesson.subject)
                            .font(.system(size: 17, weight: .semibold, design: .rounded))
                            .foregroundStyle((isCancelled || isExempted) ? .secondary : .primary)
                            .strikethrough(isCancelled || isExempted, color: .secondary)
                            .lineLimit(1)

                        HStack(spacing: 6) {
                            // Room — kis kocka, ikon nélkül, csak a terem neve
                            Text(lesson.room)
                                .font(.caption2.weight(.bold).monospacedDigit())
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 7).padding(.vertical, 4)
                                .background(
                                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                                        .fill(Color.primary.opacity(scheme == .dark ? 0.08 : 0.06))
                                        .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).strokeBorder(Color.primary.opacity(0.06), lineWidth: 1))
                                )
                                .lineLimit(1)

                            Text("•").font(.caption2).foregroundStyle(.tertiary)
                            Text(lesson.teacher)
                                .font(.caption.weight(.medium))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }

                        // Feladat pill — óra neve alatt, tap → Feladatok tab
                        if let hw = homework {
                            Button {
                                NotificationCenter.default.post(name: Notification.Name("summit.switchToTasks"), object: nil, userInfo: ["flash": hw.id])
                            } label: {
                                HStack(spacing: 4) {
                                    Image(systemName: "checklist")
                                        .font(.caption2.weight(.semibold))
                                    Text(hw.plainTitle.isEmpty ? "Házi feladat" : hw.plainTitle)
                                        .font(.caption.weight(.medium))
                                        .lineLimit(1)
                                }
                                .foregroundStyle(scheme == .dark ? Color.white.opacity(0.92) : Color.black.opacity(0.72))
                                .padding(.horizontal, 8).padding(.vertical, 5)
                                .background(
                                    Capsule()
                                        .fill(scheme == .dark ? Color.white.opacity(0.14) : Color.black.opacity(0.06))
                                        .overlay(Capsule().strokeBorder(Color.primary.opacity(scheme == .dark ? 0.12 : 0.08), lineWidth: 1))
                                )
                            }
                            .buttonStyle(.plain)
                            .padding(.top, 2)
                        }
                        // Dolgozat pill — tap → Feladatok/Dolgozatok tab
                        if let ex = exam {
                            Button {
                                NotificationCenter.default.post(name: Notification.Name("summit.switchToTasks"), object: nil, userInfo: ["segment": "exams", "flash": ex.id])
                            } label: {
                                HStack(spacing: 4) {
                                    Image(systemName: "doc.text.fill")
                                        .font(.caption2.weight(.semibold))
                                    Text(ex.plainDescription.isEmpty ? ex.mode : "\(ex.mode): \(ex.plainDescription)")
                                        .font(.caption.weight(.medium))
                                        .lineLimit(1)
                                }
                                .foregroundStyle(scheme == .dark ? Color.white.opacity(0.92) : Color.black.opacity(0.72))
                                .padding(.horizontal, 8).padding(.vertical, 5)
                                .background(
                                    Capsule()
                                        .fill((examRolled ? Color.red : Color.orange).opacity(scheme == .dark ? 0.22 : 0.14))
                                        .overlay(Capsule().strokeBorder((examRolled ? Color.red : Color.orange).opacity(scheme == .dark ? 0.35 : 0.25), lineWidth: 1))
                                )
                            }
                            .buttonStyle(.plain)
                            .padding(.top, 2)
                        }
                    }
                    Spacer(minLength: 8)
                    // Time — editorial stacked
                    VStack(alignment: .trailing, spacing: 1) {
                        Text(lesson.start.formatted(date: .omitted, time: .shortened))
                            .font(.system(size: 13, weight: .semibold, design: .rounded).monospacedDigit())
                            .foregroundStyle(isCurrent ? Color.blue : .primary)
                        Text(lesson.end.formatted(date: .omitted, time: .shortened))
                            .font(.caption2.weight(.medium).monospacedDigit())
                            .foregroundStyle(.tertiary)
                    }
                }

                // Current progress — követi a kiemelőszínt (accent)
                if isCurrent {
                    TimetableLiquidProgress(
                        progress: progress,
                        tint: isCancelled ? Color.red : isSubstituted ? Color.orange : colors.accent,
                        remainingText: remainingText,
                        scheme: scheme,
                        colors: colors
                    )
                    .padding(.top, 10)
                }
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(rowBackground)
                    .overlay(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .strokeBorder(Color.primary.opacity(scheme == .dark ? 0.08 : 0.06), lineWidth: 1)
                    )
                    .shadow(color: colors.shadow.opacity(isCurrent ? 0.18 : scheme == .dark ? 0.20 : 0.06), radius: isCurrent ? 12 : 8, y: isCurrent ? 5 : 3)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(colors.accent.opacity(isFlashing ? (flashPulse ? 0.95 : 0.22) : 0), lineWidth: isFlashing ? 2.2 : 0)
            )
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(colors.accent.opacity(isFlashing ? (flashPulse ? 0.18 : 0.04) : 0))
            )
            .scaleEffect(isFlashing && flashPulse ? 1.02 : 1.0)
            .animation(isFlashing ? .easeInOut(duration: 0.45) : .default, value: flashPulse)
            // bal csík nincs — kompakt
            .padding(.leading, 0)
        }
        .padding(.horizontal, 0)
        .contentShape(Rectangle())
    }

    private var remainingText: String {
        let rem = Int(ceil(lesson.end.timeIntervalSince(effectiveNow)/60))
        if rem <= 0 { return "Vége" }
        return "\(rem) perc van hátra"
    }
}

// MARK: - Folyamatjelző — a 15 mp-es Timeline-lépések közti ugrást
// lineárisan simítja, így az aktuális óra csíkja folyamatosan kúszik.
private struct TimetableLiquidProgress: View {
    let progress: Double
    let tint: Color
    let remainingText: String
    let scheme: ColorScheme
    let colors: AppColors
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ProgressView(value: progress).tint(tint)
                .animation(SummitMotion.progress, value: progress)
            Text(remainingText).font(.caption2.weight(.medium)).foregroundStyle(.secondary).monospacedDigit()
                .contentTransition(.numericText())
        }
    }
}

// glassEffectID morph — előkészítve későbbi finom animhoz (jelenleg transition elég)
