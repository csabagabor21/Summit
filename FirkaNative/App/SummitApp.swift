import SwiftUI

@main
struct SummitApp: App {
    @StateObject private var session = SessionStore()
    @StateObject private var kreta = KretaClient()
    @StateObject private var theme = ThemeStore()
    @StateObject private var completed = CompletedStore()
    @StateObject private var profileImages = ProfileImageStore()
    @StateObject private var analytics = AnalyticsStore()
    @StateObject private var summitSync = SummitSync()
    @Environment(\.scenePhase) private var scenePhase

    init() {
        // A legutóbbi fiók lemezes KRÉTA-gyorstára háttérszálon kezd töltődni
        // (a dekódolás nem a főszálon fut), amíg az init a többi indítási
        // munkát végzi — a végén átvesszük, így az első képkocka már a
        // mentett órarendet / jegyeket rajzolja (lásd KretaStore).
        KretaStore.shared.beginLaunchBootstrap()
        // Minecraft-skin pixelbetűje (Monocraft, OFL) — bundle-ből, plist-
        // módosítás nélkül, CSAK ha a mentett skin Minecraft (Summit skinben
        // a regisztráció fölösleges indítási munka; skinváltáskor az első
        // pixelbetű-kérés regisztrál, lásd MinecraftFontLoader.font).
        let savedMinecraft = UserDefaults.standard.string(forKey: "ui.skin") == VisualSkin.minecraft.rawValue
        if savedMinecraft { MinecraftFontLoader.registerOnce() }
        // Nav/tab-sávok pixelbetűje, ha a mentett skin Minecraft.
        MinecraftTheme.applyChromeAppearance(minecraft: savedMinecraft)
        // Régi per-típus értesítéskapcsolók összevonása a főkapcsolóba
        // (egyszeri, idempotens — csak akkor nyúl, ha régi kulcs él).
        NotificationManager.migratePerTypeKeys()
        // Live Activity háttér-ébresztés: óra/szünet végén az app
        // megnyitása nélkül is átkapcsol az activity.
        LiveActivityBackgroundRefresh.register()
        // Apple Watch: órarend + jegyek továbbítása az órára
        // (WatchConnectivity applicationContext — külön login nincs az órán).
        WatchSyncSender.activate()
        // Realtime szinkron: csak ha a GoogleService-Info.plist a
        // bundle-ben van; nélküle néma, a REST-út marad.
        SummitSync.configureIfNeeded()
        // A régi appverziók által eltárolt közös Gemini-kulcs törlése
        // (a kulcs azóta csak a workerben él, lásd GeminiFallback).
        GeminiFallback.purgeLegacyCache()
        // Gyorstár-átvétel még a nézetek születése előtt (legfeljebb ~0,8 mp
        // várakozás lassú lemeznél; utána aszinkron fejeződik be).
        KretaStore.shared.completeLaunchBootstrap()
    }

    /// Admin iskolai naptár: belépéskor / iskolakód-váltáskor automatikus
    /// letöltés az iskola kódja alapján — de csak ha az eszközön még nincs
    /// kézi beállítás (esemény vagy mentett link); az mindig nyer, az admin
    /// sosem írja felül (SchoolCalendarDirectory).
    private func resolveSchoolCalendar() {
        let code = session.selectedUser?.instituteCode
        Task {
            await SchoolCalendarDirectory.resolveAfterLogin(instituteCode: code)
        }
    }

