import Foundation
import SwiftUI

@MainActor
final class HomeViewModel: ObservableObject {
    @Published var selectedTab = 0
    @Published var liveState: LiveCardState = .morning
    @Published var isRefreshing = false

    // Real data
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

    /// Nyers dolgozatok + pótló-kereséshez használt órák (hálózat nélkül
    /// újraszámolható a kapcsoló/elvetés után).
    private var rawExamsAll: [ExamItem] = []
    private var rolloverLessons: [LessonItem] = []

    var greeting: String {
        let h = Calendar.current.component(.hour, from: Date())
        if h >= 18 { return "Jó estét" }
        if h >= 12 { return "Jó napot" }
        if h >= 4 { return "Jó reggelt" }
        return "Jó estét"
    }

    func refresh(kreta: KretaClient, user: AppUser?, completed: CompletedStore) async {
        // Egy adatsáv: demo usert is a KretaClient szolgálja ki helyből
        // (instituteCode "demo") — nincs külön demo-ág.
        guard let user else {
            error = "Nincs bejelentkezett felhasználó."
            updateLiveState()
            return
        }
        isRefreshing = true
        defer { isRefreshing = false }

        let iss = user.instituteCode.isEmpty ? (JWT.instituteCode(from: user.accessToken) ?? "") : user.instituteCode
        if iss.isEmpty || iss == "unknown" {
            error = "Hiányzó intézményi kód — jelentkezz be újra."
            lessonsToday = []
            updateLiveState()
            return
        }

        // A 6 adatsáv csendben, párhuzamosan jön — külön töltésjelző nélkül.
        async let g = kreta.fetchGrades(iss: iss)
        async let hw = kreta.fetchHomework(iss: iss)
        async let ab = kreta.fetchAbsences(iss: iss)
        async let ex = kreta.fetchExams(iss: iss)
        async let msg = kreta.fetchMessages()

        let hadData = !(grades.isEmpty && homeworks.isEmpty && absences.isEmpty && exams.isEmpty && messages.isEmpty && lessonsToday.isEmpty)
        let start = Calendar.current.startOfDay(for: Date())
        let end = Calendar.current.date(byAdding: .day, value: 1, to: start)!
        async let tt = kreta.fetchTimetable(iss: iss, from: start, to: end)
        let (gradesR, hwR, abR, exR, msgR, ttR) = await (g, hw, ab, ex, msg, tt)
        if gradesR.isEmpty && hwR.isEmpty && abR.isEmpty && exR.isEmpty && msgR.isEmpty && ttR.isEmpty {
            if hadData {
                // Totális fetch-hiba (lejárt token, offline): a legutóbbi adat
                // marad a képernyőn, nem ürül ki a főoldal — csak hibaüzenet jön.
                error = kreta.sessionExpired
                    ? "A KRÉTA-munkamenet lejárt — jelentkezz be újra."
                    : "Nem sikerült frissíteni — a legutóbbi adatokat mutatjuk."
                updateLiveState()
                return
            }
            error = "Nem érkezett adat a KRÉTÁ-tól — ellenőrizd a kapcsolatot vagy jelentkezz be újra."
            updateLiveState()
            return
        }
        self.grades = gradesR
        // Saját (kézzel felvett) tételek is a főoldalra kerülnek — ugyanazokkal
        // a lejárt-szabályokkal, mint a KRÉTA-tételek.
        let custom = CustomTasksStore.load()
        // Lejárt határidejű házi nem kerül a főoldalra (a Feladatok tabon
        // és az értesítési diffben megmarad) — demóra is ugyanez vonatkozik,
        // mint egy valós userre.
        self.homeworks = (hwR + CustomTasksStore.homeworkItems(from: custom)).filter { !HomeworkExpiry.isExpired($0) }
        self.absences = abR
        self.messages = msgR
        self.lessonsToday = ttR
        // Dolgozat-pótlás: ha valamelyik dolgozat napján hiányzás van, a
        // pontos pótló-órához tágabb órarend kell — de csak ilyenkor húzunk
        // plusz 3 hetet (egyébként a mai órák is elégnek a döntéshez).
        rawExamsAll = exR + CustomTasksStore.examItems(from: custom)
        rolloverLessons = ttR
        if Self.hasExamAbsenceOverlap(exams: rawExamsAll, absences: abR) {
            rolloverLessons += await Self.extraRolloverLessons(kreta: kreta, iss: iss)
        }
        applyRollover()
        // Helyi értesítés-diff az újakról (KRÉTA push nincs, ez polling-alapú)
        NotificationManager.shared.checkAll(
            grades: gradesR, homeworks: hwR, exams: exR, absences: abR, userId: user.id
        )
        // Apple Watch: a Főoldal lehúzása is szinkronizálja az órát.
        // Jegyek: a teljes friss lista (tárgyak a cache-ből, mint máshol).
        // Órarend: csak a mai nap jött le — belemergeljük a heti snapshotba,
        // és azt toljuk (a heti kontextust nem írjuk felül egy nappal).
        let cachedSubjects = UserDefaults.standard.stringArray(forKey: "firka.cachedSubjects.v1") ?? []
        WatchSyncSender.pushGrades(grades: gradesR, subjects: cachedSubjects)
        if !ttR.isEmpty {
            TimetableWidgetPublish.mergeToday(ttR, now: Date())
            if let snap = TimetableWidgetStore.load(), !snap.lessons.isEmpty {
                WatchSyncSender.pushSnapshot(snap)
            }
        }
        // Apple Watch: az aktív feladatok is mennek — különben az óra
        // Házik/Dolgozatok listája csak a Feladatok tab megnyitására
        // frissülne. Szűrés a Feladatok tab szabályaival (kész/lejárt ki).
        // Üresen érkezett mindkét lista → nem nyúlunk az órához (a
        // NotesView-val azonos óvatosság: az inkább sikertelen lehúzás,
        // mint valóban üres hét).
        if !hwR.isEmpty || !exR.isEmpty {
            let active = WatchSyncSender.activeTasks(
                homeworks: hwR, custom: custom, exams: exR,
                lessons: rolloverLessons, completed: completed
            )
            WatchSyncSender.pushTasks(homeworks: active.hw, exams: active.ex)
        }
        error = nil
        updateLiveState()
        return
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

    /// Plusz 3 hét órarendje a pontos pótló-órához (csak átfedéskor).
    private static func extraRolloverLessons(kreta: KretaClient, iss: String) async -> [LessonItem] {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        return await withTaskGroup(of: [LessonItem].self) { group in
            for w in 1...3 {
                group.addTask {
                    let s = cal.date(byAdding: .day, value: w * 7, to: today)!
                    let e = cal.date(byAdding: .day, value: 7, to: s)!
                    return await kreta.fetchTimetable(iss: iss, from: s, to: e)
                }
            }
            var out: [LessonItem] = []
            for await part in group { out.append(contentsOf: part) }
            return out
        }
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
