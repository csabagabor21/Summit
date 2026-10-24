import SwiftUI
import UIKit
import AVFoundation

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
        case "sun.max.fill", "sun.max": return .sprite("mc_item_torch")
        case "moon.zzz.fill", "moon.fill", "moon": return .sprite("mc_item_clock")
        case "stethoscope", "cross.case.fill", "heart.fill": return .sprite("mc_hud_heart")
        case "mountain.2.fill": return .sprite("mc_block_snow")
        case "diamond.fill": return .sprite("mc_item_diamond")
        case "cube.fill": return .sprite("mc_grass_side")
        case "hourglass": return .sprite("mc_item_barrier")
        // Órarend: tantárgy-ikonok és részletező-sorok
        case "function": return .sprite("mc_item_redstone")
        case "building.columns.fill": return .sprite("mc_block_cobblestone")
        case "globe": return .sprite("mc_item_ender_pearl")
        case "atom": return .sprite("mc_item_experience_bottle")
        case "leaf.fill": return .sprite("mc_block_oak_sapling")
        case "map.fill": return .sprite("mc_item_map")
        case "laptopcomputer": return .sprite("mc_block_command_block")
        case "figure.run": return .sprite("mc_item_iron_boots")
        case "music.note": return .sprite("mc_block_note_block")
        case "paintbrush.fill": return .sprite("mc_item_painting")
        case "lightbulb.fill": return .sprite("mc_item_glow_ink_sac")
        case "book.closed.fill", "book.closed": return .sprite("mc_item_book")
        case "person.fill.badge.plus": return .sprite("mc_item_name_tag")
        case "door.left.hand.open": return .sprite("mc_item_oak_door")
        case "briefcase.fill", "briefcase": return .sprite("mc_block_crafting_table")
        case "iphone", "iphone.gen2": return .sprite("mc_item_repeater")
        case "app.badge.fill": return .sprite("mc_item_name_tag")
        case "person.slash.fill", "key.slash.fill", "location.slash.fill": return .sprite("mc_item_barrier")
        case "envelope.open", "doc.richtext.fill": return .sprite("mc_item_paper")
        case "tablecells.fill": return .sprite("mc_block_crafting_table")
        case "rectangle.on.rectangle.fill": return .sprite("mc_item_item_frame")
        case "archivebox.fill": return .sprite("mc_block_barrel")
        case "film.fill": return .sprite("mc_item_music_disc_13")
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
            // 8 pt-os rácsra kerekítve (min. 16): a 16 px-es textúra így
            // közel egész szorzóval nő, nem kenődnek el a pixelek.
            let s = max(16, ((size ?? scaled) / 8).rounded() * 8)
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
    /// Egyetlen `.font`-modifier (nem két ágú nézet): a skin-elágazás a
    /// betű ÉRTÉKÉBEN van, így a nézet típusa nem duplázódik — a sok
    /// egymásba ágyazott if/else-típustól a készüléken a Swift runtime
    /// stack-túlcsordulással elszállt (Beállítások megnyitásakor).
    func skinFont(_ style: Font.TextStyle, weight: Font.Weight? = nil, design: Font.Design? = nil) -> some View {
        self.font(MinecraftTheme.isActive ? MinecraftTheme.font(style)
                  : weight.map { Font.system(style, design: design, weight: $0) } ?? Font.system(style, design: design))
    }
}

extension View {
    /// `.font(.system(size:weight:design:))` skin-érzékeny cseréje:
    /// Minecraftban Monocraft (a számok is, a `.rounded` design helyett).
    func skinFont(size: CGFloat, weight: Font.Weight = .regular, design: Font.Design = .default) -> some View {
        self.font(MinecraftTheme.isActive ? MinecraftFontLoader.font(size: (size * 0.92).rounded())
                  : .system(size: size, weight: weight, design: design))
    }

    /// Mint a `skinFont(_:weight:)`, de a Summit-ág `monospacedDigit()`-et
    /// is kap (az óra-/szám-kiírásokhoz); a Monocraft eleve egyenközű.
    func skinFontDigits(_ style: Font.TextStyle, weight: Font.Weight? = nil) -> some View {
        self.font(MinecraftTheme.isActive ? MinecraftTheme.font(style)
                  : (weight.map { Font.system(style, weight: $0) } ?? Font.system(style)).monospacedDigit())
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
            // A játék a lenyomás pillanatában kattan, nem elengedéskor.
            .onChange(of: configuration.isPressed) { _, pressed in
                if pressed { McSound.play(.click) }
            }
    }
}

