#if !targetEnvironment(macCatalyst)
import Foundation
import WatchConnectivity

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
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        shared.send(key: WatchPayloadKey.timetable, data: data)
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
            guard session.activationState == .activated else { return }
            // Párosítatlan óra / telepítetlen watch-app: dobja, legközelebb
            // úgyis a teljes context megy (aktiváláskor flush-elünk).
            try? session.updateApplicationContext(self.context)
        }
    }

    // MARK: WCSessionDelegate (iOS: mindhárom kötelező)

    func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: Error?
    ) {
        // Késett aktiválás: a load() már a session élesedése előtt
        // összerakhatta a contextet — most pótoljuk a küldést.
        if activationState == .activated, !context.isEmpty {
            try? session.updateApplicationContext(context)
        }
    }

    func sessionDidBecomeInactive(_ session: WCSession) {}

    func sessionDidDeactivate(_ session: WCSession) {
        // Páros órácsere után az új sessiont aktiválni kell.
        WCSession.default.activate()
    }
}
#else
import Foundation

// Mac Catalyst: nincs WatchConnectivity — a hívási helyek változatlanul
// fordulnak, futáskor nem történik semmi.
enum WatchSyncSender {
    static func activate() {}
    static func pushTimetable(_: [LessonItem]) {}
    static func pushGrades(grades _: [GradeItem], subjects _: [String]) {}
}
#endif
