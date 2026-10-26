import SwiftUI
import AVFoundation

// MARK: - Neon-kit
// A Neon-skin közös építőkockái (Neon HUD-nyelv). A képernyők
// `if theme.isNeon { … }` (vagy `NeonTheme.isActive`) ágban
// használják; minden elem tiszteli a Reduce Motion / Reduce Transparency /
// Increase Contrast beállításokat. Semmi képkockánkénti nehéz munka: a
// háttér statikus, animáció csak eseményre (glitch), rövid ideig fut.

// MARK: - Levágott sarkú alakzat

/// Mely sarkok legyenek levágva (45°-os ferde vágás).
struct NeonCorners: OptionSet, Hashable {
    let rawValue: Int
    static let topLeft = NeonCorners(rawValue: 1 << 0)
    static let topRight = NeonCorners(rawValue: 1 << 1)
    static let bottomLeft = NeonCorners(rawValue: 1 << 2)
    static let bottomRight = NeonCorners(rawValue: 1 << 3)
    static let all: NeonCorners = [.topLeft, .topRight, .bottomLeft, .bottomRight]
    /// A HUD alap-panelje: bal-felső + jobb-alsó vágás.
    static let diagonal: NeonCorners = [.topLeft, .bottomRight]
    static let none: NeonCorners = []
}

/// Levágott (chamfer) sarkú téglalap — a Neon panelek/gombok alakja.
/// `cut` a vágás oldalhossza pontban; a kisebbik oldal felénél nem nagyobb.
struct NeonChamferShape: InsettableShape {
    var cut: CGFloat = 12
    var corners: NeonCorners = .diagonal
    var insetAmount: CGFloat = 0

    func inset(by amount: CGFloat) -> NeonChamferShape {
        var s = self
        s.insetAmount += amount
        return s
    }

    func path(in rect: CGRect) -> Path {
        let r = rect.insetBy(dx: insetAmount, dy: insetAmount)
        guard r.width > 0, r.height > 0 else { return Path() }
        // Befelé tolt alakzatnál a vágás arányosan kisebb, hogy a keret
        // párhuzamos maradjon a külső éllel.
        let c = max(0, min(cut - insetAmount * 0.414, min(r.width, r.height) / 2))
        var p = Path()
        p.move(to: CGPoint(x: r.minX + (corners.contains(.topLeft) ? c : 0), y: r.minY))
        if corners.contains(.topRight) {
            p.addLine(to: CGPoint(x: r.maxX - c, y: r.minY))
            p.addLine(to: CGPoint(x: r.maxX, y: r.minY + c))
        } else {
            p.addLine(to: CGPoint(x: r.maxX, y: r.minY))
        }
        if corners.contains(.bottomRight) {
            p.addLine(to: CGPoint(x: r.maxX, y: r.maxY - c))
            p.addLine(to: CGPoint(x: r.maxX - c, y: r.maxY))
        } else {
            p.addLine(to: CGPoint(x: r.maxX, y: r.maxY))
        }
        if corners.contains(.bottomLeft) {
            p.addLine(to: CGPoint(x: r.minX + c, y: r.maxY))
            p.addLine(to: CGPoint(x: r.minX, y: r.maxY - c))
        } else {
            p.addLine(to: CGPoint(x: r.minX, y: r.maxY))
        }
        if corners.contains(.topLeft) {
            p.addLine(to: CGPoint(x: r.minX, y: r.minY + c))
        }
        p.closeSubpath()
        return p
    }
}

// MARK: - Panel

/// HUD-panel háttér: opak panel-arc levágott sarokkal, 1 px-es neon keret
/// és egy rövid, vastagabb akcent-csík a bal felső élen (a játék paneljeinek
/// „fül"-jele). Önállóan is használható háttérként (`.background(NeonPanelBackground())`).
struct NeonPanelBackground: View {
    var accent: Color = NeonTheme.red
    var fill: Color = NeonTheme.panel
    var corners: NeonCorners = .diagonal
    var cut: CGFloat = 12
    /// Akcent-fül a bal felső élen.
    var showsTab: Bool = true
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        let shape = NeonChamferShape(cut: cut, corners: corners)
        let hi = contrast == .increased
        // Áttetsző alap (a menü-háttér áttűnik, mint a játékban) és
        // rajta a játék áramkör-mintája, az alakzatra vágva.
        shape.fill(fill.opacity(hi ? 1 : 0.86))
            .overlay(NeonGamePattern(opacity: hi ? 0 : 0.30, tint: accent).clipShape(shape))
            .overlay(shape.strokeBorder(accent.opacity(hi ? 1 : 0.55), lineWidth: hi ? 1.5 : 1))
            .overlay(alignment: .topLeading) {
                if showsTab {
                    Rectangle()
                        .fill(accent)
                        .frame(width: 28, height: 2)
                        .padding(.leading, corners.contains(.topLeft) ? cut + 4 : 8)
                }
            }
            .accessibilityHidden(true)
    }
}

struct NeonPanel: ViewModifier {
    var accent: Color = NeonTheme.red
    var fill: Color = NeonTheme.panel
    var corners: NeonCorners = .diagonal
    var cut: CGFloat = 12
    var padding: CGFloat? = 14

    func body(content: Content) -> some View {
        content
            .padding(padding ?? 0)
            .background(NeonPanelBackground(accent: accent, fill: fill, corners: corners, cut: cut))
    }
}

