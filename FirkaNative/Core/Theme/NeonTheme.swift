import SwiftUI
import CoreText

/// Neon-skin betűi a bundle-ből (Info.plist-módosítás nélkül, mint a
/// Monocraft): Rajdhani (Indian Type Foundry, SIL OFL 1.1) a kijelző- és
/// folyószöveghez — a játék HUD-jának keskeny, szögletes groteszkje —, és
/// IBM Plex Mono Medium (IBM, SIL OFL 1.1) a apró adat-/kód-címkékhez.
/// (A Share Tech Mono közelebb állna a HUD-hoz, de nincs benne ő/ű.)
enum NeonFontLoader {
    static let displayMedium = "Rajdhani-Medium"
    static let displaySemiBold = "Rajdhani-SemiBold"
    static let displayBold = "Rajdhani-Bold"
    static let mono = "IBMPlexMono-Medium"

    private static var done = false
    private(set) static var displayAvailable = false
    private(set) static var monoAvailable = false

    /// Lusta, egyszeri regisztráció: Summit/Voxel skinben sosem fut
    /// (indításkor csak a mentett Neon-skin kéri, skinváltáskor az
    /// első betű-kérés intézi).
    static func registerOnce() {
        guard !done else { return }
        done = true
        for name in [displayMedium, displaySemiBold, displayBold, mono] {
            if let url = Bundle.main.url(forResource: name, withExtension: "ttf") {
                CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
            }
        }
        displayAvailable = UIFont(name: displayBold, size: 12) != nil
        monoAvailable = UIFont(name: mono, size: 12) != nil
    }
}

/// Neon skin (Neon HUD-nyelv): a paletta a játék
/// menüiből mért színekre hangolva (interfaceingame Inventory/Journal/
/// Main Menu/Pause 1920×1080 képek + a saját telepítés eredeti
/// `img_neo_menu_bg` textúrája, medián-mintavétel — részletek a commit-
/// üzenetben). A játékban a felület 50–62%-a szinte fekete, a szöveg-
/// vörös tompa korall, a cián halvány türkiz, a sárga csak a logóban
/// és apró címkéken él. a neon felület mindig éjszaka: a skin aktív
/// állapotában az app sötét sémát kap.
/// Minden szín / betű egy helyen — a képernyők innen vegyenek.
enum NeonTheme {
    // MARK: - Paletta (mért játék-színek)
    /// Tompa borostyán-sárga — a menük „NEW"/„DANGER" címkéinek mért
    /// színe (#FFC63D/#F0B437 medián). A logó tiszta sárgája (#FCEE0A)
    /// csak a `img_neo_logo` képen él, felületi színként nem használjuk.
    static let yellow: Color = Color(hex: 0xDFA32C)
    /// HUD-vörös (keretek, címek, hiba) — a menüszöveg mért korallja
    /// (#D34640 Inventory, #D73F3E Main Menu medián).
    static let red: Color = Color(hex: 0xDB4D45)
    /// Korall-vörös (másodlagos vörös) — a szöveg fényes magja (#FF6058).
    static let coral: Color = Color(hex: 0xE85A50)
    /// Cián akcentus (adat, link, aktív állapot) — mért halvány türkiz
    /// (#43CCC7 Inventory, #4DB1B8 Main Menu medián).
    static let cyan: Color = Color(hex: 0x3EB8B2)
    /// Világos cián (kiemelt adat) — mért #96DDE2, enyhén tompítva.
    static let cyanBright: Color = Color(hex: 0x8FD6D3)
    /// Türkiz-zöld (siker).
    static let green: Color = Color(hex: 0x3DBE8A)
    /// Narancs (enyhe figyelmeztetés).
    static let orange: Color = Color(hex: 0xD97A2B)
    /// Teljes képernyős háttér: meleg, vöröses fekete (a menüképek
    /// sötét mediánja #080D12, a `img_neo_menu_bg` textúráé #140E0B).
    static let bg: Color = Color(hex: 0x0B090A)
    /// Mélyebb háttér (backdrop alja, sheet).
    static let bgDeep: Color = Color(hex: 0x060405)
    /// Panel-arc (kártya, sor) — az inventory slot-hátterek (#1A0E15) ága.
    static let panel: Color = Color(hex: 0x151013)
    /// Emelt panel (kijelölt sor, lenyomott gomb, toast).
    static let panelRaised: Color = Color(hex: 0x21181B)
    /// Fő szöveg: meleg törtfehér (a fehér feliratok mediánja #D6D0CF,
    /// olvashatóságra világosítva; kontraszt a panelen ~14:1).
    static let text: Color = Color(hex: 0xE8E2DC)
    /// Halvány szöveg (címkék, másodlagos adat; panelen ~4.9:1).
    static let dim: Color = Color(hex: 0x8A807B)
    /// Vékony elválasztó-/keret-vonal alapszíne (vörös, halványítva).
    static let line: Color = red.opacity(0.32)

