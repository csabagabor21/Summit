import SwiftUI
import CoreText

/// Cyberpunk-skin betűi a bundle-ből (Info.plist-módosítás nélkül, mint a
/// Monocraft): Rajdhani (Indian Type Foundry, SIL OFL 1.1) a kijelző- és
/// folyószöveghez — a játék HUD-jának keskeny, szögletes groteszkje —, és
/// IBM Plex Mono Medium (IBM, SIL OFL 1.1) a apró adat-/kód-címkékhez.
/// (A Share Tech Mono közelebb állna a HUD-hoz, de nincs benne ő/ű.)
enum CyberpunkFontLoader {
    static let displayMedium = "Rajdhani-Medium"
    static let displaySemiBold = "Rajdhani-SemiBold"
    static let displayBold = "Rajdhani-Bold"
    static let mono = "IBMPlexMono-Medium"

    private static var done = false
    private(set) static var displayAvailable = false
    private(set) static var monoAvailable = false

    /// Lusta, egyszeri regisztráció: Summit/Minecraft skinben sosem fut
    /// (indításkor csak a mentett Cyberpunk-skin kéri, skinváltáskor az
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

/// Cyberpunk skin (Cyberpunk 2077 HUD-nyelv): majdnem fekete, enyhén
/// vörös/cián árnyalatú háttér, jellegzetes sárga (#FCEE0A), HUD-vörös,
/// cián akcentus, levágott sarkú panelek 1 px-es neon kerettel, vékony
/// vonalak, apró egyenközű nagybetűs címkék. Night City mindig éjszaka:
/// a skin aktív állapotában az app sötét sémát kap.
/// Minden szín / betű egy helyen — a képernyők innen vegyenek.
enum CyberpunkTheme {
    // MARK: - Paletta
    /// Jellegzetes CP2077-sárga (fő gomb, kijelölés, kiemelés).
    static let yellow: Color = Color(hex: 0xFCEE0A)
    /// HUD-vörös (keretek, címek, hiba, figyelmeztetés).
    static let red: Color = Color(hex: 0xFF4655)
    /// Korall-vörös (másodlagos vörös: halványabb keret, 2-es jegy-közeli).
    static let coral: Color = Color(hex: 0xF75049)
    /// Cián akcentus (adat, link, aktív állapot).
    static let cyan: Color = Color(hex: 0x02D7F2)
    /// Világos neon-cián (kiemelt adat, 5-ös jegy).
    static let cyanBright: Color = Color(hex: 0x5EF6FF)
    /// Türkiz-zöld (siker, 4-es jegy).
    static let green: Color = Color(hex: 0x2BE4A8)
    /// Narancs (2-es jegy, enyhe figyelmeztetés).
    static let orange: Color = Color(hex: 0xFF8A1F)
    /// Teljes képernyős háttér: majdnem fekete, enyhe vörös-kék tónussal.
    static let bg: Color = Color(hex: 0x0A0A0F)
    /// Mélyebb háttér (backdrop alja, sheet).
    static let bgDeep: Color = Color(hex: 0x060609)
    /// Panel-arc (kártya, sor).
    static let panel: Color = Color(hex: 0x12121A)
    /// Emelt panel (kijelölt sor, lenyomott gomb, toast).
    static let panelRaised: Color = Color(hex: 0x1B1B26)
    /// Fő szöveg: törtfehér, alig cián.
    static let text: Color = Color(hex: 0xE9F3F4)
    /// Halvány szöveg (címkék, másodlagos adat).
    static let dim: Color = Color(hex: 0x7E8C96)
    /// Vékony elválasztó-/keret-vonal alapszíne (vörös, halványítva).
    static let line: Color = red.opacity(0.32)

    /// Jegy (1–5) → HUD-szín (közös a Főoldal / Jegyek / tantárgy-részlet /
    /// ünneplés között). 1 = HUD-vörös, 2 = narancs, 3 = sárga,
    /// 4 = türkiz-zöld, 5 = cián, egyéb = halvány.
    static func gradeColor(for value: Int) -> Color {
        switch value {
        case 5: return Color(hex: 0x00F0FF)
        case 4: return green
        case 3: return yellow
        case 2: return orange
        case 1: return Color(hex: 0xFF003C)
        default: return dim
        }
    }

    /// Aktív-e a Cyberpunk-skin (UserDefaults-olvasás, Environment-függés
    /// nélkül — bármely nézetben / helperben használható, mint a
    /// `MinecraftTheme.isActive`).
    static var isActive: Bool {
        UserDefaults.standard.string(forKey: "ui.skin") == VisualSkin.cyberpunk.rawValue
    }

