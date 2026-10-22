import SwiftUI
import CoreText

/// Monocraft (Idrees Hassan, SIL OFL 1.1) pixelbetű regisztrálása a
/// bundle-ből — Info.plist-módosítás nélkül (a projekt generált
/// plistet használ, oda tömb kulcs nem tehető INFOPLIST_KEY-jel).
enum MinecraftFontLoader {
    static let familyName = "Monocraft"
    private static var done = false
    static func registerOnce() {
        guard !done else { return }
        done = true
        guard let url = Bundle.main.url(forResource: "Monocraft", withExtension: "ttf") else { return }
        CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
    }
    /// Pixelbetű, ha regisztrálva van — különben rendszer-monospace
    /// (pl. preview, widget, vagy hiányzó erőforrás esetén).
    static func font(size: CGFloat) -> Font {
        if UIFont(name: familyName, size: size) != nil {
            return .custom(familyName, size: size)
        }
        return .system(size: size, weight: .heavy, design: .monospaced)
    }
}

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

    /// Teljes paletta-átfestés: a szerkezet (melyik mező mit színez)
    /// változatlan, csak a színek cserélődnek — ezért vált egyszerre
    /// MINDEN képernyő. Sötétben mélypala, világosban pergamen
    /// (receptkönyv-hangulat), kiemelés fűzöld, jegyek concrete-színek.
    static func reskin(_ base: AppColors, scheme: ColorScheme) -> AppColors {
        let dark = scheme == .dark
        return AppColors(
            background: dark ? Color(hex: 0x121214) : Color(hex: 0xE8E0C8),
            backgroundGradientTop: base.backgroundGradientTop,
            backgroundGradientBottom: base.backgroundGradientBottom,
            surface: dark ? Color(hex: 0x2B2B30) : Color(hex: 0xF7F0DC),
            surfaceElevated: dark ? Color(hex: 0x35353B) : Color(hex: 0xFFF9E8),
            text: dark ? MinecraftTheme.cream : Color(hex: 0x2B2118),
            textSecondary: (dark ? MinecraftTheme.cream : Color(hex: 0x2B2118)).opacity(0.68),
            textTertiary: (dark ? MinecraftTheme.cream : Color(hex: 0x2B2118)).opacity(0.42),
            accent: dark ? MinecraftTheme.grass : MinecraftTheme.grassDeep,
            accentSoft: (dark ? MinecraftTheme.grass : MinecraftTheme.grassDeep).opacity(0.16),
            border: MinecraftTheme.dirtDark.opacity(dark ? 0.7 : 0.4),
            shadow: Color.black.opacity(0.45),
            red: base.red, orange: base.orange, yellow: base.yellow,
            green: base.green, teal: base.teal, blue: base.blue,
            purple: base.purple, pink: base.pink,
            gradeFive: MinecraftTheme.emerald,
            gradeFour: Color(hex: 0x7ED321),
            gradeThree: MinecraftTheme.gold,
            gradeTwo: MinecraftTheme.orange,
            gradeOne: MinecraftTheme.redstone,
            loginPrimary: dark ? MinecraftTheme.cream : Color(hex: 0x2B2118),
            loginSecondary: (dark ? MinecraftTheme.cream : Color(hex: 0x2B2118)).opacity(0.62),
            loginBackground: dark ? Color(hex: 0x121214) : Color(hex: 0xE8E0C8)
        )
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

    // MARK: - Tipográfia (Monocraft pixelbetű, OFL)
    /// Valódi pixelbetű (Monocraft), nem rendszer-monospace utánzat.
    static func headerFont(size: CGFloat) -> Font {
        MinecraftFontLoader.font(size: size)
    }
    static func bodyFont(size: CGFloat) -> Font {
        MinecraftFontLoader.font(size: size)
    }

    /// Aktív-e a Minecraft-skin (UserDefaults-olvasás — Environment-függés
    /// nélkül, hogy bármely nézetben használható legyen).
    static var isActive: Bool {
        UserDefaults.standard.string(forKey: "ui.skin") == VisualSkin.minecraft.rawValue
    }

    /// Nav-sáv + tab-sáv pixelbetűi (UIKit-appearance — a SwiftUI nem ad
    /// ezekre modifierszintű betűállítást).
    static func applyChromeAppearance(minecraft: Bool) {
        let nav = UINavigationBar.appearance()
        let tabItem = UITabBarItem.appearance()
        if minecraft {
            if let big = UIFont(name: MinecraftFontLoader.familyName, size: 32) {
                nav.largeTitleTextAttributes = [.font: big]
            }
            if let small = UIFont(name: MinecraftFontLoader.familyName, size: 16),
               let tiny = UIFont(name: MinecraftFontLoader.familyName, size: 10) {
                nav.titleTextAttributes = [.font: small]
                tabItem.setTitleTextAttributes([.font: tiny], for: .normal)
                tabItem.setTitleTextAttributes([.font: tiny], for: .selected)
            }
        } else {
            nav.largeTitleTextAttributes = [:]
            nav.titleTextAttributes = [:]
            tabItem.setTitleTextAttributes([:], for: .normal)
            tabItem.setTitleTextAttributes([:], for: .selected)
        }
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

    /// Szekció-fejléc: Summitban a gyári caption-uppercase, Minecraftban
    /// pixelbetű + blokk-árnyék. Közvetlenül a régi lánc helyére tehető.
    @ViewBuilder
    func mcSectionHeader() -> some View {
        if MinecraftTheme.isActive {
            self
                .font(MinecraftTheme.headerFont(size: 12))
                .tracking(0.5)
                .foregroundStyle(.secondary)
                .shadow(color: .black.opacity(0.4), radius: 0, x: 1, y: 1)
        } else {
            self
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
        }
    }

    /// Cím-szöveg (üdvözlés): Summitban gyári title2, Minecraftban
    /// nagy pixelbetű blokk-árnyékkal.
    @ViewBuilder
    func mcTitle() -> some View {
        if MinecraftTheme.isActive {
            self
                .font(MinecraftTheme.headerFont(size: 26))
                .foregroundStyle(.primary)
                .shadow(color: .black.opacity(0.45), radius: 0, x: 2, y: 2)
        } else {
            self
                .font(.title2.weight(.bold))
                .foregroundStyle(.primary)
        }
    }

    /// Kijelző-számok (átlagok, hero-számok): Summitban rounded,
    /// Minecraftban pixelbetű blokk-árnyékkal.
    @ViewBuilder
    func mcDisplay(_ size: CGFloat) -> some View {
        if MinecraftTheme.isActive {
            self
                .font(MinecraftTheme.headerFont(size: size))
                .shadow(color: .black.opacity(0.45), radius: 0, x: 2, y: 2)
        } else {
            self
                .font(.system(size: size, weight: .bold, design: .rounded))
        }
    }
}

/// Élő Minecraft-égbolt (shader-hangulat, BSL/Complementary-íz):
/// a nap reggeltől estig valós idő szerint vándorol át az égen
/// (éjjel pixel-hold + csillagok), az ég színe napszak szerint vált
/// (hajnal-narancs, dél-türkiz, alkony-lila, éjjel-mélykék), a lapos
/// blokk-felhők lassan sodródnak, alul fűsáv + opcionális pixel-hegy.
/// Tiszta SwiftUI-rajz, asset nélkül. `mountain: true` a Beállítások
/// mögé hegyet is tesz.
struct MinecraftBackdrop: View {
    @Environment(\.accessibilityReduceMotion) var reduceMotion
    @Environment(\.accessibilityReduceTransparency) var reduceTransparency
    var scrollOffset: CGFloat = 0
    var mountain: Bool = false
    /// Alsó fűsáv: a lista-hátterekben kikapcsoljuk, mert ott a
    /// tab-sáv fűblokkja adja a földet (különben dupla fűréteg lenne).
    var ground: Bool = true
    var body: some View {
        if reduceTransparency {
            MinecraftTheme.nightTop.ignoresSafeArea()
        } else {
            // Percenként újrarajzol: a nap/hold pozíciója és az ég színe
            // a valós időt követi (reggel→este vándorlás).
            TimelineView(.everyMinute) { tl in
                sky(at: tl.date)
            }
        }
    }

    private func sky(at date: Date) -> some View {
        GeometryReader { proxy in
            let w = proxy.size.width, h = proxy.size.height
            let comps = Calendar.current.dateComponents([.hour, .minute], from: date)
            let hour = Double(comps.hour ?? 12) + Double(comps.minute ?? 0) / 60
            let night = hour < 5.5 || hour >= 20.5
            let shift = min(0, max(-h * 0.2, scrollOffset * 0.25))
            ZStack {
                LinearGradient(colors: skyColors(hour: hour), startPoint: .top, endPoint: .bottom)
                    .ignoresSafeArea()
                // God-ray: ferde fénysáv nappal (BSL-hangulat), nagyon halvány.
                if !night {
                    LinearGradient(colors: [.white.opacity(0.20), .clear],
                                   startPoint: .topLeading, endPoint: .bottomTrailing)
                        .ignoresSafeArea()
                }
                // Nap nappal (reggel keleten alacsonyan → délben magasan →
                // este nyugaton alacsonyan), éjjel pixel-hold kráterekkel.
                if night {
                    mcMoon().position(x: w * moonX(hour: hour), y: 150 + shift)
                } else {
                    let (sx, sy, tint) = sunPose(hour: hour, w: w)
                    RoundedRectangle(cornerRadius: 4)
                        .fill(tint)
                        .frame(width: 64, height: 64)
                        .position(x: sx, y: sy + shift)
                        .shadow(color: tint.opacity(0.5), radius: 24)
                }
                // Rendes minecraft-felhők: lapos fehér blokk-lapok, lassan sodródnak.
                mcCloudLane(width: w, top: 110, night: night, duration: 140)
                mcCloudLane(width: w, top: 210, night: night, duration: 200)
                mcCloudLane(width: w, top: 300, night: night, duration: 260)
                // Éjjel csillagpixelek.
                if night {
                    ForEach(0..<24, id: \.self) { i in
                        Rectangle()
                            .fill(.white.opacity(0.7))
                            .frame(width: 3, height: 3)
                            .position(x: w * Double((i * 37) % 100) / 100,
                                      y: h * Double((i * 53) % 45) / 100 + 40 + shift * 0.4)
                    }
                }
                // Pixel-hegy (Beállítások): hátsó párás csúcs + elülső
                // hósapkás csúcs, tövében fűsávval.
                if mountain {
                    mcMountainRange(width: w, baseY: h - 46 + shift * 0.3)
                }
                // Fűsáv alul (lista-háttérben kikapcsolva — ott a tab-blokk a föld).
                if ground {
                    VStack(spacing: 0) {
                        Spacer()
                        Rectangle().fill(MinecraftTheme.grass).frame(height: 14)
                        Rectangle().fill(MinecraftTheme.dirt).frame(height: 26)
                        Rectangle().fill(MinecraftTheme.dirtDark.opacity(0.55)).frame(height: 6)
                    }.ignoresSafeArea()
                }
            }
        }
        .ignoresSafeArea()
    }

    // MARK: - Napszak

    /// Ég-szín kulcskockák (óra, fent, lent) — közte lineáris átmenet,
    /// így a hajnal/alkony is átúszik, nem vált villanva.
    private var skyKeys: [(Double, Color, Color)] {
        [
            (0, MinecraftTheme.nightTop, MinecraftTheme.nightBottom),
            (4.5, MinecraftTheme.nightTop, MinecraftTheme.nightBottom),
            (6.5, Color(hex: 0x5A7BD6), Color(hex: 0xF2A65A)),
            (8.5, MinecraftTheme.skyTop, MinecraftTheme.skyBottom),
            (16, MinecraftTheme.skyTop, MinecraftTheme.skyBottom),
            (18.5, Color(hex: 0x3B3F7A), Color(hex: 0xFF7E47)),
            (20.5, MinecraftTheme.nightTop, MinecraftTheme.nightBottom),
            (24, MinecraftTheme.nightTop, MinecraftTheme.nightBottom),
        ]
    }

    private func skyColors(hour: Double) -> [Color] {
        let ks = skyKeys
        for i in 0..<(ks.count - 1) where hour >= ks[i].0 && hour <= ks[i + 1].0 {
            let (h0, t0, b0) = ks[i]
            let (h1, t1, b1) = ks[i + 1]
            let t = h1 == h0 ? 0 : (hour - h0) / (h1 - h0)
            return [lerp(t0, t1, t), lerp(b0, b1, t)]
        }
        return [MinecraftTheme.skyTop, MinecraftTheme.skyBottom]
    }

    private func lerp(_ a: Color, _ b: Color, _ t: Double) -> Color {
        let ua = UIColor(a), ub = UIColor(b)
        var ar: CGFloat = 0, ag: CGFloat = 0, ab: CGFloat = 0, aa: CGFloat = 0
        var br: CGFloat = 0, bg: CGFloat = 0, bb: CGFloat = 0, ba: CGFloat = 0
        ua.getRed(&ar, green: &ag, blue: &ab, alpha: &aa)
        ub.getRed(&br, green: &bg, blue: &bb, alpha: &ba)
        let k = CGFloat(min(1, max(0, t)))
        return Color(red: Double(ar + (br - ar) * k), green: Double(ag + (bg - ag) * k),
                     blue: Double(ab + (bb - ab) * k), opacity: Double(aa + (ba - aa) * k))
    }

    /// Nap-pozíció és -szín: 6h-kor keleten (meleg narancs), 12h-kor
    /// magasan (meleg fehér-arany), 18h-kor nyugaton (narancs).
    private func sunPose(hour: Double, w: CGFloat) -> (CGFloat, CGFloat, Color) {
        let t = min(1, max(0, (hour - 6) / 12))
        let x = w * (0.10 + 0.80 * t)
        let y = 330 - sin(t * .pi) * 230
        let edge = min(t, 1 - t) * 2
        let tint: Color = edge < 0.35
            ? Color(hex: 0xFFB347)
            : MinecraftTheme.sun
        return (x, y, tint)
    }

    private func moonX(hour: Double) -> CGFloat {
        let t = hour >= 18 ? (hour - 18) / 12 : (hour + 6) / 12
        return 0.10 + 0.80 * min(1, max(0, t))
    }

    /// Pixel-hold: fakó kocka sötétebb kráter-kockákkal + halvány fénnyel.
    private func mcMoon() -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 4)
                .fill(Color(hex: 0xE8EDF5))
                .frame(width: 56, height: 56)
            RoundedRectangle(cornerRadius: 2).fill(Color(hex: 0xB9C2D4)).frame(width: 14, height: 14).offset(x: -10, y: -8)
            RoundedRectangle(cornerRadius: 2).fill(Color(hex: 0xB9C2D4)).frame(width: 10, height: 10).offset(x: 12, y: 6)
            RoundedRectangle(cornerRadius: 2).fill(Color(hex: 0xC7CFE0)).frame(width: 8, height: 8).offset(x: 2, y: -14)
        }
        .shadow(color: Color.white.opacity(0.4), radius: 20)
    }

    // MARK: - Felhők

    /// Egy sodródó felhősáv: lapos blokk-lapok (igazi minecraft-felhő:
    /// egy réteg éles téglalap), végtelen lineáris sodrással.
    /// Reduce Motion mellett áll.
    private func mcCloudLane(width: CGFloat, top: CGFloat, night: Bool, duration: Double) -> some View {
        let tint: Color = night ? Color(hex: 0x3A4666).opacity(0.6) : .white.opacity(0.9)
        return DriftingCloud(width: width, top: top, duration: duration, reduceMotion: reduceMotion) {
            HStack(spacing: 0) {
                Rectangle().fill(tint).frame(width: 120, height: 14)
                Rectangle().fill(tint).frame(width: 44, height: 24).offset(y: -5)
                Rectangle().fill(tint).frame(width: 84, height: 14)
                Rectangle().fill(tint).frame(width: 30, height: 20).offset(y: -3)
                Rectangle().fill(tint).frame(width: 96, height: 14)
            }
        }
    }

    // MARK: - Pixel-hegy

    /// Lépcsőzött pixel-hegy: soronként szélesedő téglalapok, jobb oldalon
    /// árnyék-sávval, tetején hósipkával.
    private func mcPeak(baseWidth: CGFloat, height: CGFloat, rock: Color, shade: Color, snow: Color) -> some View {
        let rows = max(4, Int(height / 8))
        return VStack(spacing: 0) {
            ForEach(0..<rows, id: \.self) { i in
                let frac = CGFloat(i + 1) / CGFloat(rows)
                let rowW = baseWidth * frac
                ZStack(alignment: .trailing) {
                    Rectangle()
                        .fill(i < 3 ? snow : rock)
                        .frame(width: rowW, height: 8)
                    if i >= 3 {
                        Rectangle().fill(shade).frame(width: rowW / 3, height: 8)
                    } else {
                        Rectangle().fill(shade.opacity(0.35)).frame(width: rowW / 3, height: 8)
                    }
                }
            }
        }
    }

    /// Hegylánc: hátsó párás csúcs + elülső hósapkás csúcs + fűtöve.
    private func mcMountainRange(width: CGFloat, baseY: CGFloat) -> some View {
        ZStack(alignment: .bottom) {
            HStack(alignment: .bottom, spacing: -40) {
                mcPeak(baseWidth: width * 0.55, height: 190,
                       rock: Color(hex: 0x6E7B8C), shade: Color(hex: 0x525C69), snow: Color(hex: 0xDDE6F2))
                    .opacity(0.85)
                mcPeak(baseWidth: width * 0.7, height: 260,
                       rock: Color(hex: 0x7D8A99), shade: Color(hex: 0x5A6572), snow: .white)
            }
            Rectangle().fill(MinecraftTheme.grassDeep).frame(height: 10)
        }
        .frame(width: width, height: 270, alignment: .bottom)
        .position(x: width / 2, y: baseY - 135 + 23)
    }
}

