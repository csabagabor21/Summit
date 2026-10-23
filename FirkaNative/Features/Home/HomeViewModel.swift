import Foundation
import SwiftUI

@MainActor
final class HomeViewModel: ObservableObject {
    @Published var selectedTab = 0
    @Published var liveState: LiveCardState = .morning
    @Published var isRefreshing = false

    // Real data — a közös gyorstárból (KretaStore) származtatva, így az
    // első képkocka már a mentett adatot mutatja, a frissítés pedig
    // adattípusonként, a beérkezés sorrendjében íródik be.
    @Published var grades: [GradeItem] = []
    @Published var lessonsToday: [LessonItem] = []
    @Published var homeworks: [HomeworkItem] = []
    @Published var absences: [AbsenceItem] = []
    @Published var messages: [MessageItem] = []
    /// Kijelzett dolgozatok (átütemezéssel: a hiányzás napján lévő dolgozat
    /// a következő olyan órán, azonos ID-val).
    @Published var exams: [ExamItem] = []
    /// Piros háttérhez: átütemezett dolgozat-ID-k + eredeti dátumok.
    @Published var rolledExamIDs: Set<String> = []
    @Published var originalExamDates: [String: Date] = [:]
    @Published var error: String?

    /// Ismert-e már az adott típus (van mentett vagy friss adat). Amíg nem,
    /// a Főoldal NEM mutat üres állapotot („Nincs jegy", „Ma nincs több
    /// órád") — az adat még csak töltődik, nem üres.
    @Published var gradesKnown = false
    @Published var homeworksKnown = false
    @Published var examsKnown = false
    @Published var lessonsKnown = false

    /// Nyers dolgozatok + pótló-kereséshez használt órák (hálózat nélkül
    /// újraszámolható a kapcsoló/elvetés után).
    private var rawExamsAll: [ExamItem] = []
    private var rolloverLessons: [LessonItem] = []
    /// A legutóbbi mellékhatás-kör (értesítés-diff, Watch-, widget-push)
    /// bemenetének mentési idői — csak ÚJ adatra futnak le, a puszta
    /// tabváltás / gyorstár-találat nem tolja újra az órára ugyanazt.
    private var sideEffectStamps: [KretaDataKind: Date] = [:]

    init() {
        reload()
        // Az indításkor a lemezről jött adat már átment a diffen és az
        // órán — a mellékhatások csak az ezutáni, hálózati frissítésekre futnak.
        sideEffectStamps = currentStamps()
    }

    var greeting: String {
        let h = Calendar.current.component(.hour, from: Date())
        if h >= 18 { return "Jó estét" }
        if h >= 12 { return "Jó napot" }
        if h >= 4 { return "Jó reggelt" }
        return "Jó estét"
    }

    /// A Főoldal által figyelt gyorstár-típusok (a figyelő és az állapotsor is ezt kapja).
    static func watchedKinds(now: Date = Date()) -> [KretaDataKind] {
        let monday = KretaWeek.monday(for: now)
        return [.grades, .homework, .exams, .absences, .messages, .timetable(monday)]
            + (1...3).map { .timetable(KretaWeek.adding(weeks: $0, to: monday)) }
    }

    /// Az állapotsor („Frissítés…" / „Mentve: …") típusai: amit a Főoldal
    /// ténylegesen mutat (az üzenetek csak a csengő-jelvényt adják).
    static func statusKinds(now: Date = Date()) -> [KretaDataKind] {
        [.grades, .homework, .exams, .timetable(KretaWeek.monday(for: now))]
    }

    private func currentStamps() -> [KretaDataKind: Date] {
        let store = KretaStore.shared
        var out: [KretaDataKind: Date] = [:]
        for k in Self.watchedKinds() { if let d = store.savedAt(k) { out[k] = d } }
        return out
    }

