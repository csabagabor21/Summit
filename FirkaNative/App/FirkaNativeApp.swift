import SwiftUI

@main
struct FirkaNativeApp: App {
    @StateObject private var session = SessionStore()
    @StateObject private var kreta = KretaClient()
    @StateObject private var theme = ThemeStore()
    @StateObject private var completed = CompletedStore()
    @StateObject private var profileImages = ProfileImageStore()

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
                .onAppear { kreta.accessToken = session.selectedUser?.accessToken }
                .onChange(of: session.selectedId) { _, _ in
                    kreta.accessToken = session.selectedUser?.accessToken
                    kreta.refreshToken = session.selectedUser?.refreshToken
                }
        }
    }
}
