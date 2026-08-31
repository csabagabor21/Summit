import SwiftUI

struct MainTabView: View {
    @EnvironmentObject var theme: ThemeStore
    @EnvironmentObject var session: SessionStore
    @State private var selected: Int = ProcessInfo.processInfo.arguments.contains("-FIRKA_ABSENCES") ? 4 : 0
    private let switchToTasks = Notification.Name("flint.switchToTasks")
    private let switchToTimetable = Notification.Name("flint.switchToTimetable")

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
        .onReceive(NotificationCenter.default.publisher(for: switchToTasks)) { _ in
            withAnimation(.spring(response: 0.34, dampingFraction: 0.82)) { selected = 3 }
        }
        .onReceive(NotificationCenter.default.publisher(for: switchToTimetable)) { _ in
            withAnimation(.spring(response: 0.34, dampingFraction: 0.82)) { selected = 2 }
        }
        // Floating glass is system-provided on iOS 26; no custom glass on content cards
    }
}
