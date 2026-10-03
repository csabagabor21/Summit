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
    @ObservedObject private var watchAvailability = WatchAvailability.shared
    @EnvironmentObject var completed: CompletedStore
    /// Óra nélküli iPhone-on nincs Watch tab (így a CheatView-cover sem
    /// él) — ilyenkor a Feladatok coverben nyílik (lásd switchToTasks).
    @State private var showingTasksCover = false
    @Environment(\.scenePhase) private var scenePhase
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
        .onReceive(NotificationCenter.default.publisher(for: switchToTasks)) { notif in
            #if targetEnvironment(macCatalyst)
            selected = 5
            #else
            if watchAvailability.showTab {
                selected = 3
                // A Watch-tab (CheatView) lusta: ha még sosem jártál ott,
                // nem él, így az értesítés elveszne — újraküldjük, hogy a
                // frissen született CheatView is kinyissa a Feladatok-covert.
                // (Már élő nézetnél az őre nyeli le, nincs hurok.)
                if let info = notif.userInfo {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                        NotificationCenter.default.post(name: switchToTasks, object: nil, userInfo: info)
                    }
                }
            } else if !showingTasksCover {
                // Óra nélküli iPhone: nincs Watch tab, így a CheatView
                // cover-reléje sem él — a Feladatok ilyenkor itt, coverben
                // nyílik. Az értesítést EGYSZER továbbküldjük, hogy a
                // NotesView szegmense + sorvillanása hasson; a saját
                // újraküldésünket az őr feltartóztatja (nincs hurok).
                showingTasksCover = true
                if let info = notif.userInfo {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                        NotificationCenter.default.post(name: switchToTasks, object: nil, userInfo: info)
                    }
                }
            }
            #endif
        }
        .fullScreenCover(isPresented: $showingTasksCover) {
            // Coverben "Kész" gomb is kell — nélküle az órarendi
            // dolgozat-pillből ide jutva nincs kiút a nézetből.
            NotesView(showCloseButton: true)
                .environmentObject(theme)
                .environmentObject(session)
                .environmentObject(kreta)
                .environmentObject(completed)
        }
        // Watch tab nélkül nincs min állni: ha épp azon álltál, amikor
        // eltűnt (párosítás törlése), vissza a Főoldalra (különben üres
        // lapon ragadnál). A szinkronizált órajel (peerHasWatch) miatt
        // a showTab-ot figyeljük, nem csak a helyi párosítást.
        .onChange(of: watchAvailability.showTab) { _, has in
            if !has, selected == 3 { selected = 0 }
        }
        .onAppear { watchAvailability.refresh() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { watchAvailability.refresh() }
        }
        .onReceive(NotificationCenter.default.publisher(for: switchToTimetable)) { _ in
            selected = 2
        }
        // Continuity (Handoff): másik eszközről folytatás — a tabot
        // itt állítjuk, a pozíciót a cél-nézet (pending vagy direkt).
        .onReceive(NotificationCenter.default.publisher(for: SummitHandoff.selectTab)) { notif in
            let tab = notif.userInfo?["tab"] as? Int ?? 0
            #if targetEnvironment(macCatalyst)
            if tab == 5 {
                selected = 5
            } else if tab == 0 || tab == 1 || tab == 2 || tab == 4 {
                selected = tab
            }
            // 3-as (Watch) Macen nincs külön tab — marad az aktuális.
            #else
            if tab == 5 {
                // iPhone/iPad: a Feladatok coverben nyílik (a NotesView
                // onAppear alkalmazza a pendingTasks-et) — ez MINDIG
                // működik, a Watch-tab reléjétől függetlenül.
                showingTasksCover = true
            } else if tab == 0 || tab == 1 || tab == 2 || tab == 4 {
                selected = tab
            }
            // 3-as (Watch) tab: csak órával jön — nélküle marad az aktuális.
            #endif
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
            Tab("Főoldal", systemImage: "house.fill", value: 0) {
                HomeView()
            }
            Tab("Jegyek", systemImage: "star.fill", value: 1) {
                GradesView()
            }
            Tab("Órarend", systemImage: "calendar", value: 2) {
                TimetableView()
            }
            Tab("Hiányzások", systemImage: "person.crop.rectangle.stack", value: 4) {
                AbsencesView()
            }
            // Helyi vagy szinkronizált óra nélkül nincs Watch tab a
            // dockban/sidebarban — Macen a telefon órája nyitja (jegyzet
            // Macről is készíthető, átmegy a telefonra, onnan az órára).
            if watchAvailability.showTab {
                Tab("Watch", systemImage: "applewatch", value: 3) {
                    CheatView()
                }
            }
            #if targetEnvironment(macCatalyst)
            // Macen van hely bőven: a Feladatok külön sidebar-elemet kap
            // (iPhone-on a Főoldal- és Watch-tab linkjei visznek oda).
            Tab("Feladatok", systemImage: "checklist", value: 5) {
                NotesView()
            }
            #endif
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
            AbsencesView().tabItem { Label("Hiányzások", systemImage: "person.crop.rectangle.stack") }.tag(4)
            if watchAvailability.showTab {
                CheatView().tabItem { Label("Watch", systemImage: "applewatch") }.tag(3)
            }
        }
    }
}
