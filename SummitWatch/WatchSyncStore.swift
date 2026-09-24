import Foundation
import Combine
import os
import WatchConnectivity

private let watchLog = Logger(subsystem: "hu.flint.summit.watch", category: "watchsync")

// MARK: - Watch adatfogadó — CSAK óra target
// Az iPhone tolja az órarend + jegy snapshotokat (WatchSyncSender).
// Érkezéskor dekódol + gyorsítótáraz (UserDefaults), így az óra az
// iPhone nélkül is mutatja a legutóbbit. Kézi frissítés nincs:
// megnyitáskor a rendszer kézbesíti a legfrissebb contextet.
final class WatchSyncStore: NSObject, ObservableObject {
    @Published private(set) var timetable: TimetableWidgetStore.Snapshot?
    @Published private(set) var grades: WatchGradesSnapshot?

    private let timetableKey = "watch.cache.timetable.v1"
    private let gradesKey = "watch.cache.grades.v1"

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
        var changed = false
        if let data = context[WatchPayloadKey.timetable] as? Data,
           let snap = try? JSONDecoder().decode(TimetableWidgetStore.Snapshot.self, from: data) {
            newTimetable = snap
            UserDefaults.standard.set(data, forKey: timetableKey)
            changed = true
        }
        if let data = context[WatchPayloadKey.grades] as? Data,
           let snap = try? JSONDecoder().decode(WatchGradesSnapshot.self, from: data) {
            newGrades = snap
            UserDefaults.standard.set(data, forKey: gradesKey)
            changed = true
        }
        guard changed else { return }
        DispatchQueue.main.async {
            self.timetable = newTimetable
            self.grades = newGrades
        }
    }
}
