import SwiftUI
import UIKit

// Közös Minecraft-építőkockák: igazi 1.21.11-es GUI-sprite-ok (gomb,
// checkbox, csúszka, XP-sáv, menü-háttér) és az SF-ikonok item-megfelelői.
// Minden helper skin-érzékeny: Summitban a gyári (Liquid Glass) ág fut
// változatlanul, Minecraftban a pixeles. A sprite-ok az asset catalog
// `Minecraft/` mappájában élnek (felvétel: scripts/mc-sprite.sh).

// MARK: - Sprite-betöltés

extension MinecraftTheme {
    /// Egy pixel a GUI-ban ennyi pont (a játék GUI-scale 3-as beállítása).
    static let px: CGFloat = 3

    private static let spriteCache = NSCache<NSString, UIImage>()

    /// Sprite az asset catalogból, régi laza bundle-PNG tartalékkal.
    static func sprite(_ name: String) -> UIImage? {
        if let hit = spriteCache.object(forKey: name as NSString) { return hit }
        let img = UIImage(named: name)
            ?? Bundle.main.path(forResource: name, ofType: "png").flatMap(UIImage.init(contentsOfFile:))
        if let img { spriteCache.setObject(img, forKey: name as NSString) }
        return img
    }

    /// Kilenc-szeletes GUI-sprite (gomb, csúszka, fül): a sarkok és élek
    /// `px`-szeres pixelméretben maradnak, csak a közép nyúlik — pont úgy,
    /// ahogy a játék a `nine_slice` mcmeta alapján rajzolja.
    static func nineSlice(_ name: String, border: (top: CGFloat, left: CGFloat, bottom: CGFloat, right: CGFloat)) -> UIImage? {
        let key = "\(name)#9" as NSString
        if let hit = spriteCache.object(forKey: key) { return hit }
        guard let base = sprite(name), let cg = base.cgImage else { return nil }
        // 1/px skála: a kép pontmérete px-szerese a pixelméretnek.
        let scaled = UIImage(cgImage: cg, scale: 1 / px, orientation: .up)
        let insets = UIEdgeInsets(top: border.top * px, left: border.left * px,
                                  bottom: border.bottom * px, right: border.right * px)
        let out = scaled.resizableImage(withCapInsets: insets, resizingMode: .stretch)
        spriteCache.setObject(out, forKey: key)
        return out
    }
}

/// Egy sprite éles, nearest-neighbor nagyítással.
struct McSprite: View {
    var name: String
    var size: CGFloat
    var body: some View {
        if let ui = MinecraftTheme.sprite(name) {
            Image(uiImage: ui)
                .resizable()
                .interpolation(.none)
                .aspectRatio(contentMode: .fit)
                .frame(width: size, height: size)
        } else {
            Color.clear.frame(width: size, height: size)
        }
    }
}

/// Kilenc-szeletes sprite háttérnek.
struct McNineSlice: View {
    var name: String
    var border: (top: CGFloat, left: CGFloat, bottom: CGFloat, right: CGFloat)
    init(_ name: String, border: CGFloat) {
        self.name = name
        self.border = (border, border, border, border)
    }
    init(_ name: String, top: CGFloat, left: CGFloat, bottom: CGFloat, right: CGFloat) {
        self.name = name
        self.border = (top, left, bottom, right)
    }
    var body: some View {
        if let ui = MinecraftTheme.nineSlice(name, border: border) {
            Image(uiImage: ui).resizable(capInsets: EdgeInsets(top: border.top * MinecraftTheme.px,
                                                               leading: border.left * MinecraftTheme.px,
                                                               bottom: border.bottom * MinecraftTheme.px,
                                                               trailing: border.right * MinecraftTheme.px),
                                         resizingMode: .stretch)
                .interpolation(.none)
        }
    }
}

// MARK: - Pixel-glifek (ahol a játékban nincs item-megfelelő)