    /// Frissítőknek: aki már be van lépve (update után), annál a belépéskori
    /// automatika sosem futott le — indításkor és előtérbe hozáskor (napi max
    /// egyszer) is megpróbáljuk az admin-alapértelmezést, kérdés nélkül.
    /// Ha már van kézi beállítás vagy alkalmazott naptár, a resolve úgysem
    /// nyúl semmihez (hálózat nélkül tér vissza).
    private func resolveSchoolCalendarForUpdater() {
        guard session.selectedUser != nil else { return }
        let key = "schoolcalendar.lastAutoResolve.v1"
        let last = UserDefaults.standard.double(forKey: key)
        guard Date().timeIntervalSince1970 - last > 24 * 3600 else { return }
        UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: key)
        resolveSchoolCalendar()
    }

    /// Heartbeat egy helyről: ha az iskolanév üres vagy szűrt (pl. belépéskor
    /// nem jött meg az adatlap), a KRÉTA-adatlapból pótolja, csak utána küld.
    /// - Parameter event: nil = napi (előtér), különben azonnali esemény
    ///   ("login" belépéskor, "consent" bekapcsoláskor).
    private func sendHeartbeat(event: String? = nil) async {
        // Előbb a hozzájárulás és a napi ritkítás: kikapcsolt statisztikánál
        // vagy ma már elküldött napi jelzésnél az iskolanév-pótlás (akár két
        // hálózati kör: KRÉTA-adatlap + userinfo) sem fut — eddig minden
        // előtérbe hozáskor lefutott, a beleegyezés ellenőrzése előtt.
        guard analytics.isEnabled else { return }
        if event == nil, analytics.heartbeatSentToday { return }
        _ = await session.refreshSchoolName(kreta: kreta)
        // Kézi felülírás nyer (Beállítások → Fiók), különben az adatlap neve.
        // A kódot is küldjük: ha a név használhatatlan, a szerver a kódból
        // oldja fel az iskolát (CODEBOOK).
        let name = session.heartbeatSchoolName
        let code = session.selectedUser?.instituteCode
        if let event {
            analytics.recordEvent(schoolName: name, event: event, instituteCode: code)
        } else {
            analytics.recordHeartbeat(schoolName: name, instituteCode: code)
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(session)
                .environmentObject(kreta)
                .environmentObject(theme)
                .environmentObject(completed)
                .environmentObject(profileImages)
                .environmentObject(analytics)
                .environmentObject(summitSync)
                // Mac-haptika relé: az imperatív SummitHaptics-hívások
                // Catalysten ezeket a számlálókat pörgetik, a rendszer
                // pedig trackpad-kattanást játszik rájuk. iPhone-on a
                // triggerek sosem változnak, így ott némák maradnak.
                .sensoryFeedback(.alignment, trigger: HapticRelay.shared.selectionTick)
                .sensoryFeedback(.levelChange, trigger: HapticRelay.shared.commitTick)
                .tint(theme.isMinecraft ? MinecraftTheme.grass : theme.accent)
                .preferredColorScheme(theme.mode.scheme)
                .onAppear {
                    // Macen (iPad-app Macen) ne tudjon pici ablakba zsugorodni
                    MacSupport.applyWindowSizing()
                    // Natív Mac-ablak: áttetsző háttér, hogy a Liquid Glass
                    // sidebar/toolbar/lista vibrancy-vel látszódjon (ne fehér).
                    MacSupport.applyWindowTransparency()
                    // Előtéri banner-delegált az értesítésekhez
                    NotificationManager.shared.configure()
                    // Tokenek + gyorstár-fiók; a közös adatforrás a kiválasztott
                    // fiókra áll (az indításkori előtöltés ellenőrzése: más fiók
                    // esetén a memória ürül és a helyes fiók tölt be).
                    kreta.bind(session.selectedUser)
                    KretaStore.shared.activate(session.selectedUser, knownAccounts: session.users)
                    // Token refresh perzisztálás (+ kliens-oldali lejárat szinkron,
                    // hogy a proaktív megújítás ne egy elavult dátummal számoljon)
                    kreta.onTokensRefreshed = { newAccess, newRefresh, expiresIn in
                        session.updateTokens(accessToken: newAccess, refreshToken: newRefresh, expiresIn: expiresIn)
                        kreta.accessTokenExpire = session.selectedUser?.accessTokenExpire
                    }
                    // takarítás: régi hardcoded flag már nem használt
                    UserDefaults.standard.removeObject(forKey: "timetable.useHardcoded")
                    // Frissítő (már belépett user) indításkor: ha nincs semmi
                    // beállítva, az admin iskolai naptár legyen a default —
                    // napi max egyszer (eddig minden indításkor Firestore-kör
                    // + App Check, ha nem volt esemény).
                    resolveSchoolCalendarForUpdater()
                    // Apple Watch: megnyitásra menjen át az órarend + a
                    // jegyek az órára — nem kell hozzá tabokra menni.
                    Task { await WatchAutoPush.refreshIfNeeded(session: session, kreta: kreta, completed: completed) }
                }
                .onChange(of: session.selectedId) { _, _ in
                    // A szinkron fiókonkénti opt-in: VALÓDI váltáskor kikapcsol
                    // (a jelmondat marad, újbóli bekapcsolás ugyanoda köt).
                    // Azonos fiók új belépése (lejárt munkamenet → újra-login,
                    // ilyenkor a stabil id miatt az id is gyakran azonos) nem
                    // bántja: a SessionStore ezt jelzi, a szinkron marad.
                    if session.sameAccountRelogin {
                        session.sameAccountRelogin = false
                    } else {
                        summitSync.isEnabled = false
                    }
                    // Válasz-gyorstár ürítése: a másik fiók adata nem
                    // szivároghat át, és a friss belépés se kapjon avultat.
                    kreta.invalidateCache()
                    kreta.bind(session.selectedUser)
                    // Fiókváltás: a közös gyorstár azonnal ürül, és a másik
                    // fiók saját (lemezes) könyvtárából tölt — A adata B-nek
                    // sosem látszik.
                    KretaStore.shared.activate(session.selectedUser, knownAccounts: session.users)
                    kreta.sessionExpired = false
                    kreta.showExpiredAlert = false
                    // Belépésváltáskor is: ha ugyanaz az iskola, az
                    // instituteCode nem változik, így enélkül újra-belépéskor
                    // semmi nem triggerelne heartbeatet.
                    if session.selectedUser != nil {
                        Task { await sendHeartbeat(event: "login") }
                        resolveSchoolCalendar()
                    }
                }
                .onChange(of: session.selectedUser?.accessToken) { _, new in
                    kreta.accessToken = new
                }
                .onChange(of: session.selectedUser?.refreshToken) { _, new in
                    kreta.refreshToken = new
                }
                .onChange(of: session.selectedUser?.instituteCode) { _, new in
                    kreta.instituteCode = new
                    // Kézi iskolakód-javítás: a fiókkulcs (és vele a gyorstár-
                    // könyvtár) az intézménytől függ — újrakötés.
                    kreta.cacheAccount = session.selectedUser.map(KretaStore.accountHash(for:))
                    KretaStore.shared.activate(session.selectedUser, knownAccounts: session.users)
                    Task { await sendHeartbeat(event: "login") }
                    // Kézi iskolakód-javítás (Beállítások → Fiók) után is:
                    // ha ehhez a kódhoz van admin-naptár és nincs kézi
                    // beállítás, az töltődik be alapértelmezettként.
                    resolveSchoolCalendar()
                }
                // Beleegyezés pillanatában azonnal menjen ki az első jelzés —
                // különben csak a következő előtérbe hozáskor küldene.
                .onChange(of: analytics.hasChosen) { _, chosen in
                    if chosen {
                        Task { await sendHeartbeat(event: "consent") }
                    }
                }
                // Beállítások-kapcsoló: bekapcsoláskor azonnal küldünk,
                // kikapcsoláskor direkt semmit (visszavonáskor nem gyűjtünk).
                .onChange(of: analytics.isEnabled) { _, enabled in
                    if enabled {
                        Task { await sendHeartbeat(event: "consent") }
                    }
                }
                .onChange(of: scenePhase) { _, new in
                    if new == .background {
                        // Háttérbe vonuláskor legyen függő BG-ébresztés —
                        // enélkül a rendszer nem kelti fel az appot óra-/
                        // szünetváltáskor, és az activity csak megnyitásra frissülne.
                        LiveActivityBackgroundRefresh.scheduleKeepaliveIfNeeded()
                    } else if new == .active {
                        // Előtérben először a tárolóból szinkronizálunk: a háttér-
                        // refresh (Live Activity ébresztés) rotálhatta a tokeneket
                        // és perzisztálta az újakat — a memóriában lévő régi
                        // refresh tokennel próbálkozva az IDP eldobná a kérést,
                        // és egy élő munkamenetre kapnánk hamis "lejárt" popupot.
                        // Csak ha egy másik SessionStore-példány (háttér-
                        // ébresztés) azóta tényleg írt — különben fölösleges
                        // Keychain-olvasás + dekódolás minden előtérbe hozáskor.
                        session.reloadIfChangedElsewhere()
                        let oldRT = kreta.refreshToken
                        kreta.bind(session.selectedUser)
                        if kreta.refreshToken != oldRT {
                            // Alattunk cserélődtek a tokenek — a korábbi
                            // "lejárt" ítélet elavult, töröljük.
                            kreta.sessionExpired = false
                            kreta.showExpiredAlert = false
                        }
                        // Proaktív token-megújítás: ha háttérben járt le a
                        // KRÉTA-token, az első lehúzás már friss tokennel
                        // menjen, ne 401 + üres nézetekkel. Utána heartbeat —
                        // friss tokennel az iskolanév-pótlás is sikerülhet.
                        Task {
                            await kreta.ensureValidToken()
                            await sendHeartbeat()
                        }
                        // Előtérben a szerver-oldali beállítások nyernek,
                        // ha újabbak (másik eszközről jöttek): listener,
                        // ha lehet, különben egyszeri lehúzás.
                        if let at = session.selectedUser?.accessToken {
                            summitSync.refresh(accessToken: at, theme: theme,
                                         profile: profileImages, completed: completed,
                                         userId: session.selectedUser?.id)
                        }
                        // Napközbeni megnyitáskor is menjen fel a mai terv a
                        // workerbe (ne csak reggel, az activity indításakor) —
                        // különben a szerver-oldali óraváltás nem indul be, ha
                        // a user csak napközben nyitja meg az appot.
                        Task { await SummitLiveActivityManager.shared.ensurePlanUploaded() }
                        // Frissítő, akinek nincs semmi beállítva: napi max
                        // egyszer az admin-naptár defaultolódik kérdés nélkül.
                        resolveSchoolCalendarForUpdater()
                        // Apple Watch: előtérbe hozáskor is frissüljön az óra
                        // (ritkítva — lásd WatchAutoPush).
                        Task { await WatchAutoPush.refreshIfNeeded(session: session, kreta: kreta, completed: completed) }
                    }
                }
                // Apple Watch: az óra megnyitáskor kér frisset, ha az órai
                // adat avult — erre ritkítás nélkül húzunk (a gyorstáras
                // válasz már addig is kiment az órára).
                .task {
                    for await _ in NotificationCenter.default.notifications(named: WatchSyncSender.syncRequested) {
                        await WatchAutoPush.refreshNow(session: session, kreta: kreta, completed: completed)
                    }
                }
        }
    }
}

