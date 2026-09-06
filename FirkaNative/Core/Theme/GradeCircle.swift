import SwiftUI

struct GradeCircle: View {
    let value: Int
    var size: CGFloat = 44
    @Environment(\.colorScheme) var scheme
    @EnvironmentObject var theme: ThemeStore
    var colors: AppColors { theme.colors(for: scheme) }

    var body: some View {
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
