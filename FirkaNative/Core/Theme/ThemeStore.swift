import SwiftUI

/// Felület-skin: Summit (gyári Liquid Glass) vagy Voxel (modern,
/// 1.20+ Trails & Tales íz + shader-hangulat: BSL/Complementary-szerű
/// telített fűzöld, meleg napfény, puha mélység-árnyék — nem a régi,
/// fakó alfa-stílus).
enum VisualSkin: String, CaseIterable, Identifiable {
    case summit, voxel, neon
    var id: String { rawValue }

    /// Mentett érték feloldása migrációval: a régi rawValue-k
    /// („minecraft”/„cyberpunk”) az új absztrakt skinekre képeződnek,
    /// így a meglévő userek témája nem resetelődik Summitra.
    static func fromStored(_ raw: String?) -> VisualSkin {
        switch raw {
        case "minecraft": return .voxel
        case "cyberpunk": return .neon
        default: return VisualSkin(rawValue: raw ?? "") ?? .summit
        }
    }

    /// Téma-választó csempe képe (a felirat a képbe van renderelve).
    var tileAsset: String {
        switch self {
        case .summit: return "img_tile_summit"
        case .voxel: return "img_tile_voxel"
        case .neon: return "img_tile_neon"
        }
    }
    var title: String {
        switch self {
        case .summit: return "Summit"
        case .voxel: return "Voxel"
        case .neon: return "Neon"
        }
    }
    var icon: String {
        switch self {
        case .summit: return "mountain.2.fill"
        case .voxel: return "cube.fill"
        case .neon: return "bolt.horizontal.fill"
        }
    }

    /// UIKit-chrome (nav-sáv, tab-feliratok) átállítása a skinre. Előbb a
    /// kikapcsolandó skin áll vissza, utána kapcsol be az aktív — így a két
    /// skin appearance-e nem írja felül egymást.
    func applyChromeAppearance() {
        if self == .neon {
            VoxelTheme.applyChromeAppearance(voxel: false)
            NeonTheme.applyChromeAppearance(active: true)
        } else {
            NeonTheme.applyChromeAppearance(active: false)
            VoxelTheme.applyChromeAppearance(voxel: self == .voxel)
        }
    }
}

enum AppThemeMode: String, CaseIterable, Identifiable {
    case system, light, dark
    var id: String { rawValue }
    var title: String {
        switch self {
        case .system: return "Rendszer"
        case .light: return "Világos"
        case .dark: return "Sötét"
        }
    }
    var icon: String {
        switch self {
        case .system: return "iphone.gen2"
        case .light: return "sun.max.fill"
        case .dark: return "moon.fill"
        }
    }
    var scheme: ColorScheme? {
        switch self { case .system: return nil; case .light: return .light; case .dark: return .dark }
    }
}

