#if !targetEnvironment(macCatalyst)
import Foundation
import os
import WatchConnectivity

/// Watch-szinkron napló (Console.app / `log stream` — Diagnosztika-elv:
/// a néma hibák helyett minden lépés látszik).
enum WatchSyncLog {
    static let log = Logger(subsystem: "hu.flint.summit", category: "watchsync")
}

// MARK: - Watch sync (iPhone-oldal) — CSAK fő app target
// Az órarend és a jegyek kivonatát tolja az órára WatchConnectivity
// applicationContext-tel: last-write-wins, háttérben is kézbesül, az óra
// megnyitásakor megérkezik a legfrissebb. Külön bejelentkezés nincs az
// órán — a KRÉTA-hívások továbbra is csak itt futnak.
// Hívások: activate() az app indulásakor, pushTimetable() az órarend-,
// pushGrades() a jegybetöltés végéről. Párosítatlan órán / Macen néma no-op.
final class WatchSyncSender: NSObject, WCSessionDelegate {
    static let shared = WatchSyncSender()

    /// Folyamatban lévő context — az updateApplicationContext a TELJES
    /// szótárat cseréli, ezért a két szeletet itt egyesítjük.
    private var context: [String: Any] = [:]

    static func activate() {
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        session.delegate = shared
        session.activate()
    }

    /// Heti órarend az órára (a widget-snapshot ugyanaz a mapping).
    static func pushTimetable(_ lessons: [LessonItem]) {
        guard WCSession.isSupported(), !lessons.isEmpty else { return }
        let snapshot = TimetableWidgetStore.Snapshot(
            savedAt: Date(),
            accentHex: TimetableWidgetPublish.currentAccentHex(),
            lessons: TimetableWidgetPublish.fromLessons(lessons)
        )
        pushSnapshot(snapshot)
    }

    /// Kész snapshot az órára (pl. a widget App Group-cache-éből —
    /// hálózat nélkül is mehet az utolsó ismert hét).
    static func pushSnapshot(_ snapshot: TimetableWidgetStore.Snapshot) {
        guard WCSession.isSupported(), !snapshot.lessons.isEmpty else { return }
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        shared.send(key: WatchPayloadKey.timetable, data: data)
    }

    /// Aktív feladatok az órára — a NotesView-val azonos szűrés után.
    /// Üres lista is mehet (mind kész → az óra ürül).
    static func pushTasks(homeworks: [HomeworkItem], exams: [ExamItem]) {
        guard WCSession.isSupported() else { return }
        let snapshot = WatchTasksSnapshot(
            savedAt: Date(),
            accentHex: TimetableWidgetPublish.currentAccentHex(),
            homeworks: homeworks.map {
                WatchHomework(
                    id: $0.id, subject: $0.subject,
                    title: $0.plainTitle.isEmpty ? "(nincs leírás)" : $0.plainTitle,
                    deadline: $0.deadline, teacher: $0.teacher,
                    isCustom: CustomTasksStore.isCustomId($0.id)
                )
            },
            exams: exams.map {
                WatchExam(
                    id: $0.id, subject: $0.subject, mode: $0.mode,
                    details: HomeworkPlain.text(from: $0.description),
                    date: $0.date, lessonIndex: $0.lessonIndex,
                    isCustom: CustomTasksStore.isCustomId($0.id)
                )
            }
        )
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        shared.send(key: WatchPayloadKey.tasks, data: data)
    }

    /// Aktív házik + dolgozatok a NotesView szabályaival: saját tételek
    /// belemergelve, kész/lejárt kiszűrve, határidő-sorrendben.
    /// MainActor (CompletedStore-olvasás miatt) — hívói ilyenek.
    @MainActor
    static func activeTasks(
        homeworks: [HomeworkItem],
        custom: [CustomTask],
        exams: [ExamItem],
        lessons: [LessonItem],
        completed: CompletedStore
    ) -> (hw: [HomeworkItem], ex: [ExamItem]) {
        let hw = (homeworks + CustomTasksStore.homeworkItems(from: custom))
            .filter { !completed.isHomeworkDone($0.id) && !HomeworkExpiry.isExpired($0) }
            .sorted { $0.deadline < $1.deadline }
        let ex = (exams + CustomTasksStore.examItems(from: custom))
            .filter { !ExamExpiry.isExpired($0, lessons: lessons) }
            .sorted { $0.date < $1.date }
        return (hw, ex)
    }

