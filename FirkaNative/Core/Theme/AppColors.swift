import SwiftUI

// Dark-only revamped palette — premium liquid glass
struct AppColors {
    let background: Color
    let backgroundGradientTop: Color
    let backgroundGradientBottom: Color
    let surface: Color
    let surfaceElevated: Color
    let text: Color
    let textSecondary: Color
    let textTertiary: Color
    let accent: Color
    let accentSoft: Color
    let border: Color
    let shadow: Color

    let red: Color
    let orange: Color
    let yellow: Color
    let green: Color
    let teal: Color
    let blue: Color
    let purple: Color
    let pink: Color

    let gradeFive: Color
    let gradeFour: Color
    let gradeThree: Color
    let gradeTwo: Color
    let gradeOne: Color

    let loginPrimary: Color
    let loginSecondary: Color
    let loginBackground: Color

    // Dark revamped — neutral graphite (not green) — fixes green background bug
    static let darkRevamped = AppColors(
        background: Color(hex: 0x0F0F11), // neutral graphite
        backgroundGradientTop: Color(hex: 0x1A1A1E).opacity(0.0),
        backgroundGradientBottom: Color(hex: 0x0A0A0C).opacity(1),
        surface: Color.white.opacity(0.07),
        surfaceElevated: Color.white.opacity(0.10),
        text: Color(hex: 0xF2F2F3),
        textSecondary: Color(hex: 0xF2F2F3).opacity(0.68),
        textTertiary: Color(hex: 0xF2F2F3).opacity(0.42),
        accent: Color(hex: 0xA7DC22),
        accentSoft: Color(hex: 0xA7DC22).opacity(0.16),
        border: Color.white.opacity(0.10),
        shadow: Color.black.opacity(0.45),
        red: Color(hex: 0xFF4455),
        orange: Color(hex: 0xFF8C2E),
        yellow: Color(hex: 0xFFCC33),
        green: Color(hex: 0x2ECC71),
        teal: Color(hex: 0x4ECDC4),
        blue: Color(hex: 0x4A90E2),
        purple: Color(hex: 0x9B59B6),
        pink: Color(hex: 0xFF6B9D),
        gradeFive: Color(hex: 0x22CCAD),
        gradeFour: Color(hex: 0x92EA3B),
        gradeThree: Color(hex: 0xFFD23C),
        gradeTwo: Color(hex: 0xFF7A45),
        gradeOne: Color(hex: 0xFF4D6E),
        loginPrimary: Color(hex: 0xF2F2F3),
        loginSecondary: Color(hex: 0xF2F2F3).opacity(0.62),
        loginBackground: Color(hex: 0x0F0F11)
    )

    static let lightRevamped = AppColors(
        background: Color(hex: 0xF6F7F6), // Apple.com-like light
        backgroundGradientTop: Color(hex: 0xFFFFFF).opacity(1),
        backgroundGradientBottom: Color(hex: 0xF0F2F0).opacity(1),
        surface: Color.white.opacity(0.92),
        surfaceElevated: Color.white.opacity(1),
        text: Color(hex: 0x0A0F0A),
        textSecondary: Color(hex: 0x0A0F0A).opacity(0.62),
        textTertiary: Color(hex: 0x0A0F0A).opacity(0.38),
        accent: Color(hex: 0xA7DC22),
        accentSoft: Color(hex: 0xA7DC22).opacity(0.14),
        border: Color.black.opacity(0.06),
        shadow: Color.black.opacity(0.10),
        red: Color(hex: 0xE11D48),
        orange: Color(hex: 0xEA580C),
        yellow: Color(hex: 0xCA8A04),
        green: Color(hex: 0x16A34A),
        teal: Color(hex: 0x0D9488),
        blue: Color(hex: 0x2563EB),
        purple: Color(hex: 0x7C3AED),
        pink: Color(hex: 0xDB2777),
        gradeFive: Color(hex: 0x0E9F6E),
        gradeFour: Color(hex: 0x84CC16),
        gradeThree: Color(hex: 0xEAB308),
        gradeTwo: Color(hex: 0xF97316),
        gradeOne: Color(hex: 0xEC4899),
        loginPrimary: Color(hex: 0x0A0F0A),
        loginSecondary: Color(hex: 0x0A0F0A).opacity(0.60),
        loginBackground: Color(hex: 0xF6F7F6)
    )

    static let light = lightRevamped

    static func current(for scheme: ColorScheme) -> AppColors {
        scheme == .dark ? darkRevamped : lightRevamped
    }

    func gradeColor(for value: Int) -> Color {
        switch value {
        case 5: return gradeFive
        case 4: return gradeFour
        case 3: return gradeThree
        case 2: return gradeTwo
        case 1: return gradeOne
        default: return textTertiary
        }
    }
}

extension Color {
    init(hex: UInt, alpha: Double = 1.0) {
        let r = Double((hex >> 16) & 0xFF) / 255.0
        let g = Double((hex >> 8) & 0xFF) / 255.0
        let b = Double(hex & 0xFF) / 255.0
        self.init(.sRGB, red: r, green: g, blue: b, opacity: alpha)
    }
    init?(hex: Int) { self.init(hex: UInt(hex)) }
}

private struct AppColorsKey: EnvironmentKey { static let defaultValue = AppColors.darkRevamped }
extension EnvironmentValues {
    var appColors: AppColors { get { self[AppColorsKey.self] } set { self[AppColorsKey.self] = newValue } }
}
