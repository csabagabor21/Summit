import SwiftUI
import CoreText

/// Monocraft (Idrees Hassan, SIL OFL 1.1) pixelbetű regisztrálása a
/// bundle-ből — Info.plist-módosítás nélkül (a projekt generált
/// plistet használ, oda tömb kulcs nem tehető INFOPLIST_KEY-jel).
enum VoxelFontLoader {
    static let familyName = "Monocraft"
    private static var done = false
    /// Sikerült-e a regisztráció (a betű ténylegesen elérhető-e).
    private static var available = false
    /// Lusta regisztráció: Summit skinben sosem fut le (indításkor csak a
    /// mentett Voxel-skin kéri), skinváltáskor az első pixelbetű-kérés
    /// intézi. Többször hívható.
    static func registerOnce() {
        guard !done else { return }
        done = true
        guard let url = Bundle.main.url(forResource: "Monocraft", withExtension: "ttf") else { return }
        CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
        available = UIFont(name: familyName, size: 12) != nil
    }
    /// Pixelbetű, ha regisztrálva van — különben rendszer-monospace
    /// (pl. preview, widget, vagy hiányzó erőforrás esetén). Az elérhetőség
    /// egyszer dől el — a régi kód minden hívásnál UIFont-ot példányosított.
    static func font(size: CGFloat) -> Font {
        registerOnce()
        if available {
            return .custom(familyName, size: size)
        }
        return .system(size: size, weight: .heavy, design: .monospaced)
    }
}

/// Voxel skin: modern (1.20+ Trails & Tales / Tricky Trials) íz,
/// nem a fakó alfa-stílus. Shader-inspiráció (BSL, Complementary,
/// Sildur's Vibrant): telített fűzöld, meleg napfény-arany, türkiz
/// gyémánt-akcentus, puha mélység-árnyék, god-ray-szerű fényátmenet.
/// Minden szín / mérőszám egy helyen, hogy a nézetek ne szórjanak
/// magic-number blokk-stílust.
enum VoxelTheme {
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
    static let nightTop: Color = Color(hex: 0x02030A)   // vanilla éjjeli ég: majdnem fekete
    static let nightBottom: Color = Color(hex: 0x0E1322) // horizont-köd éjjel

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
            text: dark ? VoxelTheme.cream : Color(hex: 0x2B2118),
            textSecondary: (dark ? VoxelTheme.cream : Color(hex: 0x2B2118)).opacity(0.68),
            textTertiary: (dark ? VoxelTheme.cream : Color(hex: 0x2B2118)).opacity(0.42),
            accent: dark ? VoxelTheme.grass : VoxelTheme.grassDeep,
            accentSoft: (dark ? VoxelTheme.grass : VoxelTheme.grassDeep).opacity(0.16),
            border: VoxelTheme.dirtDark.opacity(dark ? 0.7 : 0.4),
            shadow: Color.black.opacity(0.45),
            red: base.red, orange: base.orange, yellow: base.yellow,
            green: base.green, teal: base.teal, blue: base.blue,
            purple: base.purple, pink: base.pink,
            gradeFive: VoxelTheme.emerald,
            gradeFour: Color(hex: 0x7ED321),
            gradeThree: VoxelTheme.gold,
            gradeTwo: VoxelTheme.orange,
            gradeOne: VoxelTheme.redstone,
            loginPrimary: dark ? VoxelTheme.cream : Color(hex: 0x2B2118),
            loginSecondary: (dark ? VoxelTheme.cream : Color(hex: 0x2B2118)).opacity(0.62),
            loginBackground: dark ? Color(hex: 0x121214) : Color(hex: 0xE8E0C8)
        )
    }

