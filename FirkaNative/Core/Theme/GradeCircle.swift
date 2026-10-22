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
            Text("\(value)")
                .font(MinecraftTheme.headerFont(size: size > 32 ? 18 : 13))
                .foregroundStyle(.white)
                .shadow(color: .black.opacity(0.6), radius: 0, x: 1, y: 2)
                .monospacedDigit()
                .frame(width: size, height: size)
                .background(
                    RoundedRectangle(cornerRadius: 7)
                        .fill(MinecraftTheme.gradeColor(for: value))
                        .overlay(
                            RoundedRectangle(cornerRadius: 7)
                                .strokeBorder(MinecraftTheme.dirtDark, lineWidth: size > 32 ? 3 : 2)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 7)
                                .strokeBorder(Color.white.opacity(0.4), lineWidth: 1)
                                .padding(2)
                        )
                        .shadow(color: .black.opacity(0.4), radius: 0, x: 0, y: 3)
                )
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