extension View {
    /// HUD-panelbe csomagolás: belső margó + levágott sarkú opak arc +
    /// 1 px-es neon keret. `padding: nil` = nincs belső margó.
    func cpPanel(accent: Color = NeonTheme.red,
                 fill: Color = NeonTheme.panel,
                 corners: NeonCorners = .diagonal,
                 cut: CGFloat = 12,
                 padding: CGFloat? = 14) -> some View {
        modifier(NeonPanel(accent: accent, fill: fill, corners: corners, cut: cut, padding: padding))
    }
}

// MARK: - Háttér

/// Teljes képernyős menü-háttér: a játék szünet-menüjének eredeti
/// háttértextúrája (`pause_menu/tex/menu_bg_texture`, a saját
/// telepítésből kinyerve — lásd scripts/neon-ui-assets.sh), rajta egy
/// sötét fátyol, hogy a szöveg olvasható maradjon (a játékban is
/// sötét réteg/panelek ülnek a textúrán). Nincs rajzolt rács/minta.
/// Reduce Transparency mellett és emelt kontrasztnál tömör háttér.
struct NeonBackdrop: View {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        if reduceTransparency || contrast == .increased {
            NeonTheme.bg.ignoresSafeArea()
        } else {
            ZStack {
                NeonTheme.bg
                if UIImage(named: "img_neo_menu_bg") != nil {
                    Image("img_neo_menu_bg")
                        .resizable()
                        .scaledToFill()
                    Color.black.opacity(0.45)
                }
            }
            .ignoresSafeArea()
            .accessibilityHidden(true)
        }
    }
}

/// A játék szünet-menü gombjának eredeti sziluettje
/// (`atlas_pause_menu_buttons` / `pause_button_bg`): fehér forma az
/// atlaszból kivágva, sablonként az adott színre festve. Ha a kép
/// hiányzik, a hívó a saját alakzatát használja.
struct NeonGameButtonShape: View {
    var fill: Color
    /// A minta nyomainak tónusa (a játék `tintColor`-szorzása).
    var patternTint: Color = NeonGamePattern.supBlue
    var body: some View {
        if UIImage(named: "img_neo_btn_bg") != nil {
            ZStack {
                Image("img_neo_btn_bg")
                    .renderingMode(.template)
                    .resizable(capInsets: EdgeInsets(top: 26, leading: 44, bottom: 26, trailing: 44), resizingMode: .stretch)
                    .foregroundStyle(fill)
                // Áramkör-minta a gombon, a sziluett alfájára maszkolva.
                NeonGamePattern(opacity: 0.30, tint: patternTint)
                    .mask {
                        Image("img_neo_btn_bg")
                            .resizable(capInsets: EdgeInsets(top: 26, leading: 44, bottom: 26, trailing: 44), resizingMode: .stretch)
                    }
            }
        } else {
            NeonChamferShape(cut: 10, corners: [.topLeft, .bottomRight]).fill(fill)
        }
    }
}

/// A játék szünet-menü gombjának valódi cellája: a `PauseButtonItem`
/// widget (`pause_menu.inkwidget`) nem a `pause_button_bg` sziluettet,
/// hanem az `atlas_shapes_sync.inkatlas` `cell_bg` (kitöltés) +
/// `cell_fg` (keret) darabjait használja, kilenc-szeletelve, csak a
/// jobb alsó sarok vágott. A két darab fehér sablonként, a játék
/// `tintColor`-szorzásával színezve (scripts/neon-ui-assets.sh).
/// Hiányzó assetnél a jobb-alsó vágású saját alakzat a tartalék.
struct NeonGameCellBackground: View {
    var fill: Color
    var frame: Color
    var body: some View {
        if UIImage(named: "img_neo_cell_bg") != nil, UIImage(named: "img_neo_cell_fg") != nil {
            ZStack {
                Image("img_neo_cell_bg").renderingMode(.template).resizable().foregroundStyle(fill)
                NeonGamePattern(opacity: 0.22, tint: frame)
                    .mask { Image("img_neo_cell_bg").resizable() }
                Image("img_neo_cell_fg").renderingMode(.template).resizable().foregroundStyle(frame)
            }
        } else {
            let shape = NeonChamferShape(cut: 8, corners: [.bottomRight])
            shape.fill(fill).overlay(shape.strokeBorder(frame, lineWidth: 1))
        }
    }
}

/// A játék eredeti áramkör-mintája: az inventory-atlasz
/// (`base/gameplay/gui/fullscreen/inventory/atlas_inventory.inkatlas`,
/// a mögöttes `atlas_inventory.xbm` BC3 textúrából) `texture_2slot`
/// (széles slot, 636x190) darabja — lásd scripts/neon-ui-assets.sh.
/// A minta színe készre van sütve a textúrába: majdnem fekete
/// kékeszöld alapon (`#0A1419`) vékony, világos nyomvonalak futnak
/// sűrűn (a nyers textúrában ~5 px-enként). A játék a darabot
/// `tintColor`-ral szorozza (pl. a wardrobe-slot `backgroundLines`
/// képe a `MainColors.SupBlue` tónust kapja az inventory widgetben):
/// ezt utánozza a `colorMultiply`, a világos nyomok a `tint`
/// színét veszik fel, a sötét alap sötét marad. A hívó vágja a
/// saját alakjára.
///
/// Lépték: a darab FIX méretű csempeként ismétlődik, sosem nyúlik
/// a felülethez. Korábban `scaledToFill` feszítette a teljes
/// keretre, ezért a skála a felülettel nőtt: egy iPhone-cella
/// (~360 pt széles) ~0,56-os skálát kapott, egy iPad-széles
/// kártya viszont 1,5-2x-eset — a nyomvonalak óriásira nőttek.
/// Most a textúra 2x-es pontskálával (636x190 px → 318x95 pt
/// csempe, a Voxel menüháttér `1/px` trükkjének mintájára)
/// `.tile` módban ismétlődik, így minden felületen a kis
/// elemeken megszokott ~0,5-ös lépték látszik. A darab nem
/// varratmentes csempe, de 0,05-0,30 opacity mellett a
/// találkozások nem ütnek ki a sötét panelből.
struct NeonGamePattern: View {
    var opacity: Double = 0.08
    /// A játék `MainColors.SupBlue` tónusa (az inventory widget
    /// `backgroundLines` képének gyári `tintColor` értéke:
    /// HDR 0.035 / 0.466 / 0.494) — sötét cián nyomok.
    var tint: Color = NeonGamePattern.supBlue
    static let supBlue: Color = Color(red: 0.035, green: 0.466, blue: 0.494)
    /// A csempe pontskálája: 2 = a textúra felére (318x95 pt) —
    /// a kis iPhone-felületeken korábban kialakult lépték.
    private static let tilePointScale: CGFloat = 2