    /// Gyorstár → kijelzett állapot (hálózat nélkül). Indításkor, a store
    /// minden releváns változásakor és a frissítés végén fut.
    func reload(completed: CompletedStore? = nil, userId: String? = nil) {
        let store = KretaStore.shared
        let cal = Calendar.current
        let now = Date()
        let start = cal.startOfDay(for: now)
        let end = cal.date(byAdding: .day, value: 1, to: start) ?? start.addingTimeInterval(86400)

        let gradeList: [GradeItem]? = store.value(.grades)
        let hwList: [HomeworkItem]? = store.value(.homework)
        let examList: [ExamItem]? = store.value(.exams)
        let absenceList: [AbsenceItem]? = store.value(.absences)
        let messageList: [MessageItem]? = store.value(.messages)
        let today = store.lessons(from: start, to: end)

        let custom = CustomTasksStore.load()
        grades = gradeList ?? []
        gradesKnown = gradeList != nil
        // Saját (kézzel felvett) tételek is a főoldalra kerülnek — ugyanazokkal
        // a lejárt-szabályokkal, mint a KRÉTA-tételek. Lejárt határidejű házi
        // nem kerül a főoldalra (a Feladatok tabon és az értesítési diffben
        // megmarad).
        homeworks = ((hwList ?? []) + CustomTasksStore.homeworkItems(from: custom)).filter { !HomeworkExpiry.isExpired($0) }
        homeworksKnown = hwList != nil
        absences = absenceList ?? []
        let readIDs = Set(UserDefaults.standard.stringArray(forKey: "firka.readMessages.v1") ?? [])
        messages = (messageList ?? []).map { readIDs.contains($0.id) ? $0.withRead() : $0 }
        if lessonsToday != (today ?? []) { lessonsToday = today ?? [] }
        lessonsKnown = today != nil
        examsKnown = examList != nil

        // Dolgozat-pótlás: ha valamelyik dolgozat napján hiányzás van, a
        // pontos pótló-órához tágabb órarend kell — a gyorstárban lévő
        // következő 3 hétből (a frissítés lehúzza, ha hiányzik).
        rawExamsAll = (examList ?? []) + CustomTasksStore.examItems(from: custom)
        rolloverLessons = today ?? []
        if Self.hasExamAbsenceOverlap(exams: rawExamsAll, absences: absences) {
            let from = cal.date(byAdding: .day, value: 7, to: start) ?? start
            let to = cal.date(byAdding: .day, value: 28, to: start) ?? start
            rolloverLessons += store.availableLessons(from: from, to: to)
        }
        applyRollover()
        updateLiveState()

        if let completed, let userId { runSideEffectsIfNeeded(completed: completed, userId: userId) }
    }

    /// Értesítés-diff + Watch- és widget-push — csak ha a bemenet a legutóbbi
    /// kör óta tényleg új (hálózatról jött) adat.
    private func runSideEffectsIfNeeded(completed: CompletedStore, userId: String) {
        let stamps = currentStamps()
        let changed = Set(stamps.keys.filter { stamps[$0] != sideEffectStamps[$0] })
        guard !changed.isEmpty else { return }
        sideEffectStamps = stamps
        let store = KretaStore.shared
        let gradeList: [GradeItem] = store.value(.grades) ?? []
        let hwList: [HomeworkItem] = store.value(.homework) ?? []
        let examList: [ExamItem] = store.value(.exams) ?? []
        let absenceList: [AbsenceItem] = store.value(.absences) ?? []
        let monday = KretaWeek.monday(for: Date())
        // Helyi értesítés-diff az újakról (KRÉTA push nincs, ez polling-alapú).
        // Üres listával nem diffelünk (az lehúzás-hiba is lehetne).
        if changed.contains(.grades) || changed.contains(.homework) || changed.contains(.exams) || changed.contains(.absences) {
            NotificationManager.shared.checkAll(
                grades: gradeList, homeworks: hwList, exams: examList, absences: absenceList, userId: userId
            )
        }
        // Apple Watch: jegyek — a teljes lista (tárgyak a cache-ből, mint máshol).
        if changed.contains(.grades), !gradeList.isEmpty {
            let cachedSubjects = UserDefaults.standard.stringArray(forKey: KretaClient.cachedSubjectsKey) ?? []
            WatchSyncSender.pushGrades(grades: gradeList, subjects: cachedSubjects)
        }
        // Mai nap a widget heti snapshotjába mergelve, és az órára is
        // (a heti kontextust nem írjuk felül egy nappal).
        if changed.contains(.timetable(monday)), !lessonsToday.isEmpty {
            TimetableWidgetPublish.mergeToday(lessonsToday, now: Date())
            if let snap = TimetableWidgetStore.load(), !snap.lessons.isEmpty {
                WatchSyncSender.pushSnapshot(snap)
            }
        }
        // Apple Watch: az aktív feladatok is mennek — különben az óra
        // Házik/Dolgozatok listája csak a Feladatok tab megnyitására
        // frissülne. Üresen érkezett mindkét lista → nem nyúlunk az órához.
        if changed.contains(.homework) || changed.contains(.exams), !hwList.isEmpty || !examList.isEmpty {
            let active = WatchSyncSender.activeTasks(
                homeworks: hwList, custom: CustomTasksStore.load(), exams: examList,
                lessons: rolloverLessons, completed: completed
            )
            WatchSyncSender.pushTasks(homeworks: active.hw, exams: active.ex)
        }
    }

