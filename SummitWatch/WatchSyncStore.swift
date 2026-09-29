import Foundation
import Combine
import os
import WatchConnectivity
import WidgetKit

private let watchLog = Logger(subsystem: "hu.flint.summit.watch", category: "watchsync")

// MARK: - Watch adatfogadó — CSAK óra target
// Az iPhone tolja az órarend + jegy + feladat snapshotokat
// (WatchSyncSender), az óra pedig megnyitáskor KÉRI is, ha az adata
// avult vagy hiányzik — ezért nem kell az iPhone-appot megnyitni.
// Érkezéskor dekódol + gyorsítótáraz (UserDefaults), így az óra az
// iPhone nélkül is mutatja a legutóbbit.
final class WatchSyncStore: NSObject, ObservableObject {
    @Published private(set) var timetable: TimetableWidgetStore.Snapshot?
    @Published private(set) var grades: WatchGradesSnapshot?
    @Published private(set) var tasks: WatchTasksSnapshot?
    @Published private(set) var cheat: WatchCheatSnapshot?
    @Published private(set) var schoolEvents: WatchSchoolEventsSnapshot?

    /// Ennél régebbi órai adattal megnyitáskor kérünk frisset.
    private static let staleAfter: TimeInterval = 30 * 60
    /// Kérések ritkítása (megnyitások között).
    private static let requestGap: TimeInterval = 5 * 60
    private var lastRequest: Date?

    // Gyorsítótár-kulcsok: WatchSharedStore (App Group — a Smart Stack-widget
    // ugyaninnen olvas, a standard-defaultsot nem látja).

    /// Lehúzásos frissítés állapota (az óra listái ezt mutatják).
    @Published private(set) var isSyncing = false
    @Published private(set) var lastSyncDate: Date?
    @Published private(set) var lastSyncError: String?
    /// Fejlesztői idő-előnézet pillanata az iPhone-ról (csak ha a csúszka
    /// aktív) — az órarend ilyenkor az eltolt idő szerint rajzol.
    @Published private(set) var previewNow: Date?

    /// Accent az órára: órarend-snapshotből, különben jegyből, különben default.
    var accentHex: Int {
        timetable?.accentHex ?? grades?.accentHex ?? 0x4A90E2
    }

    override init() {
        super.init()
        if let data = WatchSharedStore.data(forKey: WatchSharedStore.timetableKey),
           let snap = try? JSONDecoder().decode(TimetableWidgetStore.Snapshot.self, from: data) {
            timetable = snap
        }
        if let data = WatchSharedStore.data(forKey: WatchSharedStore.gradesKey),
           let snap = try? JSONDecoder().decode(WatchGradesSnapshot.self, from: data) {
            grades = snap
        }
        if let data = WatchSharedStore.data(forKey: WatchSharedStore.tasksKey),
           let snap = try? JSONDecoder().decode(WatchTasksSnapshot.self, from: data) {
            tasks = snap
        }
        if let data = WatchSharedStore.data(forKey: WatchSharedStore.cheatKey),
           let snap = try? JSONDecoder().decode(WatchCheatSnapshot.self, from: data) {
            cheat = snap
        }
        if let data = WatchSharedStore.data(forKey: WatchSharedStore.schoolEventsKey),
           let snap = try? JSONDecoder().decode(WatchSchoolEventsSnapshot.self, from: data) {
            schoolEvents = snap
        }
        let previewTs = WatchSharedStore.defaults.double(forKey: WatchSharedStore.previewNowKey)
        if previewTs > 0 {
            previewNow = Date(timeIntervalSince1970: previewTs)
        }
        // A widget a groupból olvas, de a timeline-ja nem tudja, hogy az app
        // elindult — indításkor kérünk egy frissítést, hogy a Smart Stack a
        // legutóbbi gyorsítótárat mutassa az első szinkron előtt is.
        WidgetCenter.shared.reloadTimelines(ofKind: WatchSharedStore.widgetKind)
        if WCSession.isSupported() {
            let session = WCSession.default
            session.delegate = self
            session.activate()
        }
    }
}