    var body: some View {
        if let cg = UIImage(named: "tex_neo_pattern")?.cgImage {
            Image(decorative: cg, scale: Self.tilePointScale)
                .resizable(resizingMode: .tile)
                .colorMultiply(tint)
                .opacity(opacity)
                .accessibilityHidden(true)
        }
    }
}

// MARK: - Gomb

/// Neon-gomb a játék `PauseButtonItem` celláján (`cell_bg`+`cell_fg`,
/// csak jobb-alsó vágás): alapban sötét arc (`Fullscreen_
/// PrimaryBackgroundDarkest`), vörös keret+felirat (`MenuButton`
/// Default = `MainColors.Red`); lenyomva tömör kitöltés fekete
/// felirattal (a `ButtonPause` Hover állapota: `FullAtHover`, fekete
/// szöveg). A sárga a játékban hover-szín (`MenuButton` Hover =
/// `ActiveYellow`), érintőképernyőn nincs hover, ezért nem alapállapot.
/// - `.primary`: vörös keret/felirat, lenyomva vörös arc + fekete felirat.
/// - `.secondary`: cián keret/felirat (a játék `MainColors.Blue` családja).
/// - `.destructive`: mint a primary, halvány vörös alaptónussal.
struct NeonButtonStyle: ButtonStyle {
    enum Kind { case primary, secondary, destructive }
    var kind: Kind = .primary
    /// Kompakt (ikon / toolbar / sorba tett) gomb: kisebb margó.
    var compact: Bool = false
    var fullWidth: Bool = false
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.colorSchemeContrast) private var contrast

    func makeBody(configuration: Configuration) -> some View {
        let pressed = configuration.isPressed
        let shape = NeonChamferShape(cut: compact ? 6 : 10, corners: [.bottomRight])
        let accent: Color = {
            switch kind {
            case .primary: return NeonTheme.red
            case .secondary: return NeonTheme.cyan
            case .destructive: return NeonTheme.red
            }
        }()
        let fg: Color = {
            guard isEnabled else { return NeonTheme.dim }
            return pressed ? Color.black : accent
        }()
        let fill: Color = {
            guard isEnabled else { return NeonTheme.panel }
            if pressed { return accent }
            return kind == .destructive ? accent.opacity(0.12) : NeonTheme.panel
        }()
        return configuration.label
            .font(NeonTheme.font(compact ? .subheadline : .headline, weight: .bold))
            .textCase(.uppercase)
            .tracking(1.2)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .foregroundStyle(fg)
            .padding(.horizontal, compact ? 10 : 20)
            .padding(.vertical, compact ? 6 : 11)
            .frame(maxWidth: fullWidth ? .infinity : nil, minHeight: compact ? 34 : 46)
            .background(NeonGameCellBackground(fill: fill, frame: isEnabled ? accent.opacity(contrast == .increased ? 1 : 0.9) : NeonTheme.dim.opacity(0.5)))
            .contentShape(shape)
            .onChange(of: pressed) { _, down in
                if down { NeonSound.play(.click) }
            }
    }
}

extension ButtonStyle where Self == NeonButtonStyle {
    static var cpPrimary: NeonButtonStyle { NeonButtonStyle(kind: .primary) }
    static var cpSecondary: NeonButtonStyle { NeonButtonStyle(kind: .secondary) }
    static var cpDestructive: NeonButtonStyle { NeonButtonStyle(kind: .destructive) }
}

// MARK: - Címkék, fejlécek, elválasztók

/// Apró egyenközű HUD-címke, pl. `[ SUBJ_04 ]`. Nagybetűs, ritkított.
struct NeonLabel: View {
    var text: String
    var color: Color = NeonTheme.dim
    var bracketed: Bool = true
    var size: CGFloat = 10

    init(_ text: String, color: Color = NeonTheme.dim, bracketed: Bool = true, size: CGFloat = 10) {
        self.text = text
        self.color = color
        self.bracketed = bracketed
        self.size = size
    }

    var body: some View {
        Text(bracketed ? "[ \(text.uppercased()) ]" : text.uppercased())
            .font(NeonTheme.mono(size: size, relativeTo: .caption2))
            .tracking(1)
            .foregroundStyle(color)
            .lineLimit(1)
            .accessibilityLabel(text)
    }
}

/// Szekció-fejléc: kis akcent-négyzet + nagybetűs Rajdhani cím + kitöltő
/// vékony vonal + opcionális kód (pl. `04` → `// 04`).
struct NeonSectionHeader: View {
    var title: String
    var code: String? = nil
    var accent: Color = NeonTheme.red

