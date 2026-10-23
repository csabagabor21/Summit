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

@ViewBuilder
static func skinRowBackground(_ color: Color) -> some View {
    if isActive {
        McRowPanel(face: color)
    } else {
        color
    }
}

    /// Tab-sorrendhez EREDETI item-sprite-ok a saját 1.21.11-es
    /// telepítésből (grass_block oldala, gyémánt, óra, könyv, barrier,
    /// iránytű). - Returns: (cím, bundle-képnév).
    static func tabItemIcon(for tab: Int) -> (String, String) {
        switch tab {
        case 0: return ("Főoldal", "mc_grass_side")
        case 1: return ("Jegyek", "mc_item_diamond")
        case 2: return ("Órarend", "mc_item_clock")
        case 5: return ("Feladatok", "mc_item_writable_book")
        case 4: return ("Hiányzások", "mc_item_barrier")
        case 3: return ("Watch", "mc_item_compass")
        default: return ("", "mc_grass_side")
        }
    }

    /// Eredeti 16x16-os textúra éles, nearest-neighbor nagyítással.
    /// Direkt fájlbetöltéssel (a laza bundle-PNG-ket a sima Image(név)
    /// nem találja meg megbízhatóan).
    static func mcPixelImage(_ name: String, size: CGFloat) -> some View {
        Group {
            if let ui = MinecraftTheme.sprite(name) {
                Image(uiImage: ui)
                    .resizable()
                    .interpolation(.none)
            } else {
                Color.clear
            }
        }
        .frame(width: size, height: size)
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
            let big = UIFont(name: MinecraftFontLoader.familyName, size: 32)
            let small = UIFont(name: MinecraftFontLoader.familyName, size: 16)
            let tiny = UIFont(name: MinecraftFontLoader.familyName, size: 10)
            if let big { nav.largeTitleTextAttributes = [.font: big] }
            if let small, let tiny {
                nav.titleTextAttributes = [.font: small]
                tabItem.setTitleTextAttributes([.font: tiny], for: .normal)
                tabItem.setTitleTextAttributes([.font: tiny], for: .selected)
            }
            // Nav-sáv: görgetve a játék paneljének kő-szürkéje (a rendszer
            // iOS 26-on a háttérképet nem rajzolja, a címszínt pedig a
            // SwiftUI adja — ezért olvasható, világos/sötét sávszín kell),
            // keményen elválasztva; a tetején átlátszó.
            let title: [NSAttributedString.Key: Any] = {
                var a: [NSAttributedString.Key: Any] = [:]
                if let small { a[.font] = small }
                return a
            }()
            let large: [NSAttributedString.Key: Any] = big.map { [.font: $0] } ?? [:]
            let scrolled = UINavigationBarAppearance()
            scrolled.configureWithOpaqueBackground()
            scrolled.backgroundColor = UIColor { $0.userInterfaceStyle == .dark
                ? UIColor(red: 0x2E / 255, green: 0x2E / 255, blue: 0x33 / 255, alpha: 1)
                : UIColor(red: 0xC6 / 255, green: 0xC6 / 255, blue: 0xC6 / 255, alpha: 1) }
            scrolled.shadowColor = UIColor(red: 0x37 / 255, green: 0x37 / 255, blue: 0x37 / 255, alpha: 1)
            scrolled.titleTextAttributes = title
            scrolled.largeTitleTextAttributes = large
            let top = UINavigationBarAppearance()
            top.configureWithTransparentBackground()
            top.titleTextAttributes = title
            top.largeTitleTextAttributes = large
            nav.standardAppearance = scrolled
            nav.compactAppearance = scrolled
            nav.scrollEdgeAppearance = top
        } else {
            nav.largeTitleTextAttributes = [:]
            nav.titleTextAttributes = [:]
            tabItem.setTitleTextAttributes([:], for: .normal)
            tabItem.setTitleTextAttributes([:], for: .selected)
            // Visszaállás a rendszer-alapra (csak ha volt Minecraft-appearance).
            if chromeOverridden {
                nav.standardAppearance = UINavigationBarAppearance()
                nav.compactAppearance = UINavigationBarAppearance()
                nav.scrollEdgeAppearance = nil
            }
        }
        chromeOverridden = minecraft
    }

    private static var chromeOverridden = false
}

