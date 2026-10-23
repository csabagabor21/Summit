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
    /// Naptári napok (tanév rendje) az üres napok hivatalos feliratához.
    /// Dátum-kulcsolt, hetek közt megmarad — a régi bejegyzés csak a saját
    /// napjára illeszkedik, ezért egy sikertelen lehúzás sem kever be idegent.
    @State private var calendarDays: [SchoolDayInfo] = []
    // Kézi navigálás (hét/nap lapozás) után az okos ugrás nem dobhat vissza —
    // csak a "Ma" gomb és az első betöltés ugorhat a következő tanítási napra.
    @State private var userHasNavigated = false
    @State private var isLoading = true
    @State private var loadError: String? = nil
    @State private var flashedLessonID: String?
    /// Koppintott óra fullscreen részletezője (tanár, időpont, ikon,
    /// házi + dolgozat) — nil = zárva.
    @State private var selectedLesson: LessonItem?
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
    /// A hét-sáv kijelölő-korongja (glassEffectID / MC-ben matchedGeometryEffect) és a mérete
    /// (a Dynamic Type-pal együtt nő, hogy a szám sosem lóg ki a körből).
    @Namespace private var weekDiscNS
    @ScaledMetric(relativeTo: .title3) private var discSize: CGFloat = 36
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
        // Csak user-koppintásból hívódik ("Ma" gomb, hétnév-tap).
        SummitHaptics.selection()
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
    /// Handoff-helyreállítás: a küldő eszköz hetére/napjára áll,
    /// az okos ugrás nem szól bele; ha óraid is jött, a hét adatainak
    /// megérkezte után odagörget és villant (mint a jumpToLesson).
    private func applyHandoffPosition(week: Int, weekday: Int, lessonID: String?) {
        suppressAutoJumpUntil = Date().addingTimeInterval(10)
        userHasNavigated = true
        withAnimation(SummitMotion.page) {
            weekOffset = week
            selectedDay = weekday
        }
        guard let id = lessonID else { return }
        Task {
            for _ in 0..<40 {
                if lessons.contains(where: { $0.id == id }) { break }
                try? await Task.sleep(nanoseconds: 250_000_000)
            }
            guard lessons.contains(where: { $0.id == id }) else { return }
            withAnimation(SummitMotion.page) {
                flashedLessonID = id
                flashPulse = false
                scrollProxy?.scrollTo(id, anchor: .center)
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                withAnimation(.easeInOut(duration: 0.45).repeatCount(3, autoreverses: true)) { flashPulse = true }
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.2) {
                withAnimation { flashedLessonID = nil; flashPulse = false }
            }
        }
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
                            .summitRowSurface(colors: colors)
                            .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
                        }
                    }
                } else if filtered.isEmpty {
                    // Üres napon is ugyanaz a fejléc-cím, mint a teli napon
                    // (csak az óraszám-sor nélkül).
                    Section {
                        dayHeader(showsSummary: false)
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                        .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 2, trailing: 16))
                    }
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
                        ContentUnavailableView(emptyDayTitle, systemImage: emptyDayIcon, description: Text(emptyDayDetail))
                            .frame(maxWidth: .infinity, minHeight: 220)
                            .padding(.vertical, 16)
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                            .listRowInsets(EdgeInsets(top: 24, leading: 16, bottom: 24, trailing: 16))
                    }
                } else {
                    // MARK: Nap-fejléc — "Péntek, október 23." + "6 óra · 8:00 – 13:35"
                    // Az óraszám és az idősáv a záró felmentett órák nélkül értendő
                    // (7 órából az utolsó felmentett → "6 óra", a 6. végéig).
                    Section {
                        dayHeader(showsSummary: true)
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
                        // Napváltó swipe CSAK a napi tartalmon (nem a teljes
                        // listán): a lista-szintű gesztus a függőleges
                        // görgetéssel versenyzett, ez rángatta az órarendet.
                        .simultaneousGesture(daySwipeGesture)
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                        .listRowInsets(EdgeInsets(top: 4, leading: 8, bottom: 4, trailing: 12))
                    }
                    // Nap/hét-azonosító: a tartalom napváltáskor elölről
                    // kezdődik. Transition NINCS rajta — a beúszó animáció a
                    // görgetési pozícióval harcolt (rángatás húzogatáskor).
                    .id("\(weekOffset)-\(selectedDay)")
                }
            }
            .listStyle(.insetGrouped)
            .listSectionSpacing(.compact)
            // A hét-sáv lebegő üvegvezérlő a lista FÖLÖTT (safeAreaBar: az
            // órakártyák alatta görögnek el, a scroll-edge effekt a sávhoz
            // igazodik, nyugalmi helyzetben az első óra nem csúszik alá).
            .safeAreaBar(edge: .top, spacing: 0) { weekBar }
            .scrollEdgeEffectStyle(.soft, for: .top)
            .onChange(of: selectedDay) { _, _ in userHasNavigated = true }
            .frame(maxWidth: isPad ? MacSupport.contentWidth(ipad: 1000, mac: 1150) : .infinity)
            .padding(.horizontal, MacSupport.sidePadding)
            .frame(maxWidth: .infinity)
            .summitListChrome(colors: colors)
            // Lista-szintű .animation (selectedDay/weekOffset) és gesztus
            // NINCS: az egész lista minden napváltáskor és Timeline-ticknél
            // újraanimált — ez dobálta a görgetési pozíciót húzogatáskor.
            // A napváltás a hét-sáv koppintásánál és a daySwipeGesture
            // végpontjain animál (withAnimation), a lista tartalma meg
            // transition nélkül, azonnal cserélődik.
            .refreshable {
                // Lehúzáskor a hiányzások is frissen jönnek (a pótláshoz).
                cachedAbsences = nil
                await load(force: true)
                // Kézi frissítés vége: semleges "megvan"-koppanás.
                SummitHaptics.light()
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
            .summitToolbarBackground()
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
                if let p = HandoffCenter.shared.takeTimetable() {
                    // Másik eszközről folytatás: a küldő hét/nap/óra
                    // áll helyre az okos ugrás helyett.
                    applyHandoffPosition(week: p.week, weekday: p.day, lessonID: p.lesson)
                } else {
                    // Tabra lépéskor mindig a mai nap (első betöltés alatt a
                    // load() intézi az okos ugrást — az enterTimetable olyankor
                    // korán visszatér).
                    enterTimetable()
                }
                HandoffCenter.shared.setTimetablePosition(weekOffset: weekOffset, weekday: selectedDay)
            }
            // Hét/nap-lapozás + részletező-nyitás hirdetése Continuityhez.
            .onChange(of: weekOffset) { _, w in
                HandoffCenter.shared.setTimetablePosition(weekOffset: w, weekday: selectedDay, lessonID: selectedLesson?.id)
            }
            .onChange(of: selectedDay) { _, d in
                HandoffCenter.shared.setTimetablePosition(weekOffset: weekOffset, weekday: d, lessonID: selectedLesson?.id)
            }
            .onChange(of: selectedLesson) { _, l in
                HandoffCenter.shared.setTimetablePosition(weekOffset: weekOffset, weekday: selectedDay, lessonID: l?.id)
            }
            // Óra-részletező: a koppintott óra fullscreen nézete (tanár,
            // időpont, ikon, házi + dolgozat).
            .fullScreenCover(item: $selectedLesson) { lesson in
                LessonDetailSheet(
                    lesson: lesson,
                    homework: homework(for: lesson),
                    exam: exam(for: lesson),
                    examRolled: exam(for: lesson).map { rolledExamIDs.contains($0.id) } ?? false,
                    colors: colors,
                    scheme: scheme
                )
            }
            // Live Activity sync EGYKEZES: csak a HomeView írja (ugyanaz az AppStorage kulcs!).
            // Két író (Home + Timetable eltérő nap locked lessons-szel) egymást ütötte:
            // csúszkánál az egyik indított, a másik endAll-ozott → villogó/blank Island.
            // Felmentés-váltás: az exemptedTick puszta változása újrarajzol
            // (a sorok az ExemptedStore-ból olvasnak) — .id() NINCS rajta,
            // mert az az egész listát újraépítené és elveszne a görgetés.
            .onReceive(NotificationCenter.default.publisher(for: ExemptedStore.changedNotification)) { _ in exemptedTick += 1 }
            .onReceive(NotificationCenter.default.publisher(for: SchoolEventsStore.changedNotification)) { _ in
                schoolEvents = SchoolEventsStore.load()
                WatchSyncSender.pushSchoolEvents(events: schoolEvents, visible: schoolEventsVisible)
                // A "Mai nap" widget és a jegyzetkártya eseményfüggő —
                // import/kapcsoló után újrapublikálunk (hálózat nélkül).
                publishWidgetSnapshot()
                // A vakáció-számláló az eseménynaptár szünet-napjaiból is
                // dolgozik — import/sync után újraszámolunk, hogy a frissen
                // megjött őszi/téli szünet azonnal látszódjon (a KRÉTA-lekérés
                // gyorstárazott, ez nem plusz hálózat a gyakorlatban).
                if weekOffset == 0, let user = session.selectedUser {
                    let iss = user.instituteCode.isEmpty ? (JWT.instituteCode(from: user.accessToken) ?? "") : user.instituteCode
                    if !iss.isEmpty, iss != "unknown" { refreshVacation(iss: iss) }
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: switchToTimetable)) { notif in
                guard let info = notif.userInfo,
                      let subject = info["subject"] as? String,
                      let deadlineTS = info["deadline"] as? Double else { return }
                let deadline = Date(timeIntervalSince1970: deadlineTS)
                let hwId = info["hwId"] as? String
                Task { await jumpToLesson(subject: subject, deadline: deadline, hwId: hwId) }
            }
            // Continuity-folytatás (élő nézet): a küldő hét/nap/órája.
            // A pendinget is ürítjük — a direkt kézbesítés nyert.
            .onReceive(NotificationCenter.default.publisher(for: SummitHandoff.restoreTimetable)) { notif in
                HandoffCenter.shared.pendingTimetable = nil
                let week = notif.userInfo?["week"] as? Int ?? 0
                let day = notif.userInfo?["day"] as? Int ?? 2
                let lesson = notif.userInfo?["lesson"] as? String
                applyHandoffPosition(week: week, weekday: day, lessonID: lesson)
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
        // óraszám nélkül naponta csak EGY órára (az aznapi legkorábbira).
        ExamMatcher.exam(for: lesson, in: displayExams, allLessons: lessons)
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
                        examRolled: exam(for: lesson).map { rolledExamIDs.contains($0.id) } ?? false,
                        onSelect: { selectedLesson = lesson }
                    )
                    .id(lesson.id)
                    .padding(.vertical, 5)
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
                            examRolled: exam(for: lesson).map { rolledExamIDs.contains($0.id) } ?? false,
                            onSelect: { selectedLesson = lesson }
                        )
                        .id(lesson.id)
                        .padding(.vertical, 5)
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

    /// A hét-sáv dátumai: az aktuális hét hétfőjéhez igazítva
    /// (hétlapozáskor a dátumok is vele mennek).
    private func dayDate(for tag: Int) -> Date? {
        let cal = Calendar.current
        guard let dayIdx = dayTags.firstIndex(of: tag) else { return nil }
        return cal.date(byAdding: .day, value: dayIdx, to: currentMonday)
    }

    // MARK: Dátum-formázók (statikus, hu_HU — a rendszer adja a neveket)
    private static let huLocale = Locale(identifier: "hu_HU")
    /// "H", "K", "Sze", "Cs", "P" — a rendszer hu_HU rövid hétköznap-nevei
    /// (index: Calendar-weekday - 1, vasárnap = 0).
    private static let weekdayShortSymbols: [String] = {
        var c = Calendar(identifier: .gregorian)
        c.locale = huLocale
        return c.shortStandaloneWeekdaySymbols
    }()
    private static func formatter(_ format: String) -> DateFormatter {
        let f = DateFormatter()
        f.locale = huLocale
        f.dateFormat = format
        return f
    }
    private static let monthFormatter = formatter("LLLL")
    /// "péntek, október 23." — az aktuális évben az évszám nem kell.
    private static let dayTitleFormatter = formatter("EEEE, MMMM d.")
    private static let dayTitleYearFormatter = formatter("EEEE, yyyy. MMMM d.")

    /// Nagy kezdőbetű (a hu_HU nevek kisbetűsek: "október" → "Október").
    private static func capitalized(_ s: String) -> String {
        guard let first = s.first else { return s }
        return first.uppercased() + s.dropFirst()
    }

    private func isCurrentYear(_ date: Date) -> Bool {
        let cal = Calendar.current
        return cal.component(.year, from: date) == cal.component(.year, from: Date())
    }

    /// Hét-cím fő sora: a hét hónapja ("Október"), hónaphatáron
    /// "Október – November"; évszám csak ha nem az idei ("Január 2027").
    private var weekMonthTitle: String {
        let cal = Calendar.current
        let monday = currentMonday
        let friday = cal.date(byAdding: .day, value: 4, to: monday) ?? monday
        let m1 = Self.capitalized(Self.monthFormatter.string(from: monday))
        let m2 = Self.capitalized(Self.monthFormatter.string(from: friday))
        let months = m1 == m2 ? m1 : "\(m1) – \(m2)"
        if isCurrentYear(monday) && isCurrentYear(friday) { return months }
        return "\(months) \(cal.component(.year, from: friday))"
    }

    /// "Péntek, október 23." (évszámmal, ha nem az idei év).
    private func dayTitle(for tag: Int) -> String {
        guard let d = dayDate(for: tag) else { return "" }
        let f = isCurrentYear(d) ? Self.dayTitleFormatter : Self.dayTitleYearFormatter
        return Self.capitalized(f.string(from: d))
    }

    /// Dolgozatos napok (nap eleje → igaz, ha MINDEN aznapi dolgozat átütemezett: piros pötty) — UGYANABBÓL a forrásból,
    /// mint amit a nap idővonala mutat: a pótlással számolt `displayExams`
    /// és az ExamMatcher óra-csatolása. Így a pötty és a sorok sosem
    /// mondanak ellent egymásnak.
    private var examDays: [Date: Bool] {
        _ = rolloverTick
        guard !exams.isEmpty, !lessons.isEmpty else { return [:] }
        let cal = Calendar.current
        let resolved = ExamRollover.displayItems(exams: exams, absences: cachedAbsences ?? [], lessons: lessons)
        var out: [Date: Bool] = [:]
        for lesson in lessons {
            guard let e = ExamMatcher.exam(for: lesson, in: resolved.items, allLessons: lessons) else { continue }
            let day = cal.startOfDay(for: lesson.start)
            out[day] = (out[day] ?? true) && resolved.rolledIDs.contains(e.id)
        }
        return out
    }

    /// Hétlapozás (chevron és a sáv swipe-ja közös útja): ugyanaz a nap
    /// marad kiválasztva, a hét adata újratöltődik.
    private func pageWeek(_ delta: Int) {
        let target = weekOffset + delta
        guard (-8...8).contains(target) else { return }
        userHasNavigated = true
        SummitHaptics.selection()
        withAnimation(SummitMotion.page) { weekOffset = target }
        Task { await load() }
    }

    // MARK: Hét-sáv — lebegő Liquid Glass kártya a lista fölött
    /// Az üveg a lista fölötti UI-réteg (a tartalom alatta görög el). Három
    /// réteg, alulról: (1) a kártya üvege `.background`-ban (nem a tartalom
    /// szülő-glass modifierje — a külső margó az üvegen KÍVÜL van),
    /// (2) a kijelölő korong üvege a sáv mögött (`weekDiscLayer`), (3) a
    /// szövegek. A szöveg SOHA nem kerül GlassEffectContainerbe: a konténer
    /// a tartalmat is az üveg-passzba rántaná, és elmosná. Minecraft
    /// skinben nincs üveg: blokk-kártya és tömör korong.
    private var weekBar: some View {
        Group {
            if MinecraftTheme.isActive {
                weekCard
                    .padding(.horizontal, 8)
                    .padding(.vertical, 8)
                    // Háttérként: a blokk-kártya kemény árnyéka ne a szövegekre kerüljön.
                    .background { Color.clear.minecraftCard(cornerRadius: 6) }
            } else {
                weekCard
                    .padding(.horizontal, 8)
                    .padding(.vertical, 8)
                    .background {
                        Color.clear.glassEffect(.regular, in: .rect(cornerRadius: Self.weekBarRadius))
                    }
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 4)
        .padding(.bottom, 8)
    }
    /// A kártya sarka: a kijelző sarkához igazodó (~concentric a 16 pt-os
    /// behúzással), nem kapszula — a kártya magas.
    private static let weekBarRadius: CGFloat = 30

    /// A kijelölő üveg-korong rétege: a sáv oszlopait tükrözi (ugyanaz a
    /// függőleges ritmus), csak a kijelölt napnál van benne egy
    /// accent-tintes üveg-kör. Egyetlen GlassEffectContainer + azonos
    /// glassEffectID: koppintásra a korong a napok közt morfol. Csak üveg
    /// van benne (a szövegek fölötte, külön rétegben ülnek).
    private var weekDiscLayer: some View {
        GlassEffectContainer(spacing: 4) {
            HStack(spacing: 0) {
                ForEach(dayTags, id: \.self) { tag in
                    VStack(spacing: 3) {
                        // Láthatatlan hétköznap-betű: ugyanaz a magasság, mint a valódi oszlopban.
                        Text("X").font(.caption2.weight(.semibold)).hidden()
                        ZStack {
                            if tag == selectedDay {
                                Color.clear
                                    .glassEffect(.regular.tint(colors.accent).interactive(), in: .circle)
                                    .glassEffectID("weekDisc", in: weekDiscNS)
                            }
                        }
                        .frame(width: discSize, height: discSize)
                        Color.clear.frame(width: 5, height: 5)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
        }
        .allowsHitTesting(false)
    }

    // MARK: Hét-kártya — hónap-cím + lapozó + a 5 nap (Apple Naptár hét-sávja)
    private var weekCard: some View {
        VStack(spacing: 6) {
            ZStack {
                VStack(spacing: 2) {
                    Text(weekMonthTitle)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1).minimumScaleFactor(0.8)
                    Text(weekTitle)
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.secondary)
                }
                // A cím mindig középen áll (a "Ma" gomb meg-megjelenése
                // nem tolja el), a gombok sávját szabadon hagyja.
                .padding(.horizontal, 88)
                .contentTransition(.numericText())
                .animation(SummitMotion.page, value: weekOffset)
                .onTapGesture {
                    guard weekOffset != 0 else { return }
                    goToSmartToday()
                }

                HStack(spacing: 0) {
                    Button { pageWeek(-1) } label: {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(.primary)
                            .frame(width: 40, height: 36)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .disabled(weekOffset <= -8)
                    .accessibilityLabel("Előző hét")

                    Spacer(minLength: 0)

                    // "Ma" gomb: nem csak hetet lapozva, hanem napot
                    // ellapozva is előjön (a nap-sáv és a swipe is
                    // userHasNavigated-et állít; a gomb azt nullázza).
                    if weekOffset != 0 || userHasNavigated {
                        Button("Ma") { goToSmartToday() }
                        .font(.subheadline.weight(.semibold))
                        .tint(colors.accent)
                        .padding(.trailing, 4)
                    }

                    Button { pageWeek(1) } label: {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(.primary)
                            .frame(width: 40, height: 36)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .disabled(weekOffset >= 8)
                    .accessibilityLabel("Következő hét")
                }
            }
            // A cím-sor nem nő a végtelenségig (a chevronok fix méretűek);
            // a nap-sáv saját, tágabb plafont kap (lásd weekStrip).
            .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
            weekStrip
        }
    }

    /// 5 egyenlő oszlop (H–P): hétköznap-betű, nap-szám körben, dolgozat-pötty.
    /// A koppintás az egyetlen hely, ahol a napváltás animál (a lista-szintű
    /// .animation helyett — az rángatta a görgetést); a kijelölő-korong
    /// matchedGeometryEffect-tel csúszik a napok közt.
    private var weekStrip: some View {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let lessonDays = Set(lessons.map { cal.startOfDay(for: $0.start) })
        let examMap = examDays
        // Tanítás nélküli nap halvány — de csak betöltés után, és csak ha a
        // hétnek egyáltalán van órája (különben minden nap "üres" lenne).
        let dimEmpty = !isLoading && !lessons.isEmpty
        return HStack(spacing: 0) {
            ForEach(dayTags, id: \.self) { tag in
                if let date = dayDate(for: tag) {
                    let day = cal.startOfDay(for: date)
                    weekStripDay(
                        tag: tag, date: date,
                        isToday: day == today,
                        isEmpty: dimEmpty && !lessonDays.contains(day),
                        examRolled: examMap[day]
                    )
                }
            }
        }
        // Az üveg-korong a szövegek ALATT (lásd weekBar).
        .background { if !MinecraftTheme.isActive { weekDiscLayer } }
        .dynamicTypeSize(...DynamicTypeSize.accessibility1)
        .contentShape(Rectangle())
        // Swipe a sávon: hetet lapoz (a napi tartalom swipe-ja napot).
        .simultaneousGesture(weekSwipeGesture)
    }

    private func weekStripDay(tag: Int, date: Date, isToday: Bool, isEmpty: Bool, examRolled: Bool?) -> some View {
        let isSel = tag == selectedDay
        let weekday = Calendar.current.component(.weekday, from: date)
        // Üveg-korong (accent tint) → a kijelölt szám mindig fehér; ma = accent
        // szám, tanítás nélküli nap = halvány szám. Minecraftban tömör korong
        // (ma = accent, egyébként fekete/fehér).
        let mc = MinecraftTheme.isActive
        let number: AnyShapeStyle = isSel
            ? AnyShapeStyle(mc && !isToday ? Color(.systemBackground) : Color.white)
            : isToday ? AnyShapeStyle(colors.accent)
            : isEmpty ? AnyShapeStyle(.tertiary)
            : AnyShapeStyle(.primary)
        var label = dayTitle(for: tag)
        if isToday { label += ", ma" }
        if examRolled != nil { label += ", dolgozat" }
        return Button {
            guard tag != selectedDay else { return }
            SummitHaptics.selection()
            withAnimation(SummitMotion.page) { selectedDay = tag }
        } label: {
            VStack(spacing: 3) {
                Text(Self.weekdayShortSymbols[weekday - 1])
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                ZStack {
                    if isSel {
                        if mc {
                            Circle()
                                .fill(isToday ? colors.accent : Color.primary)
                                .matchedGeometryEffect(id: "weekDisc", in: weekDiscNS)
                        }
                    }
                    Text("\(Calendar.current.component(.day, from: date))")
                        .font(.title3.weight(.semibold).monospacedDigit())
                        .foregroundStyle(number)
                }
                .frame(width: discSize, height: discSize)
                // Dolgozat-pötty: a magassága minden oszlopban foglalt,
                // hogy semmi ne ugorjon.
                Circle()
                    .fill(examRolled == true ? Color.red : Color.orange)
                    .frame(width: 5, height: 5)
                    .opacity(examRolled == nil ? 0 : 1)
            }
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
        .accessibilityAddTraits(isSel ? [.isButton, .isSelected] : .isButton)
    }

    /// Nap-fejléc: "Péntek, október 23." + (teli napon) "6 óra · 8:00 – 13:35".
    /// A cím `mcDisplay` — Minecraft skinben a pixelbetű.
    private func dayHeader(showsSummary: Bool) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(dayTitle(for: selectedDay))
                .mcDisplay(24)
                .foregroundStyle(.primary)
                .lineLimit(1).minimumScaleFactor(0.6)
                .accessibilityAddTraits(.isHeader)
            if showsSummary {
                let items = effectiveFiltered
                let count = "\(items.count) óra"
                if let first = items.first, let last = items.last {
                    Text("\(count) · \(first.start.formatted(date: .omitted, time: .shortened)) – \(last.end.formatted(date: .omitted, time: .shortened))")
                        .font(.subheadline.monospacedDigit())
                        .foregroundStyle(.secondary)
                } else {
                    Text(count)
                        .font(.subheadline.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
        }
        // A cím fix méretű (mcDisplay) — az alsó sor se szaladjon el tőle.
        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Hét-lapozó swipe a hét-sávon. Ugyanaz a szigorú vízszintes zár, mint
    /// a daySwipeGesture-é (64 pt + kétszeres vízszintes túlsúly): a
    /// függőleges görgetés sosem lapoz hetet. Balra = következő hét.
    private var weekSwipeGesture: some Gesture {
        DragGesture(minimumDistance: 32, coordinateSpace: .local)
            .onEnded { value in
                let dx = value.translation.width
                let dy = value.translation.height
                guard abs(dx) > 64, abs(dx) > 2 * abs(dy) else { return }
                pageWeek(dx < 0 ? 1 : -1)
            }
    }

    /// Nap/hét-váltó swipe a napi tartalmon. Szigorú vízszintes zár
    /// (64 pt + kétszeres vízszintes túlsúly): a sima függőleges
    /// görgetés vagy átlós húzás sosem billenti át a napot — korábban a
    /// laza küszöb miatt húzogatáskor össze-vissza ugrált a nézet.
    private var daySwipeGesture: some Gesture {
        DragGesture(minimumDistance: 32, coordinateSpace: .local)
            .onEnded { value in
                let dx = value.translation.width
                let dy = value.translation.height
                guard abs(dx) > 64, abs(dx) > 2 * abs(dy) else { return }
                // Nap/het váltó swipe: csak tényleges lépéskor tick.
                let beforeWeek = weekOffset, beforeDay = selectedDay
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
                if weekOffset != beforeWeek || selectedDay != beforeDay {
                    userHasNavigated = true
                    SummitHaptics.selection()
                }
            }
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
    /// A kiválasztott nap naptári bejegyzése (tanév rendje) — az üres nap
    /// hivatalos feliratához („Tanítás nélküli munkanap (Nem órarendi nap)
    /// (Hétfő)"), nem az általános „Pihenőnap" szöveghez.
    private var selectedDayInfo: SchoolDayInfo? {
        guard let d = selectedDate else { return nil }
        return calendarDays.first { Calendar.current.isDate($0.date, inSameDayAs: d) }
    }
    private var emptyDayTitle: String {
        guard let info = selectedDayInfo, !info.typeName.isEmpty else { return "Nincs óra" }
        return info.typeName
    }
    private var emptyDayDetail: String {
        guard let info = selectedDayInfo, !info.typeName.isEmpty else {
            return "Pihenőnap — nincs rögzített óra erre a napra."
        }
        return info.emptyDayTexts().detail
    }
    private var emptyDayIcon: String {
        guard let info = selectedDayInfo, !info.typeName.isEmpty else { return "moon.zzz.fill" }
        return info.typeName.localizedCaseInsensitiveContains("munkanap") ? "briefcase.fill" : "moon.zzz.fill"
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

    /// Tabváltáskor a `.task` újra lefut — friss gyorstár-találatnál ez
    /// hálózat nélkül tér vissza. A váz csak üres nézetnél jön; egyébként
    /// a régi hét marad, és az új adat dinamikusan beíródik. Lehúzás
    /// (`force`) tényleges frissítés (a hiányzás-gyorstárat is nullázza).
    func load(force: Bool = false) async {
        let entryOffset = weekOffset
        // Egy adatsáv: demo usert is a KretaClient szolgálja ki helyből
        // (a kért hétre csempézett órarenddel) — nincs külön demo-ág.
        // A házik/dolgozatok abszolút dátumosak, mint élesben: másik hétre
        // lapozva csak az órarend látszik (ahogy egy valós usernél is).
        guard let user = session.selectedUser else { isLoading = false; return }
        let hadLessons = !lessons.isEmpty
        if !hadLessons { isLoading = true }
        if force { cachedAbsences = nil }
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
        await fetchWeek(force: force)
        // Okos nap csak a 0. hétről indulva ÉS csak ha a user nem lapozott
        // kézzel: ha az utolsó mai óra lement / hétvége van, a következő
        // tanítási napra ugrunk — ha az másik hét, annak az adata is kell.
        if entryOffset == 0, !userHasNavigated, applySmartDay(), weekOffset != entryOffset {
            await fetchWeek(force: force)
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
        // Vakáció-visszaszámláló: csak a 0. hétről (lapozáskor nem),
        // a widgetnek az App Groupba.
        if weekOffset == 0 { refreshVacation(iss: iss) }
        isLoading = false
    }

    /// Vakáció-info a widgetnek: naptári napok most → aug. 31. (egyetlen
    /// gyorstárazott kérés), tanítás nélküli hétköznapok a számoláshoz.
    /// A KRÉTA mellé az iskolai eseménynaptár szünet-napjai is bekerülnek:
    /// Magyarországon a szünet sokszor csak ott szerepel (nyílt titok),
    /// a KRÉTA `NaptariNapok` pedig üres — e nélkül a következő őszi/téli
    /// szünet láthatatlan maradna. Demo/hiba esetén üres lista — a fallback
    /// (jún. 15.) akkor is él.
    private func refreshVacation(iss: String) {
        // @State-pillanatfelvétel a Task előtt (a Task már háttérben fut).
        let eventsSnapshot = schoolEvents
        Task {
            let end = VacationCountdown.rangeEnd(for: Date())
            let days = await kreta.fetchCalendarDays(iss: iss, from: Date(), to: end)
            let cal = Calendar.current
            let kretaOffs = days.compactMap { info -> VacationCountdown.DayOff? in
                guard !info.isTimetableDay else { return nil }
                let day = cal.startOfDay(for: info.date)
                guard (2...6).contains(cal.component(.weekday, from: day)) else { return nil }
                return VacationCountdown.DayOff(day: day, name: info.typeName)
            }
            let eventOffs = VacationCountdown.breakDays(
                fromSchoolEvents: eventsSnapshot.map { ($0.day, $0.title) },
                calendar: cal)
            // Unió nap szerint; ütközésnél az eseménynaptár neve nyer
            // (beszédesebb: „Őszi szünet" a „Tanítás nélküli munkanap" helyett).
            var byDay: [Date: String] = [:]
            for o in kretaOffs { byDay[cal.startOfDay(for: o.day)] = o.name }
            for o in eventOffs { byDay[cal.startOfDay(for: o.day)] = o.name }
            let offs = byDay.map { VacationCountdown.DayOff(day: $0.key, name: $0.value) }
            VacationCountdown.save(VacationCountdown.compute(daysOff: offs))
        }
    }

    /// Widget-egykezesség: a heti snapshot csak innen íródik az App Groupba.
    /// A widget ebből rajzolja a mai / következő tanítási napot.
    /// (A mapping + reload a TimetableWidgetPublish-ban; a BG-ébresztés
    /// ugyanoda mergeli a mai napot.)
    private func publishWidgetSnapshot() {
        let noSchool = TimetableWidgetPublish.noSchoolDays(from: calendarDays)
        TimetableWidgetPublish.publishWeek(lessons, homeworks: homeworks, exams: displayExams, events: schoolEvents, eventsVisible: schoolEventsVisible, noSchoolDays: noSchool)
        // Apple Watch: ugyanez a heti anyag megy az órára is — a státusz-
        // flagekkel (felmentett zöld, dolgozat szürke), mint a telefonon.
        WatchSyncSender.pushTimetable(lessons, homeworks: homeworks, exams: displayExams, events: schoolEvents, eventsVisible: schoolEventsVisible, noSchoolDays: noSchool)
        // Iskolai események az óra órarend-tetejére (ugyanaz a lista).
        WatchSyncSender.pushSchoolEvents(events: schoolEvents, visible: schoolEventsVisible)
        // A 0. hétről a következő hét is megy az órára (háttérben, a nézet
        // megvárása nélkül): egyetlen kevés órás hét önmagában kevés —
        // hétvégén így is van mit mutatnia az órának.
        if weekOffset == 0 { pushNextWeekToWatch() }
    }

    /// Következő heti órák az órára: a mostani heti anyag + a jövő hét
    /// összefésülve (a házi/dolgozat/esemény-listák dátumfüggetlenek, azok
    /// változatlanul mennek). Üres jövő hét = nincs második push.
    private func pushNextWeekToWatch() {
        guard let user = session.selectedUser else { return }
        let iss = user.instituteCode.isEmpty ? (JWT.instituteCode(from: user.accessToken) ?? "") : user.instituteCode
        guard !iss.isEmpty, iss != "unknown" else { return }
        let cal = Calendar.current
        let thisMonday = mondayOfWeek(offset: 0)
        guard let nextMonday = cal.date(byAdding: .day, value: 7, to: thisMonday),
              let nextEnd = cal.date(byAdding: .day, value: 8, to: nextMonday) else { return }
        let current = lessons, hw = homeworks, ex = displayExams
        let ev = schoolEvents, vis = schoolEventsVisible, days = calendarDays
        Task {
            async let tt = kreta.fetchTimetable(iss: iss, from: nextMonday, to: nextEnd)
            async let cd = kreta.fetchCalendarDays(iss: iss, from: nextMonday, to: nextEnd)
            let (nextLessons, nextCal) = await (tt, cd)
            guard !nextLessons.isEmpty else { return }
            let merged = deduped(current + nextLessons)
            let noSchool = TimetableWidgetPublish.noSchoolDays(from: days + nextCal)
            WatchSyncSender.pushTimetable(merged, homeworks: hw, exams: ex, events: ev, eventsVisible: vis, noSchoolDays: noSchool)
        }
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
    private func fetchWeek(force: Bool = false) async {
        guard let user = session.selectedUser else { return }
        let iss = user.instituteCode.isEmpty ? (JWT.instituteCode(from: user.accessToken) ?? "") : user.instituteCode
        guard !iss.isEmpty, iss != "unknown" else { lessons = []; homeworks = []; exams = []; return }
        let monday = currentMonday
        let start = monday
        // +8 nap (jövő hétfő 00:00): a KRÉTA datumIg-határa a peremnapot
        // levághatja — a +1 nap ráhagyás miatt a következő hétfő órái és
        // naptári bejegyzése (pl. tanítás nélküli nap) is biztosan lejön.
        // A heti nézet a 7 napos dayTags-szel szűr, a plusz nap csak a
        // widget-jegyzetnek és a következő-óra számolásnak kell.
        let end = Calendar.current.date(byAdding: .day, value: 8, to: monday)!
        async let tt = kreta.fetchTimetable(iss: iss, from: start, to: end, force: force)
        async let hw = kreta.fetchHomework(iss: iss, force: force)
        async let ex = kreta.fetchExams(iss: iss, force: force)
        async let calD = kreta.fetchCalendarDays(iss: iss, from: start, to: end, force: force)
        let (ttR, hwR, exR, calR) = await (tt, hw, ex, calD)
        lessons = deduped(ttR)
        homeworks = hwR
        exams = exR
        // Naptári napok beolvasztása dátum szerint (a hét friss adata nyer,
        // a többi hét megmarad — a keresés úgyis nap-pontos).
        if !calR.isEmpty {
            let cal = Calendar.current
            let weekDays = Set((0..<7).compactMap { cal.date(byAdding: .day, value: $0, to: cal.startOfDay(for: start)) })
            calendarDays = calendarDays.filter { !weekDays.contains(cal.startOfDay(for: $0.date)) } + calR
        }
        // Hiányzások a dolgozat-pótláshoz: hetet lapozva nem húzzuk újra.
        if cachedAbsences == nil {
            cachedAbsences = await kreta.fetchAbsences(iss: iss, force: force)
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
    /// Sorkoppintás → részletező (a pillek testvér-gombok, nem részei).
    var onSelect: () -> Void = {}

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
                    .mcDisplay(15)
                    .monospacedDigit()
                    .foregroundStyle(numberColor)
                    .contentTransition(.numericText())
                    .allowsHitTesting(false)
                    .frame(width: 38, height: 38)
                    .background {
                        Group {
                            if MinecraftTheme.isActive {
                                RoundedRectangle(cornerRadius: 9)
                                    .fill(colors.surface)
                                    .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(MinecraftTheme.dirtDark, lineWidth: 2))
                                    .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(Color.white.opacity(0.3), lineWidth: 1).padding(2))
                            } else if #available(iOS 26.0, *) {
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

            // CENTER CARD — editorial content. A fejléc ÖNÁLLÓ gomb
            // (részletező-nyitás); a feladat/dolgozat-pillek a TESTVÉREI,
            // nem a részei — beágyazott Button nem tüzelne megbízhatóan,
            // és a VoiceOver egybeolvasztaná őket.
            VStack(alignment: .leading, spacing: 0) {
                Button(action: { print("SUMMIT-ROW-TAP \(lesson.id)"); onSelect() }) {
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
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("lesson-row-\(lesson.id)")
                .accessibilityLabel("\(lesson.subject), \(lesson.index). óra")
                // Feladat pill — a fejléc alatt, tap → Feladatok tab
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
                    .accessibilityLabel("Házi feladat – \(hw.subject)")
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
                    .accessibilityLabel("Dolgozat – \(ex.subject): \(ex.mode)")
                    .padding(.top, 2)
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

// MARK: - Tantárgy-ikon a részletezőhöz (SF Symbols, régóta létező készlet)
private enum LessonSubjectIcon {
    static func symbol(for subject: String) -> String {
        let s = subject.lowercased()
        if s.contains("matek") || s.contains("matematika") { return "function" }
        if s.contains("magyar") || s.contains("irodalom") || s.contains("nyelvtan") { return "book.fill" }
        if s.contains("töri") || s.contains("történelem") { return "building.columns.fill" }
        if s.contains("angol") || s.contains("német") || s.contains("olasz")
            || s.contains("francia") || s.contains("spanyol") || s.contains("orosz")
            || s.contains("nyelv") { return "globe" }
        if s.contains("fizika") { return "atom" }
        if s.contains("kémia") || s.contains("kemia") { return "flask.fill" }
        if s.contains("biológia") || s.contains("biologia") || s.contains("környezet") { return "leaf.fill" }
        if s.contains("földrajz") || s.contains("föld") { return "map.fill" }
        if s.contains("informatika") || s.contains("digitális") || s.contains("info") { return "laptopcomputer" }
        if s.contains("testnevelés") || s.contains("testneveles") || s.contains("tesi") { return "figure.run" }
        if s.contains("ének") || s.contains("enek") || s.contains("zene") { return "music.note" }
        if s.contains("rajz") || s.contains("vizuális") || s.contains("vizualis") { return "paintbrush.fill" }
        if s.contains("filozófia") || s.contains("filozofia") || s.contains("etika") { return "lightbulb.fill" }
        if s.contains("osztályfőnöki") || s.contains("osztalyfonoki") { return "person.2.fill" }
        return "book.closed.fill"
    }
}

// MARK: - Óra-részletező — koppintásra nyíló fullscreen nézet
// Hero-ikon + státusz, óra- adatok (tanár, időpont, terem, óraszám),
// a hozzá tartozó házi és dolgozat, "Megnyitás" gombokkal.
private struct LessonDetailSheet: View {
    let lesson: LessonItem
    let homework: HomeworkItem?
    let exam: ExamItem?
    let examRolled: Bool
    let colors: AppColors
    let scheme: ColorScheme
    @Environment(\.dismiss) private var dismiss
    @Environment(\.horizontalSizeClass) private var hSize
    private var isPad: Bool { hSize == .regular }

    private var isCancelled: Bool { lesson.isCancelled }
    private var isSubstituted: Bool { lesson.isSubstituted }
    private var isExempted: Bool { ExemptedStore.isExempted(lesson.subject) }
    private var isCurrent: Bool { lesson.start <= Date() && Date() <= lesson.end }

    private var heroBase: Color {
        if isExempted { return .green }
        if isCancelled { return .red }
        if isSubstituted { return .orange }
        if isCurrent { return .blue }
        return colors.accent
    }

    private var statusBadge: (text: String, color: Color)? {
        if isExempted { return ("Felmentett", .green) }
        if isCancelled { return ("Elmarad", .red) }
        if isSubstituted { return ("Helyettesítés", .orange) }
        if isCurrent { return ("Most", .blue) }
        return nil
    }

    private var dayLine: String {
        let f = DateFormatter(); f.locale = Locale(identifier: "hu_HU"); f.dateFormat = "EEEE • MMM d."
        return f.string(from: lesson.start).capitalized
    }
    private var timeLine: String {
        let t = DateFormatter(); t.locale = Locale(identifier: "hu_HU"); t.dateFormat = "H:mm"
        return "\(t.string(from: lesson.start)) – \(t.string(from: lesson.end)) • \(lesson.index). óra"
    }

    var body: some View {
        NavigationStack {
            List {
                // HERO — gradiens ikon + tárgy + nap/idő + státusz
                Section {
                    VStack(spacing: 12) {
                        Image(systemName: LessonSubjectIcon.symbol(for: lesson.subject))
                            .font(.system(size: 44, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(width: 104, height: 104)
                            .background {
                                Circle()
                                    .fill(
                                        LinearGradient(
                                            colors: [heroBase, heroBase.opacity(0.55)],
                                            startPoint: .topLeading, endPoint: .bottomTrailing
                                        )
                                    )
                                    .shadow(color: heroBase.opacity(0.35), radius: 18, y: 8)
                            }
                        Text(lesson.subject)
                            .mcDisplay(26)
                            .foregroundStyle((isCancelled || isExempted) ? .secondary : .primary)
                            .strikethrough(isCancelled || isExempted, color: .secondary)
                            .multilineTextAlignment(.center)
                        Text(dayLine)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.secondary)
                        Text(timeLine)
                            .font(.subheadline.weight(.medium).monospacedDigit())
                            .foregroundStyle(.secondary)
                        if let badge = statusBadge {
                            Text(badge.text.uppercased())
                                .font(.caption2.weight(.bold))
                                .tracking(0.5)
                                .foregroundStyle(.white)
                                .padding(.horizontal, 10).padding(.vertical, 5)
                                .background(Capsule().fill(badge.color))
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                }

                // ÓRA ADATAI
                Section("Óra adatai") {
                    detailRow(icon: "person.fill", title: "Tanár", value: lesson.teacher.isEmpty ? "—" : lesson.teacher)
                    if isSubstituted, let orig = lesson.originalTeacher, !orig.isEmpty {
                        detailRow(icon: "person.fill.badge.plus", title: "Eredeti tanár", value: orig)
                    }
                    detailRow(icon: "door.left.hand.open", title: "Terem", value: lesson.room.isEmpty ? "—" : lesson.room)
                    detailRow(icon: "clock.fill", title: "Időpont", value: timeLine)
                }

                // HÁZI
                Section("Házi feladat") {
                    if let hw = homework {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(HomeworkHTML.formatted(hw.title))
                                .font(.callout)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            if !hw.teacher.isEmpty {
                                Label(hw.teacher, systemImage: "person.fill")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            Button { openTasks(flash: hw.id) } label: {
                                Label("Megnyitás a Feladatokban", systemImage: "checklist")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(colors.accent)
                                    .padding(.horizontal, 12).padding(.vertical, 8)
                                    .background(Capsule().strokeBorder(colors.accent.opacity(0.35), lineWidth: 1))
                            }
                            .buttonStyle(.plain)
                            .padding(.top, 2)
                        }
                        .padding(.vertical, 4)
                    } else {
                        Label("Ehhez az órához nincs házi", systemImage: "checklist")
                            .font(.callout).foregroundStyle(.secondary)
                    }
                }

                // DOLGOZAT
                Section("Dolgozat") {
                    if let ex = exam {
                        VStack(alignment: .leading, spacing: 6) {
                            HStack(spacing: 6) {
                                Text(ex.mode).font(.callout.weight(.semibold))
                                if examRolled {
                                    Text("Pótló").font(.caption2.weight(.bold)).foregroundStyle(.red)
                                        .padding(.horizontal, 8).padding(.vertical, 4)
                                        .background(Capsule().fill(Color.red.opacity(0.12)))
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            if !ex.plainDescription.isEmpty {
                                Text(ex.plainDescription)
                                    .font(.callout).foregroundStyle(.secondary)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            if !ex.teacher.isEmpty {
                                Label(ex.teacher, systemImage: "person.fill")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            Button { openTasks(segment: "exams", flash: ex.id) } label: {
                                Label("Megnyitás a Dolgozatokban", systemImage: "doc.text.fill")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(colors.accent)
                                    .padding(.horizontal, 12).padding(.vertical, 8)
                                    .background(Capsule().strokeBorder(colors.accent.opacity(0.35), lineWidth: 1))
                            }
                            .buttonStyle(.plain)
                            .padding(.top, 2)
                        }
                        .padding(.vertical, 4)
                    } else {
                        Label("Ehhez az órához nincs dolgozat", systemImage: "doc.text")
                            .font(.callout).foregroundStyle(.secondary)
                    }
                }
            }
            .listStyle(.insetGrouped)
            .frame(maxWidth: isPad ? MacSupport.contentWidth(ipad: 1000, mac: 1150) : .infinity)
            .padding(.horizontal, MacSupport.sidePadding)
            .frame(maxWidth: .infinity)
            .summitListChrome(colors: colors)
            .navigationTitle(lesson.subject)
            .navigationBarTitleDisplayMode(.inline)
            .summitToolbarBackground()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Kész") { dismiss() }
                }
            }
            .accessibilityIdentifier("lesson-detail")
            .onAppear { print("SUMMIT-DETAIL-APPEARED \(lesson.id)") }
        }
        .tint(colors.accent)
    }

    private func detailRow(icon: String, title: String, value: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(colors.accent)
                .frame(width: 24)
            Text(title)
                .font(.callout)
                .foregroundStyle(.secondary)
            Spacer(minLength: 8)
            Text(value)
                .font(.callout.weight(.semibold))
                .multilineTextAlignment(.trailing)
        }
        .padding(.vertical, 2)
    }

    /// A részletező előbb csukódik, aztán megy a deeplink — különben a
    /// cover a Feladatok fölött ragadna.
    private func openTasks(segment: String? = nil, flash: String) {
        dismiss()
        var ui: [String: Any] = ["flash": flash]
        if let segment { ui["segment"] = segment }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
            NotificationCenter.default.post(
                name: Notification.Name("summit.switchToTasks"), object: nil, userInfo: ui)
        }
    }
}