/// Kis pixel-glifek az előtér-színnel rajzolva (chevron, plusz, pipa…).
/// A játék GUI-nyilai/pluszai is ilyen 1 px vonalas rajzok.
struct McGlyph: View {
    enum Kind: String {
        case chevronRight, chevronLeft, chevronUp, chevronDown
        case plus, minus, xmark, check, arrowRight, share, download, question, warning
    }
    var kind: Kind
    var size: CGFloat

    private var rows: [String] {
        switch kind {
        case .chevronRight: return ["#....", "##...", ".##..", "..##.", ".##..", "##...", "#...."]
        case .chevronLeft: return ["....#", "...##", "..##.", ".##..", "..##.", "...##", "....#"]
        case .chevronDown: return ["#.....#", "##...##", ".##.##.", "..###..", "...#..."]
        case .chevronUp: return ["...#...", "..###..", ".##.##.", "##...##", "#.....#"]
        case .plus: return ["..##..", "..##..", "######", "######", "..##..", "..##.."]
        case .minus: return ["......", "......", "######", "######", "......", "......"]
        case .xmark: return ["##...##", ".##.##.", "..###..", "..###..", ".##.##.", "##...##"]
        case .check: return [".......#", "......##", "#....##.", "##..##..", ".####...", "..##...."]
        case .arrowRight: return ["....#..", "....##.", "#######", "#######", "....##.", "....#.."]
        case .share: return ["...#...", "..###..", ".#.#.#.", "...#...", "#..#..#", "#.....#", "#######"]
        case .download: return ["...#...", "...#...", ".#.#.#.", "..###..", "#..#..#", "#.....#", "#######"]
        case .question: return [".####.", "##..##", "....##", "...##.", "..##..", "......", "..##.."]
        case .warning: return ["...#...", "..###..", "..#.#..", ".##.##.", ".#####.", "##.#.##", "#######"]
        }
    }

    var body: some View {
        let grid = rows
        let cols = grid.map(\.count).max() ?? 1
        let cell = floor(size / CGFloat(max(cols, grid.count)))
        Canvas { ctx, canvas in
            let ox = (canvas.width - cell * CGFloat(cols)) / 2
            let oy = (canvas.height - cell * CGFloat(grid.count)) / 2
            var path = Path()
            for (y, row) in grid.enumerated() {
                for (x, ch) in row.enumerated() where ch == "#" {
                    path.addRect(CGRect(x: ox + CGFloat(x) * cell, y: oy + CGFloat(y) * cell, width: cell, height: cell))
                }
            }
            ctx.fill(path, with: .foreground)
        }
        .frame(width: size, height: size)
    }
}

// MARK: - SF-ikon → Minecraft-megfelelő

extension MinecraftTheme {
    enum IconArt {
        case sprite(String)
        case glyph(McGlyph.Kind)
    }

