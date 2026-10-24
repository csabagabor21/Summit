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
    /// A kijelzett hét órái — a közös gyorstárból (KretaStore) szinkronizálva:
    /// az első képkocka és minden hétlapozás azonnal a mentett hetet mutatja,
    /// a frissítés a háttérben fut és beérkezéskor íródik be.
    @State private var lessons: [LessonItem]
    /// Van-e (mentett vagy friss) adat a kijelzett hétről. Amíg nincs, a nap
    /// NEM mutat üres állapotot („Pihenőnap") — csak a töltés-vázat.
    @State private var weekKnown: Bool
    @State private var homeworks: [HomeworkItem]
    @State private var exams: [ExamItem]
    @State private var selectedDay: Int
    @State private var weekOffset: Int // 0 = ez a hét, -1 = múlt hét, +1 = jövő hét
    /// Naptári napok (tanév rendje) az üres napok hivatalos feliratához.
    /// Dátum-kulcsolt, hetek közt megmarad — a régi bejegyzés csak a saját
    /// napjára illeszkedik, ezért egy sikertelen lehúzás sem kever be idegent.
    @State private var calendarDays: [SchoolDayInfo]
    // Kézi navigálás (hét/nap lapozás) után az okos ugrás nem dobhat vissza —
    // csak a "Ma" gomb és az első betöltés ugorhat a következő tanítási napra.
    @State private var userHasNavigated = false
    /// Legutóbb kezelt „Mutatás az órarendben" kérés (a relézett ismétlés szűréséhez).
    @State private var lastJumpKey: String?
    @State private var lastJumpAt = Date.distantPast
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
    @State private var schoolEvents: [SchoolEvent]
    /// Hiányzások a dolgozat-pótláshoz (a közös gyorstárból).
    @State private var cachedAbsences: [AbsenceItem]?
    /// A kijelzett hét még nem látott óra-változásai (óra-ID → változás).
    @State private var changeMarkers: [String: LessonChange] = [:]
    /// Ebben a megtekintésben már látottnak jelölt változások: a jelölés a
    /// képernyőn marad, amíg a user el nem hagyja az Órarendet (nem tűnik el
    /// a szeme előtt), a következő belépéskor már nincs.
    @State private var acknowledgedChanges: [String: LessonChange] = [:]
    @Environment(\.scenePhase) private var scenePhase
    /// Óránkénti házi / dolgozat / pótlás-párosítás EGYSZER adatváltozásonként
    /// (eddig soronként, minden body-ban és 15 mp-es Timeline-tickben a teljes
    /// házi- és dolgozatlista újraszkennelve + a pótlás újraszámolva).
    @State private var derived = TimetableDerived()
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
    /// Első megjelenés: a pozíció (okos nap) és a hét adata már a mentett
    /// gyorstárból áll elő — nincs üres / „Pihenőnap" első képkocka, és
    /// hétvégén sem villan fel az üres szombat a hétfő előtt.
    init() {
        let now = Date()
        let target = Self.smartDayTarget(now: now, items: Self.smartItems(now: now))
        _weekOffset = State(initialValue: target.weekOffset)
        _selectedDay = State(initialValue: target.weekday)
        let snap = Self.storeSnapshot(weekOffset: target.weekOffset, now: now)
        _lessons = State(initialValue: snap.lessons)
        _weekKnown = State(initialValue: snap.known)
        _homeworks = State(initialValue: snap.homeworks)
        _exams = State(initialValue: snap.exams)
        _calendarDays = State(initialValue: snap.calendarDays)
        _cachedAbsences = State(initialValue: snap.absences)
        _schoolEvents = State(initialValue: SchoolEventsStore.load())
        _derived = State(initialValue: TimetableDerived.make(lessons: snap.lessons, homeworks: snap.homeworks,
                                                              exams: snap.exams, absences: snap.absences ?? []))
    }

    private static func mondayOfWeek(offset: Int, now: Date = Date()) -> Date {
        KretaWeek.adding(weeks: offset, to: KretaWeek.monday(for: now))
    }
    private func mondayOfWeek(offset: Int) -> Date { Self.mondayOfWeek(offset: offset) }
    private var currentMonday: Date { mondayOfWeek(offset: weekOffset) }

    /// A kijelzett hét gyorstár-állapota egyben (órák, házik, dolgozatok,
    /// naptári napok, hiányzások) — a saját tételek belekeverve.
    private struct StoreSnapshot {
        var lessons: [LessonItem]
        var known: Bool
        var homeworks: [HomeworkItem]
        var exams: [ExamItem]
        var calendarDays: [SchoolDayInfo]
        var absences: [AbsenceItem]?
    }

    private static func storeSnapshot(weekOffset: Int, now: Date = Date()) -> StoreSnapshot {
        let store = KretaStore.shared
        let monday = mondayOfWeek(offset: weekOffset, now: now)
        let week = store.lessons(week: monday)
        let custom = CustomTasksStore.load()
        let hw: [HomeworkItem] = store.value(.homework) ?? []
        let ex: [ExamItem] = store.value(.exams) ?? []
        return StoreSnapshot(
            lessons: deduped(week ?? []),
            known: week != nil,
            homeworks: hw + CustomTasksStore.homeworkItems(from: custom),
            exams: ex + CustomTasksStore.examItems(from: custom),
            calendarDays: store.calendarDays(week: monday) ?? [],
            absences: store.value(.absences)
        )
    }

    /// Az okos naphoz: a mostani + a jövő hét mentett órái.
    private static func smartItems(now: Date = Date()) -> [LessonItem] {
        let store = KretaStore.shared
        let m0 = KretaWeek.monday(for: now)
        return (store.lessons(week: m0) ?? []) + (store.lessons(week: KretaWeek.adding(weeks: 1, to: m0)) ?? [])
    }

    /// Gyorstár → kijelzett állapot (hálózat nélkül): hétlapozáskor, a store
    /// releváns változásakor és a saját tételek változásakor.
    private func syncFromStore() {
        let snap = Self.storeSnapshot(weekOffset: weekOffset)
        if lessons != snap.lessons { lessons = snap.lessons }
        if weekKnown != snap.known { weekKnown = snap.known }
        if homeworks != snap.homeworks { homeworks = snap.homeworks }
        if exams != snap.exams { exams = snap.exams }
        if calendarDays != snap.calendarDays { calendarDays = snap.calendarDays }
        if cachedAbsences != snap.absences { cachedAbsences = snap.absences }
        recomputeDerivedIfNeeded()
        let store = KretaStore.shared
        var markers: [String: LessonChange] = [:]
        for l in snap.lessons { if let c = store.lessonChange(for: l.id) { markers[l.id] = c } }
        if changeMarkers != markers { changeMarkers = markers }
    }

    /// A származtatott párosítások újraszámolása, ha a bemenetük változott.
    private func recomputeDerivedIfNeeded(force: Bool = false) {
        let input = TimetableDerived.Input(lessons: lessons, homeworks: homeworks, exams: exams, absences: cachedAbsences ?? [])
        guard force || input != derived.input else { return }
        derived = TimetableDerived.make(lessons: input.lessons, homeworks: input.homeworks,
                                        exams: input.exams, absences: input.absences)
    }

    /// Kijelzendő változás-jelölés egy órához (látatlan vagy ebben a
    /// megtekintésben látott).
    private func changeMarker(for lesson: LessonItem) -> LessonChange? {
        changeMarkers[lesson.id] ?? acknowledgedChanges[lesson.id]
    }

    /// A sor megjelent az előtérben lévő Órarendben: a változást a user látta.
    private func acknowledgeChange(for lesson: LessonItem) {
        guard scenePhase == .active, let c = changeMarkers[lesson.id] else { return }
        acknowledgedChanges[lesson.id] = c
        changeMarkers.removeValue(forKey: lesson.id)
        KretaStore.shared.markLessonChangesSeen([lesson.id])
    }

    /// A figyelt gyorstár-típusok: a kijelzett hét + a mostani és a jövő hét
    /// (a widget / Watch mindig a mostaniból publikál), házik, dolgozatok,
    /// hiányzások, naptári napok.
    private var watchedKinds: [KretaDataKind] {
        let m0 = mondayOfWeek(offset: 0)
        var kinds: [KretaDataKind] = [.timetable(currentMonday), .calendar(currentMonday), .homework, .exams, .absences]
        for k in [KretaDataKind.timetable(m0), .timetable(KretaWeek.adding(weeks: 1, to: m0)), .calendar(m0)] where !kinds.contains(k) {
            kinds.append(k)
        }
        return kinds
    }
    /// Naptári nap → (weekOffset, hétköznap-tag) a 0. hét hétfőjéhez képest.
    private static func offsetAndTag(for day: Date, now: Date = Date()) -> (weekOffset: Int, weekday: Int) {
        let cal = Calendar.current
        let base = mondayOfWeek(offset: 0, now: now)
        let diff = cal.dateComponents([.day], from: base, to: cal.startOfDay(for: day)).day ?? 0
        let wd = cal.component(.weekday, from: day)
        guard wd >= 2 && wd <= 6 else { return (0, 2) }
        return (Int(floor(Double(diff) / 7.0)), wd)
    }
    /// Ha a mai utolsó óra már véget ért (vagy hétvége van), a következő tanítási
    /// (órával rendelkező) nap weekOffset/hétköznap párját adja vissza.
    private static func smartDayTarget(now: Date, items: [LessonItem]) -> (weekOffset: Int, weekday: Int) {
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
                    return offsetAndTag(for: day, now: now)
                }
            }
        }
        // Hétvége, vagy a cache-ben nincs előrébb óra (pl. a jövő hét még nincs
        // lehúzva): naptár szerinti következő hétköznap.
        for i in 1...7 {
            guard let day = cal.date(byAdding: .day, value: i, to: now) else { continue }
            let wd = cal.component(.weekday, from: day)
            if wd >= 2 && wd <= 6 { return offsetAndTag(for: day, now: now) }
        }
        return isWeekend ? (1, 2) : (0, weekday)
    }
    /// Tabra lépéskor / betöltés után a következő tanítási napra ugrik, ha kell.
    /// Igazat ad vissza, ha napot (vagy hetet) váltott.
    @discardableResult
    private func applySmartDay(now: Date = Date()) -> Bool {
        guard now > suppressAutoJumpUntil else { return false }
        let t = Self.smartDayTarget(now: now, items: Self.smartItems(now: now))
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
    /// A hálózati frissítést a `.task` indítja (egyszer tabra lépésenként —
    /// korábban ez is külön load()-ot futtatott, így minden belépés kétszer
    /// töltött és kétszer publikált a widgetnek / órának).
    private func enterTimetable() {
        guard Date() > suppressAutoJumpUntil else { return }
        let wd = Calendar.current.component(.weekday, from: Date())
        withAnimation(SummitMotion.page) {
            weekOffset = 0
            selectedDay = min(6, max(2, wd))
            userHasNavigated = false
            // Okos nap a mentett órákból (hétvége / nap vége → köv. tanítási nap).
            applySmartDay()
        }
        syncFromStore()
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
            syncFromStore()
            await load()
        } else if !weekKnown {
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
        syncFromStore()
        Task { await load() }
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
                        SkinLabel(err, systemImage: "wifi.exclamationmark")
                            .skinFont(.subheadline, weight: .medium)
                            .foregroundStyle(CyberpunkTheme.isActive ? CyberpunkTheme.coral : .orange)
                            .fixedSize(horizontal: false, vertical: true)
                            .listRowBackground(MinecraftTheme.skinRowBackground(Color.orange.opacity(scheme == .dark ? 0.12 : 0.08)))
                            .listRowInsets(MinecraftTheme.rowInsets(EdgeInsets(top: 10, leading: 16, bottom: 10, trailing: 16)))
                            .listRowSeparator(.hidden)
                    }
                }

                // Az idő-eltolás csúszka a Fejlesztői módban él — itt csak az
                // eltolt idő szerint rajzolunk, ha aktív (overrideNow).
                if !weekKnown {
                    // Még nincs adat erről a hétről: töltés-váz (hálózati hiba
                    // esetén a fenti hibasor marad, nem hamis üres nap).
                    if loadError == nil {
                    Section {
                        ForEach(0..<5, id: \.self) { _ in
                            HStack(spacing: 14) {
                                MinecraftTheme.circle.fill(Color.primary.opacity(0.08)).frame(width: 38, height: 38)
                                VStack(alignment: .leading, spacing: 6) {
                                    MinecraftTheme.shape(cornerRadius: 6, continuous: false).fill(Color.primary.opacity(0.08)).frame(height: 14).frame(maxWidth: 140)
                                    MinecraftTheme.shape(cornerRadius: 6, continuous: false).fill(Color.primary.opacity(0.06)).frame(height: 10).frame(maxWidth: 90)
                                }
                                Spacer()
                            }
                            .padding(.vertical, 10)
                            .redacted(reason: .placeholder)
                            .summitRowSurface(colors: colors)
                            .listRowInsets(MinecraftTheme.rowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16)))
                        }
                    }
                    }
                } else if filtered.isEmpty {
                    // Üres napon is ugyanaz a fejléc-cím, mint a teli napon
                    // (csak az óraszám-sor nélkül).
                    Section {
                        dayHeader(showsSummary: false)
                        // Üres napon is lehessen napot váltani húzással.
                        .contentShape(Rectangle())
                        .simultaneousGesture(daySwipeGesture)
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
                        TimetableEmptyState(title: emptyDayTitle, icon: emptyDayIcon, detail: emptyDayDetail)
                            // Minecraftban a talaj a lista alsó része fölé lóg: a
                            // magas, középre igazított üres-állapot szövege a fű
                            // mögé csúszna, ezért ott a fejléc alá tapad.
                            .frame(maxWidth: .infinity, minHeight: MinecraftTheme.isActive ? nil : 220)
                            .padding(.vertical, MinecraftTheme.isActive ? 0 : 16)
                            // Óra nélküli napon eddig nem volt mit húzni: a
                            // napváltó swipe csak az óra-idővonalon élt.
                            .contentShape(Rectangle())
                            .simultaneousGesture(daySwipeGesture)
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                            .listRowInsets(EdgeInsets(top: MinecraftTheme.isActive ? 8 : 24, leading: 16, bottom: 24, trailing: 16))
                    }
                    .listSectionSpacing(MinecraftTheme.isActive ? .custom(0) : .default)
                } else {
                    // MARK: Nap-fejléc — "Péntek, október 23." + "6 óra · 8:00 – 13:35"
                    // Az óraszám és az idősáv a záró felmentett órák nélkül értendő
                    // (7 órából az utolsó felmentett → "6 óra", a 6. végéig).
                    Section {
                        dayHeader(showsSummary: true)
                        .contentShape(Rectangle())
                        .simultaneousGesture(daySwipeGesture)
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
            // (A „kézi navigálás" jelzőt a user-akciók állítják — nap-sáv,
            // swipe, hétlapozás —, nem egy selectedDay-onChange: az a kód
            // okos nap-ugrására is tüzelt, így a „Ma" gomb a megnyomása után
            // is kint ragadt.)
            .frame(maxWidth: isPad ? MacSupport.contentWidth(ipad: 1000, mac: 1150) : .infinity)
            .padding(.horizontal, MacSupport.sidePadding)
            .frame(maxWidth: .infinity)
            .summitListChrome(colors: colors)
            // A közös gyorstár figyelése: beérkező hét / házi / dolgozat azonnal
            // beíródik; a mostani hét változásakor a widget és az óra is frissül.
            .background {
                KretaStoreWatcher(kinds: watchedKinds) {
                    syncFromStore()
                    publishWidgetSnapshot()
                }
            }
            // Hétlapozás: a mentett hét azonnal (hálózatra várás és üres
            // villanás nélkül), a frissítést a lapozó indítja.
            .onChange(of: weekOffset) { _, _ in
                syncFromStore()
                // A hibasor a korábbi hétre szólt — az új hét saját töltése dönt.
                loadError = nil
            }
            // Lista-szintű .animation (selectedDay/weekOffset) és gesztus
            // NINCS: az egész lista minden napváltáskor és Timeline-ticknél
            // újraanimált — ez dobálta a görgetési pozíciót húzogatáskor.
            // A napváltás a hét-sáv koppintásánál és a daySwipeGesture
            // végpontjain animál (withAnimation), a lista tartalma meg
            // transition nélkül, azonnal cserélődik.
            .refreshable {
                // Lehúzáskor a hiányzások is frissen jönnek (a pótláshoz).
                await load(force: true)
                // Kézi frissítés vége: semleges "megvan"-koppanás.
                SummitHaptics.light()
            }
            // Máshol (Feladatok tab, másik eszköz sync-kel) felvett/törölt
            // saját tétel az órarenden is azonnal látszódjon.
            .onReceive(NotificationCenter.default.publisher(for: CustomTasksStore.changedNotification)) { _ in
                syncFromStore()
                publishWidgetSnapshot()
            }
            // Dolgozat-pótlás kapcsoló/elvetés — a kijelzett dátumok újraszámolódnak.
            .onReceive(NotificationCenter.default.publisher(for: ExamRollover.changedNotification)) { _ in
                // Dolgozat-pótlás kapcsoló/elvetés — a kijelzett dátumok újraszámolódnak.
                recomputeDerivedIfNeeded(force: true)
            }
            // Dev idő-csúszka: a widget is kövesse az eltolt időt —
            // ehhez elég újrapublikálni (hálózat nem kell hozzá).
            .onChange(of: previewMinutes) { _, _ in publishWidgetSnapshot() }
            .onChange(of: isPreviewActive) { _, _ in publishWidgetSnapshot() }
            .navigationTitle("Órarend")
            // inlineLarge, nem .large: a hét-sáv (safeAreaBar) a nagy cím és a
            // lista közé ékelődik, így a nagy cím nem tudja folyamatosan követni
            // a görgetést — ~55 pt-nál egy képkocka alatt csukódott (nav-sáv
            // 106 → 54 pt, a hét-sáv vele ugrott), lassú húzásnál a küszöb
            // körül oda-vissza. Az inlineLarge ugyanaz a nagy cím a sávban,
            // a sáv magassága görgetéskor állandó.
            .toolbarTitleDisplayMode(.inlineLarge)
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
            // Az Órarend elhagyásakor a már látott változások jelölése lekerül.
            .onDisappear { acknowledgedChanges = [:] }
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
                    change: changeMarker(for: lesson),
                    homework: homework(for: lesson),
                    exam: exam(for: lesson),
                    examRolled: exam(for: lesson).map { rolledExamIDs.contains($0.id) } ?? false,
                    colors: colors,
                    scheme: scheme
                )
                // Minecraftban a játék menü-háttere a lap mögött.
                .skinSheetBackground()
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
                // A MainTabView egyszer újraküldi (lusta tab-tartalom): ha az
                // eredetit már kezeltük, az ismétlés nem ugrik/villan újra.
                let key = "\(subject)|\(deadlineTS)|\(hwId ?? "")"
                if info["summit.relayed"] != nil, key == lastJumpKey,
                   Date().timeIntervalSince(lastJumpAt) < 3 { return }
                lastJumpKey = key
                lastJumpAt = Date()
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
        if derived.lessonIDs.contains(lesson.id) { return derived.homeworkByLesson[lesson.id] }
        return HomeworkMatcher.homework(for: lesson, in: homeworks)
    }
    /// Dolgozatok átütemezéssel: a hiányzás napján lévő dolgozat a
    /// következő olyan órán jelenik meg (piros háttérrel) — a csatolás a
    /// kijelzett dátumon történik, az eredeti napról eltűnik.
    private var displayExams: [ExamItem] { derived.displayExams }
    private var rolledExamIDs: Set<String> { derived.rolledIDs }
    private func exam(for lesson: LessonItem) -> ExamItem? {
        // Óraszámos dolgozat csak a saját órájára kerül (ExamMatcher),
        // óraszám nélkül naponta csak EGY órára (az aznapi legkorábbira).
        if derived.lessonIDs.contains(lesson.id) { return derived.examByLesson[lesson.id] }
        return ExamMatcher.exam(for: lesson, in: displayExams, allLessons: lessons)
    }
    /// Konzervatív: csak az aznapi (határidő-napi) házi vagy a ráTŰZÖTT
    /// dolgozat színezi a sort (a tárgy-szintű fallback szándékosan nincs).
    private func hasAssignment(for lesson: LessonItem) -> Bool {
        homework(for: lesson) != nil || exam(for: lesson) != nil
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
                        change: changeMarker(for: lesson),
                        onSelect: { selectedLesson = lesson }
                    )
                    .id(lesson.id)
                    .padding(.vertical, 5)
                    .onAppear { acknowledgeChange(for: lesson) }
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
                            change: changeMarker(for: lesson),
                            onSelect: { selectedLesson = lesson }
                        )
                        .id(lesson.id)
                        .padding(.vertical, 5)
                        .onAppear { acknowledgeChange(for: lesson) }
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
    private var examDays: [Date: Bool] { derived.examDays }

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
            } else if CyberpunkTheme.isActive {
                // Cyberpunk: opak HUD-panel levágott sarokkal, 1 px-es sárga
                // kerettel (üveg nincs — a skin sosem áttetsző).
                weekCard
                    .padding(.horizontal, 8)
                    .padding(.vertical, 8)
                    .background {
                        CPPanelBackground(accent: CyberpunkTheme.yellow, fill: CyberpunkTheme.panel,
                                          corners: .diagonal, cut: 14)
                    }
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
                        .cpOnly { $0.textCase(.uppercase).tracking(1.6) }
                        .skinFont(.subheadline, weight: .semibold)
                        .foregroundStyle(CyberpunkTheme.isActive ? AnyShapeStyle(CyberpunkTheme.yellow) : AnyShapeStyle(.primary))
                        .lineLimit(1).minimumScaleFactor(0.8)
                    // Hét-viszony + frissítés-állapot („Ez a hét · Frissítés…");
                    // ha nem fér ki, az állapot nyer (a hónap-cím és a dátumok
                    // úgyis mutatják, melyik hét ez).
                    TimetableWeekSubtitle(weekTitle: weekTitle,
                                          kinds: [.timetable(currentMonday), .homework, .exams])
                }
                // A cím mindig középen áll (a "Ma" gomb meg-megjelenése
                // nem tolja el), a gombok sávját szabadon hagyja.
                .padding(.horizontal, 88)
                .contentTransition(.numericText())
                .animation(SummitMotion.page, value: weekOffset)
                .onTapGesture {
                    // Ugyanakkor él, amikor a „Ma" gomb látszik (napot
                    // lapozva is, nem csak más héten).
                    guard weekOffset != 0 || userHasNavigated else { return }
                    // Nem Button, ezért a kattanás kézzel (csak MC-ben szól).
                    McSound.play(.click)
                    goToSmartToday()
                }

                HStack(spacing: 0) {
                    Button { pageWeek(-1) } label: {
                        SkinIcon("chevron.left", size: 18)
                            .font(.system(size: 15, weight: .semibold))
                            // Cyberpunkban a HUD-gomb adja a színt (lenyomva invertál).
                            .unlessCP { $0.foregroundStyle(.primary) }
                            .frame(width: MinecraftTheme.isActive ? 24 : CyberpunkTheme.isActive ? 18 : 40,
                                   height: MinecraftTheme.isActive ? 24 : CyberpunkTheme.isActive ? 22 : 36)
                            .contentShape(Rectangle())
                    }
                    .mcCompactOrPlainButton()
                    .disabled(weekOffset <= -8)
                    .accessibilityLabel("Előző hét")

                    Spacer(minLength: 0)

                    // "Ma" gomb: nem csak hetet lapozva, hanem napot
                    // ellapozva is előjön (a nap-sáv és a swipe is
                    // userHasNavigated-et állít; a gomb azt nullázza).
                    if weekOffset != 0 || userHasNavigated {
                        Button("Ma") { goToSmartToday() }
                        .skinFont(.subheadline, weight: .semibold)
                        .mcCompactButtonIfActive()
                        .tint(colors.accent)
                        .padding(.trailing, 4)
                    }

                    Button { pageWeek(1) } label: {
                        SkinIcon("chevron.right", size: 18)
                            .font(.system(size: 15, weight: .semibold))
                            .unlessCP { $0.foregroundStyle(.primary) }
                            .frame(width: MinecraftTheme.isActive ? 24 : CyberpunkTheme.isActive ? 18 : 40,
                                   height: MinecraftTheme.isActive ? 24 : CyberpunkTheme.isActive ? 22 : 36)
                            .contentShape(Rectangle())
                    }
                    .mcCompactOrPlainButton()
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
        let dimEmpty = weekKnown && !lessons.isEmpty
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
        .background { if !MinecraftTheme.isActive && !CyberpunkTheme.isActive { weekDiscLayer } }
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
        // Cyberpunkban sárga, levágott sarkú kijelölő-lap fekete számmal;
        // ma = sárga szám + vékony sárga aláhúzás.
        let mc = MinecraftTheme.isActive
        let cp = CyberpunkTheme.isActive
        let number: AnyShapeStyle = isSel
            ? AnyShapeStyle(cp ? Color.black : Color.white)
            : isToday ? AnyShapeStyle(mc ? MinecraftTheme.grassDeep : cp ? CyberpunkTheme.yellow : colors.accent)
            : isEmpty ? AnyShapeStyle(.tertiary)
            : AnyShapeStyle(.primary)
        var label = dayTitle(for: tag)
        if isToday { label += ", ma" }
        if examRolled != nil { label += ", dolgozat" }
        return Button {
            guard tag != selectedDay else { return }
            SummitHaptics.selection()
            // A kattanást a `.skinPlain` stílus adja (eddig duplán szólt).
            userHasNavigated = true
            withAnimation(SummitMotion.page) { selectedDay = tag }
        } label: {
            VStack(spacing: 3) {
                Text(Self.weekdayShortSymbols[weekday - 1])
                    .cpOnly { $0.textCase(.uppercase).tracking(1) }
                    .cpMono(10)
                    .skinFont(.caption2, weight: .semibold)
                    .foregroundStyle(cp ? AnyShapeStyle(isSel || isToday ? CyberpunkTheme.yellow : CyberpunkTheme.dim) : AnyShapeStyle(.secondary))
                    .lineLimit(1)
                ZStack {
                    if isSel {
                        if mc {
                            // A hotbar kijelölése: fehér keretes kő-slot (a
                            // vanilla kiemelt gomb), ma = fűzöld arc alatta.
                            ZStack {
                                (isToday ? MinecraftTheme.grassDeep : Color(hex: 0x6B6B70))
                                McNineSlice("mc_widget_button_hi", border: 3)
                            }
                            .matchedGeometryEffect(id: "weekDisc", in: weekDiscNS)
                        } else if cp {
                            CPChamferShape(cut: 8, corners: .diagonal)
                                .fill(CyberpunkTheme.yellow)
                                .matchedGeometryEffect(id: "weekDisc", in: weekDiscNS)
                        }
                    }
                    Text("\(Calendar.current.component(.day, from: date))")
                        .skinFontDigits(.title3, weight: .semibold)
                        .foregroundStyle(number)
                        .shadow(color: mc && isSel ? Color(hex: 0x3F3F3F) : .clear, radius: 0, x: 2, y: 2)
                }
                .frame(width: discSize, height: discSize)
                .overlay(alignment: .bottom) {
                    if cp && isToday && !isSel {
                        Rectangle()
                            .fill(CyberpunkTheme.yellow)
                            .frame(height: 2)
                            .padding(.horizontal, 6)
                    }
                }
                // Dolgozat-pötty: a magassága minden oszlopban foglalt,
                // hogy semmi ne ugorjon.
                MinecraftTheme.circle
                    .fill(examRolled == true ? (cp ? CyberpunkTheme.red : Color.red)
                          : (cp ? CyberpunkTheme.yellow : Color.orange))
                    .frame(width: mc ? 6 : 5, height: mc ? 6 : 5)
                    .opacity(examRolled == nil ? 0 : 1)
            }
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.skinPlain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
        .accessibilityAddTraits(isSel ? [.isButton, .isSelected] : .isButton)
    }

    /// Nap-fejléc: "Péntek, október 23." + (teli napon) "6 óra · 8:00 – 13:35".
    /// A cím `mcDisplay` — Minecraft skinben a pixelbetű.
    private func dayHeader(showsSummary: Bool) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(dayTitle(for: selectedDay))
                // Cyberpunk: nagybetűs HUD-cím, napváltáskor egy rövid
                // glitch-rándulás (Reduce Motion mellett a kit kikapcsolja).
                .cpOnly { $0.textCase(.uppercase).tracking(1.2) }
                .mcDisplay(24)
                .foregroundStyle(.primary)
                .lineLimit(1).minimumScaleFactor(0.6)
                .cpOnly { $0.cpGlitch(trigger: "\(weekOffset)-\(selectedDay)") }
                .accessibilityAddTraits(.isHeader)
            if showsSummary {
                let items = effectiveFiltered
                let cp = CyberpunkTheme.isActive
                let count = cp ? String(format: "%02d ÓRA", items.count) : "\(items.count) óra"
                if let first = items.first, let last = items.last {
                    let span = "\(first.start.formatted(date: .omitted, time: .shortened)) – \(last.end.formatted(date: .omitted, time: .shortened))"
                    Text(cp ? "\(count) // \(span)" : "\(count) · \(span)")
                        .cpOnly {
                            $0.cpMono(12, relativeTo: .subheadline).foregroundStyle(CyberpunkTheme.cyan)
                                .accessibilityLabel("\(items.count) óra, \(span)")
                        }
                        .skinFontDigits(.subheadline)
                        .skinSecondaryOnSky()
                } else {
                    Text(count)
                        .cpOnly { $0.cpMono(12, relativeTo: .subheadline).foregroundStyle(CyberpunkTheme.cyan) }
                        .skinFontDigits(.subheadline)
                        .skinSecondaryOnSky()
                }
            }
            if CyberpunkTheme.isActive {
                CPDivider(color: CyberpunkTheme.yellow)
                    .padding(.top, 6)
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
    private static func deduped(_ items: [LessonItem]) -> [LessonItem] {
        var seen = Set<String>()
        return items.filter { seen.insert("\($0.subject)|\($0.start.timeIntervalSince1970)|\($0.end.timeIntervalSince1970)").inserted }
    }
    func isCurrent(_ l: LessonItem, now: Date) -> Bool { l.start<=now && l.end>=now }
    func progress(for l: LessonItem, now: Date) -> Double { let t=l.end.timeIntervalSince(l.start); return t>0 ? min(1,max(0,now.timeIntervalSince(l.start)/t)) : 0 }
    // legacy overloadok — ha nem adsz now-t, effectiveNow-t használja (preview vagy élő)
    func isCurrent(_ l: LessonItem) -> Bool { isCurrent(l, now: overrideNow ?? Date()) }
    func progress(for l: LessonItem) -> Double { progress(for: l, now: overrideNow ?? Date()) }

    /// Háttér-frissítés a kijelzett hétre. A mentett adat már látszik (a
    /// gyorstárból); a hét, a házik, a dolgozatok, a naptári napok és a
    /// hiányzások PÁRHUZAMOSAN jönnek, mindegyik a beérkezésekor íródik be
    /// (a figyelőn át). Friss gyorstárnál (tabváltás, visszalapozás) nincs
    /// hálózat. Lehúzás (`force`) mindent frissen kér.
    func load(force: Bool = false) async {
        // Egy adatsáv: demo usert is a KretaClient szolgálja ki helyből
        // (a kért hétre csempézett órarenddel) — nincs külön demo-ág.
        // A házik/dolgozatok abszolút dátumosak, mint élesben: másik hétre
        // lapozva csak az órarend látszik (ahogy egy valós usernél is).
        guard let user = session.selectedUser else { return }
        let iss = user.instituteCode.isEmpty ? (JWT.instituteCode(from: user.accessToken) ?? "") : user.instituteCode
        if iss.isEmpty || iss == "unknown" {
            loadError = "Hiányzó intézményi kód — jelentkezz be újra."
            return
        }
        KretaStore.shared.activate(user)
        let entryOffset = weekOffset
        // Okos nap csak a 0. hétről indulva ÉS csak ha a user nem lapozott
        // kézzel — a mentett órák alapján MÁR a hálózat előtt (a jövő hét a
        // Főoldal / az előző kör előtöltéséből általában megvan), így nincs
        // második, szekvenciális hét-lehúzás.
        if entryOffset == 0, !userHasNavigated, applySmartDay() { syncFromStore() }
        let monday = currentMonday
        let end = KretaWeek.end(of: monday)
        await withTaskGroup(of: Void.self) { group in
            group.addTask { _ = await kreta.fetchTimetableWeek(iss: iss, monday: monday, force: force) }
            group.addTask { _ = await kreta.fetchHomework(iss: iss, force: force) }
            group.addTask { _ = await kreta.fetchExams(iss: iss, force: force) }
            group.addTask { _ = await kreta.fetchCalendarDays(iss: iss, from: monday, to: end, force: force) }
            // Hiányzások a dolgozat-pótláshoz — a többivel párhuzamosan (eddig utánuk, sorban).
            group.addTask { _ = await kreta.fetchAbsences(iss: iss, force: force) }
        }
        syncFromStore()
        // A friss órák fényében még egyszer (pl. a mai utolsó óra időközben
        // véget ért): ha másik hétre ugrik, annak az adata kell.
        if entryOffset == 0, !userHasNavigated, applySmartDay() {
            syncFromStore()
            if currentMonday != monday {
                _ = await kreta.fetchTimetableWeek(iss: iss, monday: currentMonday, force: force)
                syncFromStore()
            }
        }
        // Szomszédos hetek előtöltése a háttérben: lapozáskor azonnal megvan.
        prefetchAdjacentWeeks(iss: iss)
        // Hibasor csak akkor, ha a kijelzett hétről semmi nincs — mentett adat
        // mellett a hét-sáv „Mentve: …" állapota jelzi a sikertelen frissítést.
        if weekKnown {
            loadError = nil
        } else {
            loadError = kreta.sessionExpired
                ? "A KRÉTA-munkamenet lejárt — jelentkezz be újra."
                : "Nem érkezett adat a KRÉTÁ-tól — ellenőrizd a kapcsolatot vagy jelentkezz be újra."
        }
        // Vakáció-visszaszámláló: csak a 0. hétről (lapozáskor nem),
        // a widgetnek az App Groupba.
        if weekOffset == 0 { refreshVacation(iss: iss) }
    }

    /// Az előző és a következő hét előtöltése (a lapozó ±8 hetén belül).
    /// A múlt hét csak akkor megy hálózatra, ha még nincs mentve.
    private func prefetchAdjacentWeeks(iss: String) {
        let base = weekOffset
        let mondays = [base - 1, base + 1].filter { (-8...8).contains($0) }.map { mondayOfWeek(offset: $0) }
        Task {
            await withTaskGroup(of: Void.self) { group in
                for m in mondays {
                    group.addTask { _ = await kreta.fetchTimetableWeek(iss: iss, monday: m) }
                }
            }
        }
    }

    /// Vakáció-info a widgetnek: naptári napok most → aug. 31. (egyetlen,
    /// naponta frissülő, mentett kérés), tanítás nélküli hétköznapok a számoláshoz.
    /// A KRÉTA mellé az iskolai eseménynaptár szünet-napjai is bekerülnek:
    /// Magyarországon a szünet sokszor csak ott szerepel (nyílt titok),
    /// a KRÉTA `NaptariNapok` pedig üres — e nélkül a következő őszi/téli
    /// szünet láthatatlan maradna. Demo/hiba esetén üres lista — a fallback
    /// (jún. 15.) akkor is él. Változatlan eredménynél nincs widget-reload
    /// (VacationCountdown.save).
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
    /// A widget ebből rajzolja a mai / következő tanítási napot. MINDIG a
    /// MOSTANI hét (+ a jövő hétfő) anyagából — a kijelzett hét bármi lehet
    /// (egy hónappal előre lapozva korábban az a hét írta felül a widget
    /// „mai" napját, és ment ki az órára). A közös gyorstárból számol, így
    /// a frissítés helyétől függetlenül ugyanazt adja. Változatlan
    /// tartalomnál nincs írás / reload (TimetableWidgetStore.save).
    /// (A mapping + reload a TimetableWidgetPublish-ban; a BG-ébresztés
    /// ugyanoda mergeli a mai napot.)
    private func publishWidgetSnapshot() {
        let store = KretaStore.shared
        let m0 = mondayOfWeek(offset: 0)
        let m1 = KretaWeek.adding(weeks: 1, to: m0)
        guard let week0 = store.lessons(week: m0) else { return }
        let week1 = store.lessons(week: m1) ?? []
        let cal = Calendar.current
        let nextMondayLessons = week1.filter { cal.isDate($0.start, inSameDayAs: m1) }
        let custom = CustomTasksStore.load()
        let hw = (store.value(.homework) as [HomeworkItem]? ?? []) + CustomTasksStore.homeworkItems(from: custom)
        let rawEx = (store.value(.exams) as [ExamItem]? ?? []) + CustomTasksStore.examItems(from: custom)
        let abs: [AbsenceItem] = store.value(.absences) ?? []
        let twoWeeks = Self.deduped(week0 + week1)
        let ex = ExamRollover.displayItems(exams: rawEx, absences: abs, lessons: twoWeeks).items
        let days = (store.calendarDays(week: m0) ?? []) + (store.calendarDays(week: m1) ?? [])
        let noSchool = TimetableWidgetPublish.noSchoolDays(from: days)
        TimetableWidgetPublish.publishWeek(Self.deduped(week0 + nextMondayLessons), homeworks: hw, exams: ex,
                                           events: schoolEvents, eventsVisible: schoolEventsVisible, noSchoolDays: noSchool)
        // Apple Watch: ugyanez az anyag megy az órára is — a mostani + a jövő
        // hét egyben (egyetlen kevés órás hét önmagában kevés, hétvégén is
        // legyen mit mutatnia), a státusz-flagekkel (felmentett zöld,
        // dolgozat szürke), mint a telefonon.
        WatchSyncSender.pushTimetable(twoWeeks, homeworks: hw, exams: ex, events: schoolEvents, eventsVisible: schoolEventsVisible, noSchoolDays: noSchool)
        // Iskolai események az óra órarend-tetejére (ugyanaz a lista).
        WatchSyncSender.pushSchoolEvents(events: schoolEvents, visible: schoolEventsVisible)
    }
}

// MARK: - Órarendi párosítások (egyszer adatváltozásonként)
/// A kijelzett hét óráihoz tartozó házi, dolgozat (pótlással) és a
/// dolgozatos napok térképe. A számolás napra bontva fut: az ExamMatcher és
/// a HomeworkMatcher is csak azonos napi tételt / órát vesz figyelembe, így
/// az eredmény azonos a soronkénti teljes-lista-szkenneléssel.
struct TimetableDerived {
    struct Input: Equatable {
        var lessons: [LessonItem] = []
        var homeworks: [HomeworkItem] = []
        var exams: [ExamItem] = []
        var absences: [AbsenceItem] = []
    }
    var input = Input()
    var lessonIDs: Set<String> = []
    var displayExams: [ExamItem] = []
    var rolledIDs: Set<String> = []
    var homeworkByLesson: [String: HomeworkItem] = [:]
    var examByLesson: [String: ExamItem] = [:]
    var examDays: [Date: Bool] = [:]

    static func make(lessons: [LessonItem], homeworks: [HomeworkItem], exams: [ExamItem], absences: [AbsenceItem],
                     calendar: Calendar = .current) -> TimetableDerived {
        var d = TimetableDerived()
        d.input = Input(lessons: lessons, homeworks: homeworks, exams: exams, absences: absences)
        d.lessonIDs = Set(lessons.map(\.id))
        let resolved = ExamRollover.displayItems(exams: exams, absences: absences, lessons: lessons)
        d.displayExams = resolved.items
        d.rolledIDs = resolved.rolledIDs
        // Napra bontás, az eredeti sorrendet megtartva (a "first" egyezés így azonos).
        var hwByDay: [Date: [HomeworkItem]] = [:]
        for h in homeworks { hwByDay[calendar.startOfDay(for: h.deadline), default: []].append(h) }
        var exByDay: [Date: [ExamItem]] = [:]
        for e in resolved.items { exByDay[calendar.startOfDay(for: e.date), default: []].append(e) }
        var lessonsByDay: [Date: [LessonItem]] = [:]
        for l in lessons { lessonsByDay[calendar.startOfDay(for: l.start), default: []].append(l) }
        for l in lessons {
            let day = calendar.startOfDay(for: l.start)
            if let hw = hwByDay[day]?.first(where: { SubjectMatcher.same($0.subject, l.subject) }) {
                d.homeworkByLesson[l.id] = hw
            }
            if let dayExams = exByDay[day],
               let e = ExamMatcher.exam(for: l, in: dayExams, calendar: calendar, allLessons: lessonsByDay[day] ?? []) {
                d.examByLesson[l.id] = e
                // Dolgozatos nap: igaz, ha MINDEN aznapi dolgozat átütemezett (piros pötty).
                d.examDays[day] = (d.examDays[day] ?? true) && resolved.rolledIDs.contains(e.id)
            }
        }
        return d
    }
}

// MARK: - Hét-alcím: „Ez a hét" + frissítés-állapot
/// Külön nézet, hogy a store frissítés-állapotának változása csak ezt a
/// sort rajzolja újra, ne a teljes órarendet. Ha a kettő együtt nem fér
/// ki, az állapot nyer (a hónap-cím és a dátumok úgyis mutatják a hetet).
private struct TimetableWeekSubtitle: View {
    let weekTitle: String
    let kinds: [KretaDataKind]

    var body: some View {
        let status = KretaStore.shared.status(for: kinds)
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 4) {
                Text(weekTitle)
                if status != .idle {
                    Text("·").foregroundStyle(.tertiary)
                    KretaRefreshStatusLabel(status: status)
                }
            }
            Group {
                if status == .idle {
                    Text(weekTitle)
                } else {
                    KretaRefreshStatusLabel(status: status)
                }
            }
        }
        // Cyberpunk: apró nagybetűs cián adat-sor („EZ A HÉT").
        .cpOnly { $0.textCase(.uppercase).tracking(1) }
        .cpMono(10)
        .skinFont(.caption2, weight: .medium)
        .foregroundStyle(CyberpunkTheme.isActive ? AnyShapeStyle(CyberpunkTheme.cyan.opacity(0.85)) : AnyShapeStyle(.secondary))
        .lineLimit(1)
        .animation(SummitMotion.gentle, value: status)
    }
}

