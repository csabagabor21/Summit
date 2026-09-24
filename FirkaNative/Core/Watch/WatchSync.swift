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
        guard let data = try? JSONEncoder().encode(snapshot) else {
            WatchSyncLog.log.error("órarend-kódolási hiba")
            return
        }
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
        guard let data = try? JSONEncoder().encode(snapshot) else {
            WatchSyncLog.log.error("feladat-kódolási hiba")
            return
        }
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
        guard let data = try? JSONEncoder().encode(snapshot) else {
            WatchSyncLog.log.error("jegy-kódolási hiba")
            return
        }
        shared.send(key: WatchPayloadKey.grades, data: data)
    }

    private func send(key: String, data: Data) {
        // Utolsó ismert snapshot perzisztálása: az óra kérésekor ebből
        // válaszolunk azonnal, hálózat nélkül, akár háttérből is.
        UserDefaults.standard.set(data, forKey: Self.lastKnownKeyPrefix + key)
        // WCSession-hívások főszálon (a push hívói Task-ból is jöhetnek).
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.context[key] = data
            let session = WCSession.default
            WatchSyncLog.log.info("send \(key, privacy: .public) bytes=\(data.count) state=\(String(describing: session.activationState), privacy: .public) paired=\(session.isPaired, privacy: .public) watchInstalled=\(session.isWatchAppInstalled, privacy: .public)")
            guard session.activationState == .activated else {
                WatchSyncLog.log.info("session még nem aktív — context tárolva, aktiváláskor flush")
                return
            }
            do {
                try session.updateApplicationContext(self.context)
                WatchSyncLog.log.info("context elküldve (\(key, privacy: .public))")
            } catch {
                WatchSyncLog.log.error("context-hiba (\(key, privacy: .public)): \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    // MARK: - Óra-iniciált szinkron (pull)

    /// Az óra kéréseinek értesítése — a SummitApp erre ritkítás nélkül
    /// húz frisset a hálózatról (a gyorstáras válasz már addig is kiment).
    static let syncRequested = Notification.Name("watch.syncRequested.v1")

    private static let lastKnownKeyPrefix = "watch.last.v1."

    /// Utolsó ismert snapshotok a perzisztens tárolóból — alkalmazás-
    /// újraindítás után, háttér-ébresztéskor is elérhető.
    static func lastKnownContext() -> [String: Any] {
        var ctx: [String: Any] = [:]
        for key in [WatchPayloadKey.timetable, WatchPayloadKey.grades, WatchPayloadKey.tasks] {
            if let data = UserDefaults.standard.data(forKey: lastKnownKeyPrefix + key) {
                ctx[key] = data
            }
        }
        return ctx
    }

    /// Óra-kérés kiszolgálása: azonnal a legutóbbi snapshot (hálózat
    /// nélkül), plusz jelzés az appnak a friss lehúzásra.
    private func answerSyncRequest(reply: (([String: Any]) -> Void)?) {
        let ctx = Self.lastKnownContext()
        WatchSyncLog.log.info("óra szinkronkérés, gyorsválasz kulcsok: \(ctx.keys.joined(separator: ","), privacy: .public)")
        if !ctx.isEmpty {
            reply?(ctx)
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                for (k, v) in ctx { self.context[k] = v }
                do {
                    try WCSession.default.updateApplicationContext(self.context)
                    WatchSyncLog.log.info("kérésre context frissítve")
                } catch {
                    WatchSyncLog.log.error("kérés-válasz context hiba: \(error.localizedDescription, privacy: .public)")
                }
            }
        } else {
            reply?([:])
        }
        NotificationCenter.default.post(name: Self.syncRequested, object: nil)
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

    // Óra → iPhone kérések. Gyors út (üzenet + válasz), ha az iPhone
    // elérhető; sorba állított út (userInfo), ha háttérben van — arra
    // a rendszer felébreszti az appot, és a gyorstárból válaszolunk.

    func session(
        _ session: WCSession,
        didReceiveMessage message: [String: Any],
        replyHandler: @escaping ([String: Any]) -> Void
    ) {
        guard message[WatchPayloadKey.request] != nil else { return }
        answerSyncRequest(reply: replyHandler)
    }

    func session(
        _ session: WCSession,
        didReceiveUserInfo userInfo: [String: Any] = [:]
    ) {
        guard userInfo[WatchPayloadKey.request] != nil else { return }
        answerSyncRequest(reply: nil)
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
    static let syncRequested = Notification.Name("watch.syncRequested.v1")
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