// MARK: - Blokkos felület-modifierek

extension View {
    /// Minecraft-kártya: igazi MC-dialógus panel (McPanelStyle) —
    /// világos bal-felső bevel + sötét jobb-alsó él + körvonal + kemény
    /// mélység-árnyék. Reduce Transparency mellett is opak (az a jó).
    func minecraftCard(cornerRadius: CGFloat = 6) -> some View {
        self.modifier(McPanelStyle(radius: cornerRadius))
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
            .background(McBlockPanel(face: tint, outline: Color(hex: 0x1F2A12), highlight: .white.opacity(0.35), shade: .black.opacity(0.28)))
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
                    mcMoon().scaleEffect(48 / 56).position(x: w * moonX(hour: hour), y: 150 + shift)
                } else {
                    let (sx, sy, tint) = sunPose(hour: hour, w: w)
                    // Kemény négyzet-nap, világosabb maggal (mint a játék napja);
                    // nincs lekerekítés, nincs derengés.
                    Rectangle()
                        .fill(tint)
                        .frame(width: 48, height: 48)
                        .overlay(Rectangle().fill(Color.white.opacity(0.55)).frame(width: 24, height: 24))
                        .position(x: sx, y: sy + shift)
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
                // Fűsáv alul igazi textúrából (lista-háttérben kikapcsolva
                // — ott a tab-blokk a föld).
                if ground {
                    VStack(spacing: 0) {
                        Spacer()
                        McGroundStrip()
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
        // A jobb oldali sávban vándorol, a nagy cím mellett: balra a
        // címet takarná, feljebb a toolbar-gombokat, lejjebb a tartalmat.
        let x = w * (0.66 + 0.18 * t)
        let y = 160 - sin(t * .pi) * 20
        let edge = min(t, 1 - t) * 2
        let tint: Color = edge < 0.35
            ? Color(hex: 0xFFB347)
            : MinecraftTheme.sun
        return (x, y, tint)
    }

    private func moonX(hour: Double) -> CGFloat {
        let t = hour >= 18 ? (hour - 18) / 12 : (hour + 6) / 12
        return 0.66 + 0.18 * min(1, max(0, t))
    }

    /// Pixel-hold: fakó kocka sötétebb kráter-kockákkal.
    private func mcMoon() -> some View {
        ZStack {
            Rectangle()
                .fill(Color(hex: 0xE8EDF5))
                .frame(width: 57, height: 57)
            Rectangle().fill(Color(hex: 0xB9C2D4)).frame(width: 15, height: 15).offset(x: -9, y: -9)
            Rectangle().fill(Color(hex: 0xB9C2D4)).frame(width: 9, height: 9).offset(x: 12, y: 6)
            Rectangle().fill(Color(hex: 0xC7CFE0)).frame(width: 9, height: 9).offset(x: 3, y: -15)
        }
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


extension View {
/// Lista-sor háttér skin-érzékenyen: Summitban a kapott szín simán,
/// Minecraftban lekerekített blokk dirt-kerettel + bevel-lel.
/// Teljes sor-stílus: blokk-háttér + rejtett elválasztó + blokk-távolság.
/// Summitban nem csinál semmit (marad a gyári sor).
@ViewBuilder
func mcListRow(fill: Color) -> some View {
    if MinecraftTheme.isActive {
        self.listRowBackground(MinecraftTheme.skinRowBackground(fill))
            .listRowSeparator(.hidden)
            .listRowInsets(MinecraftTheme.rowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16)))
    } else {
        self
    }
}

/// Vékony kártya-körvonal skin-érzékenyen: Summitban hajszálvékony,
/// Minecraftban dirt-blokk keret + bevel. Meglévő fill mellé tehető.
@ViewBuilder
func mcHairlineBorder(cornerRadius: CGFloat = 12) -> some View {
    if MinecraftTheme.isActive {
        self.clipShape(McPixelShape(steps: 2)).overlay(McBlockPanel(face: .clear, castsShadow: false))
    } else {
        self.overlay(RoundedRectangle(cornerRadius: cornerRadius).strokeBorder(Color.primary.opacity(0.06), lineWidth: 1))
    }
}

}

// MARK: - Talaj

/// Determinisztikus pixel-zaj: ugyanaz a (x, y, mag) mindig ugyanazt adja,
/// így a föld és a növények nem keverednek újra minden rajzolásnál.
private enum McNoise {
    static func hash(_ x: Int, _ y: Int, _ seed: Int = 0) -> Int {
        var h = UInt64(bitPattern: Int64(x &* 374_761_393 &+ y &* 668_265_263 &+ seed &* 1_442_695_041))
        h = (h ^ (h >> 13)) &* 1_274_126_177
        h ^= h >> 16
        return Int(h & 0x7FFF_FFFF)
    }
    static func unit(_ x: Int, _ y: Int, _ seed: Int = 0) -> Double {
        Double(hash(x, y, seed) % 10_000) / 10_000
    }
}

extension MinecraftTheme {
    /// Napfény 0…1 a valós idő szerint (ugyanazok a sarokpontok, mint az
    /// égbolté): éjjel 0, hajnalban/alkonykor átúszik, nappal 1.
    static func daylight(at date: Date) -> Double {
        let c = Calendar.current.dateComponents([.hour, .minute], from: date)
        let h = Double(c.hour ?? 12) + Double(c.minute ?? 0) / 60
        switch h {
        case ..<4.5: return 0
        case ..<8.5: return (h - 4.5) / 4
        case ..<16: return 1
        case ..<20.5: return 1 - (h - 16) / 4.5
        default: return 0
        }
    }
}

/// Saját rajzolású fűblokk-talaj (nincs benne Mojang-textúra): 3 pt-os
/// pixelrácson seedelt földzaj, csöpögő fűperem, kavicsok, lefelé
/// sötétedő mélység, a tetején szélben ringó fű és virágok. A fény a
/// napszakot követi, mint az égbolt. A home-jelző alá is lenyúlik.
struct McGrassBlockFooter: View {
    var height: CGFloat = 148
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.everyMinute) { tl in
            let light = MinecraftTheme.daylight(at: tl.date)
            McSoil()
                .overlay(alignment: .top) {
                    McFlora(animated: !reduceMotion)
                        .frame(height: McFlora.maxHeight)
                        .offset(y: -McFlora.maxHeight + McSoil.unit)
                        .allowsHitTesting(false)
                }
                .overlay(Color(hex: 0x0B1026).opacity(0.5 * (1 - light)).allowsHitTesting(false))
        }
        .frame(height: height)
        .ignoresSafeArea(.container, edges: .bottom)
        .accessibilityHidden(true)
    }
}