// MARK: - SummitHandoff — Continuity (Handoff) minden eszköz között
// Ha az iPhone-on az órarendben állsz, a Mac dockjában feljön a Summit
// ikon, rákattintva a Mac-app ugyanott nyílik (tab + hét/nap + óra +
// Feladatok-szegmens). Mindkét irányban, minden eszközön (iPhone/iPad/Mac
// Catalyst — ugyanaz a Bundle ID, ugyanaz a tevékenység-típus).
// Feltétel a gépeken: ugyanaz az iCloud-fiók + bekapcsolt Bluetooth/Wi-Fi.
enum SummitHandoff {
    /// Info.plist-ben is deklarálva (NSUserActivityTypes — lásd a
    /// post-build scriptet), különben a másik eszköz nem folytathatja.
    static let activityType = "hu.flint.view"
    static let selectTab = Notification.Name("summit.selectTab")
    static let restoreTimetable = Notification.Name("summit.restoreTimetable")
}

/// Egyetlen NSUserActivity-t hirdet (tab + órarend-pozíció + Feladatok-
/// szegmens). Azonos payloadot nem publikál újra — ez állítja meg a
/// vissza-pingpongot, amikor két eszköz egymástól veszi át az állapotot.
final class HandoffCenter {
    static let shared = HandoffCenter()
    /// Fogadott, még fel nem dolgozott órarend-pozíció (a nézet még nem élt
    /// az értesítéskor) — a TimetableView onAppear emészti fel, 15 mp-ig érvényes.
    var pendingTimetable: (week: Int, day: Int, lesson: String?, at: Date)?
    /// Ugyanez a Feladatokhoz (szegmens + villanó sor) — a NotesView onAppear emészti.
    var pendingTasks: (segment: Int, flash: String?, at: Date)?
    private var activity: NSUserActivity?
    private var lastPayload: [AnyHashable: Any] = [:]
    private init() {}