    init(_ title: String, code: String? = nil, accent: Color = NeonTheme.red) {
        self.title = title
        self.code = code
        self.accent = accent
    }

    var body: some View {
        HStack(spacing: 8) {
            Rectangle().fill(accent).frame(width: 6, height: 6)
            Text(title.uppercased())
                .font(NeonTheme.font(.subheadline, weight: .bold))
                .tracking(1.6)
                .foregroundStyle(accent)
                .lineLimit(1)
                // A cím az elsőbb: a vonal zsugorodik nullára, mielőtt a cím
                // „…"-ra vágódna (eddig az egyenlő elosztás levágta a hosszabb
                // címeket, pl. „LEGÚJABB JEG…").
                .layoutPriority(1)
                .minimumScaleFactor(0.8)
            Rectangle().fill(accent.opacity(0.35)).frame(minWidth: 8, maxWidth: .infinity, minHeight: 1, maxHeight: 1)
            if let code {
                Text("// \(code.uppercased())")
                    .font(NeonTheme.mono(size: 10, relativeTo: .caption2))
                    .foregroundStyle(NeonTheme.dim)
                    .lineLimit(1)
                    .fixedSize()
            }
        }
        .textCase(nil)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityAddTraits(.isHeader)
    }
}

/// Vékony HUD-vonal: 1 px-es halvány vonal, a bal végén rövid fényes
/// szakasszal.
struct NeonDivider: View {
    var color: Color = NeonTheme.red
    var showsTick: Bool = true

    var body: some View {
        ZStack(alignment: .leading) {
            Rectangle().fill(color.opacity(0.28)).frame(height: 1)
            if showsTick {
                Rectangle().fill(color).frame(width: 18, height: 2)
            }
        }
        .frame(height: 2)
        .accessibilityHidden(true)
    }
}

// MARK: - Szegmens-választó

/// `Picker(.segmented)` HUD-párja a játék `cell_bg`/`cell_fg`
/// celláin: a kijelölt tömör vörös kitöltésű fekete felirattal (a
/// `ButtonPause` Hover-kitöltése), a többi sötét arcú, halvány keretű.
/// Váltáskor blip.
struct NeonSegmentedPicker<Value: Hashable>: View {
    @Binding var selection: Value
    var options: [(value: Value, title: String)]
    var accessibilityTitle: String = ""