/// Föld + fűperem, egyetlen Canvasban (raszterizálva, nem rajzol újra
/// görgetéskor).
struct McSoil: View {
    static let unit: CGFloat = 3

    private static let grass: [Color] = [Color(hex: 0x5DAE34), Color(hex: 0x6CBF3C), Color(hex: 0x4E9A2B)]
    private static let grassLip: Color = Color(hex: 0x86D44E)
    private static let dirt: [Color] = [Color(hex: 0x8B6142), Color(hex: 0x7C5538), Color(hex: 0x966C4A), Color(hex: 0x6E4A30)]
    private static let speckDark: Color = Color(hex: 0x553722)
    private static let speckLight: Color = Color(hex: 0xA98057)
    private static let pebble: [Color] = [Color(hex: 0x8E8C88), Color(hex: 0x6F6D69), Color(hex: 0xB2AFA8)]

    var body: some View {
        Canvas(rendersAsynchronously: true) { ctx, size in
            let u = Self.unit
            let cols = Int(ceil(size.width / u)), rows = Int(ceil(size.height / u))
            func px(_ x: Int, _ y: Int, _ c: Color, w: Int = 1) {
                ctx.fill(Path(CGRect(x: CGFloat(x) * u, y: CGFloat(y) * u, width: CGFloat(w) * u, height: u)), with: .color(c))
            }
            // Alap földszín egy darabban, utána csak az eltérő pixelek.
            ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .color(Self.dirt[0]))
            for y in 0..<rows {
                var x = 0
                while x < cols {
                    // Vízszintes 1–2 px-es foltok: ettől lesz "föld", nem tévézaj.
                    let n = McNoise.unit(x, y, 7)
                    let w = McNoise.hash(x, y, 3) % 3 == 0 ? 2 : 1
                    if n < 0.07 { px(x, y, Self.speckDark, w: w) }
                    else if n < 0.12 { px(x, y, Self.speckLight, w: 1) }
                    else if n < 0.40 { px(x, y, Self.dirt[1 + McNoise.hash(x, y, 11) % 3], w: w) }
                    x += w
                }
            }
            // Kavicsok: ritka 2–3 px-es kőcsomók a mélyebb rétegben.
            var gx = 4 + McNoise.hash(1, 1, 5) % 14
            while gx < cols - 3 {
                let gy = 9 + McNoise.hash(gx, 0, 9) % max(1, rows - 12)
                px(gx, gy, Self.pebble[0], w: 2)
                px(gx + 1, gy - 1, Self.pebble[2])
                px(gx, gy + 1, Self.pebble[1], w: 3)
                gx += 22 + McNoise.hash(gx, 1, 13) % 30
            }
            // Fűperem: 3 sor tömör fű + oszloponként 0–3 px "csöpögés",
            // szomszédokhoz simítva (így ível, nem fésű).
            for x in 0..<cols {
                let a = McNoise.hash(x, 0, 21) % 4, b = McNoise.hash(x + 1, 0, 21) % 4
                let drip = 3 + (a + b + 1) / 2
                for y in 0..<drip {
                    px(x, y, Self.grass[McNoise.hash(x, y, 31) % 3])
                }
                // Árnyék-sor a fű alatt: mélységet ad a peremnek.
                px(x, drip, Self.speckDark.opacity(0.55))
                if McNoise.hash(x, 0, 41) % 3 != 0 { px(x, 0, Self.grassLip) }
            }
            // Lefelé sötétedő mélység (ambient occlusion).
            ctx.fill(Path(CGRect(x: 0, y: u * 8, width: size.width, height: size.height - u * 8)),
                     with: .linearGradient(Gradient(colors: [.clear, .black.opacity(0.38)]),
                                           startPoint: CGPoint(x: 0, y: u * 8),
                                           endPoint: CGPoint(x: 0, y: size.height)))
        }
    }
}