    /// SF Symbol → igazi item/blokk-textúra vagy pixel-glif. Ami nincs a
    /// listán, az Minecraftban is SF-ikon marad (ezért minden új
    /// ikonnál ide kell egy sor).
    static func iconArt(for systemName: String) -> IconArt? {
        switch systemName {
        case "chevron.right": return .glyph(.chevronRight)
        case "chevron.left": return .glyph(.chevronLeft)
        case "chevron.down": return .glyph(.chevronDown)
        case "chevron.up": return .glyph(.chevronUp)
        case "plus", "plus.circle", "plus.circle.fill": return .glyph(.plus)
        case "minus", "minus.circle", "minus.circle.fill": return .glyph(.minus)
        case "xmark", "xmark.circle", "xmark.circle.fill": return .sprite("mc_widget_cross")
        case "checkmark": return .sprite("mc_icon_checkmark")
        case "checkmark.circle.fill", "checkmark.square.fill": return .sprite("mc_widget_checkbox_on")
        case "circle", "square": return .sprite("mc_widget_checkbox")
        case "arrow.right", "arrow.right.circle.fill", "forward.fill": return .glyph(.arrowRight)
        case "square.and.arrow.up": return .glyph(.share)
        case "square.and.arrow.down": return .glyph(.download)
        case "questionmark.circle", "questionmark": return .glyph(.question)
        case "exclamationmark.triangle.fill", "exclamationmark.triangle": return .sprite("mc_block_tnt")
        case "info.circle", "info.circle.fill": return .sprite("mc_icon_info")
        case "magnifyingglass": return .sprite("mc_icon_search")
        case "link": return .sprite("mc_icon_link")
        case "wifi.exclamationmark", "wifi.slash": return .sprite("mc_icon_unreachable")
        case "checklist", "pencil.and.list.clipboard", "note.text", "square.and.pencil", "pencil":
            return .sprite("mc_item_writable_book")
        case "doc.text", "doc.text.fill", "doc.fill", "doc": return .sprite("mc_item_paper")
        case "envelope", "envelope.fill", "bubble.left.fill", "bubble.left": return .sprite("mc_item_book")
        case "books.vertical", "books.vertical.fill", "book", "book.fill": return .sprite("mc_block_bookshelf")
        case "trash", "trash.fill": return .sprite("mc_item_lava_bucket")
        case "person.fill", "person.crop.circle", "person.crop.circle.fill", "person": return .sprite("mc_head_steve")
        case "person.2.fill", "person.2": return .sprite("mc_head_alex")
        case "person.fill.xmark", "star.slash", "nosign": return .sprite("mc_item_barrier")
        case "calendar", "calendar.badge.exclamationmark", "calendar.badge.clock", "calendar.badge.plus":
            return .sprite("mc_item_map")
        case "clock", "clock.fill", "clock.badge.checkmark", "timer": return .sprite("mc_item_clock")
        case "applewatch", "location.north.fill", "safari": return .sprite("mc_item_compass")
        case "sparkles", "star.fill", "star": return .sprite("mc_item_nether_star")
        case "wand.and.stars": return .sprite("mc_item_blaze_rod")
        case "bell.fill", "bell", "bell.badge.fill": return .sprite("mc_item_bell")
        case "paperclip": return .sprite("mc_item_string")
        case "hammer.fill", "hammer", "wrench.and.screwdriver.fill": return .sprite("mc_item_iron_pickaxe")
        case "slider.horizontal.3", "slider.horizontal.below.rounded", "gearshape", "gearshape.fill":
            return .sprite("mc_item_comparator")
        case "megaphone", "megaphone.fill": return .sprite("mc_item_goat_horn")
        case "livephoto", "eye", "eye.fill": return .sprite("mc_item_ender_eye")
        case "arrow.triangle.2.circlepath", "arrow.clockwise", "icloud", "icloud.fill": return .sprite("mc_item_ender_pearl")
        case "key.fill", "key", "lock.fill", "lock": return .sprite("mc_item_trial_key")
        case "flask.fill", "flask": return .sprite("mc_item_brewing_stand")
        case "cup.and.saucer.fill": return .sprite("mc_item_mushroom_stew")
        case "checkmark.shield.fill", "shield", "shield.fill": return .sprite("mc_item_totem")
        case "chart.line.flattrend.xyaxis", "chart.line.downtrend.xyaxis", "chart.line.uptrend.xyaxis",
             "chart.bar.fill", "chart.xyaxis.line": return .sprite("mc_item_spyglass")
        case "camera.fill", "photo.fill", "photo": return .sprite("mc_item_painting")
        case "airplane": return .sprite("mc_item_elytra")
        case "sun.max.fill", "sun.max": return .sprite("mc_env_sun")
        case "moon.zzz.fill", "moon.fill", "moon": return .sprite("mc_env_moon")
        case "stethoscope", "cross.case.fill", "heart.fill": return .sprite("mc_hud_heart")
        case "mountain.2.fill": return .sprite("mc_block_snow")
        case "diamond.fill": return .sprite("mc_item_diamond")
        case "cube.fill": return .sprite("mc_grass_side")
        case "hourglass": return .sprite("mc_item_barrier")
        default: return nil
        }
    }
}

