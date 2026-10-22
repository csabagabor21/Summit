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
    @Environment(\.horizontalSizeClass) private var hSize
    @State private var selected: Int = ProcessInfo.processInfo.arguments.contains("-FIRKA_ABSENCES") ? 4 : 0
    @ObservedObject private var notif = NotificationManager.shared
    @ObservedObject private var watchAvailability = WatchAvailability.shared
    @EnvironmentObject var completed: CompletedStore
    /// Széles elrendezés (iPad / Mac): itt a Watch saját sidebar-tabot kap.
    /// iPhone-on (compact) nincs tab — ott a Watch a Feladatok bal felső
    /// toolbar-gombjáról nyílik (lásd NotesView).
    private var isWide: Bool { hSize == .regular || MacSupport.isMac }
    private var watchTabVisible: Bool { watchAvailability.showTab && isWide }
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
        .tint(theme.isMinecraft ? MinecraftTheme.grass : colors.accent)
        // NINCS withAnimation(.spring) — a rendszer Liquid Glass morphja animál.
        // Custom spring felülírná a natív görbét és "cooked"-nak hat.
        .onReceive(NotificationCenter.default.publisher(for: switchToTasks)) { notif in
            // A Feladatok rendes tab (Watch előtt): minden deep-link
            // (órarendi pill, értesítés-koppintás, Handoff) ide visz.
            selected = 5
            // A tab tartalma lusta: az első váltáskor a NotesView még
            // nem él, így a szegmens/villanás elveszne — egyszer
            // újraküldjük, hogy a már élő nézet is megkapja. A relézett
            // példányon rajta a jel, így az már nem ütemez újat —
            // különben végtelen 0,4 mp-es lánc rángatna vissza a
            // Feladatokra, és onnan nem lehetne kilépni.
            if let info = notif.userInfo, info["summit.relayed"] == nil {
                var relayed = info
                relayed["summit.relayed"] = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                    NotificationCenter.default.post(name: switchToTasks, object: nil, userInfo: relayed)
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: switchToTimetable)) { _ in
            selected = 2
        }
        // Continuity (Handoff): másik eszközről folytatás — a tabot
        // itt állítjuk, a pozíciót a cél-nézet (pending vagy direkt).
        .onReceive(NotificationCenter.default.publisher(for: SummitHandoff.selectTab)) { notif in
            let tab = notif.userInfo?["tab"] as? Int ?? 0
            if tab == 0 || tab == 1 || tab == 2 || tab == 4 || tab == 5 {
                selected = tab
            } else if tab == 3 {
                // Watch-tab: széles elrendezésen saját tab van, iPhone-on
                // a Feladatokra esik vissza (ott a toolbar-gomb nyitja).
                selected = watchTabVisible ? 3 : 5
            }
        }
        .onChange(of: isWide) { _, wide in
            // Szűk ablakra váltva (Split View) a Watch-tab eltűnik —
            // nem maradhat érvénytelen kijelölés.
            if !wide, selected == 3 { selected = 5 }
        }
        .onChange(of: selected) { _, tab in
            // Minden tabváltást hirdetünk — a másik eszköz dockjában
            // ettől jön fel a Summit ikon az aktuális hellyel.
            HandoffCenter.shared.setTab(tab)
        }
        .onAppear {
            // Induláskor is legyen élő tevékenység (ne csak az első
            // tabváltástól) — megnyitásra a másik eszköz már látja.
            HandoffCenter.shared.setTab(selected)
        }
        .onReceive(NotificationCenter.default.publisher(for: switchToGrades)) { _ in
            selected = 1
        }
        // Új jegy ünneplő kártya (diff, értesítés-koppintás vagy demo szimulálás után)
        .fullScreenCover(item: $notif.celebrationGrade) { grade in
            GradeCelebrationView(grade: grade)
                // Értesítés-koppintás hidegindításkor a cover az első
                // layout-körben nyílik, amikor az örökölt environment még
                // nem ért le a prezentált hosting controllerbe (a crash-log
                // szerint a theme hiányzott) — ezért explicit inject, mint
                // az AnalyticsConsentView-nál a ContentView-ban.
                .environmentObject(theme)
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
            Tab(tabTitle(0), systemImage: tabIcon(0), value: 0) {
                HomeView()
            }
            Tab(tabTitle(1), systemImage: tabIcon(1), value: 1) {
                GradesView()
            }
            Tab(tabTitle(2), systemImage: tabIcon(2), value: 2) {
                TimetableView()
            }
            Tab(tabTitle(5), systemImage: tabIcon(5), value: 5) {
                NotesView()
            }
            Tab(tabTitle(4), systemImage: tabIcon(4), value: 4) {
                AbsencesView()
            }
            // Watch-tab CSAK széles elrendezésen (iPad / Mac sidebar) —
            // iPhone-on nincs (ott a Feladatok bal felső toolbar-gombja
            // nyitja, különben 6 tab már zsúfolt lenne).
            if watchTabVisible {
                Tab("Watch", systemImage: "applewatch", value: 3) {
                    CheatView()
                }
            }
        }
        .tabViewStyle(.sidebarAdaptable)
        // Ne tegyél ide .toolbarBackground vagy .glassEffect-et:
        // iOS 26-on a TabBar/Sidebar chrome magától Liquid Glass.
        // Content glass tilos — "glass can't sample other glass".
    }

    /// Minecraft-skinben blokkos ikonok + címek, különben a gyáriak.
    private func tabIcon(_ tab: Int) -> String {
        guard theme.isMinecraft else {
            switch tab {
            case 0: return "house.fill"
            case 1: return "star.fill"
            case 2: return "calendar"
            case 5: return "checklist"
            case 4: return "person.crop.rectangle.stack"
            case 3: return "applewatch"
            default: return "circle.fill"
            }
        }
        return MinecraftTheme.tabIcon(for: tab).1
    }
    private func tabTitle(_ tab: Int) -> String {
        guard theme.isMinecraft else {
            switch tab {
            case 0: return "Főoldal"
            case 1: return "Jegyek"
            case 2: return "Órarend"
            case 5: return "Feladatok"
            case 4: return "Hiányzások"
            case 3: return "Watch"
            default: return ""
            }
        }
        return MinecraftTheme.tabIcon(for: tab).0
    }

    // MARK: - iOS 17 fallback (Summit target régebbi OS-en) — natív TabView
    private var phoneTabsLegacy: some View {
        TabView(selection: $selected) {
            HomeView().tabItem { Label(tabTitle(0), systemImage: tabIcon(0)) }.tag(0)
            GradesView().tabItem { Label(tabTitle(1), systemImage: tabIcon(1)) }.tag(1)
            TimetableView().tabItem { Label(tabTitle(2), systemImage: tabIcon(2)) }.tag(2)
            NotesView().tabItem { Label(tabTitle(5), systemImage: tabIcon(5)) }.tag(5)
            AbsencesView().tabItem { Label(tabTitle(4), systemImage: tabIcon(4)) }.tag(4)
            if watchTabVisible {
                CheatView().tabItem { Label("Watch", systemImage: "applewatch") }.tag(3)
            }
        }
    }
}
