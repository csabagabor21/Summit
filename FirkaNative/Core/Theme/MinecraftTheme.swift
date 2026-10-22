import SwiftUI

/// Minecraft skin: modern (1.20+ Trails & Tales / Tricky Trials) íz,
/// nem a fakó alfa-stílus. Shader-inspiráció (BSL, Complementary,
/// Sildur's Vibrant): telített fűzöld, meleg napfény-arany, türkiz
/// gyémánt-akcentus, puha mélység-árnyék, god-ray-szerű fényátmenet.
/// Minden szín / mérőszám egy helyen, hogy a nézetek ne szórjanak
/// magic-number blokk-stílust.
enum MinecraftTheme {
    // MARK: - Paletta (shader-hangulat, telített, nem fakó)
    static let grass: Color = Color(hex: 0x5EBB2B)      // Complementary-féle élénk fű
    static let grassDeep: Color = Color(hex: 0x3E8E1F)  // árnyékos fűoldal
    static let dirt: Color = Color(hex: 0x8A5A2B)       // gazdag, meleg föld
    static let dirtDark: Color = Color(hex: 0x5C3A1A)   // blokk-árnyék
    static let stone: Color = Color(hex: 0x8D8D93)      // modern kőszürke
    static let deepslate: Color = Color(hex: 0x2B2B30)  // mélység-háttér
    static let diamond: Color = Color(hex: 0x4EE6D2)    // gyémánt-akcentus
    static let emerald: Color = Color(hex: 0x2ECC71)    // 5-ös / XP-zöld
    static let gold: Color = Color(hex: 0xFFC93C)       // 3-as / napfény
    static let redstone: Color = Color(hex: 0xFF3B30)   // 1-es / hiba
    static let orange: Color = Color(hex: 0xFF8C2E)     // 2-es
    static let cream: Color = Color(hex: 0xFFF3D6)      // meleg papirusz-szöveg
    static let skyTop: Color = Color(hex: 0x6EC1F5)     // shader-ég felül
    static let skyBottom: Color = Color(hex: 0xCDEBFF)  // horizont-pára
    static let sun: Color = Color(hex: 0xFFE9A8)        // meleg napkorong
    static let nightTop: Color = Color(hex: 0x0B1026)   // éjszakai shader-ég
    static let nightBottom: Color = Color(hex: 0x1E2A52)

    /// Jegy → modern concrete/wool szín (telített, nem pasztell).
    static func gradeColor(for value: Int) -> Color {
        switch value {
        case 5: return emerald
        case 4: return Color(hex: 0x7ED321) // lime concrete
        case 3: return gold
        case 2: return orange
        case 1: return redstone
        default: return stone
        }
    }

    /// Tab-sorrendhez Minecraft-ízű SF-ikonok (minden tab kap blokkos ikont).
    /// - Returns: (cím, systemImage).
    static func tabIcon(for tab: Int) -> (String, String) {
        switch tab {
        case 0: return ("Főoldal", "cube.fill")            // fűblokk
        case 1: return ("Jegyek", "diamond.fill")           // gyémánt
        case 2: return ("Órarend", "map.fill")              // térkép
        case 5: return ("Feladatok", "checklist")           // nyers checklist marad olvasható
        case 4: return ("Hiányzások", "hourglass")          // homokóra
        case 3: return ("Watch", "applewatch")              // óra
        default: return ("", "cube.fill")
        }
    }

    // MARK: - Tipográfia (pixel-hangulat rendszerfontból)
    /// Minecraft-szerű fejlécl: félkövér, enyhe ritkítás, nem csupa
    /// nagybetűs kiabálás — a Mojangles/Monocraft ritmusát idézi.
    static func headerFont(size: CGFloat) -> Font {
        .system(size: size, weight: .heavy, design: .monospaced)
    }
    static func bodyFont(size: CGFloat) -> Font {
        .system(size: size, weight: .bold, design: .monospaced)
    }
}

// MARK: - Blokkos felület-modifierek

extension View {
    /// Minecraft-kártya: 6pt blokk-sarok, sötét körvonal + felső belső
    /// fényél (bevel) + kemény, el nem mosott mélység-árnyék — mint a
    /// játék gombjai/blokkjai. Reduce Transparency mellett lapos.
    @ViewBuilder
    func minecraftCard(cornerRadius: CGFloat = 6) -> some View {
        if UIAccessibility.isReduceTransparencyEnabled {
            self.background(MinecraftTheme.deepslate, in: RoundedRectangle(cornerRadius: cornerRadius))
        } else {
            self
                .background(
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .fill(Color(.systemBackground))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .strokeBorder(MinecraftTheme.dirtDark, lineWidth: 3)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .strokeBorder(Color.white.opacity(0.35), lineWidth: 1)
                        .padding(2)
                )
                .shadow(color: .black.opacity(0.35), radius: 0, x: 0, y: 4)
        }
    }

