import SwiftUI

@main
struct FlintApp: App {
    @StateObject private var session = SessionStore()
    @StateObject private var kreta = KretaClient()
    @StateObject private var theme = ThemeStore()
    @StateObject private var completed = CompletedStore()
    @StateObject private var profileImages = ProfileImageStore()

    init() {
        // Live Activity háttér-ébresztés: óra/szünet végén az app
        // megnyitása nélkül is átkapcsol az activity.
        LiveActivityBackgroundRefresh.register()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(session)
                .environmentObject(kreta)
                .environmentObject(theme)
                .environmentObject(completed)
                .environmentObject(profileImages)
                .tint(theme.accent)
                .preferredColorScheme(theme.mode.scheme)
                .onAppear {
                    kreta.accessToken = session.selectedUser?.accessToken
                    kreta.refreshToken = session.selectedUser?.refreshToken
                    kreta.instituteCode = session.selectedUser?.instituteCode
                    // Token refresh perzisztálás
                    kreta.onTokensRefreshed = { newAccess, newRefresh, expiresIn in
                        session.updateTokens(accessToken: newAccess, refreshToken: newRefresh, expiresIn: expiresIn)
                    }
                    // takarítás: régi hardcoded flag már nem használt
                    UserDefaults.standard.removeObject(forKey: "timetable.useHardcoded")
                }
                .onChange(of: session.selectedId) { _, _ in
                    kreta.accessToken = session.selectedUser?.accessToken
                    kreta.refreshToken = session.selectedUser?.refreshToken
                    kreta.instituteCode = session.selectedUser?.instituteCode
                }
                .onChange(of: session.selectedUser?.accessToken) { _, new in
                    kreta.accessToken = new
                }
                .onChange(of: session.selectedUser?.refreshToken) { _, new in
                    kreta.refreshToken = new
                }
                .onChange(of: session.selectedUser?.instituteCode) { _, new in
                    kreta.instituteCode = new
                }
        }
    }
}