@ViewBuilder
static func skinRowBackground(_ color: Color) -> some View {
    if isActive {
        VoxelRowPanel(face: color)
    } else if NeonTheme.isActive {
        NeonRowBackground(fill: color)
    } else {
        color
    }
}

    /// Tab-sorrendhez EREDETI item-sprite-ok a saját 1.21.11-es
    /// telepítésből (grass_block oldala, gyémánt, óra, könyv, barrier,
    /// iránytű). - Returns: (cím, bundle-képnév).
    static func tabItemIcon(for tab: Int) -> (String, String) {
        switch tab {
        case 0: return ("Főoldal", "img_blk_grass_side")
        case 1: return ("Jegyek", "img_blk_item_diamond")
        case 2: return ("Órarend", "img_blk_item_clock")
        case 5: return ("Feladatok", "img_blk_item_writable_book")
        case 4: return ("Hiányzások", "img_blk_item_barrier")
        case 3: return ("Watch", "img_blk_item_compass")
        default: return ("", "img_blk_grass_side")
        }
    }

    /// Eredeti 16x16-os textúra éles, nearest-neighbor nagyítással.
    /// Direkt fájlbetöltéssel (a laza bundle-PNG-ket a sima Image(név)
    /// nem találja meg megbízhatóan).
    static func voxelPixelImage(_ name: String, size: CGFloat) -> some View {
        Group {
            if let ui = VoxelTheme.sprite(name) {
                Image(uiImage: ui)
                    .resizable()
                    .interpolation(.none)
            } else {
                Color.clear
            }
        }
        .frame(width: size, height: size)
    }

    /// Tab-sorrendhez Voxel-ízű SF-ikonok (minden tab kap blokkos ikont).
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
        VoxelFontLoader.font(size: size)
    }
    static func bodyFont(size: CGFloat) -> Font {
        VoxelFontLoader.font(size: size)
    }

    /// Aktív-e a Voxel-skin (UserDefaults-olvasás — Environment-függés
    /// nélkül, hogy bármely nézetben használható legyen).
    static var isActive: Bool {
        VisualSkin.fromStored(UserDefaults.standard.string(forKey: "ui.skin")) == .voxel
    }

    /// Nav-sáv + tab-sáv pixelbetűi (UIKit-appearance — a SwiftUI nem ad
    /// ezekre modifierszintű betűállítást).
    static func applyChromeAppearance(voxel: Bool) {
        let nav = UINavigationBar.appearance()
        let tabItem = UITabBarItem.appearance()
        if voxel {
            // Futás közbeni skinváltáskor a betű még nem feltétlen él.
            VoxelFontLoader.registerOnce()
            let big = UIFont(name: VoxelFontLoader.familyName, size: 32)
            let small = UIFont(name: VoxelFontLoader.familyName, size: 16)
            let tiny = UIFont(name: VoxelFontLoader.familyName, size: 10)
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
            // Visszaállás a rendszer-alapra (csak ha volt Voxel-appearance).
            if chromeOverridden {
                nav.standardAppearance = UINavigationBarAppearance()
                nav.compactAppearance = UINavigationBarAppearance()
                nav.scrollEdgeAppearance = nil
            }
        }
        chromeOverridden = voxel
    }

    private static var chromeOverridden = false
}

// MARK: - Blokkos felület-modifierek

extension View {
    /// Voxel-kártya: igazi MC-dialógus panel (VoxelPanelStyle) —
    /// világos bal-felső bevel + sötét jobb-alsó él + körvonal + kemény
    /// mélység-árnyék. Reduce Transparency mellett is opak (az a jó).
    func voxelCard(cornerRadius: CGFloat = 6) -> some View {
        self.modifier(VoxelPanelStyle(radius: cornerRadius))
    }

    /// Voxel-nyomógomb: fűzöld blokk, bevel-lel, kemény árnyékkal.
    @ViewBuilder
    func voxelButton(tint: Color = VoxelTheme.grass) -> some View {
        self
            .font(VoxelTheme.bodyFont(size: 15))
            .foregroundStyle(.white)
            .shadow(color: .black.opacity(0.6), radius: 0, x: 2, y: 2)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(VoxelBlockPanel(face: tint, outline: Color(hex: 0x1F2A12), highlight: .white.opacity(0.35), shade: .black.opacity(0.28)))
    }

    /// Voxel-fejlécszöveg: pixel-ritmus + enyhe blokk-árnyék.
    func voxelHeader(size: CGFloat = 17) -> some View {
        self
            .font(VoxelTheme.headerFont(size: size))
            .tracking(0.5)
            .shadow(color: .black.opacity(0.35), radius: 0, x: 1, y: 2)
    }

    /// Szekció-fejléc: Summitban a gyári caption-uppercase, Voxelben
    /// pixelbetű + blokk-árnyék. Közvetlenül a régi lánc helyére tehető.
    /// (Egy típusú lánc: a skin az értékekben ágazik, lásd `skinFont`.)
    func voxelSectionHeader() -> some View {
        let mc = VoxelTheme.isActive
        let cp = NeonTheme.isActive
        // Neon: nagybetűs, ritkított, HUD-vörös Rajdhani (a belső
        // foregroundStyle nyer a `skinSecondaryOnSky` külső stílusa felett).
        return self
            .font(mc ? VoxelTheme.headerFont(size: 12)
                  : cp ? NeonTheme.font(.subheadline, weight: .bold) : .caption.weight(.semibold))
            .tracking(mc ? 0.5 : cp ? 1.6 : 0)
            .textCase(mc ? nil : .uppercase)
            .foregroundStyle(cp ? AnyShapeStyle(NeonTheme.red) : mc ? AnyShapeStyle(Color.white) : AnyShapeStyle(.secondary))
            .skinSecondaryOnSky()
    }

    /// Cím-szöveg (üdvözlés): Summitban gyári title2, Voxelben
    /// nagy pixelbetű blokk-árnyékkal.
    func voxelTitle() -> some View {
        let mc = VoxelTheme.isActive
        return self
            .font(mc ? VoxelTheme.headerFont(size: 26)
                  : NeonTheme.isActive ? NeonTheme.font(.title, weight: .bold) : .title2.weight(.bold))
            .foregroundStyle(.primary)
            .shadow(color: mc ? .black.opacity(0.45) : .clear, radius: 0, x: 2, y: 2)
    }

    /// Kijelző-számok (átlagok, hero-számok): Summitban rounded,
    /// Voxelben pixelbetű blokk-árnyékkal.
    func voxelDisplay(_ size: CGFloat) -> some View {
        let mc = VoxelTheme.isActive
        return self
            .font(mc ? VoxelTheme.headerFont(size: size)
                  : NeonTheme.isActive ? NeonTheme.display(size: (size * 1.1).rounded(), weight: .bold)
                  : .system(size: size, weight: .bold, design: .rounded))
            .shadow(color: mc ? .black.opacity(0.45) : .clear, radius: 0, x: 2, y: 2)
    }
}

