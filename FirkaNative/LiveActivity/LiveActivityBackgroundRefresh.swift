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

    /// Utoljára melyik határra ütemeztünk — az előtéri percenkénti sync
    /// minden alkalommal hív, felesleges cancel+submit churn nélkül csak
    /// akkor ütemezünk újra, ha a határ tényleg odébb ment (>30 mp).
    private static var lastScheduledBoundary: Date?

    /// A következő határra (óra vége / köv. óra kezdete) időzítünk.
    /// Ha ma már nincs több határ, a függő kérést töröljük.
    static func scheduleBoundary(lessonEnd: Date?, nextStart: Date?, now: Date = Date()) {
        let next = [lessonEnd, nextStart].compactMap { $0 }.filter { $0 > now }.min()
        // Nincs több mai határ: a függő kérést töröljük (mint eddig),
        // hogy elavult határra ne ébredjen fel az app.
        guard let next else {
            lastScheduledBoundary = nil
            BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: taskIdentifier)
            return
        }
        if let last = lastScheduledBoundary, abs(last.timeIntervalSince(next)) < 30 { return }
        BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: taskIdentifier)
        let req = BGAppRefreshTaskRequest(identifier: taskIdentifier)
        // A határ után ~10 mp-cel: az új állapot (pl. szünet→óra) a
        // `start <= now` számolás miatt ekkor már érvényes, de a kártya
        // nem ül egy percig lejárt 0:00-s timeren. (A BG-ébresztés úgysem
        // percre pontos — a régi +60 mp csak garantált avultságot adott.)
        req.earliestBeginDate = next.addingTimeInterval(10)
        do {
            try BGTaskScheduler.shared.submit(req)
            lastScheduledBoundary = next
        } catch {
            let msg = error.localizedDescription
            debugPrint("[LiveActivity] BG submit failed: \(error)")
            Task { await SummitLiveActivityManager.shared.logEvent("BG-ütemezés SIKERTELEN: \(msg)") }
        }
    }

    static func cancel() {
        lastScheduledBoundary = nil
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
                Task { await SummitLiveActivityManager.shared.logEvent("BG keepalive kérve (+20p)") }
            } catch {
                let msg = error.localizedDescription
                debugPrint("[LiveActivity] keepalive submit failed: \(error)")
                Task { await SummitLiveActivityManager.shared.logEvent("BG keepalive SIKERTELEN: \(msg)") }
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
            Task { await SummitLiveActivityManager.shared.logEvent("BG reggeli ébresztő kérve (7:05)") }
        } catch {
            let msg = error.localizedDescription
            debugPrint("[LiveActivity] morning fallback submit failed: \(error)")
            Task { await SummitLiveActivityManager.shared.logEvent("BG reggeli ébresztő SIKERTELEN: \(msg)") }
        }
    }

    // MARK: - Háttér-végrehajtás

    private static func runRefresh(task: BGAppRefreshTask) async {
        task.expirationHandler = {
            Task { await SummitLiveActivityManager.shared.logEvent("BG-ébresztés LEJÁRT (30mp ablak)") }
            task.setTaskCompleted(success: false)
        }
        await SummitLiveActivityManager.shared.logEvent("BG-ébresztés: fut")
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

    /// Órarend-frissítés + activity sync a háttérből. Sorrend:
    /// 1) AZONNALI átkapcsolás a mentett mai tervből (hálózat nélkül) —
    ///    ez a ~30 mp-es ablak legbiztosabb része;
    /// 2) pontosítás hálózatból (órarend + jegyek párhuzamosan).
    /// A régi kód 2-3 szekvenciális hálózati kört várt végig, mielőtt
    /// bármit mutatott volna — lassú hálózaton lejárt az ablak, és az
    /// óraátmenet elmaradt (lejárt 0:00-s timer a régi órával).
    @MainActor
    static func refreshNow() async -> Bool {
        let mgr = SummitLiveActivityManager.shared
        let now = Date()
        // 1) Kapcsolás cache-ből: offline is, <1 mp alatt. A következő
        //    határ ütemezése is helyreáll — a lánc akkor is él, ha a
        //    hálózat halott. (Cache csak valós előtéri syncből létezik:
        //    preview/demo-teszt sosem ír bele.)
        var cacheHit = false
        if let cached = mgr.cachedLessons(now: now) {
            cacheHit = true
            await mgr.syncDay(lessons: cached.lessons, now: now, accentHex: cached.accentHex, cacheable: false)
        } else {
            await mgr.logEvent("BG-ébresztés: nincs mai terv-cache")
        }
        // Egy adatsáv: demo usert is a KretaClient szolgálja ki helyből
        // (instituteCode "demo" → hálózat nélkül) — nincs külön demo-ág.
        let store = SessionStore()
        guard let user = store.selectedUser else { return cacheHit }
        let kreta = KretaClient()
        kreta.accessToken = user.accessToken
        kreta.refreshToken = user.refreshToken
        kreta.instituteCode = user.instituteCode
        let iss = user.instituteCode.isEmpty
            ? (JWT.instituteCode(from: user.accessToken) ?? "")
            : user.instituteCode
        guard !iss.isEmpty, iss != "unknown" else { return cacheHit }
        kreta.onTokensRefreshed = { newAccess, newRefresh, expiresIn in
            store.updateTokens(accessToken: newAccess, refreshToken: newRefresh, expiresIn: expiresIn)
        }
        let cal = Calendar.current
        let start = cal.startOfDay(for: Date())
        guard let end = cal.date(byAdding: .day, value: 1, to: start) else { return cacheHit }
        // Párhuzamosan: az órarend a kapcsoláshoz kell, a többi csak
        // értesítéshez — ezek már nem tarthatják fel az átkapcsolást.
        async let timetable = kreta.fetchTimetable(iss: iss, from: start, to: end)
        async let gradesFetch = kreta.fetchGrades(iss: iss)
        async let homeworkFetch = kreta.fetchHomework(iss: iss)
        async let examsFetch = kreta.fetchExams(iss: iss)
        async let absencesFetch = kreta.fetchAbsences(iss: iss)
        let lessons = await timetable
        let bgGrades = await gradesFetch
        let bgHomework = await homeworkFetch
        let bgExams = await examsFetch
        let bgAbsences = await absencesFetch
        // Üres órarend élesben = fetch-hiba → a cache-sync fent már
        // átkapcsolt (ha volt cache) és a következő határ be van ütemezve,
        // így a lánc él: nincs szükség 15 perces pót-ébresztésre.
        // Diffet üres listával nem futtatunk (törlési zajt okozna).
        // Demóban az üres (pl. hétvége) valós állapot → syncDay zár + reggeli ébresztő.
        if lessons.isEmpty, iss != KretaClient.demoInstitute {
            await mgr.logEvent(cacheHit
                ? "BG: hálózat hiba, cache tartja a láncot"
                : "BG: hálózat hiba, nincs cache → 15p múlva újra")
            return cacheHit
        }
        // Polling-alapú értesítés háttérből is: ha a rendszer
        // felébreszt az élő órához, az új jegyeket, házikat,
        // dolgozatokat és hiányzásokat is észrevesszük —
        // egy összevont bannerben, nem kategóriánként.
        await NotificationManager.shared.checkAll(
            grades: bgGrades, homeworks: bgHomework, exams: bgExams,
            absences: bgAbsences, userId: user.id
        )
        let accent = UserDefaults.standard.object(forKey: "theme.accentHex") as? Int ?? 0x4A90E2
        // Órarend widget életben tartása push nélkül: a mai nap friss
        // óráit mergeljük a cache-elt heti snapshotba — a widget így
        // háttér-ébresztésből is frissül, nem csak Órarend-nyitásra.
        TimetableWidgetPublish.mergeToday(lessons, now: now)
        // Heti cache kimerülve (pl. péntek este)? A következő 7 nap
        // egyben — a widget holnap is mutat, nem "Mára vége"-t.
        await TimetableWidgetPublish.prefetchUpcomingIfExhausted(now: now, kreta: kreta, iss: iss)
        // Napi-egy-activity: ez háttérből is csak UPDATE (engedélyezett),
        // új request csak akkor, ha még nincs mai activity.
        let updated = await mgr.syncDay(lessons: lessons, now: now, accentHex: accent)
        // Reggeli ébresztő CSAK akkor, ha mára tényleg nincs több óra — nem
        // akkor, ha a sync más okból hamis (pl. háttérben nincs activity és
        // a request visibility-hibával dob). Utóbbinál a runRefresh 15
        // perces pót-ébresztése tartja a láncot; a régi kód ilyenkor a mai
        // határ-láncot törölte, és holnap reggelre ütemezett.
        // (Kikapcsolt toggle / rendszer-tiltás esetén a canStart hamis —
        // oda nem kell ébresztő.)
        let hasRemaining = lessons.contains { cal.isDate($0.start, inSameDayAs: now) && $0.end > now }
        if !hasRemaining && SummitLiveActivityManager.shared.canStart {
            scheduleMorningFallback(now: now)
            return true
        }
        return updated
    }
}