/// Fű és virágok a talaj tetején, saját pixel-sprite-okból. Szélben
/// ringanak: a sprite sorai magasságarányosan, egész pixelre lépve
/// tolódnak el (mint a játék hullámzó-növény shadere), nem simán dőlnek.
struct McFlora: View {
    static let maxHeight: CGFloat = 8 * McSoil.unit
    var animated: Bool

    private struct Sprite {
        let rows: [String]
        let palette: [Character: Color]
    }

    private static let stem: [Character: Color] = ["g": Color(hex: 0x3F8A25), "l": Color(hex: 0x5DB536)]
    private static func with(_ extra: [Character: Color]) -> [Character: Color] { stem.merging(extra) { $1 } }

    private static let sprites: [Sprite] = [
        // 0 fűcsomó
        Sprite(rows: [".a...a.", ".a.a.a.", "ba.a.ab", ".bab.a.", ".babab."],
               palette: ["a": Color(hex: 0x7CCB45), "b": Color(hex: 0x4E9A2B)]),
        // 1 kis fűcsomó
        Sprite(rows: ["a..a", "a.ab", "bab.", ".ba."],
               palette: ["a": Color(hex: 0x7CCB45), "b": Color(hex: 0x4E9A2B)]),
        // 2 pipacs
        Sprite(rows: [".rrr.", "rrkrr", ".RrR.", "..g..", ".lg..", "..g..", "..gl.", "..g.."],
               palette: with(["r": Color(hex: 0xE0302B), "R": Color(hex: 0xA41E1E), "k": Color(hex: 0x2B1B12)])),
        // 3 pitypang
        Sprite(rows: [".yy.", "yoyy", ".yy.", "..g.", ".lg.", "..gl", "..g."],
               palette: with(["y": Color(hex: 0xFFD83A), "o": Color(hex: 0xE8A317)])),
        // 4 búzavirág
        Sprite(rows: [".b.b.", "bBbBb", ".bBb.", "..g..", "..gl.", ".lg..", "..g.."],
               palette: with(["b": Color(hex: 0x5B7CF5), "B": Color(hex: 0x3346BD)])),
        // 5 margaréta
        Sprite(rows: [".w.w.", "wwyww", ".w.w.", "..g..", ".lg..", "..gl.", "..g.."],
               palette: with(["w": Color(hex: 0xF6F4EC), "y": Color(hex: 0xF2C230)])),
    ]

