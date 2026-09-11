import SwiftUI

// 100% natív — 0 custom material / glass / spring a navigáción.
// Apple docs + WWDC26 Liquid Glass szabályai alapján:
//
// • "Use .tabViewStyle(.sidebarAdaptable) (iOS 18+ / iOS 26) to let the tab bar
//   adapt to sidebar on iPad/macOS while remaining a tab bar on iPhone.
//   Transitions fluidly with adaptive window sizes." — Axiom Liquid Glass Ref
//   (Apple HIG / WWDC 2025 - Liquid Glass + WWDC 2024 - TabView sessions)
// • "Glass is the navigation layer, never content. Do NOT apply .glassEffect()
//   to list rows — it competes with navigation." — u.a.
// • Compact (iPhone) → TabView bottom bar
//   Regular (iPad / Stage Manager széles) → Liquid Glass sidebar (drag-gal méretezhető)
//   Szűk ablak / Split View → visszaugrik bottom barra — hSize hack nélkül, a rendszer intézi.
// • AdaptiveAppShell (Apple Design Templates) ugyanezt használja:
//   compact = TabView, regular = NavigationSplitView — mi itt a modernebb
//   .sidebarAdaptable-t használjuk, mert iOS 18+ célon a rendszer oldja meg
//   a responsive váltást + Liquid Glass chrome-ot extra kód nélkül.
//
struct MainTabView: View {
    @EnvironmentObject var theme: ThemeStore
    @EnvironmentObject var session: SessionStore
    @EnvironmentObject var kreta: KretaClient
    @Environment(\.colorScheme) var scheme
    @State private var selected: Int = ProcessInfo.processInfo.arguments.contains("-FIRKA_ABSENCES") ? 4 : 0
    @ObservedObject private var notif = NotificationManager.shared
    private let switchToTasks = Notification.Name("summit.switchToTasks")
    private let switchToTimetable = Notification.Name("summit.switchToTimetable")
    private let switchToGrades = Notification.Name("summit.switchToGrades")

    var colors: AppColors { theme.colors(for: scheme) }

    var body: some View {
        Group {
            if #available(iOS 18.0, *) {
                nativeSidebar
            } else {
                phoneTabsLegacy
            }
        }
        .tint(colors.accent)
        // NINCS withAnimation(.spring) — a rendszer Liquid Glass morphja animál.
        // Custom spring felülírná a natív görbét és "cooked"-nak hat.
        .onReceive(NotificationCenter.default.publisher(for: switchToTasks)) { _ in
            selected = 3
        }
        .onReceive(NotificationCenter.default.publisher(for: switchToTimetable)) { _ in
            selected = 2
        }
        .onReceive(NotificationCenter.default.publisher(for: switchToGrades)) { _ in
            selected = 1
        }
        // Új jegy ünneplő kártya (diff, értesítés-koppintás vagy demo szimulálás után)
        .fullScreenCover(item: $notif.celebrationGrade) { grade in
            GradeCelebrationView(grade: grade)
        }
        // Halott KRÉTA-munkamenet: a KRÉTA a refresh tokent is elutasította —
        // ilyenkor az adatok már nem frissülnek maguktól, újra be kell lépni.
        // A "Később" csak a popupot nyugtatja: a pillanatnyi adatok a
        // képernyőn maradnak, és a MOST-kártya felett piros sáv jelzi,
        // hogy a KRÉTA-munkamenet már nem létezik.
        .alert("Munkamenet lejárt", isPresented: $kreta.showExpiredAlert) {
            Button("Bejelentkezés", role: .destructive) { session.logout() }
            Button("Később", role: .cancel) {}
        } message: {
            Text("A KRÉTA visszadobta a belépést, ezért az adatok nem frissülnek. Jelentkezz be újra a folytatáshoz.")
        }
    }

    // MARK: - iOS 18+ / iPadOS 26 natív — TabView sidebarAdaptable
    // - iPhone: bottom TabBar (Liquid Glass — floating, rendszer rajzolja)
    // - iPad nagy: Liquid Glass sidebar — a divider drag-gal méretezhető (rendszer)
    // - iPad Stage Manager / Split View szűk: automatikusan visszaugrik TabBar-ra
    // - Sem toolbar(removing:), sem listRowBackground(accentSoft), sem .balanced hack
    //   — mind rendszer. A tint adja az accentet, a többit a glass.
    @available(iOS 18.0, *)
    private var nativeSidebar: some View {
        TabView(selection: $selected) {
            Tab("Főoldal", systemImage: "house.fill", value: 0) {
                HomeView()
            }
            Tab("Jegyek", systemImage: "star.fill", value: 1) {
                GradesView()
            }
            Tab("Órarend", systemImage: "calendar", value: 2) {
                TimetableView()
            }
            Tab("Feladatok", systemImage: "checklist", value: 3) {
                NotesView()
            }
            Tab("Hiányzások", systemImage: "person.crop.rectangle.stack", value: 4) {
                AbsencesView()
            }
            Tab("Üzenetek", systemImage: "envelope.fill", value: 5) {
                MessagesView()
            }
        }
        .tabViewStyle(.sidebarAdaptable)
        // Ne tegyél ide .toolbarBackground vagy .glassEffect-et:
        // iOS 26-on a TabBar/Sidebar chrome magától Liquid Glass.
        // Content glass tilos — "glass can't sample other glass".
    }

    // MARK: - iOS 17 fallback (Summit target régebbi OS-en) — natív TabView
    private var phoneTabsLegacy: some View {
        TabView(selection: $selected) {
            HomeView().tabItem { Label("Főoldal", systemImage: "house.fill") }.tag(0)
            GradesView().tabItem { Label("Jegyek", systemImage: "star.fill") }.tag(1)
            TimetableView().tabItem { Label("Órarend", systemImage: "calendar") }.tag(2)
            NotesView().tabItem { Label("Feladatok", systemImage: "checklist") }.tag(3)
            AbsencesView().tabItem { Label("Hiányzások", systemImage: "person.crop.rectangle.stack") }.tag(4)
            MessagesView().tabItem { Label("Üzenetek", systemImage: "envelope.fill") }.tag(5)
        }
    }
}