    var body: some View {
        HStack(spacing: 4) {
            ForEach(Array(options.enumerated()), id: \.offset) { _, option in
                let on = option.value == selection
                let shape = NeonChamferShape(cut: 6, corners: [.bottomRight])
                Button {
                    if !on { NeonSound.play(.navigate) }
                    selection = option.value
                } label: {
                    Text(option.title.uppercased())
                        .font(NeonTheme.font(.subheadline, weight: .bold))
                        .tracking(1)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                        .foregroundStyle(on ? Color.black : NeonTheme.text.opacity(0.75))
                        .frame(maxWidth: .infinity, minHeight: 36)
                        .padding(.horizontal, 4)
                        .background(NeonGameCellBackground(fill: on ? NeonTheme.red : NeonTheme.panel, frame: on ? NeonTheme.red : NeonTheme.dim.opacity(0.45)))
                        .contentShape(shape)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(option.title)
                .accessibilityAddTraits(on ? .isSelected : [])
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(accessibilityTitle)
    }
}

// MARK: - Folyamatjelző

/// Szegmentált HUD-sáv (mint a játék életerő-/RAM-sávja). `value` 0…1.
/// `segments: 0` = folytonos sáv.
struct NeonProgressBar: View {
    var value: Double
    var tint: Color = NeonTheme.yellow
    var segments: Int = 20
    var height: CGFloat = 8

    var body: some View {
        let v = min(1, max(0, value))
        GeometryReader { geo in
            if segments > 0 {
                let gap: CGFloat = 2
                let w = max(1, (geo.size.width - gap * CGFloat(segments - 1)) / CGFloat(segments))
                let lit = Int((v * Double(segments)).rounded(.up))
                HStack(spacing: gap) {
                    ForEach(0..<segments, id: \.self) { i in
                        Rectangle()
                            .fill(i < lit ? tint : tint.opacity(0.14))
                            .frame(width: w)
                    }
                }
            } else {
                ZStack(alignment: .leading) {
                    Rectangle().fill(tint.opacity(0.14))
                    Rectangle().fill(tint).frame(width: geo.size.width * v)
                }
            }
        }
        .frame(height: height)
        .accessibilityElement()
        .accessibilityValue("\(Int((v * 100).rounded())) százalék")
    }
}

// MARK: - Jegy-jelvény

/// Jegy-jelvény (1–5, vagy szöveges jegy): levágott sarkú négyzet a jegy
/// HUD-színében — halvány arc, 1 px-es keret, nagy Rajdhani szám.
struct NeonGradeBadge: View {
    /// Számjegy (1–5) — ez dönti el a színt. `nil` = szöveges / ismeretlen.
    var value: Int?
    /// Kiírt szöveg (alapból a szám).
    var text: String? = nil
    var size: CGFloat = 36
    /// Kitöltött (erős) változat: tömör szín, fekete szám.
    var filled: Bool = false

    var body: some View {
        let color = NeonTheme.gradeColor(for: value ?? 0)
        let shape = NeonChamferShape(cut: size * 0.22, corners: [.topLeft, .bottomRight])
        Text(text ?? value.map(String.init) ?? "–")
            .font(NeonTheme.display(size: size * 0.62, weight: .bold, relativeTo: .title3))
            .monospacedDigit()
            .minimumScaleFactor(0.5)
            .lineLimit(1)
            .foregroundStyle(filled ? Color.black : color)
            .frame(width: size, height: size)
            .background(shape.fill(filled ? color : color.opacity(0.12)))
            .overlay(shape.strokeBorder(color, lineWidth: 1))
            .accessibilityLabel(value.map { "\($0)-es jegy" } ?? (text ?? "Jegy"))
    }
}

// MARK: - Toast

/// HUD-értesítés (pl. „ÚJ JEGY", „ADAT SZINKRONIZÁLVA").
struct NeonToastModel: Identifiable, Equatable {
    enum Kind { case info, success, warning, error }
    var id = UUID()
    var title: String
    var message: String? = nil
    var kind: Kind = .info
    var icon: String? = nil
}

struct NeonToast: View {
    var model: NeonToastModel

    var body: some View {
        let accent = Self.accent(model.kind)
        HStack(alignment: .top, spacing: 12) {
            Rectangle().fill(accent).frame(width: 3)
            if let icon = model.icon {
                Image(systemName: icon)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(accent)
                    .padding(.top, 2)
            }
            VStack(alignment: .leading, spacing: 2) {
                NeonLabel(Self.code(model.kind), color: accent)
                Text(model.title.uppercased())
                    .font(NeonTheme.font(.headline, weight: .bold))
                    .tracking(1)
                    .foregroundStyle(NeonTheme.text)
                if let message = model.message {
                    Text(message)
                        .font(NeonTheme.font(.subheadline))
                        .foregroundStyle(NeonTheme.text.opacity(0.75))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 10)
        .padding(.trailing, 14)
        .background(NeonPanelBackground(accent: accent, fill: NeonTheme.panelRaised, corners: [.bottomRight], cut: 12, showsTab: false))
        .accessibilityElement(children: .combine)
    }

    static func accent(_ kind: NeonToastModel.Kind) -> Color {
        switch kind {
        case .info: return NeonTheme.cyan
        case .success: return NeonTheme.green
        case .warning: return NeonTheme.yellow
        case .error: return NeonTheme.red
        }
    }

    static func code(_ kind: NeonToastModel.Kind) -> String {
        switch kind {
        case .info: return "INFO"
        case .success: return "OK"
        case .warning: return "WARN"
        case .error: return "ERR"
        }
    }
}

private struct NeonToastHost: ViewModifier {
    @Binding var toast: NeonToastModel?
    var duration: Double
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content.overlay(alignment: .top) {
            if let t = toast {
                NeonToast(model: t)
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                    .transition(reduceMotion ? .opacity : .move(edge: .top).combined(with: .opacity))
                    .id(t.id)
                    .onTapGesture { withAnimation { toast = nil } }
                    .task(id: t.id) {
                        NeonSound.play(t.kind == .error ? .error : .toast)
                        try? await Task.sleep(for: .seconds(duration))
                        if toast?.id == t.id { withAnimation(.easeOut(duration: 0.2)) { toast = nil } }
                    }
            }
        }
        .animation(reduceMotion ? nil : .spring(duration: 0.3), value: toast?.id)
    }
}

extension View {
    /// Felülről beúszó HUD-toast; `duration` mp után eltűnik (koppintásra
    /// azonnal). Megjelenéskor blip (hibánál hiba-hang).
    func cpToast(_ toast: Binding<NeonToastModel?>, duration: Double = 2.8) -> some View {
        modifier(NeonToastHost(toast: toast, duration: duration))
    }
}

// MARK: - Glitch / kromatikus aberráció (csak kiemelésre)

private struct NeonChromatic: ViewModifier {
    var amount: CGFloat
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast

    func body(content: Content) -> some View {
        if reduceTransparency || contrast == .increased || amount == 0 {
            content
        } else {
            content
                .background(content.foregroundStyle(NeonTheme.red.opacity(0.7)).offset(x: -amount).accessibilityHidden(true))
                .background(content.foregroundStyle(NeonTheme.cyan.opacity(0.7)).offset(x: amount).accessibilityHidden(true))
        }
    }
}

private struct NeonGlitch<T: Equatable>: ViewModifier {
    var trigger: T
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        if reduceMotion {
            content
        } else {
            content.keyframeAnimator(initialValue: CGFloat(0), trigger: trigger) { view, dx in
                view.modifier(NeonChromatic(amount: abs(dx))).offset(x: dx * 0.5)
            } keyframes: { _ in
                KeyframeTrack {
                    LinearKeyframe(3, duration: 0.04)
                    LinearKeyframe(-2, duration: 0.05)
                    LinearKeyframe(4, duration: 0.04)
                    LinearKeyframe(-1, duration: 0.06)
                    LinearKeyframe(0, duration: 0.08)
                }
            }
        }
    }
}

extension View {
    /// Statikus kromatikus aberráció (vörös/cián szellemkép) — CSAK kiemelt
    /// szövegre (hero-szám, főcím). Reduce Transparency / emelt kontraszt
    /// mellett kikapcsol.
    func cpChromatic(_ amount: CGFloat = 1) -> some View {
        modifier(NeonChromatic(amount: amount))
    }

    /// Rövid (~0,27 mp) glitch-rángás, ha `trigger` változik (pl. új jegy,
    /// tabváltás). Reduce Motion mellett nem fut.
    func cpGlitch<T: Equatable>(trigger: T) -> some View {
        modifier(NeonGlitch(trigger: trigger))
    }
}

// MARK: - Kapcsoló, beviteli mező

/// Kapcsoló a játék jelölőnégyzetén: az `atlas_shapes_sync`
/// `checkbox_frame` kerete + bekapcsolva a `checkbox_fill` kitöltése
/// (fehér sablonok, játék szerinti tintával). Asset híján a korábbi
/// csúszka-alakzat a tartalék.
struct NeonToggleStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        let on = configuration.isOn
        HStack(spacing: 10) {
            configuration.label
            Spacer(minLength: 8)
            Button {
                NeonSound.play(configuration.isOn ? .valueDown : .valueUp)
                configuration.isOn.toggle()
            } label: {
                Group {
                    if UIImage(named: "img_neo_check_frame") != nil {
                        ZStack {
                            Image("img_neo_check_frame").renderingMode(.template).resizable()
                                .foregroundStyle(on ? NeonTheme.red : NeonTheme.dim.opacity(0.6))
                            if on, UIImage(named: "img_neo_check_fill") != nil {
                                Image("img_neo_check_fill").renderingMode(.template).resizable()
                                    .foregroundStyle(NeonTheme.red)
                                    .padding(6)
                            }
                        }
                    } else {
                        ZStack(alignment: on ? .trailing : .leading) {
                            NeonChamferShape(cut: 5, corners: [.bottomRight])
                                .fill(on ? NeonTheme.red.opacity(0.18) : NeonTheme.panel)
                                .overlay(NeonChamferShape(cut: 5, corners: [.bottomRight])
                                    .strokeBorder(on ? NeonTheme.red : NeonTheme.dim.opacity(0.6), lineWidth: 1))
                            Rectangle().fill(on ? NeonTheme.red : NeonTheme.dim)
                                .frame(width: 18, height: 18).padding(4)
                        }
                    }
                }
                .frame(width: 28, height: 28)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityHidden(true)
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityValue(on ? "Be" : "Ki")
        .accessibilityAction { configuration.isOn.toggle() }
    }
}

private struct NeonInputFrame: ViewModifier {
    func body(content: Content) -> some View {
        let shape = NeonChamferShape(cut: 6, corners: [.bottomRight])
        content
            .font(NeonTheme.font(.body))
            .foregroundStyle(NeonTheme.text)
            .tint(NeonTheme.cyan)
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(shape.fill(NeonTheme.bgDeep))
            .overlay(shape.strokeBorder(NeonTheme.cyan.opacity(0.6), lineWidth: 1))
    }
}

extension View {
    /// Szövegmező HUD-kerete (mély háttér, cián körvonal, cián kurzor).
    func cpInput() -> some View { modifier(NeonInputFrame()) }
}

// MARK: - Lista / Form sorok

extension NeonTheme {
    /// Sor-háttér behúzása: az insetGrouped lista a szekciót ~30 pt-os
    /// lekerekítéssel vágja — a levágott sarkú panel ennyivel beljebb ül,
    /// így a vágás sosem éri el (ugyanaz a mérés, mint a `VoxelRowPanel`-nél).
    static let rowHorizontalInset: CGFloat = 9
    static let rowVerticalInset: CGFloat = 4

    /// Sor-margó: az alap-margó + a panel behúzása.
    static func rowInsets(_ base: EdgeInsets? = nil) -> EdgeInsets {
        let b = base ?? EdgeInsets(top: 11, leading: 16, bottom: 11, trailing: 16)
        return EdgeInsets(top: b.top + rowVerticalInset, leading: b.leading + rowHorizontalInset,
                          bottom: b.bottom + rowVerticalInset, trailing: b.trailing + rowHorizontalInset)
    }
}

/// Lista-sor háttere: behúzott HUD-panel (lásd `rowInsets`). Áttetsző
/// állapot-szín (pl. narancs 8%) a panel-arcra kerül, alatta opak alap.
struct NeonRowBackground: View {
    var accent: Color = NeonTheme.red
    var fill: Color = NeonTheme.panel
    var body: some View {
        ZStack {
            NeonChamferShape(cut: 10, corners: .diagonal).fill(NeonTheme.panel)
            NeonPanelBackground(accent: accent, fill: fill, corners: .diagonal, cut: 10, showsTab: false)
        }
        .padding(.horizontal, NeonTheme.rowHorizontalInset)
        .padding(.vertical, NeonTheme.rowVerticalInset)
    }
}

extension View {
    /// Teljes HUD-sor stílus List/Form sorra: panel-háttér + rejtett
    /// elválasztó + a panelhez igazított margó. Csak Neon-ágban hívd
    /// (vagy használd a skin-érzékeny `voxelListRow` / `summitRowSurface`-t,
    /// amelyek Neonban ezt adják).
    func cpListRow(accent: Color = NeonTheme.red, fill: Color = NeonTheme.panel, insets: EdgeInsets? = nil) -> some View {
        self.listRowBackground(NeonRowBackground(accent: accent, fill: fill))
            .listRowSeparator(.hidden)
            .listRowInsets(NeonTheme.rowInsets(insets))
    }

    /// List/Form/ScrollView mögé a a neon felület-háttér (rejtett rendszer-
    /// háttérrel).
    func cpListChrome() -> some View {
        self.scrollContentBackground(.hidden)
            .background { NeonBackdrop() }
    }
}

/// `Section("Cím") { … }` HUD-párja: `NeonSectionHeader` fejléc, HUD-sorok.
struct NeonFormSection<Content: View>: View {
    var title: String
    var code: String? = nil
    var accent: Color = NeonTheme.red
    @ViewBuilder var content: () -> Content

    var body: some View {
        Section {
            content().cpListRow(accent: accent)
        } header: {
            NeonSectionHeader(title, code: code, accent: accent)
        }
    }
}

// MARK: - Hangok (igazi Neon UI-hangok)

/// A játék saját UI-hangjai, a saját Neon-telepítésből
/// kinyerve (Wwise-esemény → `.wem` → AAC, Data Setként az asset
/// catalog `Neon/` mappájában — ahogy a Voxel-hangok is a
/// játékból jönnek). Szintetizált utánzat nincs: ha egy asset hiányzik,
/// a hang néma marad.
/// `.ambient` audio-session: ha a telefon némítva van (oldalsó némító
/// kapcsoló), az app sem csipog, és más app zenéjét sem állítja le.
/// Csak Neon-skinben szól.
enum NeonSound: String, CaseIterable {
    /// Gomb-lenyomás a játék menüiben (`ui_menu_onpress`) — a stílusos
    /// (NeonButtonStyle) gombok hangja.
    case click = "snd_neo_click"
    /// Rövid egérkattanás (`ui_menu_mouse_click`) — a stílus nélküli,
    /// hétköznapi koppintások hangja (a gyökér-gombstílus adja).
    case mouseClick = "snd_neo_mouseclick"
    /// Fülváltás a játék menüiben (`ui_gui_tab_change`) — a dockon ez szól.
    case tab = "snd_neo_tab"
    /// Visszalépés / menü-zárás (`ui_menu_close`) — a VISSZA gomb hangja.
    case back = "snd_neo_back"
    /// Érték fel (`ui_menu_value_up`) — kapcsoló be, léptetés fel.
    case valueUp = "snd_neo_valueup"
    /// Érték le (`ui_menu_value_down`) — kapcsoló ki, léptetés le.
    case valueDown = "snd_neo_valuedown"
    /// Navigáció választóban (`ui_phone_navigation`) — szegmens- és
    /// belső választók hangja, nem a docké.
    case navigate = "snd_neo_navigate"
    /// Pozitív visszaigazolás (`ui_positive`).
    case confirm = "snd_neo_confirm"
    /// Negatív visszaigazolás / hiba (`ui_generic_set_01_negative`).
    case error = "snd_neo_error"
    /// Értesítés érkezett (`ui_phone_sms`).
    case toast = "snd_neo_toast"
    /// Glitch (jegyzet-ünneplés, `ui_splash_screen_glitch`).
    case glitch = "snd_neo_glitch"
    /// Enter-belépés (`vfx_fullscreen_enter_entering`, a játék
    /// két rétege együtt, 3,4 mp-re vágva) — a téma kiválasztásakor és a
    /// boot-átmenet alatt szól.
    case enter = "snd_neo_enter"

    /// Hangonként kis lejátszó-készlet (mint a `VoxelSound`-nál): gyors
    /// egymásutánban a hangok átfedhetnek, nem vágják el egymást.
    private static var pool: [NeonSound: [AVAudioPlayer]] = [:]
    private static var sessionReady = false
    private static let poolSize = 3
    private static var lastPlay: [NeonSound: CFTimeInterval] = [:]

    /// Lejátszás (Neon-skinen kívül néma). Ugyanaz a hang 60 ms-on
    /// belül nem indul kétszer (gombstílus + akció egy koppintásra).
    static func play(_ sound: NeonSound, volume: Float = 1) {
        guard NeonTheme.isActive else { return }
        let now = CACurrentMediaTime()
        if let last = lastPlay[sound], now - last < 0.06 { return }
        lastPlay[sound] = now
        guard prepareSession() else { return }
        var players = pool[sound] ?? []
        if players.count < poolSize, let fresh = makePlayer(sound) {
            players.append(fresh)
            pool[sound] = players
        }
        guard let player = players.first(where: { !$0.isPlaying }) ?? players.first else { return }
        player.volume = volume * sound.gain
        player.currentTime = 0
        player.play()
    }

    /// Előmelegítés (Neon-skin indulásakor / bekapcsolásakor): a
    /// session és a gyakori hangok lejátszója előre elkészül, hogy az
    /// első koppintás (és a boot-glitch) ne akkor építkezzen.
    static func warmUp() {
        guard NeonTheme.isActive else { return }
        DispatchQueue.main.async {
            guard NeonTheme.isActive, prepareSession() else { return }
            for sound in [NeonSound.click, .tab, .glitch] where (pool[sound] ?? []).isEmpty {
                if let player = makePlayer(sound) { pool[sound] = [player] }
            }
        }
    }

    private var gain: Float {
        switch self {
        case .click: return 0.5
        case .mouseClick: return 0.55
        case .tab: return 0.85
        case .back: return 0.6
        case .valueUp, .valueDown: return 0.7
        case .navigate: return 0.65
        case .confirm, .toast: return 0.7
        case .error: return 0.8
        case .glitch: return 0.45
        case .enter: return 0.8
        }
    }

    /// `.ambient` session: a telefon némító kapcsolója az appot is
    /// elnémítja, más app zenéje tovább szólhat mellette.
    private static func prepareSession() -> Bool {
        if sessionReady { return true }
        do {
            try AVAudioSession.sharedInstance().setCategory(.ambient, mode: .default, options: [.mixWithOthers])
            sessionReady = true
        } catch {
            #if DEBUG
            print("NeonSound: audio session hiba: \(error)")
            #endif
        }
        return sessionReady
    }

    private static func makePlayer(_ sound: NeonSound) -> AVAudioPlayer? {
        guard let asset = NSDataAsset(name: sound.rawValue) else {
            #if DEBUG
            print("NeonSound: hiányzó hang-asset: \(sound.rawValue)")
            #endif
            return nil
        }
        do {
            let player = try AVAudioPlayer(data: asset.data)
            player.prepareToPlay()
            return player
        } catch {
            #if DEBUG
            print("NeonSound: dekódolási hiba (\(sound.rawValue)): \(error)")
            #endif
            return nil
        }
    }
}

/// Neonban minden stílus nélküli gomb rövid egérkattanást ad (az
/// app gyökerére tett `VoxelClickButtonStyle` mintájára — azt ki is
/// egészíti: a kettő skinje kizárja egymást, mindkét `play` némán tér
/// vissza a másik skinben). Nem a stílusos gombok `onpress` hangja:
/// a hétköznapi koppintás halkabb és rövidebb.
struct NeonClickButtonStyle: PrimitiveButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        Button(role: configuration.role) {
            NeonSound.play(.mouseClick)
            VoxelSound.play(.click)
            configuration.trigger()
        } label: {
            configuration.label
        }
        .buttonStyle(.automatic)
    }
}

// MARK: - Belépő „boot" átmenet (skinváltáskor)

extension NeonTheme {
    /// A felület-választó ezt postolja, amikor a user Neonra vált —
    /// a gyökér (ContentView) erre egyszer lejátssza a `NeonBootOverlay`-t.
    /// (Távoli szinkronból érkező skinváltásra szándékosan nem fut.)
    static let bootRequest = Notification.Name("summit.neon.boot")
}

/// Belépő átmenet Neonra váltáskor: az EREDETI játékbeli
/// enter-belépés videón, nem rekonstrukció. A játék effektje
/// engine worldEffect/particle (`p_enter_entering`), SwiftUI-ban
/// nem játszható le és videóra sem renderelhető ki, ezért a jelenet
/// egy gameplay-felvételből kivágott szakasza fut: `vid_neo_enter.mp4`
/// a Resourcesban (Neon gameplay, a Judy-féle furgonos
/// enter-belépés fehér vakítása, 571,5–574,9 mp a forrásban,
/// 3,4 mp-re vágva, néma, 720p — lásd a commit-leírást a forrásért).
/// A videó néma: alatta az eredeti enter-belépő hang szól
/// (`NeonSound.enter`, 3,4 mp), a kettő egyszerre indul, így a
/// kép és a hang végig szinkronban van; a videó utolsó (fehér)
/// képkockájáról az overlay elhalványulása adja a lecsengést.
/// Nincs logó, felirat, sáv vagy keret a videón és körülötte sem,
/// nem fogja meg az érintést. Ha a videófájl valamiért hiányozna a
/// bundle-ből, rekonstrukció helyett sima fekete kitartás fut a hang
/// hosszáig. Reduce Motion mellett nincs videó és villanás
/// (fényérzékenység!): csak rövid fekete átmenet, a hang halkabban
/// szól (a hang nem villog, de így az egész boot visszafogottabb).
struct NeonBootOverlay: View {
    var onFinish: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var opacity: Double = 1
    @State private var player: AVPlayer?