    /// Növény-helyek: 5–17 px-es lépésekkel, determinisztikusan; minden
    /// negyedik-ötödik virág, a többi fű.
    private static func layout(cols: Int) -> [(x: Int, sprite: Int, phase: Double)] {
        var out: [(Int, Int, Double)] = []
        var x = 2 + McNoise.hash(0, 9, 3) % 5
        var i = 0
        while x < cols - 7 {
            let r = McNoise.hash(i, 0, 77) % 100
            let sprite = r < 38 ? 0 : r < 62 ? 1 : 2 + (McNoise.hash(i, 1, 79) % 4)
            out.append((x, sprite, McNoise.unit(i, 2, 81) * .pi * 2))
            x += 5 + McNoise.hash(i, 3, 83) % 13
            i += 1
        }
        return out
    }

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 12, paused: !animated)) { tl in
            let t = animated ? tl.date.timeIntervalSinceReferenceDate : 0
            Canvas { ctx, size in
                let u = McSoil.unit
                let cols = Int(size.width / u)
                for p in Self.layout(cols: cols) {
                    let sp = Self.sprites[p.sprite]
                    let h = sp.rows.count
                    // Lassú alaphullám + apró rezgés: 0…1 px kitérés a csúcson.
                    let wave = sin(t * 1.3 + p.phase) * 0.8 + sin(t * 3.1 + p.phase * 1.7) * 0.25
                    for (ry, row) in sp.rows.enumerated() {
                        let lift = Double(h - ry) / Double(h)
                        let dx = (wave * lift * 1.6).rounded()
                        for (rx, ch) in row.enumerated() {
                            guard let c = sp.palette[ch] else { continue }
                            let x = CGFloat(p.x + rx) * u + CGFloat(dx) * u
                            let y = size.height - CGFloat(h - ry) * u
                            ctx.fill(Path(CGRect(x: x, y: y, width: u, height: u)), with: .color(c))
                        }
                    }
                }
            }
        }
    }
}

/// Vékony talajcsík a háttér aljára (pl. a Beállítások hegye alatt).
struct McGroundStrip: View {
    var body: some View {
        McGrassBlockFooter(height: 48)
    }
}

// MARK: - Pixel-panel

/// Minecraft-GUI körvonal: egyenes élek, a sarkok `steps` darab
/// pixellépcsővel letörve (a játék ablakai és gombjai így néznek ki).
struct McPixelShape: InsettableShape {
    var unit: CGFloat = 3
    var steps: Int = 2
    var inset: CGFloat = 0

    func inset(by amount: CGFloat) -> McPixelShape {
        var s = self; s.inset += amount; return s
    }

