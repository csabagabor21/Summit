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
        // A Minecraft-talaj és a hotbar MINDIG overlay-ként van jelen (üres,
        // ha nem kell), nem `if useCustomHotbar { … } else { tabContent }`
        // ágban: az ág-váltás (skinváltás, vagy Max/Plus iPhone elforgatása
        // → széles elrendezés) új identitást adott a teljes tab-fának —
        // minden NavigationStack és a kiválasztott tab elveszett, a user a
        // Főoldal gyökerére esett vissza.
        //
        // Minecraft keskeny kijelzőn: a dock (talaj + hotbar) az oldal
        // alja, nem a képernyő alja — a tab-tartalom kerete a fű tetejénél
        // véget ér (alsó padding, csak érték vált, a nézet-fa azonos
        // marad), így görgetéskor és az alsó rugózásnál (túlhúzás →
        // visszaugrás) sem csúszik semmi a föld mögé: a lista a fűnél
        // áll meg, fölötte nyílik az ég-rés. A tabok alsó safe area-ja
        // (`mcTabChrome`) már csak a talajból kilógó virágokat kerüli ki.
        // A hotbar a földön ül. Szélesen (iPad/Mac sidebar) a natív sáv
        // marad. Külön ég nincs a tab-tartalom mögött (a lista saját ege
        // tölti ki a képet).
        tabContent
            .padding(.bottom, useCustomHotbar ? Self.mcFooterHeight : useCPBar ? CPTabBar.height : 0)
            .overlay(alignment: .bottom) {
                if useCustomHotbar {
                    // Díszlet: nem nyel érintést. Eddig a teljes 148 pt-os
                    // talaj-sáv elnyelte a koppintást ÉS a görgetés indítását
                    // minden tab alján (a lista alulról felhúzva nem mozdult,
                    // a fű mögé csúszó sorok halottak voltak).
                    McGrassBlockFooter(height: Self.mcFooterHeight)
                        .allowsHitTesting(false)
                }
            }
            .overlay(alignment: .bottom) {
                if useCustomHotbar {
                    // Csak maga a hotbar (a slot-gombok egymás mellett, rés
                    // nélkül) fogad érintést; körülötte a görgetés indulhat.
                    mcHotbar.padding(.bottom, 6)
                }
            }
            .overlay(alignment: .bottom) {
                // Cyberpunk keskeny kijelzőn: saját HUD-sáv (a rendszer-
                // tabsáv rejtve, a tartalom alja a sáv fölött áll meg —
                // `mcTabChrome(inset:)`). Szélesen a natív sidebar marad.
                // Szintén mindig jelen lévő overlay, hogy a skinváltás ne
                // adjon új identitást a tab-fának.
                if useCPBar { cpTabBar }
            }
        .tint(theme.isMinecraft ? MinecraftTheme.grass : colors.accent)
        // Chrome-betűk a látható sávokra is (az init-kori beállítás
        // a már élő sávokon nem mindig fog meg).
        .onAppear {
            theme.skin.applyChromeAppearance()
            McSound.warmUp()
            CPSound.warmUp()
        }
        .onChange(of: theme.isMinecraft) { _, mc in
            if mc { McSound.warmUp() }
        }
        .onChange(of: theme.isCyberpunk) { _, cp in
            if cp { CPSound.warmUp() }
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
            // Széles elrendezés (rendszer-tabsáv): itt nincs hotbar-callback.
            if theme.isMinecraft, !useCustomHotbar { McSound.play(.tab) }
            if theme.isCyberpunk, !useCPBar { CPSound.play(.tab) }
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
            Tab(value: 0) {
                HomeView().mcTabChrome(hidden: hidesSystemTabBar, inset: customBarInset).id(mcRootTokens[0, default: 0])
            } label: { tabLabel(0) }
            Tab(value: 1) {
                GradesView().mcTabChrome(hidden: hidesSystemTabBar, inset: customBarInset).id(mcRootTokens[1, default: 0])
            } label: { tabLabel(1) }
            Tab(value: 2) {
                TimetableView().mcTabChrome(hidden: hidesSystemTabBar, inset: customBarInset).id(mcRootTokens[2, default: 0])
            } label: { tabLabel(2) }
            Tab(value: 5) {
                NotesView().mcTabChrome(hidden: hidesSystemTabBar, inset: customBarInset).id(mcRootTokens[5, default: 0])
            } label: { tabLabel(5) }
            Tab(value: 4) {
                AbsencesView().mcTabChrome(hidden: hidesSystemTabBar, inset: customBarInset).id(mcRootTokens[4, default: 0])
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
        .tabViewStyle(.sidebarAdaptable)
        // Ne tegyél ide .toolbarBackground vagy .glassEffect-et:
        // iOS 26-on a TabBar/Sidebar chrome magától Liquid Glass.
        // Content glass tilos — "glass can't sample other glass".
    }

    /// Tab-címke: Summitban a gyári `Label(cím, systemImage:)`, Minecraftban
    /// az eredeti item-textúra (előre, élesen felnagyítva — a tab-sáv
    /// maga simítaná a 16 px-es képet) a széles elrendezés sávjában.
    @ViewBuilder
    private func tabLabel(_ tab: Int) -> some View {
        if theme.isMinecraft, let ui = MinecraftTheme.tabBarImage(for: tab) {
            Label { Text(tabTitle(tab)) } icon: { Image(uiImage: ui) }
        } else {
            Label(tabTitle(tab), systemImage: tabIcon(tab))
        }
    }

    /// Minecraft-skinben blokkos ikonok + címek, különben a gyáriak.
    private func tabIcon(_ tab: Int) -> String {
        if theme.isCyberpunk { return Self.cpTabIcon(tab) }
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
    /// Minecraft keskeny kijelzőn: a rendszer-tabsáv rejtve — helyette
    /// saját hotbar jön a fűblokkra. Máshol a natív sáv marad.
    private var useCustomHotbar: Bool { theme.isMinecraft && !isWide }
    /// Cyberpunk keskeny kijelzőn: saját HUD-tabsáv (lásd `CPTabBar`).
    private var useCPBar: Bool { theme.isCyberpunk && !isWide }
    /// Rejtett-e a rendszer-tabsáv (saját sáv van helyette).
    private var hidesSystemTabBar: Bool { useCustomHotbar || useCPBar }
    /// A tab-tartalom alsó tartaléka a saját sáv fölött: Minecraftban a
    /// talajból a tartalom elé kilógó virágok magassága, Cyberpunkban egy
    /// kis levegő — a sávokat magát a `body` alsó paddingje már kivette
    /// a tartalom keretéből (a dock az oldal alja, nem a képernyő alja).
    private var customBarInset: CGFloat {
        useCPBar ? 8 : McFlora.maxHeight
    }

    /// Cyberpunk-tabikonok: körvonalas (nem kitöltött) SF-szimbólumok —
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

    /// Saját Cyberpunk HUD-tabsáv. Újrakoppintás az aktív fülre: a tab
    /// verme a gyökérre ugrik (mint a hotbaron / rendszer-sávon).
    private var cpTabBar: some View {
        CPTabBar(
            items: [0, 1, 2, 5, 4].map { CPTabBar.Item(tab: $0, icon: Self.cpTabIcon($0), title: tabTitle($0)) },
            selected: selected
        ) { tab in
            SummitHaptics.selection()
            CPSound.play(.tab)
            if tab == selected {
                mcRootTokens[tab, default: 0] += 1
            } else {
                selected = tab
            }
        }
    }
    /// Hotbar-újrakoppintás: az aktív slotra koppintva a tab navigációs
    /// verme a gyökérre ugrik (mint a rendszer-tabsávon) — az új azonosító
    /// újraépíti a tab NavigationStackjét.
    @State private var mcRootTokens: [Int: Int] = [:]
    /// A fűblokk-talaj magassága a home-jelző fölött.
    static let mcFooterHeight: CGFloat = 148

    /// Hotbar-slotok: (tab, eredeti item-sprite, cím).
    private var mcTabs: [(Int, String, String)] {
        [(0, "mc_grass_side", "Főoldal"), (1, "mc_item_diamond", "Jegyek"),
         (2, "mc_item_clock", "Órarend"), (5, "mc_item_writable_book", "Feladatok"),
         (4, "mc_item_barrier", "Hiányzások")]
    }

    /// Saját minecraft-hotbar (lásd `McHotbar`): a kijelölt slot neve a
    /// sáv fölött, a játékbeli szöveg-árnyékkal.
    private var mcHotbar: some View {
        McHotbar(
            slots: mcTabs.map { McHotbar.Slot(tab: $0.0, sprite: $0.1, title: $0.2) },
            selected: selected
        ) { tab in
            SummitHaptics.selection()
            // A hotbar-slot kattan, mint a játékban (csak MC-skinben szól) —
            // a tabsáv a legerősebb kattanás, a sima gomboké halkabb.
            McSound.play(.tab)
            if tab == selected {
                mcRootTokens[tab, default: 0] += 1
            } else {
                selected = tab
            }
        }
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
            HomeView().mcTabChrome(hidden: hidesSystemTabBar, inset: customBarInset).tabItem { tabLabel(0) }.tag(0)
            GradesView().mcTabChrome(hidden: hidesSystemTabBar, inset: customBarInset).tabItem { tabLabel(1) }.tag(1)
            TimetableView().mcTabChrome(hidden: hidesSystemTabBar, inset: customBarInset).tabItem { tabLabel(2) }.tag(2)
            NotesView().mcTabChrome(hidden: hidesSystemTabBar, inset: customBarInset).tabItem { tabLabel(5) }.tag(5)
            AbsencesView().mcTabChrome(hidden: hidesSystemTabBar, inset: customBarInset).tabItem { tabLabel(4) }.tag(4)
            if watchTabVisible {
                CheatView().tabItem { tabLabel(3) }.tag(3)
            }
        }
    }
}