/// Végtelenül sodródó felhő: balról jobbra lineárisan, hurokban.
private struct DriftingCloud<Content: View>: View {
    var width: CGFloat
    var top: CGFloat
    var duration: Double
    var reduceMotion: Bool
    @ViewBuilder var content: () -> Content
    @State private var x: CGFloat?
    var body: some View {
        content()
            .position(x: x ?? -220, y: top)
            .onAppear {
                if reduceMotion { x = width / 2; return }
                x = -220
                withAnimation(.linear(duration: duration).repeatForever(autoreverses: false)) {
                    x = width + 220
                }
            }
    }
}


/// Igazi minecraft fűblokk-lábazat a tab-sáv mögé: magas (a tab-sáv
/// fölé nyúlik), felül fűréteg világos bevel-csíkkal, alatta földdel,
/// determinisztikus pixel-zajjal (moha-, föld- és kőpöttyök), tetején
/// sötét körvonallal. Teljes szélességű, a home-jelző alá is lemegy.
struct McGrassBlockFooter: View {
    var height: CGFloat = 148
    var body: some View {
        GeometryReader { proxy in
            let w = proxy.size.width
            ZStack(alignment: .top) {
                // Földtest.
                Rectangle().fill(MinecraftTheme.dirt)
                // Föld-zaj: sötétebb/világosabb rögök + pár kő.
                ForEach(0..<46, id: \.self) { i in
                    let px = CGFloat((i * 137) % Int(max(1, Int(w)))) + 3
                    let py = 30 + CGFloat((i * 89) % Int(max(1, Int(height - 44))))
                    let c: Color = i % 7 == 0 ? Color(hex: 0x8D8D93)
                        : (i % 3 == 0 ? MinecraftTheme.dirtDark : Color(hex: 0xA06A35))
                    Rectangle().fill(c.opacity(0.85))
                        .frame(width: 7, height: 7)
                        .position(x: px, y: py)
                }
                // Fűréteg felül.
                VStack(spacing: 0) {
                    // Sötét körvonal a legtetején.
                    Rectangle().fill(MinecraftTheme.dirtDark).frame(height: 3)
                    // Bevel-fény.
                    Rectangle().fill(Color(hex: 0x7ED321)).frame(height: 2)
                    // Fűsáv zajjal.
                    ZStack(alignment: .topLeading) {
                        Rectangle().fill(MinecraftTheme.grass).frame(height: 17)
                        ForEach(0..<26, id: \.self) { i in
                            let px = CGFloat((i * 53) % Int(max(1, Int(w)))) + 4
                            Rectangle()
                                .fill(i % 4 == 0 ? Color(hex: 0x7ED321) : MinecraftTheme.grassDeep)
                                .frame(width: 6, height: 6)
                                .position(x: px, y: 9)
                        }
                    }
                    .frame(height: 17)
                    // Cakkos fűszegély: változó mélységű zöld kockák lógnak a földbe.
                    HStack(alignment: .top, spacing: 2) {
                        ForEach(0..<60, id: \.self) { i in
                            let depths: [CGFloat] = [4, 9, 6, 12, 7, 5, 10]
                            Rectangle()
                                .fill(MinecraftTheme.grass)
                                .frame(width: 6, height: depths[i % depths.count])
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    Spacer(minLength: 0)
                }
            }
        }
        .frame(height: height)
    }
}