/// Skin-érzékeny ikon: Summitban SF Symbol, Minecraftban a hozzá rendelt
/// item-textúra / pixel-glif. Az `Image(systemName:)` közvetlen cseréje.
struct SkinIcon: View {
    var systemName: String
    /// Minecraft-sprite pontmérete; nil = a betűmérethez igazodó alap.
    var size: CGFloat?
    @ScaledMetric(relativeTo: .body) private var scaled: CGFloat = 20

    init(_ systemName: String, size: CGFloat? = nil) {
        self.systemName = systemName
        self.size = size
    }

    var body: some View {
        if MinecraftTheme.isActive, let art = MinecraftTheme.iconArt(for: systemName) {
            let s = size ?? scaled
            switch art {
            case .sprite(let name): McSprite(name: name, size: s)
            case .glyph(let kind): McGlyph(kind: kind, size: s * 0.8).frame(width: s, height: s)
            }
        } else {
            Image(systemName: systemName)
        }
    }
}

/// `Label(_, systemImage:)` skin-érzékeny párja.
struct SkinLabel: View {
    var title: String
    var systemImage: String
    init(_ title: String, systemImage: String) {
        self.title = title
        self.systemImage = systemImage
    }
    var body: some View {
        Label { Text(title) } icon: { SkinIcon(systemImage) }
    }
}

// MARK: - Betű

extension View {
    /// Skin-érzékeny szövegstílus: Summitban a gyári Dynamic Type stílus,
    /// Minecraftban Monocraft ugyanazzal a Dynamic Type skálázással.
    /// A `.font(.headline)` / `.font(.caption.weight(.semibold))` cseréje.
    @ViewBuilder
    func skinFont(_ style: Font.TextStyle, weight: Font.Weight? = nil, design: Font.Design? = nil) -> some View {
        if MinecraftTheme.isActive {
            self.font(MinecraftTheme.font(style))
        } else if let weight {
            self.font(.system(style, design: design, weight: weight))
        } else {
            self.font(.system(style, design: design))
        }
    }
}

extension MinecraftTheme {
    /// Monocraft a rendszer-stílus alapméretén, Dynamic Type-pal skálázva.
    /// A pixelbetű nagyobb x-magasságú, ezért ~10%-kal kisebbre vesszük.
    static func font(_ style: Font.TextStyle) -> Font {
        let base: CGFloat
        switch style {
        case .largeTitle: base = 30
        case .title: base = 25
        case .title2: base = 20
        case .title3: base = 18
        case .headline: base = 15
        case .body: base = 15
        case .callout: base = 14
        case .subheadline: base = 13
        case .footnote: base = 12
        case .caption: base = 11
        case .caption2: base = 10
        @unknown default: base = 15
        }
        guard UIFont(name: MinecraftFontLoader.familyName, size: base) != nil else {
            return .system(style, design: .monospaced).weight(.heavy)
        }
        return .custom(MinecraftFontLoader.familyName, size: base, relativeTo: style)
    }
}

// MARK: - Gomb

/// Igazi Java-kiadás gomb: `widget/button` kilenc-szeletes sprite,
/// lenyomva / fókuszban `button_highlighted` (fehér keret), tiltva
/// `button_disabled`. Szöveg fehér, kemény 1 px-es árnyékkal.
struct McButtonStyle: ButtonStyle {
    /// Kiemelt (fő) gomb: smaragdzöld szöveg — a játékban a kijelölt
    /// opciók sárgán/zölden világítanak, a gomb maga ugyanaz a kő-gomb.
    var prominent = false
    /// Kompakt (ikon / toolbar) gomb: négyzetes, kisebb belső margó.
    var compact = false
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        let sprite = !isEnabled ? "mc_widget_button_off"
            : configuration.isPressed ? "mc_widget_button_hi" : "mc_widget_button"
        configuration.label
            .font(MinecraftTheme.font(.body))
            .foregroundStyle(!isEnabled ? Color(hex: 0xA0A0A0) : prominent ? Color(hex: 0xFFFF55) : .white)
            .shadow(color: Color(hex: 0x3F3F3F), radius: 0, x: MinecraftTheme.px / 1.5, y: MinecraftTheme.px / 1.5)
            .padding(.horizontal, compact ? 8 : 16)
            .padding(.vertical, compact ? 6 : 10)
            .frame(minWidth: compact ? 36 : nil, minHeight: compact ? 36 : 44)
            .background(McNineSlice(sprite, border: 3))
            .contentShape(Rectangle())
    }
}

