import SwiftUI

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
    @AppStorage("theme.mode") var modeRaw: String = AppThemeMode.dark.rawValue {
        didSet { objectWillChange.send() }
    }
    @AppStorage("theme.accentHex") var accentHex: Int = 0xA7DC22 {
        didSet { objectWillChange.send() }
    }

    var mode: AppThemeMode {
        get { AppThemeMode(rawValue: modeRaw) ?? .dark }
        set { modeRaw = newValue.rawValue }
    }
    var accent: Color { Color(hex: UInt(accentHex)) }

    // Preset accent colors — simple to change
    static let presets: [Int] = [
        0xA7DC22, // Firka lime
        0x4A90E2, // Apple blue
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
