import Foundation

// MARK: - WatchSyncReport — diagnosztika-jelentés (Beállítások → Diagnosztika)
// Sima értékek (Catalyst-barát): a Diagnosztika ebből rajzol, külön
// WatchConnectivity-import nélkül — Macen is fordul.
struct WatchSyncReport {
    var supportedText: String = "–"
    var activationText: String = "–"
    var pairedText: String = "–"
    var installedText: String = "–"
    var reachableText: String = "–"
    var timetableText: String = "–"
    var gradesText: String = "–"
    var tasksText: String = "–"
    var cheatText: String = "–"
    var errorText: String?
    /// Egy mondatos ítélet ("mi a baj"), plusz tennivaló.
    var verdictText: String = "–"
    var hintText: String = ""
}

#if !targetEnvironment(macCatalyst)
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

    /// Heti órarend az órára (a widget-snapshot ugyanaz a mapping —
    /// a státusz-flagekkel: felmentett zöld, dolgozat szürke).
    static func pushTimetable(_ lessons: [LessonItem], homeworks: [HomeworkItem] = [], exams: [ExamItem] = []) {
        guard WCSession.isSupported(), !lessons.isEmpty else { return }
        let snapshot = TimetableWidgetStore.Snapshot(
            savedAt: Date(),
            accentHex: TimetableWidgetPublish.currentAccentHex(),
            lessons: TimetableWidgetPublish.fromLessons(lessons, homeworks: homeworks, exams: exams)
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

    /// Tanulójegyzet-lapok az órára — a CheatView szabályaival.
    /// Üres lista is mehet (mind törölve → az óra Jegyzet-tabja ürül).
    /// Méretkorlát: az applicationContext nagy méretnél a teljes
    /// contextet eldobná — ezért max 30 lap, laponként max 20 téma,
    /// témánként 1500 karakter utazik.
    static func pushCheat(_ sheets: [CheatSheet]) {
        guard WCSession.isSupported() else { return }
        let mappedSheets = sheets.prefix(30).map {
            WatchCheatSheet(id: $0.id, subject: $0.subject, title: $0.title, date: $0.date)
        }
        var mappedTopics: [String: [WatchCheatTopic]] = [:]
        for s in sheets.prefix(30) {
            mappedTopics[s.id] = s.topics.prefix(20).map {
                WatchCheatTopic(id: $0.id, title: $0.title,
                                body: String($0.body.prefix(1500)))
            }
        }
        let snapshot = WatchCheatSnapshot(
            savedAt: Date(),
            accentHex: TimetableWidgetPublish.currentAccentHex(),
            sheets: Array(mappedSheets), topics: mappedTopics
        )
        guard let data = try? JSONEncoder().encode(snapshot) else {
            WatchSyncLog.log.error("jegyzet-kódolási hiba")
            return
        }
        shared.send(key: WatchPayloadKey.cheat, data: data)
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

    /// Iskolai események (tannaptár) az órarend tetejére.
    /// Üres lista is mehet (törlés → az óra eseménysávja ürül).
    static func pushSchoolEvents(events: [SchoolEvent], visible: Bool) {
        guard WCSession.isSupported() else { return }
        let mapped = events.prefix(500).map {
            WatchSchoolEvent(
                day: $0.day, title: $0.title, location: $0.location,
                allDay: $0.allDay, start: $0.start, end: $0.end
            )
        }
        let snapshot = WatchSchoolEventsSnapshot(
            savedAt: Date(), visible: visible, events: Array(mapped)
        )
        guard let data = try? JSONEncoder().encode(snapshot) else {
            WatchSyncLog.log.error("esemény-kódolási hiba")
            return
        }
        shared.send(key: WatchPayloadKey.schoolEvents, data: data)
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
            Self.stampPreview(into: &self.context)
            let session = WCSession.default
            WatchSyncLog.log.info("send \(key, privacy: .public) bytes=\(data.count) state=\(String(describing: session.activationState), privacy: .public) paired=\(session.isPaired, privacy: .public) watchInstalled=\(session.isWatchAppInstalled, privacy: .public)")
            Self.noteSession(session)
            guard session.activationState == .activated else {
                WatchSyncLog.log.info("session még nem aktív — context tárolva, aktiváláskor flush")
                Self.noteSkip(key: key, reason: "session nem aktív")
                return
            }
            do {
                try session.updateApplicationContext(self.context)
                WatchSyncLog.log.info("context elküldve (\(key, privacy: .public))")
                Self.notePushed(key: key, bytes: data.count)
            } catch {
                WatchSyncLog.log.error("context-hiba (\(key, privacy: .public)): \(error.localizedDescription, privacy: .public)")
                Self.noteError("\(key): \(error.localizedDescription)")
            }
        }
    }

    // MARK: - Diagnosztika-rögzítés (Beállítások → Diagnosztika)

    /// Jelentés-változás — a Diagnosztika erre frissíti a szekciót.
    static let reportChanged = Notification.Name("watch.reportChanged.v1")

    private static let diagPushAtSuffix = ".at"
    private static let diagPushBytesSuffix = ".bytes"
    private static let diagSkipSuffix = ".skip"
    private static let diagErrorKey = "watch.diag.error.v1"
    private static let diagSessionKey = "watch.diag.session.v1"

    private static func diagPushAtKey(_ key: String) -> String { "watch.diag.push.\(key)" + diagPushAtSuffix }
    private static func diagPushBytesKey(_ key: String) -> String { "watch.diag.push.\(key)" + diagPushBytesSuffix }
    private static func diagSkipKey(_ key: String) -> String { "watch.diag.skip.\(key)" + diagSkipSuffix }

    /// Session-pillanatkép minden küldésnél + aktiváláskor (főszálon hívjuk).
    private static func noteSession(_ session: WCSession) {
        let snap = "\(session.activationState.rawValue)|\(session.isPaired)|\(session.isWatchAppInstalled)|\(session.isReachable)"
        UserDefaults.standard.set(snap, forKey: diagSessionKey)
        // A post főszálon: a Diagnosztika @State-et ír rá.
        if Thread.isMainThread {
            NotificationCenter.default.post(name: reportChanged, object: nil)
        } else {
            DispatchQueue.main.async {
                NotificationCenter.default.post(name: reportChanged, object: nil)
            }
        }
    }

    /// Sikeres push: dátum + méret, a hiba törlődik.
    private static func notePushed(key: String, bytes: Int) {
        let d = UserDefaults.standard
        d.set(Date().timeIntervalSince1970, forKey: diagPushAtKey(key))
        d.set(bytes, forKey: diagPushBytesKey(key))
        d.removeObject(forKey: diagSkipKey(key))
        d.removeObject(forKey: diagErrorKey)
        NotificationCenter.default.post(name: reportChanged, object: nil)
    }

    /// Kihagyott push (pl. nem aktív session) — nem hiba, de látszik.
    private static func noteSkip(key: String, reason: String) {
        UserDefaults.standard.set("\(reason) • \(Self.huTime(Date()))", forKey: diagSkipKey(key))
        NotificationCenter.default.post(name: reportChanged, object: nil)
    }

    /// Sikertelen push — a következő sikerig megmarad.
    private static func noteError(_ message: String) {
        UserDefaults.standard.set("\(message) • \(Self.huTime(Date()))", forKey: diagErrorKey)
        NotificationCenter.default.post(name: reportChanged, object: nil)
    }

    private static func huTime(_ d: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "hu_HU")
        f.dateFormat = "MMM d. HH:mm"
        return f.string(from: d)
    }

    private static func sliceText(_ key: String) -> String {
        let d = UserDefaults.standard
        if d.double(forKey: diagPushAtKey(key)) > 0 {
            let bytes = d.integer(forKey: diagPushBytesKey(key))
            let kb = Double(bytes) / 1024.0
            let when = huTime(Date(timeIntervalSince1970: d.double(forKey: diagPushAtKey(key))))
            return "\(when) • \(String(format: "%.0f KB", kb))"
        }
        return d.string(forKey: diagSkipKey(key)) ?? "–"
    }

    /// Pillanatnyi jelentés a Diagnosztikának — sima stringek, WC nélkül.
    static func report() -> WatchSyncReport {
        var r = WatchSyncReport()
        guard WCSession.isSupported() else {
            r.supportedText = "nem"
            r.verdictText = "Ezen az eszközön nem elérhető"
            r.hintText = "Az óra-szinkron csak iPhone-on működik (WatchConnectivity) — Macen és iPaden a küldés néma no-op."
            return r
        }
        r.supportedText = "igen"
        let parts = (UserDefaults.standard.string(forKey: diagSessionKey) ?? "").split(separator: "|").map(String.init)
        let boolText: (String?) -> String = { $0 == nil ? "–" : ($0 == "true" ? "igen" : "nem") }
        if parts.count == 4 {
            let state = Int(parts[0]) ?? -1
            r.activationText = state == 2 ? "aktív" : (state == 1 ? "aktiválás alatt" : (state == 0 ? "nem aktív" : "–"))
            r.pairedText = boolText(parts[1])
            r.installedText = boolText(parts[2])
            r.reachableText = boolText(parts[3])
        }
        r.timetableText = sliceText(WatchPayloadKey.timetable)
        r.gradesText = sliceText(WatchPayloadKey.grades)
        r.tasksText = sliceText(WatchPayloadKey.tasks)
        r.cheatText = sliceText(WatchPayloadKey.cheat)
        r.errorText = UserDefaults.standard.string(forKey: diagErrorKey)
        // Ítélet — az első igaz ok nyer.
        if parts.count == 4, parts[0] != "2" {
            r.verdictText = "A session nem aktív"
            r.hintText = "Nyisd meg az appot iPhone-on és várj pár másodpercet; ha marad, indítsd újra az appot."
        } else if parts.count == 4, parts[1] != "true" {
            r.verdictText = "Nincs párosított óra"
            r.hintText = "Párosíts Apple Watch-ot az iPhone-hoz (Watch app)."
        } else if parts.count == 4, parts[2] != "true" {
            r.verdictText = "Az óra-app nincs telepítve az órán"
            r.hintText = "iPhone-on Watch app → Summit → Telepítés az órára."
        } else if let err = r.errorText {
            r.verdictText = "Utolsó push hibával halt el"
            r.hintText = "Hiba: \(err). Legtöbbször elég a Főoldal lehúzása (újraküldi mindhárom szeletet)."
        } else if r.timetableText == "–", r.gradesText == "–", r.tasksText == "–", r.cheatText == "–" {
            r.verdictText = "Még nem történt push"
            r.hintText = "Húzd le a Főoldalt, az Órarendet vagy a Jegyeket — a lehúzás végén az app tol az órára."
        } else {
            r.verdictText = "OK — az utolsó pushok átmentek"
            r.hintText = "Ha az óra mégis üreset mutat, az órán húzd le valamelyik listát (az óra kér frisset az iPhone-tól)."
        }
        return r
    }

    // MARK: - Óra-iniciált szinkron (pull)

    /// Az óra kéréseinek értesítése — a SummitApp erre ritkítás nélkül
    /// húz frisset a hálózatról (a gyorstáras válasz már addig is kiment).
    static let syncRequested = Notification.Name("watch.syncRequested.v1")

    private static let lastKnownKeyPrefix = "watch.last.v1."

    /// Fejlesztői idő-előnézet bélyegzése a contextbe: ha a csúszka
    /// aktív, az óra is az eltolt idő szerint rajzol; ha nem, a kulcs
    /// kikerül (az óra visszaáll valós időre). Minden küldési úton
    /// frissen számoljuk — a csúszka mozgatása önmagában nem pushol.
    static func stampPreview(into ctx: inout [String: Any]) {
        if let ov = WatchPreviewClock.overrideNow() {
            ctx[WatchPayloadKey.previewNow] = ov.timeIntervalSince1970
        } else {
            ctx.removeValue(forKey: WatchPayloadKey.previewNow)
        }
    }

    /// Utolsó ismert snapshotok a perzisztens tárolóból — alkalmazás-
    /// újraindítás után, háttér-ébresztéskor is elérhető.
    static func lastKnownContext() -> [String: Any] {
        var ctx: [String: Any] = [:]
        for key in [WatchPayloadKey.timetable, WatchPayloadKey.grades, WatchPayloadKey.tasks, WatchPayloadKey.cheat, WatchPayloadKey.schoolEvents] {
            if let data = UserDefaults.standard.data(forKey: lastKnownKeyPrefix + key) {
                ctx[key] = data
            }
        }
        stampPreview(into: &ctx)
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
        // Háttér-ébresztésből (az óra lehúzása ébresztette az appot) a
        // SwiftUI `.task` observer nem biztos, hogy él — ezért innen is
        // indítjuk ugyanazt a frissítést saját store-okkal. Az
        // running-flag a duplikációt kizárja, ha az observer is fut.
        Task { await WatchAutoPush.refreshForWatchWake() }
    }

    // MARK: WCSessionDelegate (iOS: mindhárom kötelező)

    func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: Error?
    ) {
        if let error {
            WatchSyncLog.log.error("aktiválási hiba: \(error.localizedDescription, privacy: .public)")
            Self.noteError("aktiválás: \(error.localizedDescription)")
        }
        WatchSyncLog.log.info("aktiválva: \(String(describing: activationState), privacy: .public) paired=\(session.isPaired, privacy: .public)")
        Self.noteSession(session)
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

    /// Óra-lehúzásos ébresztés kiszolgálása háttérből is: saját
    /// store-okkal ugyanaz a refreshNow fut, mint az előtéri
    /// observerből — a SwiftUI `.task` ilyenkor nem biztos, hogy él
    /// (pl. az appot az óra userInfo-ja ébresztette). Token-beállítás
    /// a BG-lánc mintájára (LiveActivityBackgroundRefresh.refreshNow).
    @MainActor
    static func refreshForWatchWake() async {
        let session = SessionStore()
        guard let user = session.selectedUser else {
            WatchSyncLog.log.info("watch-wake: nincs belépett user")
            return
        }
        let kreta = KretaClient()
        kreta.accessToken = user.accessToken
        kreta.refreshToken = user.refreshToken
        kreta.instituteCode = user.instituteCode
        kreta.onTokensRefreshed = { newAccess, newRefresh, expiresIn in
            session.updateTokens(accessToken: newAccess, refreshToken: newRefresh, expiresIn: expiresIn)
        }
        await refreshNow(session: session, kreta: kreta, completed: CompletedStore())
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
            let custom = CustomTasksStore.load()
            WatchSyncSender.pushTimetable(
                lessons,
                homeworks: hwR + CustomTasksStore.homeworkItems(from: custom),
                exams: exR + CustomTasksStore.examItems(from: custom)
            )
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
        // Jegyzetlapok helyből — hálózattól függetlenül mennek az órára.
        WatchSyncSender.pushCheat(CheatStore.load())
        // Iskolai események helyből — az órarend tetejére.
        WatchSyncSender.pushSchoolEvents(events: SchoolEventsStore.load(), visible: SchoolEventsStore.isVisible())
    }
}
#else