/// Minecraftban minden gomb kattan, nem csak a kő-gombok. Az app gyökerére
/// tett alapstílus: a saját stílus nélküli gombok (lista-sorok, toolbar,
/// lapok gombjai) a kontextusuk gyári `.automatic` megjelenését kapják, az
/// akció elé csak egy halk kattanás kerül. Summit-skinben a `McSound` néma,
/// így ott a gomb viselkedése a gyárival azonos.
struct McClickButtonStyle: PrimitiveButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        Button(role: configuration.role) {
            McSound.play(.click)
            configuration.trigger()
        } label: {
            configuration.label
        }
        .buttonStyle(.automatic)
    }
}

/// A `.plain` kattanó párja: ugyanaz a keret nélküli gomb, Minecraftban
/// halk kattanással (a gyökér-stílust a `.plain` felülírná, és néma lenne).
struct McPlainClickButtonStyle: PrimitiveButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        Button(role: configuration.role) {
            McSound.play(.click)
            configuration.trigger()
        } label: {
            configuration.label
        }
        .buttonStyle(.plain)
    }
}

extension PrimitiveButtonStyle where Self == McPlainClickButtonStyle {
    /// `.plain` + Minecraft-kattanás.
    static var skinPlain: McPlainClickButtonStyle { McPlainClickButtonStyle() }
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
            McSound.play(.pop)
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
    func skinToggleStyle() -> some View {
        self.toggleStyle(SkinToggleStyle())
    }
}

