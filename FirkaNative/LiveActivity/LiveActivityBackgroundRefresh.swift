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

    // MARK: - Regisztráció (app induláskor, SummitApp.init-ből)

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

    /// Biztonsági háló háttérbe vonuláskor (SummitApp scenePhase-ból hívja):
    /// ha nincs függő ébresztés, kérünk egyet ~20 perc múlva. Amikor lefut,
    /// a refreshNow → syncDay úgyis a pontos órarendi határra ütemez
    /// át, így a lánc akkor is él, ha az appot közben kilövi a rendszer.
    /// Meglévő függő kérést nem bántunk (a pontos határ fontosabb).
    static func scheduleKeepaliveIfNeeded() {
        BGTaskScheduler.shared.getPendingTaskRequests { requests in
            guard !requests.contains(where: { $0.identifier == taskIdentifier }) else { return }
            let req = BGAppRefreshTaskRequest(identifier: taskIdentifier)
            req.earliestBeginDate = Date(timeIntervalSinceNow: 20 * 60)
            do {
                try BGTaskScheduler.shared.submit(req)
            } catch {
                debugPrint("[LiveActivity] keepalive submit failed: \(error)")
            }
        }
    }

    /// Másnapi ébresztő: ha ma már nincs több óra, holnap reggel 7:05-re
    /// kérünk ébresztést, hogy az activity app-megnyitás nélkül is
    /// elinduljon a következő tanítási napon. (Enélkül a lánc az utolsó
    /// óra végén megszakadna, és másnap semmi nem keltené fel az appot.)
    static func scheduleMorningFallback(now: Date = Date()) {
        let cal = Calendar.current
        let tomorrow = cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: now)) ?? now.addingTimeInterval(86400)
        let morning = cal.date(bySettingHour: 7, minute: 5, second: 0, of: tomorrow) ?? tomorrow
        BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: taskIdentifier)
        let req = BGAppRefreshTaskRequest(identifier: taskIdentifier)
        req.earliestBeginDate = morning
        do {
            try BGTaskScheduler.shared.submit(req)
        } catch {
            debugPrint("[LiveActivity] morning fallback submit failed: \(error)")
        }
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
        // Egy adatsáv: demo usert is a KretaClient szolgálja ki helyből
        // (instituteCode "demo" → hálózat nélkül) — nincs külön demo-ág.
        let store = SessionStore()
        guard let user = store.selectedUser else { return false }
        let kreta = KretaClient()
        kreta.accessToken = user.accessToken
        kreta.refreshToken = user.refreshToken
        kreta.instituteCode = user.instituteCode
        let iss = user.instituteCode.isEmpty
            ? (JWT.instituteCode(from: user.accessToken) ?? "")
            : user.instituteCode
        guard !iss.isEmpty, iss != "unknown" else { return false }
        kreta.onTokensRefreshed = { newAccess, newRefresh, expiresIn in
            store.updateTokens(accessToken: newAccess, refreshToken: newRefresh, expiresIn: expiresIn)
        }
        let cal = Calendar.current
        let start = cal.startOfDay(for: Date())
        guard let end = cal.date(byAdding: .day, value: 1, to: start) else { return false }
        let lessons = await kreta.fetchTimetable(iss: iss, from: start, to: end)
        // Üres órarend élesben = fetch-hiba → 15 perc múlva újra (lásd lejjebb).
        // Demóban az üres (pl. hétvége) valós állapot → syncDay zár + reggeli ébresztő.
        if lessons.isEmpty, iss != KretaClient.demoInstitute { return false }
        // Polling-alapú jegy-értesítés háttérből is: ha a rendszer
        // felébreszt az élő órához, az új jegyeket is észrevesszük.
        let bgGrades = await kreta.fetchGrades(iss: iss)
        await NotificationManager.shared.checkGrades(bgGrades, userId: user.id)
        let now = Date()
        let accent = UserDefaults.standard.object(forKey: "theme.accentHex") as? Int ?? 0x4A90E2
        // Napi-egy-activity: ez háttérből is csak UPDATE (engedélyezett),
        // új request csak akkor, ha még nincs mai activity.
        let updated = await SummitLiveActivityManager.shared.syncDay(lessons: lessons, now: now, accentHex: accent)
        if !updated && SummitLiveActivityManager.shared.canStart {
            // Mai órák vége (a futó activity lezárva, nincs új határ) —
            // holnap reggelre ébresztőt kérünk, hogy a következő tanítási
            // napon app-megnyitás nélkül is elinduljon az activity.
            // (Kikapcsolt toggle / rendszer-tiltás esetén a syncDay
            // hamisat ad, de akkor a canStart hamis — oda nem kell ébresztő.)
            scheduleMorningFallback(now: now)
            return true
        }
        return updated
    }
}