// Mac Catalyst: nincs WatchConnectivity — a hívási helyek változatlanul
// fordulnak, futáskor nem történik semmi.
enum WatchSyncSender {
    static let syncRequested = Notification.Name("watch.syncRequested.v1")
    static let reportChanged = Notification.Name("watch.reportChanged.v1")

    /// Macen mindig ugyanaz: nem támogatott (a Diagnosztika ezt mutatja).
    static func report() -> WatchSyncReport {
        WatchSyncReport(
            supportedText: "nem",
            verdictText: "Ezen az eszközön nem elérhető",
            hintText: "Az óra-szinkron csak iPhone-on működik (WatchConnectivity) — Macen a küldés néma no-op."
        )
    }
    static func activate() {}
    static func pushTimetable(_: [LessonItem], homeworks _: [HomeworkItem] = [], exams _: [ExamItem] = []) {}
    static func pushSnapshot(_: TimetableWidgetStore.Snapshot) {}
    static func pushGrades(grades _: [GradeItem], subjects _: [String]) {}
    static func pushTasks(homeworks _: [HomeworkItem], exams _: [ExamItem]) {}
    static func pushCheat(_: [CheatSheet]) {}
    static func pushSchoolEvents(events _: [SchoolEvent], visible _: Bool) {}
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