    var body: some View {
        ZStack {
            Color.black
            if !reduceMotion, let player {
                NeonBootVideoView(player: player)
            }
        }
        .ignoresSafeArea()
        .opacity(opacity)
        .allowsHitTesting(false)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Neon felület bekapcsolva")
        .task { await run() }
    }

    private func run() async {
        if reduceMotion {
            // Fényérzékenység: semmi villanás/videó, csak nyugodt
            // átmenet; a belépő hang halkabban marad meg.
            NeonSound.play(.enter, volume: 0.5)
            try? await Task.sleep(for: .milliseconds(700))
            withAnimation(.easeOut(duration: 0.3)) { opacity = 0 }
            try? await Task.sleep(for: .milliseconds(320))
            onFinish()
            return
        }
        // A videó és az eredeti belépő hang egyszerre indul (3,4 mp).
        if let url = Bundle.main.url(forResource: "vid_neo_enter", withExtension: "mp4") {
            let p = AVPlayer(url: url)
            p.isMuted = true
            player = p
            NeonSound.play(.enter)
            p.play()
        } else {
            // Nincs videó a bundle-ben: fekete kitartás a hang hosszáig.
            NeonSound.play(.enter)
        }
        try? await Task.sleep(for: .milliseconds(3400))
        // A videó utolsó (fehér) képkockájáról halványul el az overlay.
        withAnimation(.easeOut(duration: 0.35)) { opacity = 0 }
        try? await Task.sleep(for: .milliseconds(380))
        player?.pause()
        player = nil
        onFinish()
    }
}

/// Teljes képernyős, kezelőelemek nélküli videóréteg a boot-videóhoz
/// (`resizeAspectFill`, mint a játék teljes képernyős átmenete).
private struct NeonBootVideoView: UIViewRepresentable {
    let player: AVPlayer

    func makeUIView(context: Context) -> NeonPlayerLayerView {
        let view = NeonPlayerLayerView()
        view.playerLayer.player = player
        view.playerLayer.videoGravity = .resizeAspectFill
        return view
    }

    func updateUIView(_ uiView: NeonPlayerLayerView, context: Context) {
        uiView.playerLayer.player = player
    }
}

private final class NeonPlayerLayerView: UIView {
    override class var layerClass: AnyClass { AVPlayerLayer.self }
    var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }
    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .black
        isUserInteractionEnabled = false
    }
    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }
}