    /// Tabváltás hirdetése (0 Főoldal, 1 Jegyek, 2 Órarend, 3 Watch, 4 Hiányzások, 5 Feladatok).
    func setTab(_ tab: Int) {
        var p = lastPayload
        p["tab"] = tab
        if tab != 2 { p.removeValue(forKey: "week"); p.removeValue(forKey: "day"); p.removeValue(forKey: "lesson") }
        if tab != 5 { p.removeValue(forKey: "seg"); p.removeValue(forKey: "flash") }
        publish(p)
    }

    func setTimetablePosition(weekOffset: Int, weekday: Int, lessonID: String? = nil) {
        var p = lastPayload
        p["tab"] = 2
        p["week"] = weekOffset
        p["day"] = weekday
        if let lessonID { p["lesson"] = lessonID } else { p.removeValue(forKey: "lesson") }
        publish(p)
    }

    func setTasksPosition(segment: Int, flashID: String? = nil) {
        var p = lastPayload
        p["tab"] = 5
        p["seg"] = segment
        if let flashID { p["flash"] = flashID } else { p.removeValue(forKey: "flash") }
        publish(p)
    }

    private func publish(_ payload: [AnyHashable: Any]) {
        guard !NSDictionary(dictionary: lastPayload).isEqual(to: payload) else { return }
        lastPayload = payload
        let a: NSUserActivity
        if let existing = activity {
            a = existing
        } else {
            a = NSUserActivity(activityType: SummitHandoff.activityType)
            a.title = "Summit"
            a.isEligibleForHandoff = true
            activity = a
            a.becomeCurrent()
        }
        a.userInfo = payload
        a.needsSave = true
    }