/// Minecraft-tabrejtés: keskeny kijelzőn Minecraft-skinben elrejti a
/// rendszer-tabsávot (helyette a saját hotbar látszik a fűblokkon).
private extension View {
    /// Egyetlen, ág nélküli lánc (a `hidden` és az `inset` csak értékeket
    /// vált): skinváltáskor a tab gyökere — és vele a NavigationStack —
    /// megmarad.
    func mcTabChrome(hidden: Bool, inset: CGFloat) -> some View {
        self.toolbar(hidden ? .hidden : .automatic, for: .tabBar)
            // Alsó tartalék a saját sáv fölött: Minecraftban a talajból
            // kilógó növények, Cyberpunkban egy kis levegő (a sávok a
            // tartalom keretén kívül vannak, lásd `body`) — a lista vége
            // ennyivel a sáv fölött áll meg.
            .safeAreaInset(edge: .bottom, spacing: 0) {
                Color.clear
                    .frame(height: hidden ? inset : 0)
                    .allowsHitTesting(false)
            }
    }
}

/// Minecraft Java/Bedrock hotbar, pixelrácsra rajzolva: 1 játék-pixel =
/// `px` pt, minden él egész számú játék-pixelre esik, nincs lekerekítés.
/// A slotok 20×20 px-esek (1 px sötét keret, 1 px letört él, 16×16 px
/// belső tér az itemnek), a kijelölést a vanilla `hotbar_selection`
/// mintájú, slotonként 2 px-szel túlnyúló fehér keret jelzi. A kijelölt
/// item neve a sáv fölött áll fehér Minecraft-betűvel, 1 px-es
/// (#3F3F3F) szövegárnyékkal.
private struct McHotbar: View {
    struct Slot: Identifiable {
        let tab: Int
        let sprite: String
        let title: String
        var id: Int { tab }
    }

