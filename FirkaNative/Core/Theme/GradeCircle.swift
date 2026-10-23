import SwiftUI

struct GradeCircle: View {
    let value: Int
    var size: CGFloat = 44
    @Environment(\.colorScheme) var scheme
    @EnvironmentObject var theme: ThemeStore
    var colors: AppColors { theme.colors(for: scheme) }

    var body: some View {
        if theme.isMinecraft {
            // Minecraft: tömör concrete-blokk, bevel-lel és kemény árnyékkal.
            McGradeBlock(value: value, size: size)
        } else {
        // Az üveg a szám háttere — testvér-ZStackben az üveg-passz takarná a számot.
        Text("\(value)")
            .font(.system(size: size > 32 ? 18 : 13, weight: .bold, design: .rounded))
            .foregroundStyle(colors.gradeColor(for: value))
            .monospacedDigit()
            .frame(width: size, height: size)
            .background {
                Circle()
                    .fill(Color.clear)
                    .glassEffect(.clear, in: .circle)
            }
            .overlay(Circle().strokeBorder(colors.border.opacity(0.9), lineWidth: size > 32 ? 1.2 : 1))
        }
    }
}

/// Jegy-blokk Minecraftban: a jegy színű concrete-kocka lépcsős sarkokkal,
/// bevel-lel és kemény árnyékkal, benne Monocraft számmal. A `GradeCircle`
/// és a tantárgy-részlet kis jegykarikái is ezt használják.
struct McGradeBlock: View {
    let value: Int
    var size: CGFloat = 44
    /// nil = a méretből: nagy blokkon 18, kicsin 13 pont.
    var fontSize: CGFloat?

    var body: some View {
        Text("\(value)")
            .font(MinecraftTheme.headerFont(size: fontSize ?? (size > 32 ? 18 : 13)))
            .foregroundStyle(.white)
            .shadow(color: .black.opacity(0.6), radius: 0, x: 1, y: 2)
            .monospacedDigit()
            .frame(width: size, height: size)
            .background(
                // Pixel-blokk: lépcsős sarok, bevel, kemény árnyék — ugyanaz
                // a rács, mint a kártyáké, így a kocka sosem lekerekített.
                McBlockPanel(face: MinecraftTheme.gradeColor(for: value),
                             outline: Color(hex: 0x1E1A16),
                             highlight: .white.opacity(0.38),
                             shade: .black.opacity(0.28))
            )
            .accessibilityLabel("\(value)")
    }
}
