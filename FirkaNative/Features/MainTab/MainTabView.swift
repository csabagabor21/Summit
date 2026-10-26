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
    @State private var selected: Int = ProcessInfo.processInfo.arguments.contains("-FIRKA_ABSENCES") ? 4 : (ProcessInfo.processInfo.arguments.contains("-FIRKA_TIMETABLE") ? 2 : 0)
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

    /// Tab-tartalom (natív sávval vagy anélkül — a chrome-döntés lent).
    private var tabContent: some View {
        Group {
            if #available(iOS 18.0, *) {
                nativeSidebar
            } else {
                phoneTabsLegacy
            }
        }
    }

    var body: some View {
        // A Voxel-talaj és a hotbar MINDIG overlay-ként van jelen (üres,
        // ha nem kell), nem `if useCustomHotbar { … } else { tabContent }`
        // ágban: az ág-váltás (skinváltás, vagy Max/Plus iPhone elforgatása
        // → széles elrendezés) új identitást adott a teljes tab-fának —
        // minden NavigationStack és a kiválasztott tab elveszett, a user a
        // Főoldal gyökerére esett vissza.
        //
        // Voxel minden méretosztályban: a dock (talaj + hotbar) az oldal
        // alja, nem a képernyő alja — a tab-tartalom kerete a fű tetejénél
        // véget ér (alsó padding, csak érték vált, a nézet-fa azonos
        // marad), így görgetéskor és az alsó rugózásnál (túlhúzás →
        // visszaugrás) sem csúszik semmi a föld mögé iPaden/Macen sem: a
        // lista a fűnél áll meg, fölötte nyílik az ég-rés. A tabok alsó
        // safe area-ja (`voxelTabChrome`) már csak a talajból kilógó
        // virágokat kerüli ki. A hotbar a földön ül, témahűen középre
        // igazítva; a talaj teljes szélességben fut ki. Csak a
        // Summit-alaptémában marad szélesen a natív sidebar. Külön ég
        // nincs a tab-tartalom mögött (a lista saját ege tölti ki a képet).
        tabContent
            .padding(.bottom, useCustomHotbar ? Self.voxelFooterHeight : useCPBar ? NeonTabBar.height(wide: isWide) : 0)
            .overlay(alignment: .bottom) {
                if useCustomHotbar {
                    // Díszlet: nem nyel érintést. Eddig a teljes 148 pt-os
                    // talaj-sáv elnyelte a koppintást ÉS a görgetés indítását
                    // minden tab alján (a lista alulról felhúzva nem mozdult,
                    // a fű mögé csúszó sorok halottak voltak).
                    VoxelGrassBlockFooter(height: Self.voxelFooterHeight)
                        .allowsHitTesting(false)
                }
            }
            .overlay(alignment: .bottom) {
                if useCustomHotbar {
                    // Csak maga a hotbar (a slot-gombok egymás mellett, rés
                    // nélkül) fogad érintést; körülötte a görgetés indulhat.
                    voxelHotbar.padding(.bottom, 6)
                }
            }
            .overlay(alignment: .bottom) {
                // Neon minden méretosztályban: saját HUD-sáv (a rendszer-
                // tabsáv rejtve, a tartalom alja a sáv fölött áll meg —
                // `voxelTabChrome(inset:)`), iPaden/Macen is teljes
                // szélességben az oldal alján.
                // Szintén mindig jelen lévő overlay, hogy a skinváltás ne
                // adjon új identitást a tab-fának.
                if useCPBar { cpTabBar }
            }
        .tint(theme.isVoxel ? VoxelTheme.grass : colors.accent)
        // Chrome-betűk a látható sávokra is (az init-kori beállítás
        // a már élő sávokon nem mindig fog meg).
        .onAppear {
            theme.skin.applyChromeAppearance()
            VoxelSound.warmUp()
            NeonSound.warmUp()
        }
        .onChange(of: theme.isVoxel) { _, mc in
            if mc { VoxelSound.warmUp() }
        }
        .onChange(of: theme.isNeon) { _, cp in
            if cp { NeonSound.warmUp() }
        }
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
        .onReceive(NotificationCenter.default.publisher(for: switchToTimetable)) { notif in
            selected = 2
            // Mint a Feladatoknál: az Órarend tab tartalma lusta — ha még
            // sosem nyitották meg, a TimetableView nem él, és a „Mutatás az
            // órarendben" ugrás elveszne. Egyszer újraküldjük (a relézett
            // példányon jelölés van, az már nem ütemez újat); a TimetableView
            // a már kezelt kérés ismétlését eldobja.
            if let info = notif.userInfo, info["summit.relayed"] == nil {
                var relayed = info
                relayed["summit.relayed"] = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                    NotificationCenter.default.post(name: switchToTimetable, object: nil, userInfo: relayed)
                }
            }
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
            // Programozott tabváltásnál (deep-link, Handoff) nincs
            // dock-callback — a hangot itt pótoljuk, ha nincs custom dock.
            if theme.isVoxel, !useCustomHotbar { VoxelSound.play(.tab) }
            if theme.isNeon, !useCPBar { NeonSound.play(.tab) }
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
    // - Témázott (Voxel/Neon) skinben a `.tabBar` toolbar minden
    //   méretosztályban rejtett (`voxelTabChrome(hidden:)`): sem az iPad
    //   felső tabsáv, sem a sidebar nem jön át, a custom dock veszi át
    //   a helyét az oldal alján. A `.sidebarAdaptable` stílus ilyenkor
    //   csak a Summit-alaptéma széles sávját adja.
    // - Sem toolbar(removing:), sem listRowBackground(accentSoft), sem .balanced hack
    //   — mind rendszer. A tint adja az accentet, a többit a glass.
    @available(iOS 18.0, *)
    private var nativeSidebar: some View {
        TabView(selection: $selected) {
            Tab(value: 0) {
                HomeView().voxelTabChrome(hidden: hidesSystemTabBar, inset: customBarInset).id(voxelRootTokens[0, default: 0])
            } label: { tabLabel(0) }
            Tab(value: 1) {
                GradesView().voxelTabChrome(hidden: hidesSystemTabBar, inset: customBarInset).id(voxelRootTokens[1, default: 0])
            } label: { tabLabel(1) }
            Tab(value: 2) {
                TimetableView().voxelTabChrome(hidden: hidesSystemTabBar, inset: customBarInset).id(voxelRootTokens[2, default: 0])
            } label: { tabLabel(2) }
            Tab(value: 5) {
                NotesView().voxelTabChrome(hidden: hidesSystemTabBar, inset: customBarInset).id(voxelRootTokens[5, default: 0])
            } label: { tabLabel(5) }
            Tab(value: 4) {
                AbsencesView().voxelTabChrome(hidden: hidesSystemTabBar, inset: customBarInset).id(voxelRootTokens[4, default: 0])
            } label: { tabLabel(4) }
            // Watch-tab CSAK széles elrendezésen (iPad / Mac sidebar) —
            // iPhone-on nincs (ott a Feladatok bal felső toolbar-gombja
            // nyitja, különben 6 tab már zsúfolt lenne).
            if watchTabVisible {
                Tab(value: 3) {
                    CheatView()
                } label: { tabLabel(3) }
            }
        }
        // Custom docknál NEM elég a `.tabBar` toolbar elrejtése:
        // `.sidebarAdaptable` mellett iPaden a navigációs sávban ott
        // marad a rendszer sidebar-kapcsológombja, amiből a natív
        // sidebar (dupla navigáció) nyílik. Ezért ilyenkor a stílus
        // `.tabBarOnly` — nincs sidebar, nincs kapcsoló, az alsó sávot
        // pedig a `voxelTabChrome` rejti. Summit-alaptémában marad a
        // `.sidebarAdaptable`. (A stílusváltás skinváltáskor iPaden
        // újraépítheti a tab-fát — ez az ára annak, hogy a natív dock
        // se gombként, se sávként ne jöjjön át.)
        .summitTabStyle(customDock: hidesSystemTabBar)
        // Ne tegyél ide .toolbarBackground vagy .glassEffect-et:
        // iOS 26-on a TabBar/Sidebar chrome magától Liquid Glass.
        // Content glass tilos — "glass can't sample other glass".
    }

    /// Tab-címke: Summitban a gyári `Label(cím, systemImage:)`, Voxelben
    /// az eredeti item-textúra (előre, élesen felnagyítva — a tab-sáv
    /// maga simítaná a 16 px-es képet) a széles elrendezés sávjában.
    @ViewBuilder
    private func tabLabel(_ tab: Int) -> some View {
        if theme.isVoxel, let ui = VoxelTheme.tabBarImage(for: tab) {
            Label { Text(tabTitle(tab)) } icon: { Image(uiImage: ui) }
        } else {
            Label(tabTitle(tab), systemImage: tabIcon(tab))
        }
    }

    /// Voxel-skinben blokkos ikonok + címek, különben a gyáriak.
    private func tabIcon(_ tab: Int) -> String {
        if theme.isNeon { return Self.cpTabIcon(tab) }
        guard theme.isVoxel else {
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
        return VoxelTheme.tabIcon(for: tab).1
    }
    /// Voxel-skinben a rendszer-tabsáv MINDEN méretosztályban rejtve —
    /// helyette saját hotbar jön a fűblokkra iPaden és Macen (Catalyst)
    /// is. Korábban a `!isWide` kapu miatt széles kijelzőn a natív
    /// `.sidebarAdaptable` sáv (iPad felső tabsáv / sidebar) maradt, és
    /// a custom dock egyáltalán nem jelent meg — a user ezt látta úgy,
    /// hogy „átjön a normál iPad dock". A Summit-alaptémában nincs
    /// custom dock, ott a natív széles sáv továbbra is marad.
    private var useCustomHotbar: Bool { theme.isVoxel }
    /// Neon-skinben saját HUD-tabsáv (lásd `NeonTabBar`) minden
    /// méretosztályban, iPaden/Macen is — lásd `useCustomHotbar`.
    private var useCPBar: Bool { theme.isNeon }
    /// Rejtett-e a rendszer-tabsáv (saját sáv van helyette).
    private var hidesSystemTabBar: Bool { useCustomHotbar || useCPBar }
    /// A tab-tartalom alsó tartaléka a saját sáv fölött: Voxelben a
    /// talajból a tartalom elé kilógó virágok magassága, Neonban egy
    /// kis levegő — a sávokat magát a `body` alsó paddingje már kivette
    /// a tartalom keretéből (a dock az oldal alja, nem a képernyő alja).
    private var customBarInset: CGFloat {
        useCPBar ? 8 : VoxelFlora.maxHeight
    }

    /// Neon-tabikonok: körvonalas (nem kitöltött) SF-szimbólumok —
    /// vékony HUD-rajzolat.
    static func cpTabIcon(_ tab: Int) -> String {
        switch tab {
        case 0: return "house"
        case 1: return "star"
        case 2: return "calendar"
        case 5: return "checklist"
        case 4: return "person.crop.rectangle.stack"
        case 3: return "applewatch"
        default: return "circle"
        }
    }

    /// Neon-dock ikonjai: a játék hub-atlaszának (`hub_atlas_1080p`)
    /// eredeti fül-ikonjai, tartalmi leképezéssel (lásd `NeonTabBar`).
    static func cpTabAsset(_ tab: Int) -> String {
        switch tab {
        case 0: return "img_neo_tab_home"
        case 1: return "img_neo_tab_grades"
        case 2: return "img_neo_tab_timetable"
        case 5: return "img_neo_tab_tasks"
        case 4: return "img_neo_tab_absences"
        default: return "img_neo_tab_home"
        }
    }

    /// Saját Neon HUD-tabsáv. Újrakoppintás az aktív fülre: a tab
    /// verme a gyökérre ugrik (mint a hotbaron / rendszer-sávon).
    /// Dock-elemek: az öt fő tab, plusz széles elrendezésen a Watch —
    /// ott eddig a natív sidebar vitte, a custom dockban is elérhető
    /// kell legyen (játék-atlasz ikonja nincs, SF-szimbólumot kap).
    private var neonDockItems: [NeonTabBar.Item] {
        var items = [0, 1, 2, 5, 4].map { NeonTabBar.Item(tab: $0, icon: Self.cpTabAsset($0), title: tabTitle($0)) }
        if watchTabVisible {
            items.append(NeonTabBar.Item(tab: 3, icon: "", title: tabTitle(3), systemIcon: "applewatch"))
        }
        return items
    }

    private var cpTabBar: some View {
        NeonTabBar(
            items: neonDockItems,
            selected: selected
        ) { tab in
            SummitHaptics.selection()
            NeonSound.play(.tab)
            if tab == selected {
                voxelRootTokens[tab, default: 0] += 1
            } else {
                selected = tab
            }
        }
    }
    /// Hotbar-újrakoppintás: az aktív slotra koppintva a tab navigációs
    /// verme a gyökérre ugrik (mint a rendszer-tabsávon) — az új azonosító
    /// újraépíti a tab NavigationStackjét.
    @State private var voxelRootTokens: [Int: Int] = [:]
    /// A fűblokk-talaj magassága a home-jelző fölött.
    static let voxelFooterHeight: CGFloat = 148

    /// Hotbar-slotok: (tab, eredeti item-sprite, cím). Széles
    /// elrendezésen a Watch is slotot kap (iránytű-sprite), különben
    /// iPaden/Macen a custom dockból nem lenne elérhető.
    private var voxelTabs: [(Int, String, String)] {
        var tabs = [(0, "img_blk_grass_side", "Főoldal"), (1, "img_blk_item_diamond", "Jegyek"),
                    (2, "img_blk_item_clock", "Órarend"), (5, "img_blk_item_writable_book", "Feladatok"),
                    (4, "img_blk_item_barrier", "Hiányzások")]
        if watchTabVisible { tabs.append((3, "img_blk_item_compass", "Watch")) }
        return tabs
    }

    /// Saját voxel-hotbar (lásd `VoxelHotbar`): a kijelölt slot neve a
    /// sáv fölött, a játékbeli szöveg-árnyékkal.
    private var voxelHotbar: some View {
        VoxelHotbar(
            slots: voxelTabs.map { VoxelHotbar.Slot(tab: $0.0, sprite: $0.1, title: $0.2) },
            selected: selected
        ) { tab in
            SummitHaptics.selection()
            // A hotbar-slot kattan, mint a játékban (csak MC-skinben szól) —
            // a tabsáv a legerősebb kattanás, a sima gomboké halkabb.
            VoxelSound.play(.tab)
            if tab == selected {
                voxelRootTokens[tab, default: 0] += 1
            } else {
                selected = tab
            }
        }
    }

    private func tabTitle(_ tab: Int) -> String {
        guard theme.isVoxel else {
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
        return VoxelTheme.tabIcon(for: tab).0
    }

    // MARK: - iOS 17 fallback (Summit target régebbi OS-en) — natív TabView
    private var phoneTabsLegacy: some View {
        TabView(selection: $selected) {
            HomeView().voxelTabChrome(hidden: hidesSystemTabBar, inset: customBarInset).tabItem { tabLabel(0) }.tag(0)
            GradesView().voxelTabChrome(hidden: hidesSystemTabBar, inset: customBarInset).tabItem { tabLabel(1) }.tag(1)
            TimetableView().voxelTabChrome(hidden: hidesSystemTabBar, inset: customBarInset).tabItem { tabLabel(2) }.tag(2)
            NotesView().voxelTabChrome(hidden: hidesSystemTabBar, inset: customBarInset).tabItem { tabLabel(5) }.tag(5)
            AbsencesView().voxelTabChrome(hidden: hidesSystemTabBar, inset: customBarInset).tabItem { tabLabel(4) }.tag(4)
            if watchTabVisible {
                CheatView().tabItem { tabLabel(3) }.tag(3)
            }
        }
    }
}

private extension View {
    /// TabView-stílus a dock-döntéshez: custom docknál `.tabBarOnly`
    /// (különben iPaden maradna a sidebar és a kapcsoló-gombja),
    /// különben a szélesen adaptív natív sáv/sidebar.
    @ViewBuilder
    func summitTabStyle(customDock: Bool) -> some View {
        if customDock {
            self.tabViewStyle(.tabBarOnly)
        } else {
            self.tabViewStyle(.sidebarAdaptable)
        }
    }
}

/// Tabrejtés: témázott skinben minden méretosztályban elrejti a
/// rendszer-tabsávot (iPaden a felső sávot/sidebart is — helyette a
/// saját dock látszik az oldal alján).
private extension View {
    /// Egyetlen, ág nélküli lánc (a `hidden` és az `inset` csak értékeket
    /// vált): skinváltáskor a tab gyökere — és vele a NavigationStack —
    /// megmarad.
    func voxelTabChrome(hidden: Bool, inset: CGFloat) -> some View {
        self.toolbar(hidden ? .hidden : .automatic, for: .tabBar)
            // Alsó tartalék a saját sáv fölött: Voxelben a talajból
            // kilógó növények, Neonban egy kis levegő (a sávok a
            // tartalom keretén kívül vannak, lásd `body`) — a lista vége
            // ennyivel a sáv fölött áll meg.
            .safeAreaInset(edge: .bottom, spacing: 0) {
                Color.clear
                    .frame(height: hidden ? inset : 0)
                    .allowsHitTesting(false)
            }
    }
}

/// Voxel Java/Bedrock hotbar, pixelrácsra rajzolva: 1 játék-pixel =
/// `px` pt, minden él egész számú játék-pixelre esik, nincs lekerekítés.
/// A slotok 20×20 px-esek (1 px sötét keret, 1 px letört él, 16×16 px
/// belső tér az itemnek), a kijelölést a vanilla `hotbar_selection`
/// mintájú, slotonként 2 px-szel túlnyúló fehér keret jelzi. A kijelölt
/// item neve a sáv fölött áll fehér Voxel-betűvel, 1 px-es
/// (#3F3F3F) szövegárnyékkal.
private struct VoxelHotbar: View {
    struct Slot: Identifiable {
        let tab: Int
        let sprite: String
        let title: String
        var id: Int { tab }
    }

    let slots: [Slot]
    let selected: Int
    let onSelect: (Int) -> Void

    @Environment(\.horizontalSizeClass) private var hotbarHSize
    /// Egy játék-pixel pontban (3 pt → 6/9 fizikai pixel, mindig egész).
    /// iPaden (regular) 4 pt: a hotbar arányos marad a széles kijelzőn is,
    /// iPhone-on változatlanul 3 pt.
    private var px: CGFloat { hotbarHSize == .regular ? 4 : 3 }
    private let slotPx = 20
    private var barWidthPx: Int { slotPx * slots.count + 2 }
    private let barHeightPx = 22

    private var selectedIndex: Int? { slots.firstIndex { $0.tab == selected } }
    private var selectedTitle: String { slots.first { $0.tab == selected }?.title ?? "" }

    var body: some View {
        VStack(spacing: 2 * px) {
            itemName
            ZStack(alignment: .topLeading) {
                barArt
                ForEach(Array(slots.enumerated()), id: \.element.id) { index, slot in
                    VoxelTheme.voxelPixelImage(slot.sprite, size: 16 * px)
                        .offset(x: CGFloat(1 + index * slotPx + 2) * px,
                                y: 3 * px)
                        .allowsHitTesting(false)
                }
                selectionFrame
                ForEach(Array(slots.enumerated()), id: \.element.id) { index, slot in
                    Button { onSelect(slot.tab) } label: {
                        Color.clear
                            .frame(width: CGFloat(slotPx) * px, height: CGFloat(barHeightPx) * px)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Text(slot.title))
                    .accessibilityAddTraits(slot.tab == selected ? .isSelected : [])
                    .offset(x: CGFloat(1 + index * slotPx) * px - px)
                }
            }
            .frame(width: CGFloat(barWidthPx) * px, height: CGFloat(barHeightPx) * px,
                   alignment: .topLeading)
        }
    }

    /// A kijelölt item neve: fehér szöveg + sötétszürke árnyék 1 px-szel
    /// jobbra-le, váltáskor áttűnéssel (mint a játékban).
    private var itemName: some View {
        let font = VoxelFontLoader.font(size: 8 * px)
        return ZStack(alignment: .topLeading) {
            Text(selectedTitle)
                .font(font)
                .foregroundStyle(Color(red: 0.247, green: 0.247, blue: 0.247))
                .offset(x: px, y: px)
            Text(selectedTitle)
                .font(font)
                .foregroundStyle(.white)
        }
        .fixedSize()
        .padding(.trailing, px)
        .padding(.bottom, px)
        .id(selected)
        .transition(.opacity.animation(.easeOut(duration: 0.18)))
        .accessibilityHidden(true)
        // Csak felirat: a mögötte lévő lista görgethető marad.
        .allowsHitTesting(false)
        .frame(height: 12 * px)
    }

    /// Sáv + slotok. Koordináták játék-pixelben.
    private var barArt: some View {
        Canvas { ctx, _ in
            func rect(_ x: Int, _ y: Int, _ w: Int, _ h: Int, _ c: Color) {
                ctx.fill(Path(CGRect(x: CGFloat(x) * px, y: CGFloat(y) * px,
                                     width: CGFloat(w) * px, height: CGFloat(h) * px)), with: .color(c))
            }
            // Sötét, áttetsző alap + 1 px külső keret.
            rect(0, 0, barWidthPx, barHeightPx, Color(white: 0.06, opacity: 0.88))
            rect(1, 1, barWidthPx - 2, barHeightPx - 2, Color(white: 0.16, opacity: 0.80))
            for i in 0..<slots.count {
                let x = 1 + i * slotPx
                // Slot-keret (sötét) és 18×18-as test.
                rect(x, 1, slotPx, 20, Color(white: 0.04, opacity: 0.95))
                rect(x + 1, 2, 18, 18, Color(white: 0.42, opacity: 0.62))
                // Letört élek: bal/felső sötét, jobb/alsó világos.
                rect(x + 1, 2, 18, 1, Color(white: 0.215, opacity: 0.95))
                rect(x + 1, 2, 1, 18, Color(white: 0.215, opacity: 0.95))
                rect(x + 1, 19, 18, 1, Color(white: 1.0, opacity: 0.55))
                rect(x + 18, 2, 1, 18, Color(white: 1.0, opacity: 0.55))
                // A két sarok (egyetlen pixel) a klasszikus slot szerint.
                rect(x + 1, 19, 1, 1, Color(white: 0.42, opacity: 0.62))
                rect(x + 18, 2, 1, 1, Color(white: 0.42, opacity: 0.62))
            }
        }
        .frame(width: CGFloat(barWidthPx) * px, height: CGFloat(barHeightPx) * px)
        .allowsHitTesting(false)
    }

    /// Kijelölő keret: 24×24 px, 1 px fekete külső él, 2 px fehér gyűrű,
    /// 1 px világosszürke belső él; a slotot minden oldalon 2 px-szel
    /// túllépi (a belső 16×16 itemtér szabad marad).
    private var selectionFrame: some View {
        Canvas { ctx, _ in
            guard let i = selectedIndex else { return }
            // A vászon 2 px-szel nagyobb a sávnál minden oldalon, hogy a
            // túlnyúló keret ne vágódjon le.
            let ox = 1 + i * slotPx
            let oy = 1
            func ring(_ inset: Int, _ c: Color) {
                let side = 24 - inset * 2
                let outer = CGRect(x: CGFloat(ox + inset) * px, y: CGFloat(oy + inset) * px,
                                   width: CGFloat(side) * px, height: CGFloat(side) * px)
                let inner = outer.insetBy(dx: px, dy: px)
                var p = Path(outer)
                p.addRect(inner)
                ctx.fill(p, with: .color(c), style: FillStyle(eoFill: true))
            }
            ring(0, Color(white: 0.0, opacity: 0.9))
            ring(1, .white)
            ring(2, .white)
            ring(3, Color(white: 0.55))
        }
        .frame(width: CGFloat(barWidthPx + 4) * px, height: CGFloat(barHeightPx + 4) * px)
        .offset(x: -2 * px, y: -2 * px)
        .allowsHitTesting(false)
    }
}

/// Neon hub-fülsor alsó dockként: a játékban nincs alsó
/// tabsáv, a legközelebbi rokon a hub-menü felső fül-sora (ikon +
/// nagybetűs felirat, a kiválasztott alatt vörös jelölés). Az ikonok a
/// játék eredeti `hub_atlas_1080p.xbm` atlaszának darabjai (WolvenKit
/// unbundle + BC7-dekódolás, az `.inkatlas` UV-rectjei alapján vágva,
/// fehér sablonként színezve — `img_neo_tab_*` imagesetek):
/// Főoldal = `ico_inventory_hub` (hátizsák), Jegyek = `ico_stats_hub`
/// (STATS), Órarend = `ico_data_hub` (DATA-lista), Feladatok =
/// `ico_journal_hub` (TASKS-napló), Hiányzások = `ico_character_hub`
/// (személy/jelenlét). A kijelölt cella háttere az `atlas_tabs`
/// `button_big2_bg_tab` fül-formája mélyvörösre festve, alatta a
/// `button_big2_bg_tab_line` vörös jelölővonala — ahogy a játék
/// hub-fülénél. A sáv alapja a menük sötét alapja, halvány eredeti
/// `tex_neo_pattern` mintával. Működés változatlan: 60 pt magasság,
/// koppintás + újrakoppintásra gyökérre ugrás a hívóban.
/// Statikus, olcsó nézet: nincs animáció, nincs üveg.
struct NeonTabBar: View {
    struct Item: Identifiable {
        let tab: Int
        /// Eredeti játék-ikon assetneve (`img_neo_tab_*`).
        let icon: String
        let title: String
        /// SF-szimbólum, ha a tabhoz nincs játék-atlasz ikon (Watch).
        var systemIcon: String? = nil
        var id: Int { tab }
    }
    var items: [Item]
    var selected: Int
    var onSelect: (Int) -> Void
    @Environment(\.horizontalSizeClass) private var hSize
    /// Széles elrendezés (iPad): a sáv arányosan magasabb, nagyobb ikonokkal.
    private var isWideLayout: Bool { hSize == .regular }

    /// A sáv magassága a home-jelző fölött (a tartalom ennyivel előbb áll meg).
    static let height: CGFloat = 60
    /// Méretosztályhoz igazított sávmagasság (iPhone: 60, iPad: 72).
    static func height(wide: Bool) -> CGFloat { wide ? 72 : height }

    var body: some View {
        VStack(spacing: 0) {
            ZStack(alignment: .leading) {
                Rectangle().fill(NeonTheme.red.opacity(0.5)).frame(height: 1)
                Rectangle().fill(NeonTheme.red).frame(width: 56, height: 2)
            }
            .frame(height: 2)
            HStack(spacing: 4) {
                ForEach(items) { item in
                    let on = item.tab == selected
                    Button { onSelect(item.tab) } label: {
                        cell(item, on: on)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(item.title)
                    .accessibilityAddTraits(on ? [.isSelected, .isButton] : .isButton)
                }
            }
            .padding(.horizontal, 8)
            .padding(.top, 6)
            .padding(.bottom, 4)
        }
        // Teljes szélesség minden méretosztályban: iPaden/Macen az
        // overlay csak a tartalom szélességét ajánlaná fel, a sávnak
        // viszont az oldal alját végig ki kell töltenie.
        .frame(maxWidth: .infinity)
        .frame(height: Self.height(wide: isWideLayout), alignment: .top)
        .background {
            ZStack {
                NeonTheme.bg.opacity(0.96)
                NeonGamePattern(opacity: 0.05)
            }
            .ignoresSafeArea(edges: .bottom)
        }
    }

    private func cell(_ item: Item, on: Bool) -> some View {
        VStack(spacing: 3) {
            if let systemIcon = item.systemIcon {
                Image(systemName: systemIcon)
                    .font(.system(size: isWideLayout ? 24 : 20, weight: .regular))
                    .frame(width: isWideLayout ? 28 : 24, height: isWideLayout ? 28 : 24)
            } else {
                Image(item.icon)
                    .renderingMode(.template)
                    .resizable()
                    .scaledToFit()
                    .frame(width: isWideLayout ? 28 : 24, height: isWideLayout ? 28 : 24)
            }
            Text(item.title.uppercased())
                .font(NeonTheme.mono(size: isWideLayout ? 10 : 9, relativeTo: .caption2))
                .tracking(0.6)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
        .foregroundStyle(on ? Color.black : NeonTheme.text.opacity(0.62))
        .frame(maxWidth: .infinity, minHeight: isWideLayout ? 56 : 48)
        .background {
            if on {
                // A hub-fül eredeti formája (`button_big2_bg_tab`),
                // a tompított paletta mélyvörösére festve.
                Image("img_neo_tab_selbg")
                    .renderingMode(.template)
                    .resizable()
                    .foregroundStyle(NeonTheme.red)
            }
        }
        .overlay(alignment: .bottom) {
            if on {
                // A játék fül-jelölővonala (`button_big2_bg_tab_line`).
                Image("img_neo_tab_selline")
                    .renderingMode(.template)
                    .resizable()
                    .frame(height: 2)
                    .foregroundStyle(NeonTheme.coral)
                    .accessibilityHidden(true)
            }
        }
        .contentShape(Rectangle())
    }
}