// MARK: - 0. óra — full-width iskolai esemény (számozott kör nélkül)
private struct SchoolEventCard: View {
    let event: SchoolEvent
    let colors: AppColors
    let scheme: ColorScheme

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            SkinIcon("calendar.badge.clock", size: 32)
                .skinFont(size: 16, weight: .semibold)
                .foregroundStyle(CyberpunkTheme.isActive ? CyberpunkTheme.cyan : colors.accent)
                .padding(.top, 3)
            VStack(alignment: .leading, spacing: 3) {
                Text(CyberpunkTheme.isActive ? "[ ISKOLAI ESEMÉNY ]" : "ISKOLAI ESEMÉNY")
                    .cpMono(10)
                    .skinFont(.caption2, weight: .bold)
                    .tracking(CyberpunkTheme.isActive ? 1 : 0.6)
                    .foregroundStyle(CyberpunkTheme.isActive ? AnyShapeStyle(CyberpunkTheme.cyan) : AnyShapeStyle(.secondary))
                    .cpOnly { $0.accessibilityLabel("Iskolai esemény") }
                Text(event.title)
                    .skinFont(size: 17, weight: .semibold, design: .rounded)
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)
                if !event.subtitle.isEmpty {
                    Text(event.subtitle)
                        .skinFontDigits(.caption, weight: .medium)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
            Spacer(minLength: 8)
        }
        .padding(14)
        .background {
            if MinecraftTheme.isActive {
                McBlockPanel(face: colors.surfaceElevated)
            } else if CyberpunkTheme.isActive {
                CPPanelBackground(accent: CyberpunkTheme.cyan, fill: CyberpunkTheme.panel)
            } else {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(colors.accent.opacity(scheme == .dark ? 0.14 : 0.08))
                    .overlay(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .strokeBorder(colors.accent.opacity(scheme == .dark ? 0.30 : 0.22), lineWidth: 1)
                    )
                    .shadow(color: colors.shadow.opacity(scheme == .dark ? 0.20 : 0.06), radius: 8, y: 3)
            }
        }
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
    /// Háttér-frissítésből felismert, még nem látott változás (kék jelölés).
    var change: LessonChange? = nil
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
    /// Minecraftban a sor állapot-színe a tömör panelre rétegezve
    /// (a kártya sosem áttetsző); nil = sima felület.
    private var rowTint: Color? {
        if isExempted { return Color.green.opacity(0.28) }
        if isCancelled { return Color.red.opacity(0.28) }
        if isSubstituted { return Color.orange.opacity(0.28) }
        if isCurrent { return Color.blue.opacity(0.28) }
        if hasAssignment { return scheme == .dark ? Color.white.opacity(0.14) : Color.black.opacity(0.07) }
        return nil
    }
    /// Cyberpunk állapot-szín (HUD-paletta): felmentett = zöld, elmarad =
    /// HUD-vörös, helyettesítés = sárga, most = cián, feladat = törtfehér.
    private var cpTint: Color? {
        if isExempted { return CyberpunkTheme.green }
        if isCancelled { return CyberpunkTheme.red }
        if isSubstituted { return CyberpunkTheme.yellow }
        if isCurrent { return CyberpunkTheme.cyan }
        if hasAssignment { return CyberpunkTheme.text }
        return nil
    }
    private var numberColor: Color {
        if CyberpunkTheme.isActive { return cpTint ?? CyberpunkTheme.dim }
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
        if CyberpunkTheme.isActive {
            if isExempted { return CyberpunkTheme.green }
            if isCancelled { return CyberpunkTheme.red }
            return CyberpunkTheme.yellow
        }
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
                                // Az állapot (most / elmarad / helyettesítés) a tömör
                                // panelre rétegzett színnel látszik, nem üveg-tintként.
                                McTintedPanel(base: colors.surface, tint: ringTint?.opacity(0.32), castsShadow: false)
                            } else if CyberpunkTheme.isActive {
                                CPLessonNumberTile(tint: cpTint)
                            } else if #available(iOS 26.0, *) {
                                Circle()
                                    .fill(Color.clear)
                                    .glassEffect(
                                        isTintedGlass
                                            ? .regular.tint((ringTint ?? colors.accent).opacity(scheme == .dark ? (hasAssignment ? 0.22 : isCurrent ? 0.18 : 0.12) : (hasAssignment ? 0.18 : isCurrent ? 0.14 : 0.09)))
                                            : .regular.tint(Color.white.opacity(scheme == .dark ? 0.06 : 0.04)),
                                        in: .circle
                                    )
                            } else {
                                Circle()
                                    .fill(isTintedGlass ? (ringTint ?? colors.accent).opacity(scheme == .dark ? 0.10 : 0.08) : Color.primary.opacity(scheme == .dark ? 0.08 : 0.07))
                                    .overlay(Circle().fill(.ultraThinMaterial).opacity(isTintedGlass ? 0.35 : 0.82))
                            }
                        }
                    }
                    .shadow(color: MinecraftTheme.isActive || CyberpunkTheme.isActive ? Color.clear : (ringTint ?? Color.clear).opacity(isTintedGlass ? (scheme == .dark ? 0.14 : 0.08) : 0), radius: MinecraftTheme.isActive ? 0 : 6, y: MinecraftTheme.isActive ? 0 : 2)

                // Spine — vékony editorial vonal a következő körig
                // (Minecraftban 1 játék-pixel vastag, kemény vonal).
                if !isLast {
                    Rectangle()
                        .fill(MinecraftTheme.isActive ? Color(hex: 0x555555)
                              : CyberpunkTheme.isActive ? CyberpunkTheme.yellow.opacity(0.3)
                              : Color.primary.opacity(scheme == .dark ? 0.09 : 0.07))
                        .frame(width: MinecraftTheme.isActive ? MinecraftTheme.px : CyberpunkTheme.isActive ? 1 : 1.2)
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
                Button(action: openDetail) {
                    HStack(alignment: .top, spacing: 10) {
                        VStack(alignment: .leading, spacing: 4) {
                        // Badge row — felmentett is zöld, elmarad piros, helyettesítés narancs;
                        // mellette a friss változás kék jelölése („Új", „Teremcsere"…).
                        if badgeLabel != nil || change != nil {
                            HStack(spacing: 5) {
                                if let lbl = badgeLabel {
                                    Text(lbl.uppercased())
                                        .cpMono(10)
                                        .skinFont(.caption2, weight: .bold)
                                        .tracking(CyberpunkTheme.isActive ? 1 : 0.5)
                                        .foregroundStyle(CyberpunkTheme.isActive ? Color.black : .white)
                                        .padding(.horizontal, 7).padding(.vertical, 3.5)
                                        .background(MinecraftTheme.capsule.fill(badgeColor))
                                }
                                if let change {
                                    Text(change.markerTitle.uppercased())
                                        .cpMono(10)
                                        .skinFont(.caption2, weight: .bold)
                                        .tracking(CyberpunkTheme.isActive ? 1 : 0.5)
                                        .foregroundStyle(CyberpunkTheme.isActive ? Color.black : .white)
                                        .padding(.horizontal, 7).padding(.vertical, 3.5)
                                        .background(MinecraftTheme.capsule.fill(CyberpunkTheme.isActive ? CyberpunkTheme.cyan : Color.blue))
                                        .accessibilityLabel("Változás: \(change.markerTitle)")
                                }
                            }
                        }

                        Text(lesson.subject)
                            .skinFont(size: 17, weight: .semibold, design: .rounded)
                            .foregroundStyle((isCancelled || isExempted) ? .secondary : .primary)
                            .strikethrough(isCancelled || isExempted, color: .secondary)
                            .lineLimit(1)

                        HStack(spacing: 6) {
                            // Room — kis kocka, ikon nélkül, csak a terem neve
                            TimetableRoomChip(room: lesson.room, scheme: scheme)

                            Text(CyberpunkTheme.isActive ? "//" : "•").cpMono(10).skinFont(.caption2).foregroundStyle(.tertiary)
                            Text(lesson.teacher)
                                .skinFont(.caption, weight: .medium)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }

                        }
                    Spacer(minLength: 8)
                    // Time — editorial stacked
                    VStack(alignment: .trailing, spacing: 1) {
                        Text(lesson.start.formatted(date: .omitted, time: .shortened))
                            .cpMono(13, relativeTo: .footnote)
                            .skinFontDigits(size: 13, weight: .semibold, design: .rounded)
                            .foregroundStyle(isCurrent ? (CyberpunkTheme.isActive ? CyberpunkTheme.cyan : Color.blue)
                                             : (CyberpunkTheme.isActive ? CyberpunkTheme.yellow : .primary))
                        Text(lesson.end.formatted(date: .omitted, time: .shortened))
                            .cpMono(10)
                            .skinFontDigits(.caption2, weight: .medium)
                            .foregroundStyle(.tertiary)
                    }
                    }
                    // Teljes fejléc-felület koppintható (a Spacer-rés és a
                    // rövid sorok melletti üres hely is), nem csak a szövegek.
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("lesson-row-\(lesson.id)")
                .accessibilityLabel("\(lesson.subject), \(lesson.index). óra" + (change.map { ", változás: \($0.markerTitle)" } ?? ""))
                // Feladat pill — a fejléc alatt, tap → Feladatok tab
                if let hw = homework {
                    Button {
                        McSound.play(.click)
                        NotificationCenter.default.post(name: Notification.Name("summit.switchToTasks"), object: nil, userInfo: ["flash": hw.id])
                    } label: {
                        HStack(spacing: 4) {
                            SkinIcon("checklist", size: 16)
                                .skinFont(.caption2, weight: .semibold)
                            Text(hw.plainTitle.isEmpty ? "Házi feladat" : hw.plainTitle)
                                .skinFont(.caption, weight: .medium)
                                .lineLimit(1)
                        }
                        .foregroundStyle(scheme == .dark ? Color.white.opacity(0.92) : Color.black.opacity(0.72))
                        .padding(.horizontal, MinecraftTheme.isActive ? 10 : 8).padding(.vertical, MinecraftTheme.isActive ? 8 : 5)
                        .background {
                            if MinecraftTheme.isActive {
                                McTintedPanel(base: colors.surface, tint: nil, castsShadow: false)
                            } else if CyberpunkTheme.isActive {
                                CPChamferShape(cut: 6, corners: .diagonal).fill(CyberpunkTheme.panelRaised)
                                    .overlay(CPChamferShape(cut: 6, corners: .diagonal)
                                        .strokeBorder(CyberpunkTheme.cyan.opacity(0.55), lineWidth: 1))
                            } else {
                                Capsule()
                                    .fill(scheme == .dark ? Color.white.opacity(0.14) : Color.black.opacity(0.06))
                                    .overlay(Capsule().strokeBorder(Color.primary.opacity(scheme == .dark ? 0.12 : 0.08), lineWidth: 1))
                            }
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Házi feladat – \(hw.subject)")
                    .padding(.top, 2)
                }
                // Dolgozat pill — tap → Feladatok/Dolgozatok tab
                if let ex = exam {
                    Button {
                        McSound.play(.click)
                        NotificationCenter.default.post(name: Notification.Name("summit.switchToTasks"), object: nil, userInfo: ["segment": "exams", "flash": ex.id])
                    } label: {
                        HStack(spacing: 4) {
                            SkinIcon("doc.text.fill", size: 16)
                                .skinFont(.caption2, weight: .semibold)
                            Text(ex.plainDescription.isEmpty ? ex.mode : "\(ex.mode): \(ex.plainDescription)")
                                .skinFont(.caption, weight: .medium)
                                .lineLimit(1)
                        }
                        .foregroundStyle(scheme == .dark ? Color.white.opacity(0.92) : Color.black.opacity(0.72))
                        .padding(.horizontal, MinecraftTheme.isActive ? 10 : 8).padding(.vertical, MinecraftTheme.isActive ? 8 : 5)
                        .background {
                            if MinecraftTheme.isActive {
                                McTintedPanel(base: colors.surface, tint: (examRolled ? Color.red : Color.orange).opacity(0.30), castsShadow: false)
                            } else if CyberpunkTheme.isActive {
                                let c = examRolled ? CyberpunkTheme.red : CyberpunkTheme.yellow
                                CPChamferShape(cut: 6, corners: .diagonal).fill(CyberpunkTheme.panelRaised)
                                    .overlay(CPChamferShape(cut: 6, corners: .diagonal).fill(c.opacity(0.10)))
                                    .overlay(CPChamferShape(cut: 6, corners: .diagonal).strokeBorder(c.opacity(0.75), lineWidth: 1))
                            } else {
                                Capsule()
                                    .fill((examRolled ? Color.red : Color.orange).opacity(scheme == .dark ? 0.22 : 0.14))
                                    .overlay(Capsule().strokeBorder((examRolled ? Color.red : Color.orange).opacity(scheme == .dark ? 0.35 : 0.25), lineWidth: 1))
                            }
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Dolgozat – \(ex.subject): \(ex.mode)")
                    .padding(.top, 2)
                }

                // Current progress — követi a kiemelőszínt (accent)
                if isCurrent {
                    TimetableLiquidProgress(
                        progress: progress,
                        tint: CyberpunkTheme.isActive ? (cpTint ?? CyberpunkTheme.cyan)
                            : isCancelled ? Color.red : isSubstituted ? Color.orange : colors.accent,
                        remainingText: remainingText,
                        scheme: scheme,
                        colors: colors
                    )
                    .padding(.top, 10)
                }
            }
            .padding(14)
            .background {
                if MinecraftTheme.isActive {
                    McTintedPanel(base: colors.surface, tint: rowTint)
                } else if CyberpunkTheme.isActive {
                    CPLessonCardBackground(tint: cpTint, isCurrent: isCurrent)
                } else {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(rowBackground)
                        .overlay(
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .strokeBorder(Color.primary.opacity(scheme == .dark ? 0.08 : 0.06), lineWidth: 1)
                        )
                        .shadow(color: colors.shadow.opacity(isCurrent ? 0.18 : scheme == .dark ? 0.20 : 0.06), radius: isCurrent ? 12 : 8, y: isCurrent ? 5 : 3)
                }
            }
            .overlay {
                if MinecraftTheme.isActive {
                    // Deeplink-villanás: sárga, kemény pixelkeret (a játék kijelölés-sárgája).
                    McPixelShape(steps: 2)
                        .strokeBorder(Color(hex: 0xFFFF55).opacity(isFlashing ? (flashPulse ? 0.95 : 0.22) : 0), lineWidth: isFlashing ? MinecraftTheme.px : 0)
                } else if CyberpunkTheme.isActive {
                    // Deeplink-villanás: sárga HUD-keret pulzál (nagyítás nélkül).
                    CPChamferShape(cut: 12, corners: .diagonal)
                        .strokeBorder(CyberpunkTheme.yellow.opacity(isFlashing ? (flashPulse ? 0.95 : 0.22) : 0), lineWidth: isFlashing ? 2 : 0)
                } else {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .strokeBorder(colors.accent.opacity(isFlashing ? (flashPulse ? 0.95 : 0.22) : 0), lineWidth: isFlashing ? 2.2 : 0)
                }
            }
            .background {
                if MinecraftTheme.isActive {
                    McPixelShape(steps: 2)
                        .fill(Color(hex: 0xFFFF55).opacity(isFlashing ? (flashPulse ? 0.18 : 0.04) : 0))
                } else if CyberpunkTheme.isActive {
                    CPChamferShape(cut: 12, corners: .diagonal)
                        .fill(CyberpunkTheme.yellow.opacity(isFlashing ? (flashPulse ? 0.14 : 0.03) : 0))
                } else {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(colors.accent.opacity(isFlashing ? (flashPulse ? 0.18 : 0.04) : 0))
                }
            }
            // Minecraftban nincs sima nagyítás (a pixelek nem skálázódnak törtre).
            .scaleEffect(isFlashing && flashPulse && !MinecraftTheme.isActive && !CyberpunkTheme.isActive ? 1.02 : 1.0)
            .animation(isFlashing ? .easeInOut(duration: 0.45) : .default, value: flashPulse)
            // bal csík nincs — kompakt
            .padding(.leading, 0)
        }
        .padding(.horizontal, 0)
        // Az egész kártya (14 pt-os margó, óraszám-kör, üres sávok) nyitja a
        // részletet. A fejléc-gomb és a házi/dolgozat-pillek saját gombok —
        // a gyermek-gomb mindig nyer, így azok a saját céljukra visznek.
        // Eddig csak a szövegek pixelei voltak koppinthatók: „többször kell
        // rányomni, mire megnyílik".
        .contentShape(Rectangle())
        .onTapGesture(perform: openDetail)
    }

    /// Részletező megnyitása (fejléc-gomb és a kártya többi felülete).
    /// A gomb `.plain`, így a Minecraft-kattanás innen jön (egy forrás).
    private func openDetail() {
        McSound.play(.click)
        onSelect()
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
            SkinProgressBar(value: progress, tint: tint)
                .animation(SummitMotion.progress, value: progress)
            Text(remainingText)
                .cpOnly { $0.textCase(.uppercase).tracking(1) }
                .cpMono(10)
                .skinFont(.caption2, weight: .medium).foregroundStyle(.secondary).monospacedDigit()
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
    /// Friss (még nem / épp most látott) óra-változás — a „Változás" sorhoz.
    var change: LessonChange? = nil
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
        if CyberpunkTheme.isActive {
            if isExempted { return CyberpunkTheme.green }
            if isCancelled { return CyberpunkTheme.red }
            if isSubstituted { return CyberpunkTheme.yellow }
            if isCurrent { return CyberpunkTheme.cyan }
            return CyberpunkTheme.yellow
        }
        if isExempted { return .green }
        if isCancelled { return .red }
        if isSubstituted { return .orange }
        if isCurrent { return .blue }
        return colors.accent
    }

    private var statusBadge: (text: String, color: Color)? {
        if CyberpunkTheme.isActive {
            if isExempted { return ("Felmentett", CyberpunkTheme.green) }
            if isCancelled { return ("Elmarad", CyberpunkTheme.red) }
            if isSubstituted { return ("Helyettesítés", CyberpunkTheme.yellow) }
            if isCurrent { return ("Most", CyberpunkTheme.cyan) }
            return nil
        }
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

    /// Cyberpunk kód-sor a hero alatt: „[ CSÜTÖRTÖK // OKT 23. ]".
    private var cpDayCode: String {
        let f = DateFormatter(); f.locale = Locale(identifier: "hu_HU"); f.dateFormat = "EEEE // MMM d."
        return "[ \(f.string(from: lesson.start).uppercased()) ]"
    }
    /// „[ 7:45–8:30 // 1. ÓRA ]".
    private var cpTimeCode: String {
        let t = DateFormatter(); t.locale = Locale(identifier: "hu_HU"); t.dateFormat = "H:mm"
        return "[ \(t.string(from: lesson.start))–\(t.string(from: lesson.end)) // \(lesson.index). ÓRA ]"
    }

    var body: some View {
        NavigationStack {
            List {
                // HERO — gradiens ikon + tárgy + nap/idő + státusz
                Section {
                    VStack(spacing: 12) {
                        SkinIcon(LessonSubjectIcon.symbol(for: lesson.subject), size: 64)
                            .skinFont(size: 44, weight: .semibold)
                            .foregroundStyle(CyberpunkTheme.isActive ? heroBase : .white)
                            .frame(width: 104, height: 104)
                            .background {
                                if MinecraftTheme.isActive {
                                    // Inventory-rekesz, az óra állapotának színével átitatva.
                                    McTintedPanel(base: Color(hex: 0x8B8B8B), tint: heroBase.opacity(0.40), slot: true, castsShadow: false)
                                } else if CyberpunkTheme.isActive {
                                    // HUD-lapka az óra állapot-színében (statikus).
                                    CPChamferShape(cut: 18, corners: .diagonal).fill(CyberpunkTheme.panel)
                                        .overlay(CPChamferShape(cut: 18, corners: .diagonal).fill(heroBase.opacity(0.14)))
                                        .overlay(CPChamferShape(cut: 18, corners: .diagonal).strokeBorder(heroBase, lineWidth: 1))
                                } else {
                                    Circle()
                                        .fill(
                                            LinearGradient(
                                                colors: [heroBase, heroBase.opacity(0.55)],
                                                startPoint: .topLeading, endPoint: .bottomTrailing
                                            )
                                        )
                                        .shadow(color: heroBase.opacity(0.35), radius: 18, y: 8)
                                }
                            }
                        Text(lesson.subject)
                            .mcDisplay(26)
                            .foregroundStyle((isCancelled || isExempted) ? .secondary : .primary)
                            .strikethrough(isCancelled || isExempted, color: .secondary)
                            .multilineTextAlignment(.center)
                            // Kiemelt cím: halvány, statikus kromatikus szellemkép.
                            .cpOnly { $0.cpChromatic(1) }
                        Text(CyberpunkTheme.isActive ? cpDayCode : dayLine)
                            .cpMono(12, relativeTo: .subheadline)
                            .skinFont(.subheadline, weight: .semibold)
                            .foregroundStyle(CyberpunkTheme.isActive ? AnyShapeStyle(CyberpunkTheme.cyan) : AnyShapeStyle(.secondary))
                            .cpOnly { $0.accessibilityLabel(dayLine) }
                        Text(CyberpunkTheme.isActive ? cpTimeCode : timeLine)
                            .cpMono(12, relativeTo: .subheadline)
                            .skinFontDigits(.subheadline, weight: .medium)
                            .foregroundStyle(CyberpunkTheme.isActive ? AnyShapeStyle(CyberpunkTheme.dim) : AnyShapeStyle(.secondary))
                            .cpOnly { $0.accessibilityLabel(timeLine) }
                        if let badge = statusBadge {
                            Text(badge.text.uppercased())
                                .cpMono(11)
                                .skinFont(.caption2, weight: .bold)
                                .tracking(CyberpunkTheme.isActive ? 1.2 : 0.5)
                                .foregroundStyle(CyberpunkTheme.isActive ? Color.black : .white)
                                .padding(.horizontal, 10).padding(.vertical, 5)
                                .background(MinecraftTheme.capsule.fill(badge.color))
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                }

                // ÓRA ADATAI
                Section {
                    detailRow(icon: "person.fill", title: "Tanár", value: lesson.teacher.isEmpty ? "—" : lesson.teacher)
                        .mcListRow(fill: colors.surface)
                    if isSubstituted, let orig = lesson.originalTeacher, !orig.isEmpty {
                        detailRow(icon: "person.fill.badge.plus", title: "Eredeti tanár", value: orig)
                            .mcListRow(fill: colors.surface)
                    }
                    detailRow(icon: "door.left.hand.open", title: "Terem", value: lesson.room.isEmpty ? "—" : lesson.room)
                        .mcListRow(fill: colors.surface)
                    if let change {
                        detailRow(icon: "arrow.triangle.2.circlepath", title: "Változás",
                                  value: change.kind == .added ? change.markerTitle : change.detail)
                            .mcListRow(fill: colors.surface)
                    }
                    detailRow(icon: "clock.fill", title: "Időpont", value: timeLine)
                        .mcListRow(fill: colors.surface)
                } header: { sectionTitle("Óra adatai", code: "01") }

                // HÁZI
                Section {
                    if let hw = homework {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(HomeworkHTML.formatted(hw.title))
                                .skinFont(.callout)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            if !hw.teacher.isEmpty {
                                SkinLabel(hw.teacher, systemImage: "person.fill")
                                    .skinFont(.caption).foregroundStyle(.secondary)
                            }
                            Button { openTasks(flash: hw.id) } label: {
                                TimetableOpenLabel(title: "Megnyitás a Feladatokban", icon: "checklist", colors: colors)
                            }
                            .mcButtonOrPlain(compact: false)
                            .padding(.top, 2)
                        }
                        .padding(.vertical, 4)
                        .mcListRow(fill: colors.surface)
                    } else {
                        SkinLabel("Ehhez az órához nincs házi", systemImage: "checklist")
                            .skinFont(.callout).foregroundStyle(.secondary)
                            .mcListRow(fill: colors.surface)
                    }
                } header: { sectionTitle("Házi feladat", code: "02") }

                // DOLGOZAT
                Section {
                    if let ex = exam {
                        VStack(alignment: .leading, spacing: 6) {
                            HStack(spacing: 6) {
                                Text(ex.mode).skinFont(.callout, weight: .semibold)
                                if examRolled {
                                    Text("Pótló").skinFont(.caption2, weight: .bold).foregroundStyle(CyberpunkTheme.isActive ? CyberpunkTheme.red : .red)
                                        .padding(.horizontal, 8).padding(.vertical, 4)
                                        .background(MinecraftTheme.capsule.fill(Color.red.opacity(0.12)))
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            if !ex.plainDescription.isEmpty {
                                Text(ex.plainDescription)
                                    .skinFont(.callout).foregroundStyle(.secondary)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            if !ex.teacher.isEmpty {
                                SkinLabel(ex.teacher, systemImage: "person.fill")
                                    .skinFont(.caption).foregroundStyle(.secondary)
                            }
                            Button { openTasks(segment: "exams", flash: ex.id) } label: {
                                TimetableOpenLabel(title: "Megnyitás a Dolgozatokban", icon: "doc.text.fill", colors: colors)
                            }
                            .mcButtonOrPlain(compact: false)
                            .padding(.top, 2)
                        }
                        .padding(.vertical, 4)
                        .mcListRow(fill: colors.surface)
                    } else {
                        SkinLabel("Ehhez az órához nincs dolgozat", systemImage: "doc.text")
                            .skinFont(.callout).foregroundStyle(.secondary)
                            .mcListRow(fill: colors.surface)
                    }
                } header: { sectionTitle("Dolgozat", code: "03") }
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
                        .skinToolbarItem()
                }
                .skinToolbarBackground()
            }
            .accessibilityIdentifier("lesson-detail")
        }
        .tint(colors.accent)
    }

    /// Szekció-fejléc: Summitban a gyári `Section("…")` felirat, Minecraftban pixelbetű.
    @ViewBuilder
    private func sectionTitle(_ text: String, code: String? = nil) -> some View {
        if MinecraftTheme.isActive {
            Text(text).mcSectionHeader()
        } else if CyberpunkTheme.isActive {
            // HUD-szekciófej: akcent-négyzet + cím + vonal + „// 01".
            CPSectionHeader(text, code: code, accent: CyberpunkTheme.yellow)
        } else {
            Text(text)
        }
    }

    private func detailRow(icon: String, title: String, value: String) -> some View {
        HStack(spacing: 10) {
            SkinIcon(icon, size: 32)
                .skinFont(size: 14, weight: .semibold)
                .foregroundStyle(CyberpunkTheme.isActive ? CyberpunkTheme.cyan : colors.accent)
                .frame(width: MinecraftTheme.isActive ? 32 : 24)
            Text(title)
                .cpOnly { $0.textCase(.uppercase).tracking(1) }
                .cpMono(11, relativeTo: .callout)
                .skinFont(.callout)
                .foregroundStyle(CyberpunkTheme.isActive ? AnyShapeStyle(CyberpunkTheme.dim) : AnyShapeStyle(.secondary))
            Spacer(minLength: 8)
            Text(value)
                .skinFont(.callout, weight: .semibold)
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


// MARK: - Minecraft-segédek (az órarendi nézetekhez)

/// Tömör panel az állapot-színnel átitatva: az alap (felület) opak marad,
/// a szín rá van rétegezve — a McBlockPanel áttetsző `face`-e különben
/// átengedné a mögötte lévő égboltot a tintelt kártyán.
private struct McTintedPanel: View {
    var base: Color
    var tint: Color?
    /// Inventory-rekesz (fordított bevel) a sima panel helyett.
    var slot = false
    var castsShadow = true

    var body: some View {
        ZStack {
            panel(face: base, casts: castsShadow)
            if let tint {
                panel(face: tint, casts: false)
            }
        }
    }

    @ViewBuilder
    private func panel(face: Color, casts: Bool) -> some View {
        if slot {
            McBlockPanel(face: face, outline: Color(hex: 0x373737),
                         highlight: .black.opacity(0.28), shade: .white.opacity(0.55), castsShadow: casts)
        } else {
            McBlockPanel(face: face, castsShadow: casts)
        }
    }
}

/// Terem-címke: Summitban a halvány lekerekített kocka, Minecraftban
/// inventory-rekesz fehér, árnyékolt Monocraft felirattal.
private struct TimetableRoomChip: View {
    let room: String
    let scheme: ColorScheme

    var body: some View {
        if MinecraftTheme.isActive {
            Text(room)
                .skinFontDigits(.caption2, weight: .bold)
                .foregroundStyle(.white)
                .shadow(color: Color(hex: 0x3F3F3F), radius: 0, x: MinecraftTheme.px / 1.5, y: MinecraftTheme.px / 1.5)
                .padding(.horizontal, 10).padding(.vertical, 7)
                .background(McInventorySlot())
                .lineLimit(1)
        } else if CyberpunkTheme.isActive {
            // Cyberpunk: egyenközű cián terem-kód, levágott sarkú vékony keretben.
            Text(room)
                .font(CyberpunkTheme.mono(size: 11, relativeTo: .caption2))
                .foregroundStyle(CyberpunkTheme.cyan)
                .padding(.horizontal, 6).padding(.vertical, 3)
                .background(CPChamferShape(cut: 4, corners: .diagonal).fill(CyberpunkTheme.cyan.opacity(0.06)))
                .overlay(CPChamferShape(cut: 4, corners: .diagonal).strokeBorder(CyberpunkTheme.cyan.opacity(0.55), lineWidth: 1))
                .lineLimit(1)
        } else {
            Text(room)
                .font(.caption2.weight(.bold).monospacedDigit())
                .foregroundStyle(.secondary)
                .padding(.horizontal, 7).padding(.vertical, 4)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(Color.primary.opacity(scheme == .dark ? 0.08 : 0.06))
                        .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).strokeBorder(Color.primary.opacity(0.06), lineWidth: 1))
                )
                .lineLimit(1)
        }
    }
}

/// „Megnyitás a …ban" gomb felirata: Summitban az accent-körvonalas
/// kapszula, Minecraftban a sima felirat (a gombot a McButtonStyle rajzolja).
private struct TimetableOpenLabel: View {
    let title: String
    let icon: String
    let colors: AppColors

    var body: some View {
        if MinecraftTheme.isActive {
            SkinLabel(title, systemImage: icon)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        } else if CyberpunkTheme.isActive {
            // Cyberpunk: cián, levágott sarkú HUD-gomb-felirat (a gomb maga
            // `.skinPlain`, az kattan).
            Label(title, systemImage: icon)
                .font(CyberpunkTheme.font(.subheadline, weight: .bold))
                .textCase(.uppercase)
                .tracking(1)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .foregroundStyle(CyberpunkTheme.cyan)
                .padding(.horizontal, 12).padding(.vertical, 8)
                .background(CPChamferShape(cut: 6, corners: .diagonal).fill(CyberpunkTheme.cyan.opacity(0.06)))
                .overlay(CPChamferShape(cut: 6, corners: .diagonal).strokeBorder(CyberpunkTheme.cyan.opacity(0.85), lineWidth: 1))
                .contentShape(CPChamferShape(cut: 6, corners: .diagonal))
        } else {
            Label(title, systemImage: icon)
                .font(.caption.weight(.semibold))
                .foregroundStyle(colors.accent)
                .padding(.horizontal, 12).padding(.vertical, 8)
                .background(Capsule().strokeBorder(colors.accent.opacity(0.35), lineWidth: 1))
        }
    }
}

/// Üres nap: Summitban a gyári `ContentUnavailableView`, Minecraftban
/// item-ikon + Monocraft cím és leírás (a rendszer-nézet SF-ikont és
/// rendszerbetűt rajzolna).
private struct TimetableEmptyState: View {
    let title: String
    let icon: String
    let detail: String

    var body: some View {
        if MinecraftTheme.isActive {
            VStack(spacing: 12) {
                SkinIcon(icon, size: 64)
                Text(title)
                    .font(MinecraftTheme.font(.title3))
                    .multilineTextAlignment(.center)
                Text(detail)
                    .font(MinecraftTheme.font(.subheadline))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .accessibilityElement(children: .combine)
        } else if CyberpunkTheme.isActive {
            // Cyberpunk: HUD-„nincs adat" blokk — kód-címke, nagybetűs cím,
            // halvány leírás, rövid sárga vonal.
            VStack(spacing: 10) {
                CPLabel("NO_DATA // NAP", color: CyberpunkTheme.yellow)
                Text(title)
                    .font(CyberpunkTheme.font(.title3))
                    .textCase(.uppercase)
                    .tracking(1.4)
                    .foregroundStyle(CyberpunkTheme.text)
                    .multilineTextAlignment(.center)
                Text(detail)
                    .font(CyberpunkTheme.font(.subheadline, weight: .medium))
                    .foregroundStyle(CyberpunkTheme.dim)
                    .multilineTextAlignment(.center)
                Rectangle().fill(CyberpunkTheme.yellow).frame(width: 28, height: 2)
                    .accessibilityHidden(true)
            }
            .accessibilityElement(children: .combine)
        } else {
            ContentUnavailableView(title, systemImage: icon, description: Text(detail))
        }
    }
}

private extension View {
    /// Heti lapozó gombjai: Summitban `.plain`, Minecraftban kompakt kő-gomb.
    @ViewBuilder
    func mcCompactOrPlainButton() -> some View {
        if MinecraftTheme.isActive {
            self.buttonStyle(McButtonStyle(compact: true))
        } else if CyberpunkTheme.isActive {
            // Cyberpunk: kompakt, cián körvonalas HUD-gomb.
            self.buttonStyle(CPButtonStyle(kind: .secondary, compact: true))
        } else {
            self.buttonStyle(.plain)
        }
    }

    /// Csak Minecraftban kő-gomb stílus (Summitban a gombnak nincs explicit stílusa).
    @ViewBuilder
    func mcCompactButtonIfActive() -> some View {
        if MinecraftTheme.isActive {
            self.buttonStyle(McButtonStyle(compact: true))
        } else if CyberpunkTheme.isActive {
            // Cyberpunk: kompakt sárga fő HUD-gomb („MA").
            self.buttonStyle(CPButtonStyle(kind: .primary, compact: true))
        } else {
            self
        }
    }
}

// MARK: - Cyberpunk-segédek (az órarendi nézetekhez)

private extension View {
    /// Csak Cyberpunk-skinben alkalmazott módosítás (Summit/Minecraft
    /// alatt a nézet érintetlen). Egyetlen if-szint — mély elágazás-lánc
    /// helyett (lásd dcfe1eb: túl mély nézet-típus a készüléken).
    @ViewBuilder
    func cpOnly<V: View>(_ transform: (Self) -> V) -> some View {
        if CyberpunkTheme.isActive { transform(self) } else { self }
    }

    /// Csak Cyberpunkon KÍVÜL alkalmazott módosítás (pl. a HUD-gomb
    /// saját színét ne írja felül a felirat explicit színe).
    @ViewBuilder
    func unlessCP<V: View>(_ transform: (Self) -> V) -> some View {
        if CyberpunkTheme.isActive { self } else { transform(self) }
    }

    /// Cyberpunkban apró egyenközű HUD-betű (IBM Plex Mono), máshol
    /// semmi. A KÜLSŐ `skinFont`/`mcDisplay` elé (belülre) kell tenni:
    /// a környezeti betűt alakítja át, így Summitban/Minecraftban a
    /// külső betű változatlanul érvényes.
    func cpMono(_ size: CGFloat, relativeTo style: Font.TextStyle = .caption2) -> some View {
        transformEnvironment(\.font) { font in
            if CyberpunkTheme.isActive { font = CyberpunkTheme.mono(size: size, relativeTo: style) }
        }
    }
}

/// Cyberpunk óra-szám lapka: levágott sarkú opak négyzet, az állapot
/// színében halvány töltés + 1 px-es keret (nil = halvány semleges).
private struct CPLessonNumberTile: View {
    var tint: Color?
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        let shape = CPChamferShape(cut: 7, corners: .diagonal)
        let edge = tint ?? CyberpunkTheme.text.opacity(0.22)
        shape.fill(CyberpunkTheme.panel)
            .overlay(shape.fill((tint ?? .clear).opacity(0.14)))
            .overlay(shape.strokeBorder(edge.opacity(contrast == .increased ? 1 : 0.8), lineWidth: 1))
    }
}

/// Cyberpunk órakártya-háttér: opak panel levágott sarokkal, 1 px-es
/// keret az állapot színében, aktív állapotnál 3 pt-os bal akcent-csík
/// és halvány színes töltés. Statikus (nincs per-frame rajzolás).
private struct CPLessonCardBackground: View {
    var tint: Color?
    var isCurrent: Bool
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        let shape = CPChamferShape(cut: 12, corners: .diagonal)
        let hi = contrast == .increased
        let edge = tint ?? CyberpunkTheme.text.opacity(0.16)
        shape.fill(isCurrent ? CyberpunkTheme.panelRaised : CyberpunkTheme.panel)
            .overlay(shape.fill((tint ?? .clear).opacity(0.07)))
            .overlay(alignment: .leading) {
                if let tint {
                    Rectangle().fill(tint).frame(width: 3)
                        .padding(.vertical, 12)
                }
            }
            .overlay(shape.strokeBorder(edge.opacity(hi ? 1 : (tint == nil ? 1 : 0.7)), lineWidth: hi ? 1.5 : 1))
            .accessibilityHidden(true)
    }
}