    func path(in rect: CGRect) -> Path {
        let r = rect.insetBy(dx: inset, dy: inset)
        let s = unit, n = max(0, min(steps, Int(min(r.width, r.height) / (2 * s))))
        var p = Path()
        guard r.width > 0, r.height > 0 else { return p }
        var x = r.maxX - CGFloat(n) * s, y = r.minY
        p.move(to: CGPoint(x: r.minX + CGFloat(n) * s, y: r.minY))
        p.addLine(to: CGPoint(x: x, y: y))
        for _ in 0..<n { y += s; p.addLine(to: CGPoint(x: x, y: y)); x += s; p.addLine(to: CGPoint(x: x, y: y)) }
        x = r.maxX; y = r.maxY - CGFloat(n) * s
        p.addLine(to: CGPoint(x: x, y: y))
        for _ in 0..<n { x -= s; p.addLine(to: CGPoint(x: x, y: y)); y += s; p.addLine(to: CGPoint(x: x, y: y)) }
        x = r.minX + CGFloat(n) * s; y = r.maxY
        p.addLine(to: CGPoint(x: x, y: y))
        for _ in 0..<n { y -= s; p.addLine(to: CGPoint(x: x, y: y)); x -= s; p.addLine(to: CGPoint(x: x, y: y)) }
        x = r.minX; y = r.minY + CGFloat(n) * s
        p.addLine(to: CGPoint(x: x, y: y))
        for _ in 0..<n { x += s; p.addLine(to: CGPoint(x: x, y: y)); y -= s; p.addLine(to: CGPoint(x: x, y: y)) }
        p.closeSubpath()
        return p
    }
}

/// Pixel-blokk háttér: sötét körvonal lépcsős sarkokkal, 1 px fényél
/// felül-balra, 1 px árnyékél alul-jobbra, alatta kemény 1 px vetett
/// árnyék. Minden él 3 pt-os rácson — nincs lekerekítés sehol.
struct McBlockPanel: View {
    var face: Color
    var outline: Color? = nil
    var highlight: Color? = nil
    var shade: Color? = nil
    var castsShadow = true
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let u = McSoil.unit
        let dark = scheme == .dark
        let line: Color = outline ?? (dark ? Color.black : Color(hex: 0x3A2A1C) as Color)
        let hi = highlight ?? .white.opacity(dark ? 0.10 : 0.65)
        let lo = shade ?? .black.opacity(dark ? 0.35 : 0.13)
        Canvas { ctx, size in
            let rect = CGRect(origin: .zero, size: size)
            ctx.fill(McPixelShape(unit: u, steps: 2).path(in: rect), with: .color(line))
            let inner = rect.insetBy(dx: u, dy: u)
            // A körvonal belsejét előbb kivágjuk, hogy az áttetsző face
            // ne a sötét körvonalon keresztül látsszon.
            ctx.blendMode = .clear
            ctx.fill(McPixelShape(unit: u, steps: 1).path(in: inner), with: .color(.black))
            ctx.blendMode = .normal
            ctx.fill(McPixelShape(unit: u, steps: 1).path(in: inner), with: .color(face))
            guard inner.width > 2 * u, inner.height > 2 * u else { return }
            ctx.fill(Path(CGRect(x: inner.minX + u, y: inner.minY, width: inner.width - 2 * u, height: u)), with: .color(hi))
            ctx.fill(Path(CGRect(x: inner.minX, y: inner.minY + u, width: u, height: inner.height - 2 * u)), with: .color(hi))
            ctx.fill(Path(CGRect(x: inner.minX + u, y: inner.maxY - u, width: inner.width - 2 * u, height: u)), with: .color(lo))
            ctx.fill(Path(CGRect(x: inner.maxX - u, y: inner.minY + u, width: u, height: inner.height - 2 * u)), with: .color(lo))
        }
        .background {
            if castsShadow {
                McPixelShape(unit: u, steps: 2).fill(Color.black.opacity(dark ? 0.45 : 0.22)).offset(y: u)
            }
        }
    }
}