    /// Jegy (1–5) → HUD-szín (közös a Főoldal / Jegyek / tantárgy-részlet /
    /// ünneplés között). 1 = HUD-vörös, 2 = narancs, 3 = sárga,
    /// 4 = türkiz-zöld, 5 = cián, egyéb = halvány.
    static func gradeColor(for value: Int) -> Color {
        // A jegyszínek szemantikája szándékosan NEM követi a tompított
        // felületi palettát: az eredeti, jól megkülönböztethető értékek.
        switch value {
        case 5: return Color(hex: 0x00F0FF)
        case 4: return Color(hex: 0x2BE4A8)
        case 3: return Color(hex: 0xFCEE0A)
        case 2: return Color(hex: 0xFF8A1F)
        case 1: return Color(hex: 0xFF003C)
        default: return dim
        }
    }

    /// Aktív-e a Neon-skin (UserDefaults-olvasás, Environment-függés
    /// nélkül — bármely nézetben / helperben használható, mint a
    /// `VoxelTheme.isActive`).
    static var isActive: Bool {
        VisualSkin.fromStored(UserDefaults.standard.string(forKey: "ui.skin")) == .neon
    }

    /// Teljes paletta-átfestés (a szerkezet változatlan, csak a színek
    /// cserélődnek, így egyszerre vált minden képernyő). Mindig sötét —
    /// a skin a sémát is sötétre kényszeríti, a `scheme` csak a
    /// biztonság kedvéért van itt (pl. widget-előnézet).
    static func reskin(_ base: AppColors, scheme: ColorScheme) -> AppColors {
        AppColors(
            background: bg,
            backgroundGradientTop: Color(hex: 0x14090B),
            backgroundGradientBottom: Color(hex: 0x090B0C),
            surface: panel,
            surfaceElevated: panelRaised,
            text: text,
            textSecondary: text.opacity(0.66),
            textTertiary: dim,
            // A játékban az interaktív akcentus a halvány cián; a sárga
            // csak logó/apró címke — ezért nem sárga az általános akcentus.
            accent: cyan,
            accentSoft: cyan.opacity(0.14),
            border: line,
            shadow: Color.black.opacity(0.6),
            red: red, orange: orange, yellow: yellow,
            green: green, teal: cyan, blue: cyan,
            purple: Color(hex: 0x9A7EB8), pink: Color(hex: 0xC4516B),
            gradeFive: gradeColor(for: 5),
            gradeFour: gradeColor(for: 4),
            gradeThree: gradeColor(for: 3),
            gradeTwo: gradeColor(for: 2),
            gradeOne: gradeColor(for: 1),
            loginPrimary: text,
            loginSecondary: text.opacity(0.62),
            loginBackground: bg
        )
    }

    // MARK: - Tipográfia (Dynamic Type-pal skálázva)

    /// A Rajdhani kisebb x-magasságú a rendszerbetűnél: ~8%-kal nagyobb
    /// alapméret kell az azonos olvashatósághoz.
    private static func baseSize(_ style: Font.TextStyle) -> CGFloat {
        switch style {
        case .largeTitle: return 36
        case .title: return 30
        case .title2: return 24
        case .title3: return 22
        case .headline: return 18
        case .body: return 18
        case .callout: return 17
        case .subheadline: return 16
        case .footnote: return 14
        case .caption: return 13
        case .caption2: return 12
        @unknown default: return 18
        }
    }

    /// Szöveg-stílus Rajdhaniban (Dynamic Type-pal skálázva). Alapból a
    /// címek Bold, minden más SemiBold (a Medium vékony a sötét háttéren);
    /// `weight` felülírja (≤ medium → Medium, semibold → SemiBold, fölötte
    /// Bold). Betű nélkül (preview / hiányzó erőforrás) keskeny rendszer-betű.
    static func font(_ style: Font.TextStyle, weight: Font.Weight? = nil) -> Font {
        NeonFontLoader.registerOnce()
        let size = baseSize(style)
        let w: Font.Weight = weight ?? {
            switch style {
            case .largeTitle, .title, .title2, .title3: return .bold
            default: return .semibold
            }
        }()
        guard NeonFontLoader.displayAvailable else {
            return Font.system(style).width(.condensed).weight(w)
        }
        return .custom(fontName(for: w), size: size, relativeTo: style)
    }