@MainActor
final class ThemeStore: ObservableObject {
    @AppStorage("theme.mode") var modeRaw: String = AppThemeMode.system.rawValue {
        didSet { objectWillChange.send() }
    }
    @AppStorage("theme.accentHex") var accentHex: Int = 0x4A90E2 {
        didSet { objectWillChange.send() }
    }
    /// Felület-skin (Megjelenés → Felület kapcsoló). Alapértelmezett Summit,
    /// a meglévő telepítéseken semmi nem változik magától.
    @AppStorage("ui.skin") var skinRaw: String = VisualSkin.summit.rawValue {
        didSet { objectWillChange.send() }
    }
    var skin: VisualSkin {
        get { VisualSkin.fromStored(skinRaw) }
        set { skinRaw = newValue.rawValue }
    }
    var isVoxel: Bool { skin == .voxel }
    /// Neon HUD-skin (mindig sötét séma, sárga akcentus).
    var isNeon: Bool { skin == .neon }
    /// Az app tényleges színsémája: Neonban kényszerített sötét
    /// (a neon felület mindig éjszaka), különben a user választása.
    var effectiveScheme: ColorScheme? { isNeon ? .dark : mode.scheme }
    // Szövegméret-felülírás ("system" = rendszer). Macen (iPad-app Macen)
    // alapból nagyobb, hogy ne legyen apró az egész felület.
    // (A SwiftUI-s ContentSizeCategory nem String-rawValue-s, ezért saját kulcs.)
    @AppStorage("ui.sizeCategory") var sizeCategoryKey: String = MacSupport.isMac ? "extraLarge" : "system" {
        didSet { objectWillChange.send() }
    }
    var sizeCategoryOverride: ContentSizeCategory? {
        get { Self.category(for: sizeCategoryKey) }
        set { sizeCategoryKey = Self.key(for: newValue) }
    }
    static let sizeSteps: [(title: String, key: String)] = [
        ("Rendszer", "system"),
        ("Alap", "large"),
        ("Nagy", "extraLarge"),
        ("Nagyobb", "extraExtraLarge"),
        ("Hatalmas", "extraExtraExtraLarge"),
    ]
    static func category(for key: String) -> ContentSizeCategory? {
        switch key {
        case "large": return .large
        case "extraLarge": return .extraLarge
        case "extraExtraLarge": return .extraExtraLarge
        case "extraExtraExtraLarge": return .extraExtraExtraLarge
        default: return nil
        }
    }
    static func key(for value: ContentSizeCategory?) -> String {
        guard let v = value else { return "system" }
        if v == .large { return "large" }
        if v == .extraLarge { return "extraLarge" }
        if v == .extraExtraLarge { return "extraExtraLarge" }
        if v == .extraExtraExtraLarge { return "extraExtraExtraLarge" }
        return "system"
    }

    var mode: AppThemeMode {
        get { AppThemeMode(rawValue: modeRaw) ?? .system }
        set { modeRaw = newValue.rawValue }
    }
    var accent: Color { Color(hex: UInt(accentHex)) }

    // Preset accent colors — simple to change
    static let presets: [Int] = [
        0x4A90E2, // Summit blue (világos kék, default)
        0x2B4C7E, // Navy
        0xFF6B6B, // Coral
        0x8B5CF6, // Violet
        0xEC4899, // Pink
        0x14B8A6, // Teal
        0xF59E0B, // Amber
    ]

    func colors(for scheme: ColorScheme) -> AppColors {
        let base: AppColors
        switch scheme {
        case .dark: base = AppColors.darkRevamped
        case .light: base = AppColors.lightRevamped
        @unknown default: base = AppColors.darkRevamped
        }
        // Voxel-skin: teljes paletta-átfestés (a saját kiemelőszín
        // ilyenkor nem él — a skiné a fűzöld).
        if skin == .voxel { return VoxelTheme.reskin(base, scheme: scheme) }
        // Neon-skin: mindig sötét HUD-paletta, sárga akcentus.
        if skin == .neon { return NeonTheme.reskin(base, scheme: scheme) }
        // Apply custom accent
        return base.withAccent(accent)
    }
}

extension AppColors {
    func withAccent(_ accent: Color) -> AppColors {
        AppColors(
            background: background,
            backgroundGradientTop: backgroundGradientTop,
            backgroundGradientBottom: backgroundGradientBottom,
            surface: surface,
            surfaceElevated: surfaceElevated,
            text: text,
            textSecondary: textSecondary,
            textTertiary: textTertiary,
            accent: accent,
            accentSoft: accent.opacity(0.16),
            border: border,
            shadow: shadow,
            red: red, orange: orange, yellow: yellow, green: green, teal: teal, blue: blue, purple: purple, pink: pink,
            gradeFive: gradeFive, gradeFour: gradeFour, gradeThree: gradeThree, gradeTwo: gradeTwo, gradeOne: gradeOne,
            loginPrimary: loginPrimary, loginSecondary: loginSecondary, loginBackground: loginBackground
        )
    }
}