/// Élő Voxel-égbolt (shader-hangulat, BSL/Complementary-íz):
/// a nap reggeltől estig valós idő szerint vándorol át az égen
/// (éjjel a játék holdja a valós holdfázissal + csillagok), az ég színe
/// napszak szerint vált (hajnal-narancs, dél-türkiz, alkony-lila, éjjel
/// vanilla-fekete), a lapos blokk-felhők lassan sodródnak, alul fűsáv +
/// opcionális pixel-hegy. Sötét módban egész nap éjszaka van, 1:1 a játék
/// éjjeli ege. `mountain: true` a Beállítások
/// mögé hegyet is tesz.
struct VoxelBackdrop: View {
    @Environment(\.accessibilityReduceMotion) var reduceMotion
    @Environment(\.accessibilityReduceTransparency) var reduceTransparency
    /// Sötét módban mindig éjszaka van (vanilla éjjeli ég, valós holdfázis).
    @Environment(\.colorScheme) var scheme
    var scrollOffset: CGFloat = 0
    var mountain: Bool = false
    /// Alsó fűsáv: a lista-hátterekben kikapcsoljuk, mert ott a
    /// tab-sáv fűblokkja adja a földet (különben dupla fűréteg lenne).
    var ground: Bool = true
    var body: some View {
        if reduceTransparency {
            VoxelTheme.nightTop.ignoresSafeArea()
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
            let forcedNight = scheme == .dark
            let night = forcedNight || hour < 5.5 || hour >= 20.5
            let shift = min(0, max(-h * 0.2, scrollOffset * 0.25))
            ZStack {
                LinearGradient(colors: forcedNight ? [VoxelTheme.nightTop, VoxelTheme.nightBottom] : skyColors(hour: hour),
                               startPoint: .top, endPoint: .bottom)
                    .ignoresSafeArea()
                // God-ray: ferde fénysáv nappal (BSL-hangulat), nagyon halvány.
                if !night {
                    LinearGradient(colors: [.white.opacity(0.20), .clear],
                                   startPoint: .topLeading, endPoint: .bottomTrailing)
                        .ignoresSafeArea()
                }
                // Éjjel csillagok a hold és a felhők mögött (a játékban is
                // az ég-kupolán ülnek, mindennél hátrébb).
                if night {
                    VoxelStarField(shift: shift * 0.4)
                }
                // Nap nappal (reggel keleten alacsonyan → délben magasan →
                // este nyugaton alacsonyan), éjjel a játék holdja a valós
                // holdfázissal.
                if night {
                    VoxelMoon(phase: VoxelTheme.moonPhase(at: date))
                        .position(x: w * moonX(hour: hour), y: 150 + shift)
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
                // Rendes voxel-felhők: lapos fehér blokk-lapok, lassan sodródnak.
                VoxelCloudLayer(width: w, night: night, animated: !reduceMotion)
                // Pixel-hegy (Beállítások): hátsó párás csúcs + elülső
                // hósapkás csúcs, tövében fűsávval.
                if mountain {
                    voxelMountainRange(width: w, baseY: h - 46 + shift * 0.3)
                        .colorMultiply(VoxelTheme.lightTint(VoxelTheme.daylight(at: date, scheme: scheme)))
                }
                // Fűsáv alul igazi textúrából (lista-háttérben kikapcsolva
                // — ott a tab-blokk a föld).
                if ground {
                    VStack(spacing: 0) {
                        Spacer()
                        VoxelGroundStrip()
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
            (0, VoxelTheme.nightTop, VoxelTheme.nightBottom),
            (4.5, VoxelTheme.nightTop, VoxelTheme.nightBottom),
            (6.5, Color(hex: 0x5A7BD6), Color(hex: 0xF2A65A)),
            (8.5, VoxelTheme.skyTop, VoxelTheme.skyBottom),
            (16, VoxelTheme.skyTop, VoxelTheme.skyBottom),
            (18.5, Color(hex: 0x3B3F7A), Color(hex: 0xFF7E47)),
            (20.5, VoxelTheme.nightTop, VoxelTheme.nightBottom),
            (24, VoxelTheme.nightTop, VoxelTheme.nightBottom),
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
        return [VoxelTheme.skyTop, VoxelTheme.skyBottom]
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
            : VoxelTheme.sun
        return (x, y, tint)
    }

    /// Hold-pozíció: este keleten kel (18h), hajnalban nyugaton nyugszik
    /// (6h). Sötét módban nappal az ív közepén áll (ott nincs valós pálya).
    private func moonX(hour: Double) -> CGFloat {
        let t: Double
        if hour >= 18 { t = (hour - 18) / 12 }
        else if hour < 6 { t = (hour + 6) / 12 }
        else { t = 0.5 }
        return 0.66 + 0.18 * t
    }


    // MARK: - Pixel-hegy

    /// Lépcsőzött pixel-hegy: soronként szélesedő téglalapok, jobb oldalon
    /// árnyék-sávval, tetején hósipkával.
    private func voxelPeak(baseWidth: CGFloat, height: CGFloat, rock: Color, shade: Color, snow: Color) -> some View {
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
    private func voxelMountainRange(width: CGFloat, baseY: CGFloat) -> some View {
        ZStack(alignment: .bottom) {
            HStack(alignment: .bottom, spacing: -40) {
                voxelPeak(baseWidth: width * 0.55, height: 190,
                       rock: Color(hex: 0x6E7B8C), shade: Color(hex: 0x525C69), snow: Color(hex: 0xDDE6F2))
                    .opacity(0.85)
                voxelPeak(baseWidth: width * 0.7, height: 260,
                       rock: Color(hex: 0x7D8A99), shade: Color(hex: 0x5A6572), snow: .white)
            }
            Rectangle().fill(VoxelTheme.grassDeep).frame(height: 10)
        }
        .frame(width: width, height: 270, alignment: .bottom)
        .position(x: width / 2, y: baseY - 135 + 23)
    }
}

/// Sodródó felhők: három sáv lapos blokk-lap (igazi voxel-felhő: egy
/// réteg éles téglalap), végtelen lineáris sodrással balról jobbra.
/// Egyetlen Canvas egy alacsony (15 fps) idővonalon — eddig felhőnként
/// külön, örökké futó SwiftUI-animáció pörgött (hat égbolt-példánnyal
/// akár 18 egyszerre, képkockánként a főszálon). A sodrás 1-2 pt/mp, így
/// 15 fps mellett is folyamatos. Reduce Motion mellett és háttérben áll.
private struct VoxelCloudLayer: View {
    var width: CGFloat
    var night: Bool
    var animated: Bool
    @Environment(\.scenePhase) private var scenePhase

    /// (függőleges középvonal, egy kör ideje mp-ben, kezdő fázis 0…1).
    private static let lanes: [(top: CGFloat, duration: Double, phase: Double)] = [
        (110, 140, 0.10), (210, 200, 0.55), (300, 260, 0.30)
    ]
    /// Egy felhő blokkjai: (szélesség, magasság, függőleges eltolás) balról jobbra.
    private static let blocks: [(w: CGFloat, h: CGFloat, dy: CGFloat)] = [
        (120, 14, 0), (44, 24, -5), (84, 14, 0), (30, 20, -3), (96, 14, 0)
    ]
    private static let cloudWidth: CGFloat = blocks.reduce(0) { $0 + $1.w }

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 15, paused: !animated || scenePhase != .active)) { tl in
            let t = tl.date.timeIntervalSinceReferenceDate
            Canvas { ctx, _ in
                // Éjjel a vanilla felhő is szinte az ég színére sötétül.
                let tint: Color = night ? Color(hex: 0x161A26).opacity(0.85) : .white.opacity(0.9)
                let travel = width + 440
                for lane in Self.lanes {
                    // Reduce Motion: középen áll (mint eddig).
                    let cx: CGFloat = animated
                        ? -220 + travel * CGFloat((t / lane.duration + lane.phase).truncatingRemainder(dividingBy: 1))
                        : width / 2
                    var x = cx - Self.cloudWidth / 2
                    var path = Path()
                    for b in Self.blocks {
                        path.addRect(CGRect(x: x, y: lane.top - b.h / 2 + b.dy, width: b.w, height: b.h))
                        x += b.w
                    }
                    ctx.fill(path, with: .color(tint))
                }
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}


extension View {
/// Lista-sor háttér skin-érzékenyen: Summitban a kapott szín simán,
/// Voxelben lekerekített blokk dirt-kerettel + bevel-lel.
/// Teljes sor-stílus: blokk-háttér + rejtett elválasztó + blokk-távolság.
/// Summitban nem csinál semmit (marad a gyári sor).
@ViewBuilder
func voxelListRow(fill: Color) -> some View {
    if VoxelTheme.isActive || NeonTheme.isActive {
        self.listRowBackground(VoxelTheme.skinRowBackground(fill))
            .listRowSeparator(.hidden)
            .listRowInsets(VoxelTheme.rowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16)))
    } else {
        self
    }
}

/// Vékony kártya-körvonal skin-érzékenyen: Summitban hajszálvékony,
/// Voxelben dirt-blokk keret + bevel. Meglévő fill mellé tehető.
@ViewBuilder
func voxelHairlineBorder(cornerRadius: CGFloat = 12) -> some View {
    if VoxelTheme.isActive || NeonTheme.isActive {
        let cp = NeonTheme.isActive
        self.clipShape(cp ? AnyShape(NeonChamferShape(cut: 10)) : AnyShape(VoxelPixelShape(steps: 2)))
            .overlay {
                if cp {
                    NeonChamferShape(cut: 10).strokeBorder(NeonTheme.red.opacity(0.55), lineWidth: 1)
                } else {
                    VoxelBlockPanel(face: .clear, castsShadow: false)
                }
            }
    } else {
        self.overlay(RoundedRectangle(cornerRadius: cornerRadius).strokeBorder(Color.primary.opacity(0.06), lineWidth: 1))
    }
}

}

// MARK: - Talaj

/// Determinisztikus pixel-zaj: ugyanaz a (x, y, mag) mindig ugyanazt adja,
/// így a föld és a növények nem keverednek újra minden rajzolásnál.
private enum VoxelNoise {
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

extension VoxelTheme {
    /// Napfény 0…1 a valós idő szerint (ugyanazok a sarokpontok, mint az
    /// égbolté): éjjel 0, hajnalban/alkonykor átúszik, nappal 1. Sötét
    /// módban mindig éjszaka van.
    static func daylight(at date: Date, scheme: ColorScheme) -> Double {
        if scheme == .dark { return 0 }
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

    /// Világítás-szorzó (a játék lightmapje): nappal fehér (nincs hatás),
    /// éjjel sötét, kékes égfény — a talajra, fűre, hegyre egyformán.
    static func lightTint(_ light: Double) -> Color {
        let k = 1 - min(1, max(0, light))
        return Color(red: 1 - 0.68 * k, green: 1 - 0.66 * k, blue: 1 - 0.52 * k)
    }

    /// A játék nyolc holdfázisa a sajátja sorrendjében (0 = újhold,
    /// 4 = telihold), a hozzájuk tartozó 1.21.11-es textúrával.
    static let moonSprites: [String] = [
        "img_blk_env_moon_new_moon", "img_blk_env_moon_waxing_crescent", "img_blk_env_moon_first_quarter",
        "img_blk_env_moon_waxing_gibbous", "img_blk_env_moon", "img_blk_env_moon_waning_gibbous",
        "img_blk_env_moon_third_quarter", "img_blk_env_moon_waning_crescent",
    ]

    /// Valós holdfázis 0…7-re kerekítve: az égen ugyanaz a hold látszik,
    /// ami kint. Referencia-újhold 2000-01-06 18:14 UTC, szinodikus hónap
    /// 29,530588853 nap (a hiba pár óra, a 8 fokozathoz bőven elég).
    static func moonPhase(at date: Date) -> Int {
        let synodic = 29.530588853
        let reference = Date(timeIntervalSince1970: 947_182_440)
        let days = date.timeIntervalSince(reference) / 86_400
        let age = (days.truncatingRemainder(dividingBy: synodic) + synodic).truncatingRemainder(dividingBy: synodic)
        return Int((age / synodic * 8).rounded()) % 8
    }
}

/// A játék holdja: a 32×32-es textúra (a 8×8-as korong + derengés) 6 pt-os
/// pixelekkel, additív keveréssel — a fekete háttere így eltűnik, a
/// derengés az égre világít, pont ahogy a játék rajzolja.
struct VoxelMoon: View {
    var phase: Int

    var body: some View {
        VoxelTheme.voxelPixelImage(VoxelTheme.moonSprites[(phase % 8 + 8) % 8], size: 32 * 6)
            .blendMode(.plusLighter)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

/// Éjjeli csillagmező: apró, eltérő fényerejű négyzetek fix (seedelt)
/// helyen, nem villognak — a vanilla csillagai sem. Egy Canvasban, hogy
/// a sok pont ne legyen sok nézet.
struct VoxelStarField: View {
    var shift: CGFloat = 0

    var body: some View {
        Canvas { ctx, size in
            // Sűrűség területarányosan: kb. egy csillag 3000 pt²-enként a
            // felső 70 %-ban (lent a horizont-köd elnyeli őket).
            let band = size.height * 0.7
            let count = Int(size.width * band / 3000)
            for i in 0..<count {
                let x = VoxelNoise.unit(i, 1, 101) * size.width
                let y = VoxelNoise.unit(i, 2, 103) * band + shift
                let s: CGFloat = VoxelNoise.hash(i, 3, 107) % 4 == 0 ? 3 : 2
                let fade = 1 - y / max(1, band)
                let a = (0.35 + VoxelNoise.unit(i, 4, 109) * 0.45) * (0.4 + 0.6 * fade)
                ctx.fill(Path(CGRect(x: x.rounded(), y: y.rounded(), width: s, height: s)),
                         with: .color(.white.opacity(a)))
            }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// Saját rajzolású fűblokk-talaj (nincs benne Mojang-textúra): 3 pt-os
/// pixelrácson seedelt földzaj, csöpögő fűperem, kavicsok, lefelé
/// sötétedő mélység, a tetején szélben ringó fű és virágok. A fény a
/// napszakot követi, mint az égbolt; sötét módban éjszaka van. A home-jelző alá is lenyúlik.
struct VoxelGrassBlockFooter: View {
    var height: CGFloat = 148
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        TimelineView(.everyMinute) { tl in
            let light = VoxelTheme.daylight(at: tl.date, scheme: scheme)
            VoxelSoil()
                .overlay(alignment: .top) {
                    VoxelFlora(animated: !reduceMotion)
                        .frame(height: VoxelFlora.maxHeight)
                        .offset(y: -VoxelFlora.maxHeight + VoxelSoil.unit)
                        .allowsHitTesting(false)
                }
                // Szorzás, nem rátett réteg: a talaj fölé lógó fű és
                // virágok is ugyanúgy sötétülnek, az ég nem.
                .colorMultiply(VoxelTheme.lightTint(light))
        }
        // Előbb a safe area elengedése, utána a fix magasság: így a föld a
        // keret alján túl, a home-jelző alá is lenyúlik (fordítva a fix
        // keret középre tenné, és alul kilátszana a lista).
        .ignoresSafeArea(.container, edges: .bottom)
        .frame(height: height)
        .accessibilityHidden(true)
    }
}

/// Föld + fűperem, egyetlen Canvasban (raszterizálva, nem rajzol újra
/// görgetéskor).
struct VoxelSoil: View {
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
                    let n = VoxelNoise.unit(x, y, 7)
                    let w = VoxelNoise.hash(x, y, 3) % 3 == 0 ? 2 : 1
                    if n < 0.07 { px(x, y, Self.speckDark, w: w) }
                    else if n < 0.12 { px(x, y, Self.speckLight, w: 1) }
                    else if n < 0.40 { px(x, y, Self.dirt[1 + VoxelNoise.hash(x, y, 11) % 3], w: w) }
                    x += w
                }
            }
            // Kavicsok: ritka 2–3 px-es kőcsomók a mélyebb rétegben.
            var gx = 4 + VoxelNoise.hash(1, 1, 5) % 14
            while gx < cols - 3 {
                let gy = 9 + VoxelNoise.hash(gx, 0, 9) % max(1, rows - 12)
                px(gx, gy, Self.pebble[0], w: 2)
                px(gx + 1, gy - 1, Self.pebble[2])
                px(gx, gy + 1, Self.pebble[1], w: 3)
                gx += 22 + VoxelNoise.hash(gx, 1, 13) % 30
            }
            // Fűperem: 3 sor tömör fű + oszloponként 0–3 px "csöpögés",
            // szomszédokhoz simítva (így ível, nem fésű).
            for x in 0..<cols {
                let a = VoxelNoise.hash(x, 0, 21) % 4, b = VoxelNoise.hash(x + 1, 0, 21) % 4
                let drip = 3 + (a + b + 1) / 2
                for y in 0..<drip {
                    px(x, y, Self.grass[VoxelNoise.hash(x, y, 31) % 3])
                }
                // Árnyék-sor a fű alatt: mélységet ad a peremnek.
                px(x, drip, Self.speckDark.opacity(0.55))
                if VoxelNoise.hash(x, 0, 41) % 3 != 0 { px(x, 0, Self.grassLip) }
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
struct VoxelFlora: View {
    static let maxHeight: CGFloat = 8 * VoxelSoil.unit
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
        var x = 2 + VoxelNoise.hash(0, 9, 3) % 5
        var i = 0
        while x < cols - 7 {
            let r = VoxelNoise.hash(i, 0, 77) % 100
            let sprite = r < 38 ? 0 : r < 62 ? 1 : 2 + (VoxelNoise.hash(i, 1, 79) % 4)
            out.append((x, sprite, VoxelNoise.unit(i, 2, 81) * .pi * 2))
            x += 5 + VoxelNoise.hash(i, 3, 83) % 13
            i += 1
        }
        return out
    }

    @Environment(\.scenePhase) private var scenePhase

    /// A szél egész pixelre lépő eltolásai (növényenként, soronként) egy
    /// időpontban. A rajzolás csak akkor fut újra, ha ezek közül valamelyik
    /// tényleg elmozdult — eddig 12 fps-sel minden képkocka újrarajzolt
    /// mindent, akkor is, ha egyetlen pixel sem mozdult.
    private static func offsets(at t: Double, count: Int) -> [Int8] {
        var out: [Int8] = []
        out.reserveCapacity(count * 8)
        for (i, p) in layoutCache(count: count).enumerated() where i < count {
            let h = sprites[p.sprite].rows.count
            // Lassú alaphullám + apró rezgés: 0…1 px kitérés a csúcson.
            let wave = sin(t * 1.3 + p.phase) * 0.8 + sin(t * 3.1 + p.phase * 1.7) * 0.25
            for ry in 0..<h {
                let lift = Double(h - ry) / Double(h)
                out.append(Int8((wave * lift * 1.6).rounded()))
            }
        }
        return out
    }

    /// Elrendezés oszlopszámonként egyszer (eddig képkockánként újra). Szálbiztos.
    private static let layoutLock = NSLock()
    nonisolated(unsafe) private static var layoutMemo: [Int: [(x: Int, sprite: Int, phase: Double)]] = [:]
    private static func layoutCache(count cols: Int) -> [(x: Int, sprite: Int, phase: Double)] {
        layoutLock.lock(); defer { layoutLock.unlock() }
        if let hit = layoutMemo[cols] { return hit }
        let l = layout(cols: cols)
        layoutMemo[cols] = l
        return l
    }

    var body: some View {
        GeometryReader { geo in
            let cols = Int(geo.size.width / VoxelSoil.unit)
            TimelineView(.animation(minimumInterval: 1.0 / 12, paused: !animated || scenePhase != .active)) { tl in
                let t = animated ? tl.date.timeIntervalSinceReferenceDate : 0
                FloraCanvas(cols: cols, offsets: Self.offsets(at: t, count: cols))
                    .equatable()
            }
        }
    }

    /// A tényleges rajzolás: színenként EGY összevont útvonal (eddig
    /// pixelenként külön fill, képkockánként több száz).
    private struct FloraCanvas: View, Equatable {
        let cols: Int
        let offsets: [Int8]

        var body: some View {
            Canvas { ctx, size in
                let u = VoxelSoil.unit
                var paths: [Color: Path] = [:]
                var k = 0
                for p in VoxelFlora.layoutCache(count: cols) {
                    let sp = VoxelFlora.sprites[p.sprite]
                    let h = sp.rows.count
                    for (ry, row) in sp.rows.enumerated() {
                        let dx = k < offsets.count ? Int(offsets[k]) : 0
                        k += 1
                        for (rx, ch) in row.enumerated() {
                            guard let c = sp.palette[ch] else { continue }
                            let x = CGFloat(p.x + rx + dx) * u
                            let y = size.height - CGFloat(h - ry) * u
                            paths[c, default: Path()].addRect(CGRect(x: x, y: y, width: u, height: u))
                        }
                    }
                }
                for (c, path) in paths { ctx.fill(path, with: .color(c)) }
            }
        }
    }
}

/// Vékony talajcsík a háttér aljára (pl. a Beállítások hegye alatt).
struct VoxelGroundStrip: View {
    var body: some View {
        VoxelGrassBlockFooter(height: 48)
    }
}

// MARK: - Pixel-panel

/// Voxel-GUI körvonal: egyenes élek, a sarkok `steps` darab
/// pixellépcsővel letörve (a játék ablakai és gombjai így néznek ki).
struct VoxelPixelShape: InsettableShape {
    var unit: CGFloat = 3
    var steps: Int = 2
    var inset: CGFloat = 0

    func inset(by amount: CGFloat) -> VoxelPixelShape {
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
struct VoxelBlockPanel: View {
    var face: Color
    var outline: Color? = nil
    var highlight: Color? = nil
    var shade: Color? = nil
    var castsShadow = true
    /// Biztosan opak a face (pl. `opaqueFace`-ből): ilyenkor a körvonal
    /// belsejének kivágása (`.clear` keverés — külön rétegpassz) fölösleges,
    /// a face úgyis teljesen takar. A kép azonos.
    var faceIsOpaque = false
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let u = VoxelSoil.unit
        let dark = scheme == .dark
        let line: Color = outline ?? (dark ? Color.black : Color(hex: 0x3A2A1C) as Color)
        let hi = highlight ?? .white.opacity(dark ? 0.10 : 0.65)
        let lo = shade ?? .black.opacity(dark ? 0.35 : 0.13)
        let opaque = faceIsOpaque
        Canvas { ctx, size in
            let rect = CGRect(origin: .zero, size: size)
            ctx.fill(VoxelPixelShape(unit: u, steps: 2).path(in: rect), with: .color(line))
            let inner = rect.insetBy(dx: u, dy: u)
            // A körvonal belsejét előbb kivágjuk, hogy az áttetsző face
            // ne a sötét körvonalon keresztül látsszon.
            if !opaque {
                ctx.blendMode = .clear
                ctx.fill(VoxelPixelShape(unit: u, steps: 1).path(in: inner), with: .color(.black))
                ctx.blendMode = .normal
            }
            ctx.fill(VoxelPixelShape(unit: u, steps: 1).path(in: inner), with: .color(face))
            guard inner.width > 2 * u, inner.height > 2 * u else { return }
            ctx.fill(Path(CGRect(x: inner.minX + u, y: inner.minY, width: inner.width - 2 * u, height: u)), with: .color(hi))
            ctx.fill(Path(CGRect(x: inner.minX, y: inner.minY + u, width: u, height: inner.height - 2 * u)), with: .color(hi))
            ctx.fill(Path(CGRect(x: inner.minX + u, y: inner.maxY - u, width: inner.width - 2 * u, height: u)), with: .color(lo))
            ctx.fill(Path(CGRect(x: inner.maxX - u, y: inner.minY + u, width: u, height: inner.height - 2 * u)), with: .color(lo))
        }
        .background {
            if castsShadow {
                VoxelPixelShape(unit: u, steps: 2).fill(Color.black.opacity(dark ? 0.45 : 0.22)).offset(y: u)
            }
        }
    }
}

/// Lista-sor háttere pixel-panelként. A sor-hátteret a rendszer a
/// szekció lekerekített sarkára vágja — a panel ezért annyira be van
/// húzva, hogy a vágás sosem érje el a lépcsős sarkot.
extension VoxelTheme {
    /// Áttetsző állapot-szín (pl. narancs 8%) opak panel-archoz: a panel
    /// alap-színére keverve — a játék paneljein nem látszik át az ég.
    /// Memó (szín + sötét mód → kevert szín): a sorok minden body-jában
    /// hívódik, a UIColor-felbontás és -keverés így színenként egyszer fut.
    /// Szálbiztos.
    private static let opaqueFaceLock = NSLock()
    nonisolated(unsafe) private static var opaqueFaceMemo: [OpaqueFaceKey: (color: Color, opaque: Bool)] = [:]
    private struct OpaqueFaceKey: Hashable { let color: Color; let dark: Bool }

    static func opaqueFace(_ color: Color) -> Color { resolvedOpaqueFace(color).color }

    /// A kevert szín + hogy biztosan opak-e (a színfelbontás sikerült).
    static func resolvedOpaqueFace(_ color: Color) -> (color: Color, opaque: Bool) {
        let dark = UITraitCollection.current.userInterfaceStyle == .dark
        let key = OpaqueFaceKey(color: color, dark: dark)
        opaqueFaceLock.lock(); defer { opaqueFaceLock.unlock() }
        if let hit = opaqueFaceMemo[key] { return hit }
        let out = blendOntoPanel(color, dark: dark)
        if opaqueFaceMemo.count > 256 { opaqueFaceMemo.removeAll() }
        opaqueFaceMemo[key] = out
        return out
    }

    private static func blendOntoPanel(_ color: Color, dark: Bool) -> (color: Color, opaque: Bool) {
        let ui = UIColor(color)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        guard ui.getRed(&r, green: &g, blue: &b, alpha: &a) else { return (color, false) }
        guard a < 0.99 else { return (color, true) }
        let base = UIColor(dark ? Color(hex: 0x2B2B30) : Color(hex: 0xF7F0DC))
        var br: CGFloat = 0, bg: CGFloat = 0, bb: CGFloat = 0, ba: CGFloat = 0
        base.getRed(&br, green: &bg, blue: &bb, alpha: &ba)
        return (Color(red: Double(br + (r - br) * a), green: Double(bg + (g - bg) * a), blue: Double(bb + (b - bb) * a)), true)
    }

    /// Sor-margó skin-érzékenyen: Voxelben a `VoxelRowPanel` behúzásával
    /// (+ a körvonal és a bevel két pixelével) bővítve, hogy a szöveg ne
    /// a kereten üljön. Summitban az eredeti érték (nil = rendszer-alap).
    static func rowInsets(_ base: EdgeInsets?) -> EdgeInsets? {
        if NeonTheme.isActive { return NeonTheme.rowInsets(base) }
        guard isActive else { return base }
        let b = base ?? EdgeInsets(top: 11, leading: 16, bottom: 11, trailing: 16)
        let h = VoxelRowPanel.horizontalInset, v = VoxelSoil.unit
        return EdgeInsets(top: b.top + v, leading: b.leading + h, bottom: b.bottom + v + VoxelSoil.unit, trailing: b.trailing + h)
    }
}

struct VoxelRowPanel: View {
    var face: Color
    /// A szekció-vágás sugara iOS 26/27 insetGrouped listán ~30 pt (mérve).
    /// Egy (x, y) pont akkor marad ki a vágásból, ha (R−x)² + (R−y)² ≤ R²;
    /// a lépcsős sarok legkülső pontjaira (6,0), (3,3), (0,6) ez 9 pt
    /// oldalt és 6 pt függőleges behúzással teljesül, R = 31-ig.
    /// Alul +3 pt a vetett árnyéknak.
    static let horizontalInset: CGFloat = 9
    static let verticalInset: CGFloat = 6
    var body: some View {
        let resolved = VoxelTheme.resolvedOpaqueFace(face)
        VoxelBlockPanel(face: resolved.color, faceIsOpaque: resolved.opaque)
            .padding(.horizontal, Self.horizontalInset)
            .padding(.top, Self.verticalInset)
            .padding(.bottom, Self.verticalInset + VoxelSoil.unit)
    }
}

/// Üres inventory-slot (a játék szürke rekesze, fordított bevellel:
/// sötét felül-balra, világos alul-jobbra) — jegy nélküli tárgyhoz.
struct VoxelInventorySlot: View {
    var body: some View {
        VoxelBlockPanel(face: Color(hex: 0x8B8B8B), outline: Color(hex: 0x373737),
                     highlight: .black.opacity(0.28), shade: .white.opacity(0.55), castsShadow: false)
    }
}

/// Kártya-háttér skin-érzékenyen: Voxelben pixel-panel, Summitban
/// a gyári lekerekített felület hajszálvonallal.
struct VoxelCardBackground: View {
    var fill: Color
    var cornerRadius: CGFloat = 12
    var body: some View {
        if VoxelTheme.isActive {
            VoxelBlockPanel(face: fill)
        } else if NeonTheme.isActive {
            // A kapott (akár áttetsző állapot-) szín az opak panel-alapon.
            ZStack {
                NeonChamferShape(cut: 12, corners: .diagonal).fill(NeonTheme.panel)
                NeonPanelBackground(fill: fill)
            }
        } else {
            RoundedRectangle(cornerRadius: cornerRadius)
                .fill(fill)
                .overlay(RoundedRectangle(cornerRadius: cornerRadius).strokeBorder(Color.primary.opacity(0.06), lineWidth: 1))
        }
    }
}

/// Igazi Voxel-dialógus panel (Java-kiadás beállításmenü-hangulat):
/// sötét módban mélypala, világosban klasszikus világosszürke (#C6C6C6),
/// bal-felső fényéllel és jobb-alsó árnyékéllel + körvonal + kemény árnyék.
/// A tartalom színei mindkét módban olvashatók maradnak.
struct VoxelPanelStyle: ViewModifier {
    @Environment(\.colorScheme) var scheme
    var radius: CGFloat = 6
    func body(content: Content) -> some View {
        content
            .background {
                // Neonban ugyanez a modifier HUD-panelt ad (a
                // `summitGlassRow` és a `voxelCard` így egy típusú marad).
                if NeonTheme.isActive {
                    NeonPanelBackground()
                } else {
                    VoxelBlockPanel(face: panel)
                }
            }
    }
    private var panel: Color {
        scheme == .dark ? Color(hex: 0x2E2E33) : Color(hex: 0xC6C6C6)
    }
}