/// Egy típusú kapcsoló-stílus, az elágazás a stílus belsejében: Minecraftban
/// checkbox, Summitban a gyári (automatic) kapcsoló.
struct SkinToggleStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        if MinecraftTheme.isActive {
            McCheckboxToggleStyle().makeBody(configuration: configuration)
        } else {
            Toggle(configuration).toggleStyle(.automatic)
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
    /// `continuous: false` a sima (`.circular`) `RoundedRectangle` Summit-ága.
    static func shape(cornerRadius: CGFloat, continuous: Bool = true) -> AnyShape {
        isActive ? AnyShape(McPixelShape(steps: cornerRadius >= 12 ? 2 : 1))
                 : AnyShape(RoundedRectangle(cornerRadius: cornerRadius, style: continuous ? .continuous : .circular))
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

// MARK: - Hangok

/// Igazi Minecraft UI-hangok (a játék `.ogg`-jai AAC-ra konvertálva, az
/// asset catalog `Minecraft/` mappájában Data Setként). Csak Minecraft-
/// skinben szólal meg; `.ambient` munkamenet, így a némító kapcsoló
/// elnémítja, és sosem szakítja meg a zenét. Hangerő-/némítás-beállítás
/// az appban nincs, a rendszeré érvényes.
///
/// Hangerő-hierarchia: a sima gombok kattanása halk (`buttonVolume`), a
/// tabsáv/hotbar `tab`-kattanása a legerősebb — ez egy limiterrel feljebb
/// húzott külön asset, mert az eredeti klikk csúcsa már 0 dBFS, a lejátszó
/// hangereje 1 fölé nem mehet.
enum McSound: String, CaseIterable {
    case click = "mc_snd_click_stereo"
    case tab = "mc_snd_click_tab"
    case levelUp = "mc_snd_levelup"
    case orb = "mc_snd_orb"
    case pop = "mc_snd_pop"
    case toastIn = "mc_snd_toast_in"
    case challengeComplete = "mc_snd_challenge_complete"

    /// Hangonként kis lejátszó-készlet: gyors egymásutánban (tabváltás,
    /// sorozatos gombnyomás) a hangok átfedhetnek, nem vágják el egymást.
    private static var pool: [McSound: [AVAudioPlayer]] = [:]
    private static var sessionReady = false
    private static let poolSize = 3

    /// Sima gomb-kattanás hangereje (a tabsávhoz képest halk).
    static let buttonVolume: Float = 0.45

    /// Ugyanazon hang utolsó indítása: ha egy gomb a stílusából ÉS az
    /// akciójából is kattan (vagy a globális gombstílus és egy explicit hívás
    /// fut egyszerre), a második nem indít új lejátszást, csak a hangerőt
    /// emeli a nagyobbikra — egy koppintás = egy kattanás.
    private static var lastStart: [McSound: (at: CFTimeInterval, player: AVAudioPlayer)] = [:]
    private static let mergeWindow: CFTimeInterval = 0.09

    static func play(_ sound: McSound, volume: Float? = nil) {
        guard MinecraftTheme.isActive else { return }
        let volume = volume ?? (sound == .click ? buttonVolume : 1)
        let now = CACurrentMediaTime()
        if let last = lastStart[sound], now - last.at < mergeWindow, last.player.isPlaying {
            last.player.volume = max(last.player.volume, volume)
            return
        }
        guard prepareSession() else { return }
        var players = pool[sound] ?? []
        if players.count < poolSize, let fresh = makePlayer(sound) {
            players.append(fresh)
            pool[sound] = players
        }
        // Szabad lejátszó, különben a legrégebbit indítjuk újra.
        guard let player = players.first(where: { !$0.isPlaying }) ?? players.first else { return }
        player.volume = volume
        player.currentTime = 0
        player.play()
        lastStart[sound] = (now, player)
    }

    /// Előmelegítés (Minecraft-skin indulásakor / bekapcsolásakor): az
    /// audio-session és a gyakori hangok első lejátszója előre elkészül.
    /// Eddig az ELSŐ koppintás építette fel őket szinkron a főszálon — épp a
    /// push-animáció alatt, így az első megnyitás akadt („többször kell
    /// rányomni"). A következő futási körre ütemezve, nem az indítás útjában.
    static func warmUp() {
        guard MinecraftTheme.isActive else { return }
        DispatchQueue.main.async {
            guard MinecraftTheme.isActive, prepareSession() else { return }
            for sound in [McSound.click, .tab] where (pool[sound] ?? []).isEmpty {
                if let player = makePlayer(sound) { pool[sound] = [player] }
            }
        }
    }

    /// Hosszú hang (pl. a 5-ös jegy fanfárja) idő előtti leállítása.
    static func stop(_ sound: McSound) {
        pool[sound]?.forEach { $0.stop() }
    }

    private static func prepareSession() -> Bool {
        if sessionReady { return true }
        do {
            try AVAudioSession.sharedInstance().setCategory(.ambient, mode: .default, options: [])
            sessionReady = true
        } catch {
            #if DEBUG
            print("McSound: audio session hiba: \(error)")
            #endif
        }
        return sessionReady
    }

    private static func makePlayer(_ sound: McSound) -> AVAudioPlayer? {
        guard let asset = NSDataAsset(name: sound.rawValue) else {
            #if DEBUG
            print("McSound: hiányzó hang-asset: \(sound.rawValue)")
            #endif
            return nil
        }
        do {
            let player = try AVAudioPlayer(data: asset.data)
            player.prepareToPlay()
            return player
        } catch {
            #if DEBUG
            print("McSound: dekódolási hiba (\(sound.rawValue)): \(error)")
            #endif
            return nil
        }
    }
}

// MARK: - Szegmens-választó (fül-sor)

/// `Picker(.segmented)` skin-érzékeny cseréje: Summitban pontosan a gyári
/// szegmens-választó, Minecraftban a 1.21-es játék fül-sora (`widget/tab`,
/// a kijelölt fehér keretes `tab_selected` sprite-tal), kattanással.
struct SkinSegmentedPicker<Value: Hashable>: View {
    @Binding var selection: Value
    var options: [(value: Value, title: String)]
    var accessibilityTitle: String = ""

    var body: some View {
        if MinecraftTheme.isActive {
            HStack(spacing: 0) {
                ForEach(Array(options.enumerated()), id: \.offset) { _, option in
                    let isOn = option.value == selection
                    Button {
                        if !isOn { McSound.play(.click) }
                        selection = option.value
                    } label: {
                        Text(option.title)
                            .font(MinecraftTheme.font(.subheadline))
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                            .foregroundStyle(isOn ? Color.white : Color(hex: 0xA0A0A0))
                            .shadow(color: Color(hex: 0x3F3F3F), radius: 0, x: MinecraftTheme.px / 1.5, y: MinecraftTheme.px / 1.5)
                            .frame(maxWidth: .infinity, minHeight: 40)
                            // A tab-sprite-ok félig áttetszők (sötét játék-háttérre
                            // valók): opak alap kell alájuk, a kijelölt világosabb.
                            .background(McNineSlice(isOn ? "mc_widget_tab_sel" : "mc_widget_tab",
                                                    top: 2, left: 2, bottom: 0, right: 2))
                            .background(isOn ? Color(hex: 0x6B6B70) : Color(hex: 0x1E1E22))
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(isOn ? .isSelected : [])
                }
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel(accessibilityTitle)
        } else {
            Picker(accessibilityTitle, selection: $selection) {
                ForEach(Array(options.enumerated()), id: \.offset) { _, option in
                    Text(option.title).tag(option.value)
                }
            }
            .pickerStyle(.segmented)
        }
    }
}

// MARK: - Folyamatjelző

/// `ProgressView(value:).tint(_)` skin-érzékeny cseréje: Minecraftban az
/// igazi XP-sáv, Summitban a gyári lineáris folyamatjelző.
struct SkinProgressBar: View {
    var value: Double
    var tint: Color
    var body: some View {
        if MinecraftTheme.isActive {
            McProgressBar(value: value)
        } else {
            ProgressView(value: value).tint(tint)
        }
    }
}

// MARK: - Toolbar

extension ToolbarContent {
    /// A rendszer Liquid Glass kapszulája a toolbar-elem mögött Minecraftban
    /// rejtve (a gombot `skinToolbarItem()` stílusozza), Summitban marad.
    func skinToolbarBackground() -> some ToolbarContent {
        self.sharedBackgroundVisibility(MinecraftTheme.isActive ? .hidden : .automatic)
    }
}

// MARK: - Advancement-toast

/// A játék „Advancement Made!" értesítése: `toast/advancement` kilenc-
/// szeletes sprite, balra az item-ikon, mellette sárga cím és fehér
/// szöveg 1 px-es szürke árnyékkal. Challenge-nél lila cím (#FF55FF).
struct McAdvancementToast: View {
    var icon: String
    var title: String
    var message: String
    var challenge = false

    var body: some View {
        HStack(spacing: 4 * MinecraftTheme.px) {
            McSprite(name: icon, size: 16 * MinecraftTheme.px)
            VStack(alignment: .leading, spacing: MinecraftTheme.px) {
                Text(title)
                    .font(MinecraftTheme.font(.subheadline))
                    .foregroundStyle(challenge ? Color(hex: 0xFF55FF) : Color(hex: 0xFFFF00))
                    .shadow(color: Color(hex: 0x3F3F3F), radius: 0, x: MinecraftTheme.px / 1.5, y: MinecraftTheme.px / 1.5)
                Text(message)
                    .font(MinecraftTheme.font(.footnote))
                    .foregroundStyle(.white)
                    .shadow(color: Color(hex: 0x3F3F3F), radius: 0, x: MinecraftTheme.px / 1.5, y: MinecraftTheme.px / 1.5)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 8 * MinecraftTheme.px)
        .padding(.vertical, 8 * MinecraftTheme.px)
        .background(McNineSlice("mc_toast_advancement", top: 2, left: 2, bottom: 0, right: 2))
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Üres állapot / űrlap-szekció

/// `Section("Cím") { … }` skin-érzékeny párja űrlapokhoz: Minecraftban
/// pixelbetűs fejléc és blokk-sor háttér (`fill`), Summitban a gyári
/// szöveges fejlécű szekció.
struct SkinFormSection<Content: View>: View {
    var title: String
    var fill: Color
    @ViewBuilder var content: () -> Content
    var body: some View {
        if MinecraftTheme.isActive {
            Section {
                content().mcListRow(fill: fill)
            } header: {
                Text(title).mcSectionHeader()
            }
        } else {
            Section(title) { content() }
        }
    }
}

extension View {
    /// Űrlap/lista saját háttere Minecraftban rejtve (a sheet menü-háttere
    /// látszik át); Summitban nem változtat semmin.
    @ViewBuilder
    func skinFormBackground() -> some View {
        if MinecraftTheme.isActive {
            self.scrollContentBackground(.hidden)
        } else {
            self
        }
    }
}

// MARK: - Betű (méret-alapú, egyenközű számjegyekkel)

extension View {
    /// `.font(.system(size:weight:design:).monospacedDigit())` skin-érzékeny
    /// cseréje: Minecraftban Monocraft (az eleve egyenközű).
    func skinFontDigits(size: CGFloat, weight: Font.Weight = .regular, design: Font.Design = .default) -> some View {
        self.font(MinecraftTheme.isActive ? MinecraftFontLoader.font(size: (size * 0.92).rounded())
                  : .system(size: size, weight: weight, design: design).monospacedDigit())
    }
}

// MARK: - Navigációs sor, alapbetű, kis gomb

/// `NavigationLink` listasorban: Summitban pontosan a gyári link (rendszer-
/// chevronnal), Minecraftban rejtett link + saját pixel-chevron — a
/// rendszer-szimbólum helyett. A teljes sor koppintható marad.
struct McNavLink<Destination: View, Label: View>: View {
    @ViewBuilder var destination: () -> Destination
    @ViewBuilder var label: () -> Label

    var body: some View {
        if MinecraftTheme.isActive {
            HStack(spacing: 8) {
                label().frame(maxWidth: .infinity, alignment: .leading)
                McGlyph(kind: .chevronRight, size: 16).foregroundStyle(.secondary)
            }
            .overlay { NavigationLink { destination().mcBackButton().mcPushClick() } label: { EmptyView() }.opacity(0) }
        } else {
            NavigationLink(destination: destination, label: label)
        }
    }
}

/// Push-olt nézet első megjelenésekor egy halk klikk. Visszatéréskor (egy
/// mélyebb nézetről visszalépve) nem szól újra: az állapot a push idejére él.
/// Summit-skinben a `McSound` néma.
struct McPushClickModifier: ViewModifier {
    @State private var played = false

    func body(content: Content) -> some View {
        content.onAppear {
            guard !played else { return }
            played = true
            McSound.play(.click)
        }
    }
}

/// Érték-alapú párja (`NavigationLink(value:)`). A klikket a hívó
/// `navigationDestination`-je adja (`mcPushClick()`).
struct McNavValueLink<Value: Hashable, Label: View>: View {
    var value: Value
    @ViewBuilder var label: () -> Label

    var body: some View {
        if MinecraftTheme.isActive {
            HStack(spacing: 8) {
                label().frame(maxWidth: .infinity, alignment: .leading)
                McGlyph(kind: .chevronRight, size: 16).foregroundStyle(.secondary)
            }
            .overlay { NavigationLink(value: value) { EmptyView() }.opacity(0) }
        } else {
            NavigationLink(value: value, label: label)
        }
    }
}

extension View {
    /// Rejtett `NavigationLink`-es listasor kattanása. A lista a linket nem
    /// gombstílussal rajzolja, így a gyökér-stílus nem ér el hozzá — ezért a
    /// klikk a megnyitott CÉLnézetre kerül, nem a sorra: a sorra tett
    /// (akár egyidejű) TapGesture iOS 18+ alatt elnyeli a lista
    /// sor-kiválasztását, és a link meg sem nyílik.
    func mcPushClick() -> some View {
        modifier(McPushClickModifier())
    }

    /// Alap szövegstílus egy egész felületre (lista, lap): Minecraftban a
    /// stílus nélküli szövegek is Monocraft betűt kapnak; Summitban semmi.
    @ViewBuilder
    func mcDefaultFont(_ style: Font.TextStyle = .body) -> some View {
        if MinecraftTheme.isActive {
            self.font(MinecraftTheme.font(style))
        } else {
            self
        }
    }

    /// Soron belüli szöveges gomb: Summitban `.plain`, Minecraftban kis kő-gomb.
    @ViewBuilder
    func skinInlineButton() -> some View {
        if MinecraftTheme.isActive {
            self.buttonStyle(McButtonStyle(compact: true))
        } else {
            self.buttonStyle(.plain)
        }
    }
}

extension MinecraftTheme {
    private static let tabImageCache = NSCache<NSString, UIImage>()

    /// A tab item-textúrája a rendszer-tabsávhoz: előre, nearest-neighbor
    /// módon felnagyítva (a tabsáv a nyers 16 px-es képet elkenné), eredeti
    /// színekkel (nem template).
    static func tabBarImage(for tab: Int) -> UIImage? {
        let name = tabItemIcon(for: tab).1
        if let hit = tabImageCache.object(forKey: name as NSString) { return hit }
        guard let base = sprite(name) else { return nil }
        let side: CGFloat = 32
        let drawn = UIGraphicsImageRenderer(size: CGSize(width: side, height: side)).image { ctx in
            ctx.cgContext.interpolationQuality = .none
            base.draw(in: CGRect(x: 0, y: 0, width: side, height: side))
        }.withRenderingMode(.alwaysOriginal)
        tabImageCache.setObject(drawn, forKey: name as NSString)
        return drawn
    }
}

/// Slot-keret egy kép köré: 1 px sötét külső él, a Java-kiadás
/// inventory-rekeszének fordított bevelével (sötét fent-balra, világos
/// lent-jobbra). Csak keret, a tartalmat nem takarja.
struct McSlotFrame: View {
    var body: some View {
        Canvas { ctx, size in
            let u = MinecraftTheme.px / 1.5
            func edge(_ r: CGRect, _ c: Color) { ctx.fill(Path(r), with: .color(c)) }
            let w = size.width, h = size.height
            edge(CGRect(x: 0, y: 0, width: w, height: u), Color(hex: 0x373737))
            edge(CGRect(x: 0, y: 0, width: u, height: h), Color(hex: 0x373737))
            edge(CGRect(x: 0, y: h - u, width: w, height: u), Color(hex: 0xFFFFFF))
            edge(CGRect(x: w - u, y: 0, width: u, height: h), Color(hex: 0xFFFFFF))
        }
        .allowsHitTesting(false)
    }
}

// MARK: - Égre írt szöveg

extension View {
    /// Közvetlenül az égboltra írt másodlagos szöveg (szekció-fejléc,
    /// lábjegyzet, dátum-sor): Summitban `.secondary`, Minecraftban a játék
    /// szövege — fehér, kemény #3F3F3F árnyékkal —, mert a szürke a nappali
    /// égen olvashatatlan. Egy típusú lánc (az ág az értékekben van).
    func skinSecondaryOnSky() -> some View {
        let mc = MinecraftTheme.isActive
        return self
            .foregroundStyle(mc ? AnyShapeStyle(Color.white) : AnyShapeStyle(.secondary))
            .shadow(color: mc ? Color(hex: 0x3F3F3F) : .clear, radius: 0,
                    x: mc ? MinecraftTheme.px / 1.5 : 0, y: mc ? MinecraftTheme.px / 1.5 : 0)
    }
}

// MARK: - Vissza-gomb

/// Minecraftban a rendszer Liquid Glass vissza-köre helyett kő-gomb pixel-
/// nyíllal; Summitban a gyári vissza-gomb érintetlen. A visszahúzás
/// gesztus megmarad (lásd `McSwipeBackEnabler`).
struct McBackButtonModifier: ViewModifier {
    @Environment(\.dismiss) private var dismiss

    func body(content: Content) -> some View {
        content
            .navigationBarBackButtonHidden(MinecraftTheme.isActive)
            .toolbar {
                if MinecraftTheme.isActive {
                    ToolbarItem(placement: .topBarLeading) {
                        Button {
                            McSound.play(.click)
                            dismiss()
                        } label: {
                            McGlyph(kind: .chevronLeft, size: 16)
                                .frame(width: 24, height: 24)
                        }
                        .buttonStyle(McButtonStyle(compact: true))
                        .accessibilityLabel("Vissza")
                    }
                    .sharedBackgroundVisibility(.hidden)
                }
            }
    }
}

extension View {
    /// Push-olt nézetre: Minecraftban kő vissza-gomb (lásd `McBackButtonModifier`).
    func mcBackButton() -> some View {
        modifier(McBackButtonModifier())
    }
}

/// A rejtett rendszer-vissza-gombbal a UIKit kikapcsolná a széléről húzós
/// visszalépést; ez visszakapcsolja minden navigációs vermen, ha van hova
/// visszalépni. Summitban is ártalmatlan (ott a gesztus amúgy is él).
extension UINavigationController: @retroactive UIGestureRecognizerDelegate {
    override open func viewDidLoad() {
        super.viewDidLoad()
        interactivePopGestureRecognizer?.delegate = self
    }

    public func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        guard gestureRecognizer == interactivePopGestureRecognizer else { return true }
        // Futó push/pop alatt NEM indulhat: a félbehagyott átmenet (a
        // push-animáció alatt indított szélső húzás) „beragadt" vermet
        // hagyott, ami a következő navigációig minden koppintást elnyelt.
        // (A darabszám push közben már 2, az önmagában nem véd.)
        return viewControllers.count > 1 && transitionCoordinator == nil
    }
}