/// Lista-sor háttere pixel-panelként. A sor-hátteret a rendszer a
/// szekció lekerekített sarkára vágja — a panel ezért annyira be van
/// húzva, hogy a vágás sosem érje el a lépcsős sarkot.
extension MinecraftTheme {
    /// Áttetsző állapot-szín (pl. narancs 8%) opak panel-archoz: a panel
    /// alap-színére keverve — a játék paneljein nem látszik át az ég.
    static func opaqueFace(_ color: Color) -> Color {
        let ui = UIColor(color)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        guard ui.getRed(&r, green: &g, blue: &b, alpha: &a), a < 0.99 else { return color }
        let dark = UITraitCollection.current.userInterfaceStyle == .dark
        let base = UIColor(dark ? Color(hex: 0x2B2B30) : Color(hex: 0xF7F0DC))
        var br: CGFloat = 0, bg: CGFloat = 0, bb: CGFloat = 0, ba: CGFloat = 0
        base.getRed(&br, green: &bg, blue: &bb, alpha: &ba)
        return Color(red: Double(br + (r - br) * a), green: Double(bg + (g - bg) * a), blue: Double(bb + (b - bb) * a))
    }

    /// Sor-margó skin-érzékenyen: Minecraftban a `McRowPanel` behúzásával
    /// (+ a körvonal és a bevel két pixelével) bővítve, hogy a szöveg ne
    /// a kereten üljön. Summitban az eredeti érték (nil = rendszer-alap).
    static func rowInsets(_ base: EdgeInsets?) -> EdgeInsets? {
        guard isActive else { return base }
        let b = base ?? EdgeInsets(top: 11, leading: 16, bottom: 11, trailing: 16)
        let h = McRowPanel.horizontalInset, v = McSoil.unit
        return EdgeInsets(top: b.top + v, leading: b.leading + h, bottom: b.bottom + v + McSoil.unit, trailing: b.trailing + h)
    }
}

struct McRowPanel: View {
    var face: Color
    /// A szekció-vágás sugara iOS 26/27 insetGrouped listán ~30 pt (mérve).
    /// Egy (x, y) pont akkor marad ki a vágásból, ha (R−x)² + (R−y)² ≤ R²;
    /// a lépcsős sarok legkülső pontjaira (6,0), (3,3), (0,6) ez 9 pt
    /// oldalt és 6 pt függőleges behúzással teljesül, R = 31-ig.
    /// Alul +3 pt a vetett árnyéknak.
    static let horizontalInset: CGFloat = 9
    static let verticalInset: CGFloat = 6
    var body: some View {
        McBlockPanel(face: MinecraftTheme.opaqueFace(face))
            .padding(.horizontal, Self.horizontalInset)
            .padding(.top, Self.verticalInset)
            .padding(.bottom, Self.verticalInset + McSoil.unit)
    }
}

/// Üres inventory-slot (a játék szürke rekesze, fordított bevellel:
/// sötét felül-balra, világos alul-jobbra) — jegy nélküli tárgyhoz.
struct McInventorySlot: View {
    var body: some View {
        McBlockPanel(face: Color(hex: 0x8B8B8B), outline: Color(hex: 0x373737),
                     highlight: .black.opacity(0.28), shade: .white.opacity(0.55), castsShadow: false)
    }
}

/// Kártya-háttér skin-érzékenyen: Minecraftban pixel-panel, Summitban
/// a gyári lekerekített felület hajszálvonallal.
struct McCardBackground: View {
    var fill: Color
    var cornerRadius: CGFloat = 12
    var body: some View {
        if MinecraftTheme.isActive {
            McBlockPanel(face: fill)
        } else {
            RoundedRectangle(cornerRadius: cornerRadius)
                .fill(fill)
                .overlay(RoundedRectangle(cornerRadius: cornerRadius).strokeBorder(Color.primary.opacity(0.06), lineWidth: 1))
        }
    }
}

/// Igazi Minecraft-dialógus panel (Java-kiadás beállításmenü-hangulat):
/// sötét módban mélypala, világosban klasszikus világosszürke (#C6C6C6),
/// bal-felső fényéllel és jobb-alsó árnyékéllel + körvonal + kemény árnyék.
/// A tartalom színei mindkét módban olvashatók maradnak.
struct McPanelStyle: ViewModifier {
    @Environment(\.colorScheme) var scheme
    var radius: CGFloat = 6
    func body(content: Content) -> some View {
        content
            .background(McBlockPanel(face: panel))
    }
    private var panel: Color {
        scheme == .dark ? Color(hex: 0x2E2E33) : Color(hex: 0xC6C6C6)
    }
}