    static func fontName(for weight: Font.Weight) -> String {
        switch weight {
        case .ultraLight, .thin, .light, .regular, .medium: return NeonFontLoader.displayMedium
        case .semibold: return NeonFontLoader.displaySemiBold
        default: return NeonFontLoader.displayBold
        }
    }

    /// Kijelző-betű adott méretben (hero-számok, nagy címek), Dynamic
    /// Type-pal a megadott stílushoz viszonyítva skálázva.
    static func display(size: CGFloat, weight: Font.Weight = .bold, relativeTo style: Font.TextStyle = .title) -> Font {
        NeonFontLoader.registerOnce()
        guard NeonFontLoader.displayAvailable else {
            return .system(size: size, weight: weight).width(.condensed)
        }
        return .custom(fontName(for: weight), size: size, relativeTo: style)
    }

    /// Egyenközű adat-/címke-betű (IBM Plex Mono Medium), Dynamic Type-pal
    /// a megadott stílushoz viszonyítva skálázva.
    static func mono(size: CGFloat, relativeTo style: Font.TextStyle = .caption) -> Font {
        NeonFontLoader.registerOnce()
        guard NeonFontLoader.monoAvailable else {
            return .system(size: size, weight: .medium, design: .monospaced)
        }
        return .custom(NeonFontLoader.mono, size: size, relativeTo: style)
    }

    // MARK: - UIKit-chrome (nav-sáv, tab-feliratok)

    private static var chromeOverridden = false

    /// Nav-sáv + tab-feliratok betűje/színe (UIKit-appearance — a SwiftUI
    /// nem ad rájuk modifierszintű betűállítást). Ki/be kapcsolható;
    /// kikapcsoláskor csak akkor nyúl a rendszer-alaphoz, ha korábban
    /// Neon-appearance volt. Közvetlenül ne hívd: a
    /// `VisualSkin.applyChromeAppearance()` intézi a helyes sorrendet
    /// (előbb a kikapcsolandó skin áll vissza, utána kapcsol az aktív).
    static func applyChromeAppearance(active: Bool) {
        let nav = UINavigationBar.appearance()
        let tabItem = UITabBarItem.appearance()
        if active {
            NeonFontLoader.registerOnce()
            let textUI = UIColor(red: 0xE8 / 255, green: 0xE2 / 255, blue: 0xDC / 255, alpha: 1)
            let big = UIFont(name: NeonFontLoader.displayBold, size: 36)
            let small = UIFont(name: NeonFontLoader.displayBold, size: 19)
            let tiny = UIFont(name: NeonFontLoader.mono, size: 10)
            var title: [NSAttributedString.Key: Any] = [.foregroundColor: textUI, .kern: 1.2]
            if let small { title[.font] = small }
            // Nagy cím is törtfehér (a játékban a sárga csak a logóé).
            var large: [NSAttributedString.Key: Any] = [.foregroundColor: textUI, .kern: 0.8]
            if let big { large[.font] = big }
            if let tiny {
                tabItem.setTitleTextAttributes([.font: tiny, .kern: 0.8], for: .normal)
                tabItem.setTitleTextAttributes([.font: tiny, .kern: 0.8], for: .selected)
            }
            // Görgetve: opak, majdnem fekete sáv vékony vörös alsó vonallal
            // (a HUD fejléc-sávja); a tetején átlátszó, a backdrop látszik.
            let scrolled = UINavigationBarAppearance()
            scrolled.configureWithOpaqueBackground()
            scrolled.backgroundColor = UIColor(red: 0x0B / 255, green: 0x09 / 255, blue: 0x0A / 255, alpha: 1)
            scrolled.shadowColor = UIColor(red: 0xDB / 255, green: 0x4D / 255, blue: 0x45 / 255, alpha: 0.55)
            scrolled.titleTextAttributes = title
            scrolled.largeTitleTextAttributes = large
            let top = UINavigationBarAppearance()
            top.configureWithTransparentBackground()
            top.titleTextAttributes = title
            top.largeTitleTextAttributes = large
            nav.standardAppearance = scrolled
            nav.compactAppearance = scrolled
            nav.scrollEdgeAppearance = top
            chromeOverridden = true
        } else if chromeOverridden {
            nav.largeTitleTextAttributes = [:]
            nav.titleTextAttributes = [:]
            tabItem.setTitleTextAttributes([:], for: .normal)
            tabItem.setTitleTextAttributes([:], for: .selected)
            nav.standardAppearance = UINavigationBarAppearance()
            nav.compactAppearance = UINavigationBarAppearance()
            nav.scrollEdgeAppearance = nil
            chromeOverridden = false
        }
    }
}
