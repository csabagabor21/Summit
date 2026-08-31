import SwiftUI

struct MainTabView: View {
    @EnvironmentObject var theme: ThemeStore
    @EnvironmentObject var session: SessionStore
    @State private var selected: Int = 0

    @Environment(\.colorScheme) var scheme
    var colors: AppColors { theme.colors(for: scheme) }

    var body: some View {
        // Native TabView — system provides Liquid Glass tab bar on iOS 26+ automatically (functional layer)
        TabView(selection: $selected) {
            HomeView()
                .tabItem { Label("Főoldal", systemImage: "house.fill") }
                .tag(0)
            GradesView()
                .tabItem { Label("Jegyek", systemImage: "star.fill") }
                .tag(1)
            TimetableView()
                .tabItem { Label("Órarend", systemImage: "calendar") }
                .tag(2)
            NotesView()
                .tabItem { Label("Feladatok", systemImage: "checklist") }
                .tag(3)
            AbsencesView()
                .tabItem { Label("Hiányzások", systemImage: "person.crop.rectangle.stack") }
                .tag(4)
        }
        .tint(colors.accent)
        // Content flows under bars — HIG
        .toolbarBackground(.visible, for: .tabBar)
        // Floating glass is system-provided on iOS 26; no custom glass on content cards
    }
}