extension WatchSyncStore: WCSessionDelegate {
    func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: Error?
    ) {
        if let error {
            watchLog.error("aktiválási hiba: \(error.localizedDescription, privacy: .public)")
        }
        watchLog.info("óra aktiválva: \(String(describing: activationState), privacy: .public)")
        // Megnyitáskor a legfrissebb context is megérkezik — ami már
        // korábban megjött tárolva, azt is alkalmazzuk.
        apply(session.receivedApplicationContext)
        if activationState == .activated {
            requestSyncIfNeeded(session: session)
        }
    }

    func session(
        _ session: WCSession,
        didReceiveApplicationContext applicationContext: [String: Any]
    ) {
        apply(applicationContext)
    }

    private func apply(_ context: [String: Any]) {
        watchLog.info("context érkezett, kulcsok: \(context.keys.joined(separator: ","), privacy: .public)")
        // Idő-előnézet: minden context/válasz úton frissen jön; hiánya =
        // a csúszka ki van kapcsolva → vissza valós időre.
        let newPreview: Date? = (context[WatchPayloadKey.previewNow] as? Double).map { Date(timeIntervalSince1970: $0) }
        var newTimetable = timetable
        var newGrades = grades
        var newTasks = tasks
        var newCheat = cheat
        var newSchoolEvents = schoolEvents
        var changed = false
        if let data = context[WatchPayloadKey.timetable] as? Data {
            if let snap = try? JSONDecoder().decode(TimetableWidgetStore.Snapshot.self, from: data) {
                newTimetable = snap
                WatchSharedStore.set(data, forKey: WatchSharedStore.timetableKey)
                changed = true
            } else {
                watchLog.error("órarend-dekódhiba, \(data.count) bájt eldobva")
            }
        }
        if let data = context[WatchPayloadKey.grades] as? Data {
            if let snap = try? JSONDecoder().decode(WatchGradesSnapshot.self, from: data) {
                newGrades = snap
                WatchSharedStore.set(data, forKey: WatchSharedStore.gradesKey)
                changed = true
            } else {
                watchLog.error("jegy-dekódhiba, \(data.count) bájt eldobva")
            }
        }
        if let data = context[WatchPayloadKey.tasks] as? Data {
            if let snap = try? JSONDecoder().decode(WatchTasksSnapshot.self, from: data) {
                newTasks = snap
                WatchSharedStore.set(data, forKey: WatchSharedStore.tasksKey)
                changed = true
            } else {
                watchLog.error("feladat-dekódhiba, \(data.count) bájt eldobva")
            }
        }
        if let data = context[WatchPayloadKey.cheat] as? Data {
            if let snap = try? JSONDecoder().decode(WatchCheatSnapshot.self, from: data) {
                newCheat = snap
                WatchSharedStore.set(data, forKey: WatchSharedStore.cheatKey)
                changed = true
            } else {
                watchLog.error("jegyzet-dekódhiba, \(data.count) bájt eldobva")
            }
        }
        if let data = context[WatchPayloadKey.schoolEvents] as? Data {
            if let snap = try? JSONDecoder().decode(WatchSchoolEventsSnapshot.self, from: data) {
                newSchoolEvents = snap
                WatchSharedStore.set(data, forKey: WatchSharedStore.schoolEventsKey)
                changed = true
            } else {
                watchLog.error("esemény-dekódhiba, \(data.count) bájt eldobva")
            }
        }
        // Az előnézetet akkor is átírjuk, ha snapshot nem változott
        // (pl. csak a csúszkát mozgatták, vagy kikapcsolták) — különben
        // az óra beragadna az eltolt időbe. A groupban él, hogy a Smart
        // Stack-widget is az eltolt idő szerint rajzoljon.
        if let p = newPreview {
            WatchSharedStore.defaults.set(p.timeIntervalSince1970, forKey: WatchSharedStore.previewNowKey)
        } else {
            WatchSharedStore.defaults.removeObject(forKey: WatchSharedStore.previewNowKey)
        }
        let previewChanged = newPreview != previewNow
        guard changed || previewChanged else { return }
        DispatchQueue.main.async {
            self.timetable = newTimetable
            self.grades = newGrades
            self.tasks = newTasks
            self.cheat = newCheat
            self.schoolEvents = newSchoolEvents
            self.previewNow = newPreview
            // Friss adat a groupban → a widget timeline-ja is újratölt,
            // különben a Smart Stack a régi (üres) belépőnél ragadna.
            WidgetCenter.shared.reloadTimelines(ofKind: WatchSharedStore.widgetKind)
        }
    }

    // MARK: - Lehúzásos szinkronkérés (az óra listáiról)

    /// Kézi frissítés lehúzásra (ritkítás nélkül): gyors üzenet-válasz, ha
    /// az iPhone elérhető, különben sorba állított userInfo — arra a
    /// rendszer az iPhone-t háttérben is felébreszti. 8 mp válasz nélkül
    /// is sorba állunk, nem lóg a spinner.
    @MainActor
    func requestSyncNow() async {
        lastSyncError = nil
        guard WCSession.isSupported() else {
            lastSyncError = "Az óra nem támogatja a szinkront."
            return
        }
        let session = WCSession.default
        guard session.activationState == .activated else {
            lastSyncError = "A kapcsolat még aktiválódik — próbáld újra pár mp múlva."
            return
        }
        isSyncing = true
        defer { isSyncing = false }
        lastRequest = Date()
        let msg = [WatchPayloadKey.request: true]
        // Azonnali út + időkorlát egyben: amelyik előbb jelez, az nyer.
        let reply: [String: Any]? = await withTaskGroup(of: [String: Any]?.self) { group in
            group.addTask {
                try? await withCheckedThrowingContinuation { (cont: CheckedContinuation<[String: Any], Error>) in
                    session.sendMessage(msg, replyHandler: { cont.resume(returning: $0) }, errorHandler: { cont.resume(throwing: $0) })
                }
            }
            group.addTask {
                try? await Task.sleep(nanoseconds: 8_000_000_000)
                return nil
            }
            let first = await group.next() ?? nil
            group.cancelAll()
            return first
        }
        if let reply {
            apply(reply)
            lastSyncDate = Date()
            watchLog.info("lehúzásos szinkron kész")
        } else {
            // iPhone nem elérhető / nem válaszolt: userInfo-sor — a rendszer
            // háttér-ébresztéskor kézbesíti, az adat megjön az órára.
            watchLog.info("iPhone nem válaszolt, userInfo-sor")
            session.transferUserInfo(msg)
            lastSyncError = "Az iPhone most nem elérhető — a kérés sorba állt, az adat háttérben megjön."
        }
    }

    // MARK: - Szinkronkérés az iPhone felé

    /// Avult vagy hiányzó adattal megnyitáskor kérünk az iPhone-tól.
    /// Gyors út: üzenet + azonnali válasz, ha az iPhone elérhető.
    /// Lassú út: sorba állított userInfo — arra az iPhone-t a rendszer
    /// háttérben is felébreszti, és a gyorstárból válaszol.
    private func requestSyncIfNeeded(session: WCSession) {
        let now = Date()
        let savedAts = [timetable?.savedAt, grades?.savedAt, tasks?.savedAt, cheat?.savedAt, schoolEvents?.savedAt]
        let stale = savedAts.contains(where: { $0 == nil })
            || savedAts.compactMap { $0 }.contains { now.timeIntervalSince($0) > Self.staleAfter }
        guard stale else { return }
        if let last = lastRequest, now.timeIntervalSince(last) < Self.requestGap { return }
        lastRequest = now
        let msg = [WatchPayloadKey.request: true]
        watchLog.info("szinkronkérés az iPhone felé")
        session.sendMessage(msg, replyHandler: { [weak self] reply in
            watchLog.info("gyorsválasz érkezett az iPhone-ról")
            self?.apply(reply)
        }, errorHandler: { error in
            // iPhone nem elérhető (pl. lezárva a zsebben): userInfo
            // sorba áll — háttér-ébresztéskor megjön a válasz.
            watchLog.info("iPhone nem elérhető, userInfo-sor: \(error.localizedDescription, privacy: .public)")
            session.transferUserInfo(msg)
        })
    }
}