extension View {
    /// `.buttonStyle(.glass)` / `.glassProminent` skin-érzékeny cseréje.
    @ViewBuilder
    func skinGlassButton(prominent: Bool = false, compact: Bool = false) -> some View {
        if MinecraftTheme.isActive {
            self.buttonStyle(McButtonStyle(prominent: prominent, compact: compact))
        } else if prominent {
            self.buttonStyle(.glassProminent)
        } else {
            self.buttonStyle(.glass)
        }
    }

    /// `.buttonStyle(.borderedProminent)` / `.bordered` skin-érzékeny cseréje.
    @ViewBuilder
    func skinBorderedButton(prominent: Bool = false) -> some View {
        if MinecraftTheme.isActive {
            self.buttonStyle(McButtonStyle(prominent: prominent))
        } else if prominent {
            self.buttonStyle(.borderedProminent)
        } else {
            self.buttonStyle(.bordered)
        }
    }

    /// Toolbar-elem: Minecraftban a rendszer Liquid Glass-kapszulája
    /// helyett kő-gomb (a közös glass-háttér elrejtve).
    @ViewBuilder
    func skinToolbarItem() -> some View {
        if MinecraftTheme.isActive {
            self.buttonStyle(McButtonStyle(compact: true))
        } else {
            self
        }
    }
}

// MARK: - Kapcsoló

/// Java-kiadás checkbox: `widget/checkbox` / `checkbox_selected` sprite,
/// a felirat mellette. A teljes sor koppintható.
struct McCheckboxToggleStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        Button {
            configuration.isOn.toggle()
        } label: {
            HStack(spacing: 12) {
                configuration.label
                    .frame(maxWidth: .infinity, alignment: .leading)
                McSprite(name: configuration.isOn ? "mc_widget_checkbox_on" : "mc_widget_checkbox", size: 30)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityValue(configuration.isOn ? "Be" : "Ki")
        .accessibilityAddTraits(.isToggle)
    }
}

extension View {
    /// Skin-érzékeny kapcsoló-stílus: Summitban gyári switch.
    @ViewBuilder
    func skinToggleStyle() -> some View {
        if MinecraftTheme.isActive {
            self.toggleStyle(McCheckboxToggleStyle())
        } else {
            self
        }
    }
}

// MARK: - Csúszka-szerű kijelzők

/// XP-sáv: igazi `experience_bar_background` + `experience_bar_progress`,
/// a teljes szélességre nyújtva (1 px-es sarkok élesek maradnak).
struct McProgressBar: View {
    /// 0…1
    var value: Double
    var height: CGFloat = 5 * MinecraftTheme.px
    var body: some View {
        GeometryReader { geo in
            let v = min(1, max(0, value))
            ZStack(alignment: .leading) {
                McNineSlice("mc_hud_xp_bg", border: 1)
                McNineSlice("mc_hud_xp", border: 1)
                    .frame(width: max(0, geo.size.width * v))
                    .opacity(v > 0 ? 1 : 0)
            }
        }
        .frame(height: height)
        .accessibilityElement()
        .accessibilityValue("\(Int((min(1, max(0, value)) * 100).rounded())) százalék")
    }
}

// MARK: - Felületek

extension View {
    /// `.glassEffect(.regular…, in: shape)` skin-érzékeny cseréje:
    /// Minecraftban pixel-panel (`McBlockPanel`), Summitban valódi üveg.
    @ViewBuilder
    func skinGlass<S: Shape>(in shape: S, tint: Color? = nil, interactive: Bool = true, face: Color? = nil) -> some View {
        if MinecraftTheme.isActive {
            self.background(McBlockPanel(face: face ?? tint?.opacity(0.85) ?? MinecraftTheme.panelFace))
        } else {
            let base: Glass = tint.map { Glass.regular.tint($0) } ?? .regular
            self.glassEffect(interactive ? base.interactive() : base, in: shape)
        }
    }

