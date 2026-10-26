import SwiftUI

struct GradeCircle: View {
    let value: Int
    var size: CGFloat = 44
    @Environment(\.colorScheme) var scheme
    @EnvironmentObject var theme: ThemeStore
    var colors: AppColors { theme.colors(for: scheme) }

    var body: some View {
        if theme.isVoxel {
            // Voxel: tömör concrete-blokk, bevel-lel és kemény árnyékkal.
            VoxelGradeBlock(value: value, size: size)
        } else if theme.isNeon {
            // Neon: levágott sarkú HUD-jelvény a jegy színében,
            // szint-csíkkal (lásd `CpGradeChip`).
            CpGradeChip(value: value, size: size)
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

/// Jegy-blokk Voxelben: a jegy színű concrete-kocka lépcsős sarkokkal,
/// bevel-lel és kemény árnyékkal, benne Monocraft számmal. A `GradeCircle`
/// és a tantárgy-részlet kis jegykarikái is ezt használják.
struct VoxelGradeBlock: View {
    let value: Int
    var size: CGFloat = 44
    /// nil = a méretből: nagy blokkon 18, kicsin 13 pont.
    var fontSize: CGFloat?

    var body: some View {
        Text("\(value)")
            .font(VoxelTheme.headerFont(size: fontSize ?? (size > 32 ? 18 : 13)))
            .foregroundStyle(.white)
            .shadow(color: .black.opacity(0.6), radius: 0, x: 1, y: 2)
            .monospacedDigit()
            .frame(width: size, height: size)
            .background(
                // Pixel-blokk: lépcsős sarok, bevel, kemény árnyék — ugyanaz
                // a rács, mint a kártyáké, így a kocka sosem lekerekített.
                VoxelBlockPanel(face: VoxelTheme.gradeColor(for: value),
                             outline: Color(hex: 0x1E1A16),
                             highlight: .white.opacity(0.38),
                             shade: .black.opacity(0.28))
            )
            .accessibilityLabel("\(value)")
    }
}

/// Jegy-jelvény Neonban: a kit `NeonGradeBadge`-e (levágott sarkú,
/// 1 px-es neon keret a jegy színében) kiegészítve, hogy a jegy szín
/// nélkül is azonnal olvasható legyen:
/// - alul 5 szegmenses szint-csík, ahány a jegy, annyi világít (a játék
///   HUD-jának töltöttség-pipjei — színtévesztőnek is egyértelmű);
/// - az 1-es inverz (tömör HUD-vörös lap, fekete szám) — riasztás-panel;
/// - az 5-ös jobb felső sarkában kis cián sarokjel.
/// Mindig opak, majdnem fekete alapon ül, így bármilyen felületen
/// (Főoldal, lista-sor, tantárgy-részlet) ugyanúgy néz ki. Statikus:
/// se animáció, se glitch (listában tucatszám van belőle).
/// A `GradeCircle` Neon-ága ezt használja; a tantárgy-részletező
/// közvetlenül is hívhatja (mint Voxelben a `VoxelGradeBlock`-ot).
struct CpGradeChip: View {
    let value: Int
    var size: CGFloat = 44
    /// Szint-csík (alapból 28 pt fölött látszik, kisebb jelvényen zsúfolt).
    var showsLevel: Bool = true
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        let color = NeonTheme.gradeColor(for: value)
        let isGrade = (1...5).contains(value)
        let alert = value == 1
        // Nagyon nagy betűméretnél a szám a csíkra csúszna — ott a szám nyer.
        let level = showsLevel && isGrade && size >= 28 && typeSize <= .xxLarge
        NeonGradeBadge(value: value, size: size, filled: alert)
            .background(NeonChamferShape(cut: size * 0.22, corners: [.topLeft, .bottomRight]).fill(NeonTheme.bg))
            .overlay(alignment: .bottom) {
                if level {
                    CpGradeLevelBar(value: value, color: alert ? .black : color, width: size * 0.56)
                        .padding(.bottom, max(4, size * 0.13))
                }
            }
            .overlay(alignment: .topTrailing) {
                if value == 5 {
                    CpCornerMark()
                        .fill(NeonTheme.cyanBright)
                        .frame(width: size * 0.2, height: size * 0.2)
                        .padding(2)
                }
            }
            .frame(width: size, height: size)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(value)-es jegy")
    }
}

/// Öt szegmenses szint-csík a jegy-jelvény alján.
private struct CpGradeLevelBar: View {
    let value: Int
    let color: Color
    let width: CGFloat
    var body: some View {
        let gap: CGFloat = width > 20 ? 2 : 1
        let seg = max(1, (width - gap * 4) / 5)
        HStack(spacing: gap) {
            ForEach(1...5, id: \.self) { i in
                Rectangle()
                    .fill(i <= value ? color : color.opacity(0.22))
                    .frame(width: seg, height: 2)
            }
        }
        .accessibilityHidden(true)
    }
}

/// Jobb felső sarokjel (kis derékszögű háromszög) az 5-ös jelvényen.
private struct CpCornerMark: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: rect.minX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        p.closeSubpath()
        return p
    }
}