    let slots: [Slot]
    let selected: Int
    let onSelect: (Int) -> Void

    /// Egy játék-pixel pontban (3 pt → 6/9 fizikai pixel, mindig egész).
    private let px: CGFloat = 3
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
                    MinecraftTheme.mcPixelImage(slot.sprite, size: 16 * px)
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
        let font = MinecraftFontLoader.font(size: 8 * px)
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

/// Cyberpunk 2077 HUD-tabsáv: majdnem fekete, opak sáv vékony vörös felső
/// vonallal (bal végén fényes szakasz), öt cella vékony ikonnal és apró
/// egyenközű nagybetűs felirattal; a kijelölt cella vörös, levágott sarkú
/// kitöltést kap fekete tartalommal, sarkában a fül kódja (01–05).
/// Statikus, olcsó nézet: nincs animáció, nincs üveg.
struct CPTabBar: View {
    struct Item: Identifiable {
        let tab: Int
        let icon: String
        let title: String
        var id: Int { tab }
    }
    var items: [Item]
    var selected: Int
    var onSelect: (Int) -> Void

    /// A sáv magassága a home-jelző fölött (a tartalom ennyivel előbb áll meg).
    static let height: CGFloat = 60

    var body: some View {
        VStack(spacing: 0) {
            ZStack(alignment: .leading) {
                Rectangle().fill(CyberpunkTheme.red.opacity(0.5)).frame(height: 1)
                Rectangle().fill(CyberpunkTheme.red).frame(width: 56, height: 2)
            }
            .frame(height: 2)
            HStack(spacing: 4) {
                ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                    let on = item.tab == selected
                    Button { onSelect(item.tab) } label: {
                        cell(item, index: index, on: on)
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
        .frame(height: Self.height, alignment: .top)
        .background(CyberpunkTheme.bg.ignoresSafeArea(edges: .bottom))
    }

    private func cell(_ item: Item, index: Int, on: Bool) -> some View {
        VStack(spacing: 3) {
            Image(systemName: item.icon)
                .font(.system(size: 19, weight: on ? .regular : .light))
                .frame(height: 22)
            Text(item.title.uppercased())
                .font(CyberpunkTheme.mono(size: 9, relativeTo: .caption2))
                .tracking(0.6)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
        .foregroundStyle(on ? Color.black : CyberpunkTheme.text.opacity(0.62))
        .frame(maxWidth: .infinity, minHeight: 48)
        .background {
            if on {
                // A játék szünet-menü gombformája, vörösre festve.
                CPGameButtonShape(fill: CyberpunkTheme.red)
            }
        }
        .overlay(alignment: .topTrailing) {
            Text(String(format: "%02d", index + 1))
                .font(CyberpunkTheme.mono(size: 7, relativeTo: .caption2))
                .foregroundStyle(on ? Color.black.opacity(0.6) : CyberpunkTheme.dim.opacity(0.7))
                .padding(.top, 2)
                .padding(.trailing, 4)
                .accessibilityHidden(true)
        }
        .contentShape(Rectangle())
    }
}
