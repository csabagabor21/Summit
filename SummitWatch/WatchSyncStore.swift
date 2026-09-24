import Foundation
import Combine
import os
import WatchConnectivity

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

    /// Ennél régebbi órai adattal megnyitáskor kérünk frisset.
    private static let staleAfter: TimeInterval = 30 * 60
    /// Kérések ritkítása (megnyitások között).
    private static let requestGap: TimeInterval = 5 * 60
    private var lastRequest: Date?

    private let timetableKey = "watch.cache.timetable.v1"
    private let gradesKey = "watch.cache.grades.v1"
    private let tasksKey = "watch.cache.tasks.v1"

    /// Accent az órára: órarend-snapshotből, különben jegyből, különben default.
    var accentHex: Int {
        timetable?.accentHex ?? grades?.accentHex ?? 0x4A90E2
    }

    override init() {
        super.init()
        if let data = UserDefaults.standard.data(forKey: timetableKey),
           let snap = try? JSONDecoder().decode(TimetableWidgetStore.Snapshot.self, from: data) {
            timetable = snap
        }
        if let data = UserDefaults.standard.data(forKey: gradesKey),
           let snap = try? JSONDecoder().decode(WatchGradesSnapshot.self, from: data) {
            grades = snap
        }
        if let data = UserDefaults.standard.data(forKey: tasksKey),
           let snap = try? JSONDecoder().decode(WatchTasksSnapshot.self, from: data) {
            tasks = snap
        }
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
        var newTimetable = timetable
        var newGrades = grades
        var newTasks = tasks
        var changed = false
        if let data = context[WatchPayloadKey.timetable] as? Data {
            if let snap = try? JSONDecoder().decode(TimetableWidgetStore.Snapshot.self, from: data) {
                newTimetable = snap
                UserDefaults.standard.set(data, forKey: timetableKey)
                changed = true
            } else {
                watchLog.error("órarend-dekódhiba, \(data.count) bájt eldobva")
            }
        }
        if let data = context[WatchPayloadKey.grades] as? Data {
            if let snap = try? JSONDecoder().decode(WatchGradesSnapshot.self, from: data) {
                newGrades = snap
                UserDefaults.standard.set(data, forKey: gradesKey)
                changed = true
            } else {
                watchLog.error("jegy-dekódhiba, \(data.count) bájt eldobva")
            }
        }
        if let data = context[WatchPayloadKey.tasks] as? Data {
            if let snap = try? JSONDecoder().decode(WatchTasksSnapshot.self, from: data) {
                newTasks = snap
                UserDefaults.standard.set(data, forKey: tasksKey)
                changed = true
            } else {
                watchLog.error("feladat-dekódhiba, \(data.count) bájt eldobva")
            }
        }
        guard changed else { return }
        DispatchQueue.main.async {
            self.timetable = newTimetable
            self.grades = newGrades
            self.tasks = newTasks
        }
    }

    // MARK: - Szinkronkérés az iPhone felé

    /// Avult vagy hiányzó adattal megnyitáskor kérünk az iPhone-tól.
    /// Gyors út: üzenet + azonnali válasz, ha az iPhone elérhető.
    /// Lassú út: sorba állított userInfo — arra az iPhone-t a rendszer
    /// háttérben is felébreszti, és a gyorstárból válaszol.
    private func requestSyncIfNeeded(session: WCSession) {
        let now = Date()
        let savedAts = [timetable?.savedAt, grades?.savedAt, tasks?.savedAt]
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