    /// Másik eszközről folytatás: a tabot a MainTabView, a pozíciót a
    /// cél-nézet állítja helyre (élő nézet direkt értesítéssel, még meg
    /// nem született nézet pending-gel).
    static func handle(_ activity: NSUserActivity) {
        guard activity.activityType == SummitHandoff.activityType,
              let info = activity.userInfo else { return }
        let now = Date()
        let tab = info["tab"] as? Int ?? 0
        if tab == 2 {
            let pending = (
                week: info["week"] as? Int ?? 0,
                day: info["day"] as? Int ?? 2,
                lesson: info["lesson"] as? String,
                at: now
            )
            shared.pendingTimetable = pending
            NotificationCenter.default.post(
                name: SummitHandoff.restoreTimetable, object: nil,
                userInfo: ["week": pending.week, "day": pending.day, "lesson": pending.lesson as Any])
        } else if tab == 5 {
            shared.pendingTasks = (
                segment: info["seg"] as? Int ?? 0,
                flash: info["flash"] as? String,
                at: now
            )
        }
        NotificationCenter.default.post(
            name: SummitHandoff.selectTab, object: nil, userInfo: ["tab": tab])
    }

    /// Órarend megnyitása egy adott óra napján (pl. óra-változás értesítés
    /// koppintásából): ugyanaz az út, mint a Handoff-folytatásé — élő nézet
    /// direkt értesítéssel, még meg nem született nézet pending-gel.
    static func openTimetable(at start: Date, lessonID: String?) {
        let cal = Calendar.current
        let current = KretaWeek.monday(for: Date())
        let days = cal.dateComponents([.day], from: current, to: cal.startOfDay(for: start)).day ?? 0
        let week = max(-8, min(8, Int(floor(Double(days) / 7.0))))
        var wd = cal.component(.weekday, from: start)
        if wd < 2 || wd > 6 { wd = 6 }
        let pending = (week: week, day: wd, lesson: lessonID, at: Date())
        shared.pendingTimetable = pending
        NotificationCenter.default.post(
            name: SummitHandoff.restoreTimetable, object: nil,
            userInfo: ["week": pending.week, "day": pending.day, "lesson": pending.lesson as Any])
        NotificationCenter.default.post(name: SummitHandoff.selectTab, object: nil, userInfo: ["tab": 2])
    }

    /// Pending-ürítés 15 mp-es érvényességgel (öreg folytatás ne írja felül
    /// a frisset — pl. később kézzel nyitott Feladatok szegmensét).
    func takeTimetable() -> (week: Int, day: Int, lesson: String?)? {
        guard let p = pendingTimetable, Date().timeIntervalSince(p.at) < 15 else {
            pendingTimetable = nil
            return nil
        }
        pendingTimetable = nil
        return (p.week, p.day, p.lesson)
    }
    func takeTasks() -> (segment: Int, flash: String?)? {
        guard let p = pendingTasks, Date().timeIntervalSince(p.at) < 15 else {
            pendingTasks = nil
            return nil
        }
        pendingTasks = nil
        return (p.segment, p.flash)
    }
}