    /// Teljes paletta-átfestés (a szerkezet változatlan, csak a színek
    /// cserélődnek, így egyszerre vált minden képernyő). Mindig sötét —
    /// a skin a sémát is sötétre kényszeríti, a `scheme` csak a
    /// biztonság kedvéért van itt (pl. widget-előnézet).
    static func reskin(_ base: AppColors, scheme: ColorScheme) -> AppColors {
        AppColors(
            background: bg,
            backgroundGradientTop: Color(hex: 0x12060A),
            backgroundGradientBottom: Color(hex: 0x03121A),
            surface: panel,
            surfaceElevated: panelRaised,
            text: text,
            textSecondary: text.opacity(0.66),
            textTertiary: dim,
            accent: yellow,
            accentSoft: yellow.opacity(0.14),
            border: line,
            shadow: Color.black.opacity(0.6),
            red: red, orange: orange, yellow: yellow,
            green: green, teal: cyan, blue: cyan,
            purple: Color(hex: 0xB45CFF), pink: Color(hex: 0xFF2A6D),
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
        CyberpunkFontLoader.registerOnce()
        let size = baseSize(style)
        let w: Font.Weight = weight ?? {
            switch style {
            case .largeTitle, .title, .title2, .title3: return .bold
            default: return .semibold
            }
        }()
        guard CyberpunkFontLoader.displayAvailable else {
            return Font.system(style).width(.condensed).weight(w)
        }
        return .custom(fontName(for: w), size: size, relativeTo: style)
    }

    static func fontName(for weight: Font.Weight) -> String {
        switch weight {
        case .ultraLight, .thin, .light, .regular, .medium: return CyberpunkFontLoader.displayMedium
        case .semibold: return CyberpunkFontLoader.displaySemiBold
        default: return CyberpunkFontLoader.displayBold
        }
    }

    /// Kijelző-betű adott méretben (hero-számok, nagy címek), Dynamic
    /// Type-pal a megadott stílushoz viszonyítva skálázva.
    static func display(size: CGFloat, weight: Font.Weight = .bold, relativeTo style: Font.TextStyle = .title) -> Font {
        CyberpunkFontLoader.registerOnce()
        guard CyberpunkFontLoader.displayAvailable else {
            return .system(size: size, weight: weight).width(.condensed)
        }
        return .custom(fontName(for: weight), size: size, relativeTo: style)
    }

    /// Egyenközű adat-/címke-betű (IBM Plex Mono Medium), Dynamic Type-pal
    /// a megadott stílushoz viszonyítva skálázva.
    static func mono(size: CGFloat, relativeTo style: Font.TextStyle = .caption) -> Font {
        CyberpunkFontLoader.registerOnce()
        guard CyberpunkFontLoader.monoAvailable else {
            return .system(size: size, weight: .medium, design: .monospaced)
        }
        return .custom(CyberpunkFontLoader.mono, size: size, relativeTo: style)
    }

    // MARK: - UIKit-chrome (nav-sáv, tab-feliratok)

    private static var chromeOverridden = false

    /// Nav-sáv + tab-feliratok betűje/színe (UIKit-appearance — a SwiftUI
    /// nem ad rájuk modifierszintű betűállítást). Ki/be kapcsolható;
    /// kikapcsoláskor csak akkor nyúl a rendszer-alaphoz, ha korábban
    /// Cyberpunk-appearance volt. Közvetlenül ne hívd: a
    /// `VisualSkin.applyChromeAppearance()` intézi a helyes sorrendet
    /// (előbb a kikapcsolandó skin áll vissza, utána kapcsol az aktív).
    static func applyChromeAppearance(active: Bool) {
        let nav = UINavigationBar.appearance()
        let tabItem = UITabBarItem.appearance()
        if active {
            CyberpunkFontLoader.registerOnce()
            let yellowUI = UIColor(red: 0xFC / 255, green: 0xEE / 255, blue: 0x0A / 255, alpha: 1)
            let textUI = UIColor(red: 0xE9 / 255, green: 0xF3 / 255, blue: 0xF4 / 255, alpha: 1)
            let big = UIFont(name: CyberpunkFontLoader.displayBold, size: 36)
            let small = UIFont(name: CyberpunkFontLoader.displayBold, size: 19)
            let tiny = UIFont(name: CyberpunkFontLoader.mono, size: 10)
            var title: [NSAttributedString.Key: Any] = [.foregroundColor: textUI, .kern: 1.2]
            if let small { title[.font] = small }
            var large: [NSAttributedString.Key: Any] = [.foregroundColor: yellowUI, .kern: 0.8]
            if let big { large[.font] = big }
            if let tiny {
                tabItem.setTitleTextAttributes([.font: tiny, .kern: 0.8], for: .normal)
                tabItem.setTitleTextAttributes([.font: tiny, .kern: 0.8], for: .selected)
            }
            // Görgetve: opak, majdnem fekete sáv vékony vörös alsó vonallal
            // (a HUD fejléc-sávja); a tetején átlátszó, a backdrop látszik.
            let scrolled = UINavigationBarAppearance()
            scrolled.configureWithOpaqueBackground()
            scrolled.backgroundColor = UIColor(red: 0x0A / 255, green: 0x0A / 255, blue: 0x0F / 255, alpha: 1)
            scrolled.shadowColor = UIColor(red: 0xFF / 255, green: 0x46 / 255, blue: 0x55 / 255, alpha: 0.55)
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