    /// Minecraft-nyomógomb: fűzöld blokk, bevel-lel, kemény árnyékkal.
    @ViewBuilder
    func minecraftButton(tint: Color = MinecraftTheme.grass) -> some View {
        self
            .font(MinecraftTheme.bodyFont(size: 15))
            .foregroundStyle(.white)
            .shadow(color: .black.opacity(0.6), radius: 0, x: 2, y: 2)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(tint)
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .strokeBorder(MinecraftTheme.dirtDark, lineWidth: 3)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .strokeBorder(Color.white.opacity(0.4), lineWidth: 1)
                            .padding(2)
                    )
                    .shadow(color: .black.opacity(0.4), radius: 0, x: 0, y: 4)
            )
    }

    /// Minecraft-fejlécszöveg: pixel-ritmus + enyhe blokk-árnyék.
    func minecraftHeader(size: CGFloat = 17) -> some View {
        self
            .font(MinecraftTheme.headerFont(size: size))
            .tracking(0.5)
            .shadow(color: .black.opacity(0.35), radius: 0, x: 1, y: 2)
    }
}

/// Shader-hangulatú Minecraft-háttér: nappal telített ég + blokkos
/// napkorong + pixel-felhők + god-ray fénypászma, alul fűsávval;
/// éjjel mélykék shader-ég csillagpixelekkel. Textúra helyett tiszta
/// SwiftUI-rajz (asset nélkül), parallax-kompatibilis.
struct MinecraftBackdrop: View {
    @Environment(\.colorScheme) var scheme
    @Environment(\.accessibilityReduceTransparency) var reduceTransparency
    var scrollOffset: CGFloat = 0
    var body: some View {
        if reduceTransparency {
            (scheme == .dark ? MinecraftTheme.nightTop : MinecraftTheme.cream).ignoresSafeArea()
        } else {
            GeometryReader { proxy in
                let w = proxy.size.width, h = proxy.size.height
                let shift = min(0, max(-h * 0.2, scrollOffset * 0.25))
                ZStack {
                    LinearGradient(
                        colors: scheme == .dark
                            ? [MinecraftTheme.nightTop, MinecraftTheme.nightBottom]
                            : [MinecraftTheme.skyTop, MinecraftTheme.skyBottom],
                        startPoint: .top, endPoint: .bottom
                    ).ignoresSafeArea()
                    // God-ray: ferde fénysáv (BSL-hangulat), nagyon halvány.
                    LinearGradient(
                        colors: [.white.opacity(scheme == .dark ? 0.06 : 0.22), .clear],
                        startPoint: .topLeading, endPoint: .bottomTrailing
                    ).ignoresSafeArea()
                    // Blokkos nap / hold.
                    RoundedRectangle(cornerRadius: 4)
                        .fill(scheme == .dark ? .white.opacity(0.9) : MinecraftTheme.sun)
                        .frame(width: 64, height: 64)
                        .position(x: w * 0.78, y: 140 + shift)
                        .shadow(color: (scheme == .dark ? Color.white : MinecraftTheme.sun).opacity(0.5), radius: 24)
                    // Pixel-felhők.
                    Group {
                        mcCloud(x: w * 0.2, y: 110 + shift * 0.6, scale: 1)
                        mcCloud(x: w * 0.6, y: 210 + shift * 0.6, scale: 0.7)
                        mcCloud(x: w * 0.35, y: 300 + shift * 0.6, scale: 0.5)
                    }
                    // Éjjel csillagpixelek.
                    if scheme == .dark {
                        Group {
                            ForEach(0..<24, id: \.self) { i in
                                let sx = w * Double((i * 37) % 100) / 100
                                let sy = h * Double((i * 53) % 45) / 100 + 40
                                Rectangle()
                                    .fill(.white.opacity(0.7))
                                    .frame(width: 3, height: 3)
                                    .position(x: sx, y: sy + shift * 0.4)
                            }
                        }
                    }
                    // Fűsáv alul: világos fű + sötét föld-csík (oldalnézeti blokk).
                    VStack(spacing: 0) {
                        Spacer()
                        Rectangle().fill(MinecraftTheme.grass).frame(height: 14)
                        Rectangle().fill(MinecraftTheme.dirt).frame(height: 26)
                        Rectangle().fill(MinecraftTheme.dirtDark.opacity(0.55)).frame(height: 6)
                    }.ignoresSafeArea()
                }
            }
            .ignoresSafeArea()
        }
    }

    /// Téglalapokból rakott pixel-felhő.
    private func mcCloud(x: CGFloat, y: CGFloat, scale: CGFloat) -> some View {
        HStack(spacing: 0) {
            Rectangle().fill(.white.opacity(0.85)).frame(width: 46, height: 14)
            Rectangle().fill(.white.opacity(0.85)).frame(width: 30, height: 22).offset(y: -4)
            Rectangle().fill(.white.opacity(0.85)).frame(width: 40, height: 14)
        }
        .scaleEffect(scale)
        .position(x: x, y: y)
    }
}