    /// Háttér-frissítés: a Főoldal adattípusai párhuzamosan, egymástól
    /// függetlenül jönnek — mindegyik a beérkezésekor íródik a store-ba (a
    /// nézet a figyelőn át azonnal rajzol), nem a leglassabbat megvárva.
    /// Friss gyorstár-találatnál (tabváltás) nincs hálózat. Lehúzás
    /// (`force`) tényleges frissítés.
    func refresh(kreta: KretaClient, user: AppUser?, completed: CompletedStore, force: Bool = false) async {
        // Egy adatsáv: demo usert is a KretaClient szolgálja ki helyből
        // (instituteCode "demo") — nincs külön demo-ág.
        guard let user else {
            error = "Nincs bejelentkezett felhasználó."
            updateLiveState()
            return
        }
        let iss = user.instituteCode.isEmpty ? (JWT.instituteCode(from: user.accessToken) ?? "") : user.instituteCode
        if iss.isEmpty || iss == "unknown" {
            error = "Hiányzó intézményi kód — jelentkezz be újra."
            lessonsToday = []
            updateLiveState()
            return
        }
        KretaStore.shared.activate(user)
        isRefreshing = true
        defer { isRefreshing = false }

        let monday = KretaWeek.monday(for: Date())
        let nextMonday = KretaWeek.adding(weeks: 1, to: monday)
        await withTaskGroup(of: Void.self) { group in
            group.addTask { _ = await kreta.fetchGrades(iss: iss, force: force) }
            group.addTask { _ = await kreta.fetchHomework(iss: iss, force: force) }
            group.addTask { _ = await kreta.fetchAbsences(iss: iss, force: force) }
            group.addTask { _ = await kreta.fetchExams(iss: iss, force: force) }
            group.addTask { _ = await kreta.fetchMessages(force: force) }
            group.addTask { _ = await kreta.fetchTimetableWeek(iss: iss, monday: monday, force: force) }
            // A jövő hét előtöltése: az Órarend hétvégi / nap végi okos
            // ugrása és a Watch is azonnal megkapja.
            group.addTask { _ = await kreta.fetchTimetableWeek(iss: iss, monday: nextMonday, force: force) }
        }
        // Dolgozat-pótlás: átfedéskor a következő 3 hét is kell (gyorstárból,
        // ha friss — különben lehúzza).
        if Self.hasExamAbsenceOverlap(exams: rawExamsAll, absences: absences) {
            await withTaskGroup(of: Void.self) { group in
                for w in 1...3 {
                    let m = KretaWeek.adding(weeks: w, to: monday)
                    group.addTask { _ = await kreta.fetchTimetableWeek(iss: iss, monday: m, force: force) }
                }
            }
        }
        reload(completed: completed, userId: user.id)
        // Hibaüzenet csak akkor, ha egyáltalán nincs mit mutatni: mentett
        // adat mellett a „Mentve: …" állapotsor jelzi a sikertelen frissítést.
        let store = KretaStore.shared
        let nothingKnown = !gradesKnown && !homeworksKnown && !examsKnown && !lessonsKnown && store.messages == nil
        if nothingKnown {
            error = kreta.sessionExpired
                ? "A KRÉTA-munkamenet lejárt — jelentkezz be újra."
                : "Nem érkezett adat a KRÉTÁ-tól — ellenőrizd a kapcsolatot vagy jelentkezz be újra."
        } else {
            error = nil
        }
    }

    func updateLiveState() {
        if lessonsToday.isEmpty {
            // Valódi üres: ne hazudjunk "óra közben"-t — ha nincs órarend, az empty.
            // Demo-ban sosem üres, élesben viszont API hiba miatt lehet — ilyenkor empty, nem fake duringLesson.
            let h = Calendar.current.component(.hour, from: Date())
            if h < 7 { liveState = .morning }
            else if h < 16 { liveState = .empty }
            else { liveState = .empty }
            return
        }
        let now = Date()
        if lessonsToday.contains(where: { $0.start <= now && $0.end >= now }) {
            liveState = .duringLesson
        } else if let next = lessonsToday.first(where: { $0.start > now }),
                  let prev = lessonsToday.last(where: { $0.end < now }),
                  next.start.timeIntervalSince(prev.end) > 0 {
            liveState = .duringBreak
        } else if now < lessonsToday.first!.start {
            liveState = .morning
        } else {
            liveState = .empty
        }
    }

    /// Átütemezés újraszámolása hálózat nélkül (kapcsoló/elvetés után a
    /// HomeView hívja) — a lejárt-határ a kijelzett (pótolt) dátumon dől el.
    func applyRollover() {
        let r = ExamRollover.displayItems(exams: rawExamsAll, absences: absences, lessons: rolloverLessons)
        // Lejárt dolgozat a főoldalra sem kerül (a Feladatok tab Kész
        // szegmensében és az értesítési diffben megmarad). Az órához tűzött
        // aznapi dolgozat az óra végén jár le (nem éjfélkor).
        self.exams = r.items.filter { !ExamExpiry.isExpired($0, lessons: rolloverLessons) }
        self.rolledExamIDs = r.rolledIDs
        self.originalExamDates = r.originalDates
    }

    /// Van-e dolgozat olyan napon, amikor hiányzás is van.
    private static func hasExamAbsenceOverlap(exams: [ExamItem], absences: [AbsenceItem]) -> Bool {
        let cal = Calendar.current
        let days = Set(absences.map { cal.startOfDay(for: $0.date) })
        return exams.contains { days.contains(cal.startOfDay(for: $0.date)) }
    }

    var nextLesson: LessonItem? {
        let now = Date()
        return lessonsToday.first(where: { $0.start > now })
    }
    var currentLesson: LessonItem? {
        let now = Date()
        return lessonsToday.first(where: { $0.start <= now && $0.end >= now })
    }
}