    /// `.clipShape(RoundedRectangle/Capsule/Circle)` skin-érzékeny cseréje:
    /// Minecraftban lépcsős pixelsarok, sosem kerek.
    @ViewBuilder
    func skinClip<S: Shape>(_ shape: S) -> some View {
        if MinecraftTheme.isActive {
            self.clipShape(McPixelShape(steps: 1))
        } else {
            self.clipShape(shape)
        }
    }

    /// Teljes képernyős lap / sheet háttere: Minecraftban a játék menü-
    /// háttere (sötét föld-csempe), Summitban a rendszeré.
    @ViewBuilder
    func skinSheetBackground() -> some View {
        if MinecraftTheme.isActive {
            self.presentationBackground { McMenuBackground() }
        } else {
            self
        }
    }
}

extension MinecraftTheme {
    /// Alap panel-arc (a `McPanelStyle`-lal egyező szürke / pala).
    static var panelFace: Color {
        UITraitCollection.current.userInterfaceStyle == .dark ? Color(hex: 0x2E2E33) : Color(hex: 0xC6C6C6)
    }

    /// Skin-érzékeny alakzat a `RoundedRectangle(cornerRadius:)` helyére
    /// (fill/stroke/background-ban): Minecraftban lépcsős pixelsarok.
    static func shape(cornerRadius: CGFloat) -> AnyShape {
        isActive ? AnyShape(McPixelShape(steps: cornerRadius >= 12 ? 2 : 1))
                 : AnyShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }

    /// Skin-érzékeny kapszula / kör.
    static var capsule: AnyShape { isActive ? AnyShape(McPixelShape(steps: 1)) : AnyShape(Capsule()) }
    static var circle: AnyShape { isActive ? AnyShape(McPixelShape(steps: 2)) : AnyShape(Circle()) }
}

/// A játék menü-háttere: a `menu_background` csempe, 3x pixelekkel.
struct McMenuBackground: View {
    var body: some View {
        Group {
            if let ui = MinecraftTheme.sprite("mc_menu_background")?.cgImage {
                Image(decorative: ui, scale: 1 / MinecraftTheme.px)
                    .resizable(resizingMode: .tile)
                    .interpolation(.none)
            } else {
                MinecraftTheme.deepslate
            }
        }
        .background(Color(hex: 0x1A1209))
        .ignoresSafeArea()
    }
}

/// A játék fejléc/lábléc-elválasztója (2 px-es csík a listák szélén).
struct McSeparator: View {
    var footer = false
    var body: some View {
        Group {
            if let ui = MinecraftTheme.sprite(footer ? "mc_footer_separator" : "mc_header_separator")?.cgImage {
                Image(decorative: ui, scale: 1 / MinecraftTheme.px)
                    .resizable(resizingMode: .tile)
                    .interpolation(.none)
            }
        }
        .frame(height: 2 * MinecraftTheme.px)
        .accessibilityHidden(true)
    }
}

/// Java-kiadás szövegmező-keret: fekete belső, világosszürke 1 px-es
/// keret, fókuszban fehér.
struct McTextFieldFrame: ViewModifier {
    @FocusState private var focused: Bool
    func body(content: Content) -> some View {
        content
            .font(MinecraftTheme.font(.body))
            .foregroundStyle(Color(hex: 0xE0E0E0))
            .tint(Color(hex: 0xE0E0E0))
            .focused($focused)
            .padding(.horizontal, 10)
            .padding(.vertical, 9)
            .background(Color.black)
            .overlay(Rectangle().strokeBorder(focused ? Color.white : Color(hex: 0xA0A0A0), lineWidth: MinecraftTheme.px / 1.5))
    }
}
