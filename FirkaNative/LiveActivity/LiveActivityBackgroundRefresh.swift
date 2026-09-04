import BackgroundTasks
import Foundation

// MARK: - Live Activity háttér-ébresztés
//
// Cél: óra/szünet végén az activity akkor is átkapcsoljon, ha az app nincs megnyitva.
// Működés: minden sikeres start/update után beütemezünk egy BGAppRefreshTask-ot
// a következő határra (óra vége / következő óra kezdete + ~1 perc). A rendszer
// ilyenkor felébreszti az appot a háttérben (~30 mp futásidő), frissítjük az
// órarend alapján az activityt, és láncszerűen ütemezzük a következőt.
//
// Feltételek (project.yml-ben beállítva):
//   UIBackgroundModes = fetch, BGTaskSchedulerPermittedIdentifiers = taskIdentifier.
// A felhasználó készülékén is be kell legyen kapcsolva:
//   Beállítások → Általános → Háttérben futó appok frissítése.
// Pontosság: a rendszer nem garantál percre pontos ébresztést (tipikusan
// pár perces csúszás lehet) — de az élő timerInterval miatt a countdown
// addig is pontosan tickel, csak az óra→szünet átkapcsolás csúszhat kicsit.

enum LiveActivityBackgroundRefresh {
    static let taskIdentifier = "hu.flint.app.Flint.liveactivity-refresh"

    // MARK: - Regisztráció (app induláskor, FlintApp.init-ből)

    static func register() {
        BGTaskScheduler.shared.register(forTaskWithIdentifier: taskIdentifier, using: nil) { task in
            guard let refresh = task as? BGAppRefreshTask else {
                task.setTaskCompleted(success: false)
                return
            }
            Task {
                await runRefresh(task: refresh)
            }
        }
    }

    // MARK: - Ütemezés (a Manager hívja minden sikeres start/update után)

    /// A következő határra (óra vége / köv. óra kezdete) időzítünk.
    /// Ha ma már nincs több határ, a függő kérést töröljük.
    static func scheduleBoundary(lessonEnd: Date?, nextStart: Date?, now: Date = Date()) {
        let next = [lessonEnd, nextStart].compactMap { $0 }.filter { $0 > now }.min()
        BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: taskIdentifier)
        guard let next else { return }
        let req = BGAppRefreshTaskRequest(identifier: taskIdentifier)
        // A határ után ~1 perccel: az új állapot (pl. szünet) ekkor már érvényes.
        req.earliestBeginDate = next.addingTimeInterval(60)
        do {
            try BGTaskScheduler.shared.submit(req)
        } catch {
            debugPrint("[LiveActivity] BG submit failed: \(error)")
        }
    }

    static func cancel() {
        BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: taskIdentifier)
    }

    // MARK: - Háttér-végrehajtás

    private static func runRefresh(task: BGAppRefreshTask) async {
        task.expirationHandler = {
            task.setTaskCompleted(success: false)
        }
        let ok = await refreshNow()
        task.setTaskCompleted(success: ok)
        // Sikertelen frissítésnél (pl. nincs hálózat) 15 perc múlva újra —
        // a lánc ne szakadjon meg egy kimaradt ébresztéstől.
        if !ok {
            let req = BGAppRefreshTaskRequest(identifier: taskIdentifier)
            req.earliestBeginDate = Date(timeIntervalSinceNow: 15 * 60)
            try? BGTaskScheduler.shared.submit(req)
        }
    }

    /// Órarend-frissítés + activity sync a háttérből. Csak az órarendet
    /// kérjük le (jegyek/házik nélkül), hogy beleférjünk a ~30 mp-be.
    @MainActor
    static func refreshNow() async -> Bool {
        let store = SessionStore()
        let user = store.selectedUser
        let lessons: [LessonItem]
        if user == nil || user!.isDemo {
            // Demo: determinisztikus mai órarend, hálózat nélkül is megy.
            lessons = DemoData.lessonsToday()
        } else {
            let kreta = KretaClient()
            kreta.accessToken = user!.accessToken
            kreta.refreshToken = user!.refreshToken
            let iss = user!.instituteCode.isEmpty
                ? (JWT.instituteCode(from: user!.accessToken) ?? "")
                : user!.instituteCode
            guard !iss.isEmpty, iss != "unknown" else { return false }
            kreta.onTokensRefreshed = { newAccess, newRefresh, expiresIn in
                store.updateTokens(accessToken: newAccess, refreshToken: newRefresh, expiresIn: expiresIn)
            }
            let cal = Calendar.current
            let start = cal.startOfDay(for: Date())
            guard let end = cal.date(byAdding: .day, value: 1, to: start) else { return false }
            lessons = await kreta.fetchTimetable(iss: iss, from: start, to: end)
            if lessons.isEmpty { return false }
        }
        let now = Date()
        let cur = lessons.first { $0.start <= now && $0.end >= now }
        let nxt = lessons.first { $0.start > now }
        let accent = UserDefaults.standard.object(forKey: "theme.accentHex") as? Int ?? 0xA7DC22
        return await FlintLiveActivityManager.shared.startOrUpdate(current: cur, next: nxt, now: now, accentHex: accent)
    }
}
