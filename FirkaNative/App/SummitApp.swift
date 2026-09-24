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
        // Live Activity háttér-ébresztés: óra/szünet végén az app
        // megnyitása nélkül is átkapcsol az activity.
        LiveActivityBackgroundRefresh.register()
        // Apple Watch: órarend + jegyek továbbítása az órára
        // (WatchConnectivity applicationContext — külön login nincs az órán).
        WatchSyncSender.activate()
        // Realtime szinkron: csak ha a GoogleService-Info.plist a
        // bundle-ben van; nélküle néma, a REST-út marad.
        SummitSync.configureIfNeeded()
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
        await session.refreshSchoolName(kreta: kreta)
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
                .tint(theme.accent)
                .preferredColorScheme(theme.mode.scheme)
                .onAppear {
                    // Macen (iPad-app Macen) ne tudjon pici ablakba zsugorodni
                    MacSupport.applyWindowSizing()
                    // Előtéri banner-delegált az értesítésekhez
                    NotificationManager.shared.configure()
                    kreta.accessToken = session.selectedUser?.accessToken
                    kreta.refreshToken = session.selectedUser?.refreshToken
                    kreta.instituteCode = session.selectedUser?.instituteCode
                    kreta.accessTokenExpire = session.selectedUser?.accessTokenExpire
                    // Token refresh perzisztálás (+ kliens-oldali lejárat szinkron,
                    // hogy a proaktív megújítás ne egy elavult dátummal számoljon)
                    kreta.onTokensRefreshed = { newAccess, newRefresh, expiresIn in
                        session.updateTokens(accessToken: newAccess, refreshToken: newRefresh, expiresIn: expiresIn)
                        kreta.accessTokenExpire = session.selectedUser?.accessTokenExpire
                    }
                    // takarítás: régi hardcoded flag már nem használt
                    UserDefaults.standard.removeObject(forKey: "timetable.useHardcoded")
                    // Frissítő (már belépett user) indításkor: ha nincs semmi
                    // beállítva, az admin iskolai naptár legyen a default.
                    if session.selectedUser != nil {
                        resolveSchoolCalendar()
                    }
                    // Apple Watch: megnyitásra menjen át az órarend + a
                    // jegyek az órára — nem kell hozzá tabokra menni.
                    Task { await WatchAutoPush.refreshIfNeeded(session: session, kreta: kreta, completed: completed) }
                }
                .onChange(of: session.selectedId) { _, _ in
                    // A szinkron fiókonkénti opt-in: váltáskor kikapcsol
                    // (a jelmondat marad, újbóli bekapcsolás ugyanoda köt).
                    summitSync.isEnabled = false
                    kreta.accessToken = session.selectedUser?.accessToken
                    kreta.refreshToken = session.selectedUser?.refreshToken
                    kreta.instituteCode = session.selectedUser?.instituteCode
                    kreta.accessTokenExpire = session.selectedUser?.accessTokenExpire
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
                        session.load()
                        let oldRT = kreta.refreshToken
                        kreta.accessToken = session.selectedUser?.accessToken
                        kreta.refreshToken = session.selectedUser?.refreshToken
                        kreta.instituteCode = session.selectedUser?.instituteCode
                        kreta.accessTokenExpire = session.selectedUser?.accessTokenExpire
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
        }
    }
}