    /// Jegyek + tárgyak + kerekítési küszöbök az órára.
    static func pushGrades(grades: [GradeItem], subjects: [String]) {
        guard WCSession.isSupported(), !grades.isEmpty else { return }
        let mapped = grades.map {
            WatchGrade(
                id: $0.id, subject: $0.subject, value: $0.value,
                valueText: $0.valueText, date: $0.date, teacher: $0.teacher,
                type: $0.type, weight: $0.weight, topic: $0.topic
            )
        }
        let snapshot = WatchGradesSnapshot(
            savedAt: Date(),
            accentHex: TimetableWidgetPublish.currentAccentHex(),
            subjects: subjects, grades: mapped,
            thresholds: GradingLogic.loadThresholds()
        )
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        shared.send(key: WatchPayloadKey.grades, data: data)
    }

    private func send(key: String, data: Data) {
        // WCSession-hívások főszálon (a push hívói Task-ból is jöhetnek).
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.context[key] = data
            let session = WCSession.default
            WatchSyncLog.log.info("send \(key, privacy: .public) bytes=\(data.count) state=\(String(describing: session.activationState), privacy: .public) paired=\(session.isPaired, privacy: .public) watchInstalled=\(session.isWatchAppInstalled, privacy: .public)")
            guard session.activationState == .activated else { return }
            do {
                try session.updateApplicationContext(self.context)
                WatchSyncLog.log.info("context elküldve (\(key, privacy: .public))")
            } catch {
                WatchSyncLog.log.error("context-hiba (\(key, privacy: .public)): \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    // MARK: WCSessionDelegate (iOS: mindhárom kötelező)

    func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: Error?
    ) {
        if let error {
            WatchSyncLog.log.error("aktiválási hiba: \(error.localizedDescription, privacy: .public)")
        }
        WatchSyncLog.log.info("aktiválva: \(String(describing: activationState), privacy: .public) paired=\(session.isPaired, privacy: .public)")
        // Késett aktiválás: a load() már a session élesedése előtt
        // összerakhatta a contextet — most pótoljuk a küldést.
        if activationState == .activated, !context.isEmpty {
            do {
                try session.updateApplicationContext(context)
                WatchSyncLog.log.info("függő context flush-elve")
            } catch {
                WatchSyncLog.log.error("flush-hiba: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    func sessionDidBecomeInactive(_ session: WCSession) {}

    func sessionDidDeactivate(_ session: WCSession) {
        // Páros órácsere után az új sessiont aktiválni kell.
        WCSession.default.activate()
    }
}

// MARK: - Automatikus watch-frissítés az app megnyitásakor
// A tabok megnyitása nélkül is menjen át az adat: induláskor és előtérbe
// hozáskor (ritkítva) lehúzzuk az aktuális hetet + a jegyeket, és toljuk
// az órára. Hálózat nélkül / üres válasznál a meglévő órai adat marad.
@MainActor
enum WatchAutoPush {
    private static let lastKey = "watch.autopush.last.v1"
    /// Ritkítás: két automatikus frissítés között ennyi telhet el minimum.
    private static let minInterval: TimeInterval = 10 * 60
    private static var running = false

    /// Ritkított frissítés (induláskor, előtérbe hozáskor).
    static func refreshIfNeeded(session: SessionStore, kreta: KretaClient, completed: CompletedStore) async {
        let last = UserDefaults.standard.double(forKey: lastKey)
        let age = Date().timeIntervalSince1970 - last
        guard age > minInterval else {
            WatchSyncLog.log.info("ritkítva, legutóbbi \(Int(age)) mp-je volt")
            return
        }
        await refreshNow(session: session, kreta: kreta, completed: completed)
    }

    /// Azonnali frissítés (ritkítás nélkül).
    static func refreshNow(session: SessionStore, kreta: KretaClient, completed: CompletedStore) async {
        WatchSyncLog.log.info("refreshNow indul")
        guard WCSession.isSupported() else {
            WatchSyncLog.log.error("WCSession nem támogatott ezen az eszközön")
            return
        }
        guard !running else {
            WatchSyncLog.log.info("már fut egy frissítés, kihagyva")
            return
        }
        guard let user = session.selectedUser else {
            WatchSyncLog.log.info("nincs belépett user, nincs mit tolni")
            return
        }
        running = true
        defer { running = false }
        UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: lastKey)

        // Azonnal: a widget-snapshotban lévő heti anyag (ha van) megy ki
        // hálózat nélkül is — az óra nem vár a lehúzásra.
        if let snap = TimetableWidgetStore.load(), !snap.lessons.isEmpty {
            WatchSyncSender.pushSnapshot(snap)
        }

        let iss = user.instituteCode.isEmpty
            ? (JWT.instituteCode(from: user.accessToken) ?? "")
            : user.instituteCode
        guard !iss.isEmpty, iss != "unknown" else { return }

        // Aktuális hét (hétfő → +7 nap), mint a TimetableView.fetchWeek.
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let weekday = cal.component(.weekday, from: today)
        let mondayOffset = (weekday == 1 ? -6 : 2 - weekday)
        guard let monday = cal.date(byAdding: .day, value: mondayOffset, to: today),
              let end = cal.date(byAdding: .day, value: 7, to: monday) else { return }
        async let ttTask = kreta.fetchTimetable(iss: iss, from: monday, to: end)
        async let gradesTask = kreta.fetchGrades(iss: iss)
        async let subjectsTask = kreta.fetchAllSubjectNames(iss: iss)
        async let hwTask = kreta.fetchHomework(iss: iss)
        async let exTask = kreta.fetchExams(iss: iss)
        let (lessons, grades, subjects, hwR, exR) = await (ttTask, gradesTask, subjectsTask, hwTask, exTask)
        WatchSyncLog.log.info("lehúzva: \(lessons.count) óra, \(grades.count) jegy, \(subjects.count) tárgy, \(hwR.count) házi, \(exR.count) dolgozat")

        if !lessons.isEmpty {
            WatchSyncSender.pushTimetable(lessons)
        }
        if !grades.isEmpty {
            // Tárgyak: hálózati + cache-elt unió, mint a GradesView-load.
            let cached = UserDefaults.standard.stringArray(forKey: "firka.cachedSubjects.v1") ?? []
            let all = Array(Set(subjects).union(cached)).sorted()
            if !subjects.isEmpty {
                UserDefaults.standard.set(subjects.sorted(), forKey: "firka.cachedSubjects.v1")
            }
            WatchSyncSender.pushGrades(grades: grades, subjects: all)
        }
        if !hwR.isEmpty || !exR.isEmpty {
            // Saját tételek helyből — hálózati hiba esetén is vannak.
            let custom = CustomTasksStore.load()
            let active = WatchSyncSender.activeTasks(
                homeworks: hwR, custom: custom, exams: exR,
                lessons: lessons, completed: completed
            )
            WatchSyncSender.pushTasks(homeworks: active.hw, exams: active.ex)
        }
    }
}
#else
import Foundation

// Mac Catalyst: nincs WatchConnectivity — a hívási helyek változatlanul
// fordulnak, futáskor nem történik semmi.
enum WatchSyncSender {
    static func activate() {}
    static func pushTimetable(_: [LessonItem]) {}
    static func pushSnapshot(_: TimetableWidgetStore.Snapshot) {}
    static func pushGrades(grades _: [GradeItem], subjects _: [String]) {}
    static func pushTasks(homeworks _: [HomeworkItem], exams _: [ExamItem]) {}
    @MainActor
    static func activeTasks(
        homeworks _: [HomeworkItem],
        custom _: [CustomTask],
        exams _: [ExamItem],
        lessons _: [LessonItem],
        completed _: CompletedStore
    ) -> (hw: [HomeworkItem], ex: [ExamItem]) { ([], []) }
}

enum WatchAutoPush {
    static func refreshIfNeeded(session _: SessionStore, kreta _: KretaClient, completed _: CompletedStore) async {}
    static func refreshNow(session _: SessionStore, kreta _: KretaClient, completed _: CompletedStore) async {}
}
#endif
