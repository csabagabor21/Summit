import SwiftUI

@main
struct SummitApp: App {
    @StateObject private var session = SessionStore()
    @StateObject private var kreta = KretaClient()
    @StateObject private var theme = ThemeStore()
    @StateObject private var completed = CompletedStore()
    @StateObject private var profileImages = ProfileImageStore()
    @StateObject private var analytics = AnalyticsStore()
    @Environment(\.scenePhase) private var scenePhase

    init() {
        // Live Activity háttér-ébresztés: óra/szünet végén az app
        // megnyitása nélkül is átkapcsol az activity.
        LiveActivityBackgroundRefresh.register()
    }

    /// Heartbeat egy helyről: ha az iskolanév üres vagy szűrt (pl. belépéskor
    /// nem jött meg az adatlap), a KRÉTA-adatlapból pótolja, csak utána küld.
    /// - Parameter event: nil = napi (előtér), különben azonnali esemény
    ///   ("login" belépéskor, "consent" bekapcsoláskor).
    private func sendHeartbeat(event: String? = nil) async {
        await session.refreshSchoolName(kreta: kreta)
        if let event {
            analytics.recordEvent(schoolName: session.selectedUser?.schoolName, event: event)
        } else {
            analytics.recordHeartbeat(schoolName: session.selectedUser?.schoolName)
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
                }
                .onChange(of: session.selectedId) { _, _ in
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
                    }
                }
        }
    }
}
