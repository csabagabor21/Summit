import SwiftUI
import AVFoundation

// MARK: - Cyberpunk-kit
// A Cyberpunk-skin közös építőkockái (CP2077 HUD-nyelv). A képernyők
// `if theme.isCyberpunk { … }` (vagy `CyberpunkTheme.isActive`) ágban
// használják; minden elem tiszteli a Reduce Motion / Reduce Transparency /
// Increase Contrast beállításokat. Semmi képkockánkénti nehéz munka: a
// háttér statikus, animáció csak eseményre (glitch), rövid ideig fut.

// MARK: - Levágott sarkú alakzat

/// Mely sarkok legyenek levágva (45°-os ferde vágás).
struct CPCorners: OptionSet, Hashable {
    let rawValue: Int
    static let topLeft = CPCorners(rawValue: 1 << 0)
    static let topRight = CPCorners(rawValue: 1 << 1)
    static let bottomLeft = CPCorners(rawValue: 1 << 2)
    static let bottomRight = CPCorners(rawValue: 1 << 3)
    static let all: CPCorners = [.topLeft, .topRight, .bottomLeft, .bottomRight]
    /// A HUD alap-panelje: bal-felső + jobb-alsó vágás.
    static let diagonal: CPCorners = [.topLeft, .bottomRight]
    static let none: CPCorners = []
}

/// Levágott (chamfer) sarkú téglalap — a CP2077 panelek/gombok alakja.
/// `cut` a vágás oldalhossza pontban; a kisebbik oldal felénél nem nagyobb.
struct CPChamferShape: InsettableShape {
    var cut: CGFloat = 12
    var corners: CPCorners = .diagonal
    var insetAmount: CGFloat = 0

    func inset(by amount: CGFloat) -> CPChamferShape {
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
/// „fül"-jele). Önállóan is használható háttérként (`.background(CPPanelBackground())`).
struct CPPanelBackground: View {
    var accent: Color = CyberpunkTheme.red
    var fill: Color = CyberpunkTheme.panel
    var corners: CPCorners = .diagonal
    var cut: CGFloat = 12
    /// Akcent-fül a bal felső élen.
    var showsTab: Bool = true
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        let shape = CPChamferShape(cut: cut, corners: corners)
        let hi = contrast == .increased
        // Áttetsző alap (a menü-háttér áttűnik, mint a játékban) és
        // rajta a játék áramkör-mintája, az alakzatra vágva.
        shape.fill(fill.opacity(hi ? 1 : 0.86))
            .overlay(CPGamePattern(opacity: hi ? 0 : 0.07).clipShape(shape))
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

struct CPPanel: ViewModifier {
    var accent: Color = CyberpunkTheme.red
    var fill: Color = CyberpunkTheme.panel
    var corners: CPCorners = .diagonal
    var cut: CGFloat = 12
    var padding: CGFloat? = 14

    func body(content: Content) -> some View {
        content
            .padding(padding ?? 0)
            .background(CPPanelBackground(accent: accent, fill: fill, corners: corners, cut: cut))
    }
}

extension View {
    /// HUD-panelbe csomagolás: belső margó + levágott sarkú opak arc +
    /// 1 px-es neon keret. `padding: nil` = nincs belső margó.
    func cpPanel(accent: Color = CyberpunkTheme.red,
                 fill: Color = CyberpunkTheme.panel,
                 corners: CPCorners = .diagonal,
                 cut: CGFloat = 12,
                 padding: CGFloat? = 14) -> some View {
        modifier(CPPanel(accent: accent, fill: fill, corners: corners, cut: cut, padding: padding))
    }
}

// MARK: - Háttér

/// Teljes képernyős menü-háttér: a játék szünet-menüjének eredeti
/// háttértextúrája (`pause_menu/tex/menu_bg_texture`, a saját
/// telepítésből kinyerve — lásd scripts/cp-ui-assets.sh), rajta egy
/// sötét fátyol, hogy a szöveg olvasható maradjon (a játékban is
/// sötét réteg/panelek ülnek a textúrán). Nincs rajzolt rács/minta.
/// Reduce Transparency mellett és emelt kontrasztnál tömör háttér.
struct CPBackdrop: View {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        if reduceTransparency || contrast == .increased {
            CyberpunkTheme.bg.ignoresSafeArea()
        } else {
            ZStack {
                CyberpunkTheme.bg
                if UIImage(named: "cp_menu_bg") != nil {
                    Image("cp_menu_bg")
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
struct CPGameButtonShape: View {
    var fill: Color
    var body: some View {
        if UIImage(named: "cp_btn_bg") != nil {
            ZStack {
                Image("cp_btn_bg")
                    .renderingMode(.template)
                    .resizable(capInsets: EdgeInsets(top: 26, leading: 44, bottom: 26, trailing: 44), resizingMode: .stretch)
                    .foregroundStyle(fill)
                // Áramkör-minta a gombon, a sziluett alfájára maszkolva.
                CPGamePattern(opacity: 0.10)
                    .mask {
                        Image("cp_btn_bg")
                            .resizable(capInsets: EdgeInsets(top: 26, leading: 44, bottom: 26, trailing: 44), resizingMode: .stretch)
                    }
            }
        } else {
            CPChamferShape(cut: 10, corners: [.topLeft, .bottomRight]).fill(fill)
        }
    }
}

/// A játék áramkör-mintája (`fx/textures/other/fx_circuit_y_tile`,
/// fehér nyomvonalak fekete alapon) csempézve, screen-keveréssel:
/// a fekete eltűnik, csak a halvány nyomvonalak maradnak az áttetsző
/// gomb-/panel-alapon — ahogy a játék menü-elemein is minta ül a
/// sötét, áttetsző háttéren. A hívó vágja a saját alakjára.
struct CPGamePattern: View {
    var opacity: Double = 0.08
    var body: some View {
        if UIImage(named: "cp_pattern") != nil {
            Image("cp_pattern")
                .resizable(resizingMode: .tile)
                .blendMode(.screen)
                .opacity(opacity)
                .accessibilityHidden(true)
        }
    }
}

// MARK: - Gomb

/// CP2077-gomb: levágott sarok, nagybetűs, ritkított Rajdhani felirat.
/// - `.primary`: a játék menü-kijelölése — tömör vörös kitöltés, fekete
///   felirat (a sárga a játékban márka-/kiemelőszín, nem gombkitöltés).
/// - `.secondary`: cián körvonal, cián felirat.
/// - `.destructive`: vörös körvonal + halvány vörös arc, vörös felirat.
/// Lenyomva a kitöltés invertál / felvillan, és halk blip szól.
struct CPButtonStyle: ButtonStyle {
    enum Kind { case primary, secondary, destructive }
    var kind: Kind = .primary
    /// Kompakt (ikon / toolbar / sorba tett) gomb: kisebb margó.
    var compact: Bool = false
    var fullWidth: Bool = false
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.colorSchemeContrast) private var contrast

    func makeBody(configuration: Configuration) -> some View {
        let pressed = configuration.isPressed
        let shape = CPChamferShape(cut: compact ? 6 : 10, corners: [.topLeft, .bottomRight])
        let accent: Color = {
            switch kind {
            case .primary: return CyberpunkTheme.red
            case .secondary: return CyberpunkTheme.cyan
            case .destructive: return CyberpunkTheme.red
            }
        }()
        let fg: Color = {
            guard isEnabled else { return CyberpunkTheme.dim }
            switch kind {
            case .primary: return pressed ? CyberpunkTheme.red : Color.black
            default: return pressed ? Color.black : accent
            }
        }()
        let fill: Color = {
            guard isEnabled else { return CyberpunkTheme.panel }
            switch kind {
            case .primary: return pressed ? CyberpunkTheme.panelRaised : CyberpunkTheme.red
            default: return pressed ? accent : accent.opacity(kind == .destructive ? 0.12 : 0.06)
            }
        }()
        return configuration.label
            .font(CyberpunkTheme.font(compact ? .subheadline : .headline, weight: .bold))
            .textCase(.uppercase)
            .tracking(1.2)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .foregroundStyle(fg)
            .padding(.horizontal, compact ? 10 : 20)
            .padding(.vertical, compact ? 6 : 11)
            .frame(maxWidth: fullWidth ? .infinity : nil, minHeight: compact ? 34 : 46)
            .background(CPGameButtonShape(fill: fill))
            .overlay {
                // A játék gombformáján nincs külön körvonal-él: csak ha a
                // textúra hiányzik, rajzolunk saját keretet az alakzatra.
                if UIImage(named: "cp_btn_bg") == nil {
                    shape.strokeBorder(isEnabled ? accent.opacity(contrast == .increased ? 1 : 0.85) : CyberpunkTheme.dim.opacity(0.5), lineWidth: 1)
                }
            }
            .contentShape(shape)
            .onChange(of: pressed) { _, down in
                if down { CPSound.play(.click) }
            }
    }
}

extension ButtonStyle where Self == CPButtonStyle {
    static var cpPrimary: CPButtonStyle { CPButtonStyle(kind: .primary) }
    static var cpSecondary: CPButtonStyle { CPButtonStyle(kind: .secondary) }
    static var cpDestructive: CPButtonStyle { CPButtonStyle(kind: .destructive) }
}

// MARK: - Címkék, fejlécek, elválasztók

/// Apró egyenközű HUD-címke, pl. `[ SUBJ_04 ]`. Nagybetűs, ritkított.
struct CPLabel: View {
    var text: String
    var color: Color = CyberpunkTheme.dim
    var bracketed: Bool = true
    var size: CGFloat = 10

    init(_ text: String, color: Color = CyberpunkTheme.dim, bracketed: Bool = true, size: CGFloat = 10) {
        self.text = text
        self.color = color
        self.bracketed = bracketed
        self.size = size
    }

    var body: some View {
        Text(bracketed ? "[ \(text.uppercased()) ]" : text.uppercased())
            .font(CyberpunkTheme.mono(size: size, relativeTo: .caption2))
            .tracking(1)
            .foregroundStyle(color)
            .lineLimit(1)
            .accessibilityLabel(text)
    }
}

/// Szekció-fejléc: kis akcent-négyzet + nagybetűs Rajdhani cím + kitöltő
/// vékony vonal + opcionális kód (pl. `04` → `// 04`).
struct CPSectionHeader: View {
    var title: String
    var code: String? = nil
    var accent: Color = CyberpunkTheme.red

    init(_ title: String, code: String? = nil, accent: Color = CyberpunkTheme.red) {
        self.title = title
        self.code = code
        self.accent = accent
    }

    var body: some View {
        HStack(spacing: 8) {
            Rectangle().fill(accent).frame(width: 6, height: 6)
            Text(title.uppercased())
                .font(CyberpunkTheme.font(.subheadline, weight: .bold))
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
                    .font(CyberpunkTheme.mono(size: 10, relativeTo: .caption2))
                    .foregroundStyle(CyberpunkTheme.dim)
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
struct CPDivider: View {
    var color: Color = CyberpunkTheme.red
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

/// `Picker(.segmented)` HUD-párja: egymás melletti levágott sarkú fülek,
/// a kijelölt vörös kitöltésű fekete felirattal, a többi halvány
/// körvonalas. Váltáskor blip.
struct CPSegmentedPicker<Value: Hashable>: View {
    @Binding var selection: Value
    var options: [(value: Value, title: String)]
    var accessibilityTitle: String = ""

    var body: some View {
        HStack(spacing: 4) {
            ForEach(Array(options.enumerated()), id: \.offset) { _, option in
                let on = option.value == selection
                let shape = CPChamferShape(cut: 6, corners: [.topLeft, .bottomRight])
                Button {
                    if !on { CPSound.play(.navigate) }
                    selection = option.value
                } label: {
                    Text(option.title.uppercased())
                        .font(CyberpunkTheme.font(.subheadline, weight: .bold))
                        .tracking(1)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                        .foregroundStyle(on ? Color.black : CyberpunkTheme.text.opacity(0.75))
                        .frame(maxWidth: .infinity, minHeight: 36)
                        .padding(.horizontal, 4)
                        .background(shape.fill(on ? CyberpunkTheme.red : CyberpunkTheme.panel))
                        .overlay(shape.strokeBorder(on ? CyberpunkTheme.red : CyberpunkTheme.dim.opacity(0.45), lineWidth: 1))
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
struct CPProgressBar: View {
    var value: Double
    var tint: Color = CyberpunkTheme.yellow
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
struct CPGradeBadge: View {
    /// Számjegy (1–5) — ez dönti el a színt. `nil` = szöveges / ismeretlen.
    var value: Int?
    /// Kiírt szöveg (alapból a szám).
    var text: String? = nil
    var size: CGFloat = 36
    /// Kitöltött (erős) változat: tömör szín, fekete szám.
    var filled: Bool = false

    var body: some View {
        let color = CyberpunkTheme.gradeColor(for: value ?? 0)
        let shape = CPChamferShape(cut: size * 0.22, corners: [.topLeft, .bottomRight])
        Text(text ?? value.map(String.init) ?? "–")
            .font(CyberpunkTheme.display(size: size * 0.62, weight: .bold, relativeTo: .title3))
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
struct CPToastModel: Identifiable, Equatable {
    enum Kind { case info, success, warning, error }
    var id = UUID()
    var title: String
    var message: String? = nil
    var kind: Kind = .info
    var icon: String? = nil
}

struct CPToast: View {
    var model: CPToastModel

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
                CPLabel(Self.code(model.kind), color: accent)
                Text(model.title.uppercased())
                    .font(CyberpunkTheme.font(.headline, weight: .bold))
                    .tracking(1)
                    .foregroundStyle(CyberpunkTheme.text)
                if let message = model.message {
                    Text(message)
                        .font(CyberpunkTheme.font(.subheadline))
                        .foregroundStyle(CyberpunkTheme.text.opacity(0.75))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 10)
        .padding(.trailing, 14)
        .background(CPPanelBackground(accent: accent, fill: CyberpunkTheme.panelRaised, corners: [.bottomRight], cut: 12, showsTab: false))
        .accessibilityElement(children: .combine)
    }

    static func accent(_ kind: CPToastModel.Kind) -> Color {
        switch kind {
        case .info: return CyberpunkTheme.cyan
        case .success: return CyberpunkTheme.green
        case .warning: return CyberpunkTheme.yellow
        case .error: return CyberpunkTheme.red
        }
    }

    static func code(_ kind: CPToastModel.Kind) -> String {
        switch kind {
        case .info: return "INFO"
        case .success: return "OK"
        case .warning: return "WARN"
        case .error: return "ERR"
        }
    }
}

private struct CPToastHost: ViewModifier {
    @Binding var toast: CPToastModel?
    var duration: Double
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content.overlay(alignment: .top) {
            if let t = toast {
                CPToast(model: t)
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                    .transition(reduceMotion ? .opacity : .move(edge: .top).combined(with: .opacity))
                    .id(t.id)
                    .onTapGesture { withAnimation { toast = nil } }
                    .task(id: t.id) {
                        CPSound.play(t.kind == .error ? .error : .toast)
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
    func cpToast(_ toast: Binding<CPToastModel?>, duration: Double = 2.8) -> some View {
        modifier(CPToastHost(toast: toast, duration: duration))
    }
}

// MARK: - Glitch / kromatikus aberráció (csak kiemelésre)

private struct CPChromatic: ViewModifier {
    var amount: CGFloat
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast

    func body(content: Content) -> some View {
        if reduceTransparency || contrast == .increased || amount == 0 {
            content
        } else {
            content
                .background(content.foregroundStyle(CyberpunkTheme.red.opacity(0.7)).offset(x: -amount).accessibilityHidden(true))
                .background(content.foregroundStyle(CyberpunkTheme.cyan.opacity(0.7)).offset(x: amount).accessibilityHidden(true))
        }
    }
}

private struct CPGlitch<T: Equatable>: ViewModifier {
    var trigger: T
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        if reduceMotion {
            content
        } else {
            content.keyframeAnimator(initialValue: CGFloat(0), trigger: trigger) { view, dx in
                view.modifier(CPChromatic(amount: abs(dx))).offset(x: dx * 0.5)
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
        modifier(CPChromatic(amount: amount))
    }

    /// Rövid (~0,27 mp) glitch-rángás, ha `trigger` változik (pl. új jegy,
    /// tabváltás). Reduce Motion mellett nem fut.
    func cpGlitch<T: Equatable>(trigger: T) -> some View {
        modifier(CPGlitch(trigger: trigger))
    }
}

// MARK: - Kapcsoló, beviteli mező

/// Szögletes HUD-kapcsoló: bekapcsolva vörös, kikapcsolva halvány keret.
struct CPToggleStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        let on = configuration.isOn
        HStack(spacing: 10) {
            configuration.label
            Spacer(minLength: 8)
            Button {
                CPSound.play(configuration.isOn ? .valueDown : .valueUp)
                configuration.isOn.toggle()
            } label: {
                ZStack(alignment: on ? .trailing : .leading) {
                    CPChamferShape(cut: 5, corners: [.topLeft, .bottomRight])
                        .fill(on ? CyberpunkTheme.red.opacity(0.18) : CyberpunkTheme.panel)
                        .overlay(CPChamferShape(cut: 5, corners: [.topLeft, .bottomRight])
                            .strokeBorder(on ? CyberpunkTheme.red : CyberpunkTheme.dim.opacity(0.6), lineWidth: 1))
                    Rectangle()
                        .fill(on ? CyberpunkTheme.red : CyberpunkTheme.dim)
                        .frame(width: 18, height: 18)
                        .padding(4)
                }
                .frame(width: 52, height: 28)
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

private struct CPInputFrame: ViewModifier {
    func body(content: Content) -> some View {
        let shape = CPChamferShape(cut: 6, corners: [.bottomRight])
        content
            .font(CyberpunkTheme.font(.body))
            .foregroundStyle(CyberpunkTheme.text)
            .tint(CyberpunkTheme.cyan)
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(shape.fill(CyberpunkTheme.bgDeep))
            .overlay(shape.strokeBorder(CyberpunkTheme.cyan.opacity(0.6), lineWidth: 1))
    }
}

extension View {
    /// Szövegmező HUD-kerete (mély háttér, cián körvonal, cián kurzor).
    func cpInput() -> some View { modifier(CPInputFrame()) }
}

// MARK: - Lista / Form sorok

extension CyberpunkTheme {
    /// Sor-háttér behúzása: az insetGrouped lista a szekciót ~30 pt-os
    /// lekerekítéssel vágja — a levágott sarkú panel ennyivel beljebb ül,
    /// így a vágás sosem éri el (ugyanaz a mérés, mint a `McRowPanel`-nél).
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
struct CPRowBackground: View {
    var accent: Color = CyberpunkTheme.red
    var fill: Color = CyberpunkTheme.panel
    var body: some View {
        ZStack {
            CPChamferShape(cut: 10, corners: .diagonal).fill(CyberpunkTheme.panel)
            CPPanelBackground(accent: accent, fill: fill, corners: .diagonal, cut: 10, showsTab: false)
        }
        .padding(.horizontal, CyberpunkTheme.rowHorizontalInset)
        .padding(.vertical, CyberpunkTheme.rowVerticalInset)
    }
}

extension View {
    /// Teljes HUD-sor stílus List/Form sorra: panel-háttér + rejtett
    /// elválasztó + a panelhez igazított margó. Csak Cyberpunk-ágban hívd
    /// (vagy használd a skin-érzékeny `mcListRow` / `summitRowSurface`-t,
    /// amelyek Cyberpunkban ezt adják).
    func cpListRow(accent: Color = CyberpunkTheme.red, fill: Color = CyberpunkTheme.panel, insets: EdgeInsets? = nil) -> some View {
        self.listRowBackground(CPRowBackground(accent: accent, fill: fill))
            .listRowSeparator(.hidden)
            .listRowInsets(CyberpunkTheme.rowInsets(insets))
    }

    /// List/Form/ScrollView mögé a Night City-háttér (rejtett rendszer-
    /// háttérrel).
    func cpListChrome() -> some View {
        self.scrollContentBackground(.hidden)
            .background { CPBackdrop() }
    }
}

/// `Section("Cím") { … }` HUD-párja: `CPSectionHeader` fejléc, HUD-sorok.
struct CPFormSection<Content: View>: View {
    var title: String
    var code: String? = nil
    var accent: Color = CyberpunkTheme.red
    @ViewBuilder var content: () -> Content

    var body: some View {
        Section {
            content().cpListRow(accent: accent)
        } header: {
            CPSectionHeader(title, code: code, accent: accent)
        }
    }
}

// MARK: - Hangok (igazi Cyberpunk 2077 UI-hangok)

/// A játék saját UI-hangjai, a saját Cyberpunk 2077-telepítésből
/// kinyerve (Wwise-esemény → `.wem` → AAC, Data Setként az asset
/// catalog `Cyberpunk/` mappájában — ahogy a Minecraft-hangok is a
/// játékból jönnek). Szintetizált utánzat nincs: ha egy asset hiányzik,
/// a hang néma marad.
/// `.ambient` audio-session: ha a telefon némítva van (oldalsó némító
/// kapcsoló), az app sem csipog, és más app zenéjét sem állítja le.
/// Csak Cyberpunk-skinben szól.
enum CPSound: String, CaseIterable {
    /// Gomb-lenyomás a játék menüiben (`ui_menu_onpress`) — a stílusos
    /// (CPButtonStyle) gombok hangja.
    case click = "cp_snd_click"
    /// Rövid egérkattanás (`ui_menu_mouse_click`) — a stílus nélküli,
    /// hétköznapi koppintások hangja (a gyökér-gombstílus adja).
    case mouseClick = "cp_snd_mouseclick"
    /// Fülváltás a játék menüiben (`ui_gui_tab_change`) — a dockon ez szól.
    case tab = "cp_snd_tab"
    /// Visszalépés / menü-zárás (`ui_menu_close`) — a VISSZA gomb hangja.
    case back = "cp_snd_back"
    /// Érték fel (`ui_menu_value_up`) — kapcsoló be, léptetés fel.
    case valueUp = "cp_snd_valueup"
    /// Érték le (`ui_menu_value_down`) — kapcsoló ki, léptetés le.
    case valueDown = "cp_snd_valuedown"
    /// Navigáció választóban (`ui_phone_navigation`) — szegmens- és
    /// belső választók hangja, nem a docké.
    case navigate = "cp_snd_navigate"
    /// Pozitív visszaigazolás (`ui_positive`).
    case confirm = "cp_snd_confirm"
    /// Negatív visszaigazolás / hiba (`ui_generic_set_01_negative`).
    case error = "cp_snd_error"
    /// Értesítés érkezett (`ui_phone_sms`).
    case toast = "cp_snd_toast"
    /// Glitch (jegyzet-ünneplés, `ui_splash_screen_glitch`).
    case glitch = "cp_snd_glitch"
    /// Braindance-belépés (`vfx_fullscreen_braindance_entering`, a játék
    /// két rétege együtt, 3,4 mp-re vágva) — a téma kiválasztásakor és a
    /// boot-átmenet alatt szól.
    case braindance = "cp_snd_braindance"

    /// Hangonként kis lejátszó-készlet (mint a `McSound`-nál): gyors
    /// egymásutánban a hangok átfedhetnek, nem vágják el egymást.
    private static var pool: [CPSound: [AVAudioPlayer]] = [:]
    private static var sessionReady = false
    private static let poolSize = 3
    private static var lastPlay: [CPSound: CFTimeInterval] = [:]

    /// Lejátszás (Cyberpunk-skinen kívül néma). Ugyanaz a hang 60 ms-on
    /// belül nem indul kétszer (gombstílus + akció egy koppintásra).
    static func play(_ sound: CPSound, volume: Float = 1) {
        guard CyberpunkTheme.isActive else { return }
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

    /// Előmelegítés (Cyberpunk-skin indulásakor / bekapcsolásakor): a
    /// session és a gyakori hangok lejátszója előre elkészül, hogy az
    /// első koppintás (és a boot-glitch) ne akkor építkezzen.
    static func warmUp() {
        guard CyberpunkTheme.isActive else { return }
        DispatchQueue.main.async {
            guard CyberpunkTheme.isActive, prepareSession() else { return }
            for sound in [CPSound.click, .tab, .glitch] where (pool[sound] ?? []).isEmpty {
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
        case .braindance: return 0.8
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
            print("CPSound: audio session hiba: \(error)")
            #endif
        }
        return sessionReady
    }

    private static func makePlayer(_ sound: CPSound) -> AVAudioPlayer? {
        guard let asset = NSDataAsset(name: sound.rawValue) else {
            #if DEBUG
            print("CPSound: hiányzó hang-asset: \(sound.rawValue)")
            #endif
            return nil
        }
        do {
            let player = try AVAudioPlayer(data: asset.data)
            player.prepareToPlay()
            return player
        } catch {
            #if DEBUG
            print("CPSound: dekódolási hiba (\(sound.rawValue)): \(error)")
            #endif
            return nil
        }
    }
}

/// Cyberpunkban minden stílus nélküli gomb rövid egérkattanást ad (az
/// app gyökerére tett `McClickButtonStyle` mintájára — azt ki is
/// egészíti: a kettő skinje kizárja egymást, mindkét `play` némán tér
/// vissza a másik skinben). Nem a stílusos gombok `onpress` hangja:
/// a hétköznapi koppintás halkabb és rövidebb.
struct CPClickButtonStyle: PrimitiveButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        Button(role: configuration.role) {
            CPSound.play(.mouseClick)
            McSound.play(.click)
            configuration.trigger()
        } label: {
            configuration.label
        }
        .buttonStyle(.automatic)
    }
}

// MARK: - Belépő „boot" átmenet (skinváltáskor)

extension CyberpunkTheme {
    /// A felület-választó ezt postolja, amikor a user Cyberpunkra vált —
    /// a gyökér (ContentView) erre egyszer lejátssza a `CPBootOverlay`-t.
    /// (Távoli szinkronból érkező skinváltásra szándékosan nem fut.)
    static let bootRequest = Notification.Name("summit.cyberpunk.boot")
}

/// Belépő átmenet Cyberpunkra váltáskor: az EREDETI játékbeli
/// braindance-belépés videón, nem rekonstrukció. A játék effektje
/// engine worldEffect/particle (`p_braindance_entering`), SwiftUI-ban
/// nem játszható le és videóra sem renderelhető ki, ezért a jelenet
/// egy gameplay-felvételből kivágott szakasza fut: `cp_braindance.mp4`
/// a Resourcesban (Cyberpunk 2077 gameplay, a Judy-féle furgonos
/// braindance-belépés fehér vakítása, 571,5–574,9 mp a forrásban,
/// 3,4 mp-re vágva, néma, 720p — lásd a commit-leírást a forrásért).
/// A videó néma: alatta az eredeti braindance-belépő hang szól
/// (`CPSound.braindance`, 3,4 mp), a kettő egyszerre indul, így a
/// kép és a hang végig szinkronban van; a videó utolsó (fehér)
/// képkockájáról az overlay elhalványulása adja a lecsengést.
/// Nincs logó, felirat, sáv vagy keret a videón és körülötte sem,
/// nem fogja meg az érintést. Ha a videófájl valamiért hiányozna a
/// bundle-ből, rekonstrukció helyett sima fekete kitartás fut a hang
/// hosszáig. Reduce Motion mellett nincs videó és villanás
/// (fényérzékenység!): csak rövid fekete átmenet, a hang halkabban
/// szól (a hang nem villog, de így az egész boot visszafogottabb).
struct CPBootOverlay: View {
    var onFinish: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var opacity: Double = 1
    @State private var player: AVPlayer?

    var body: some View {
        ZStack {
            Color.black
            if !reduceMotion, let player {
                CPBootVideoView(player: player)
            }
        }
        .ignoresSafeArea()
        .opacity(opacity)
        .allowsHitTesting(false)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Cyberpunk felület bekapcsolva")
        .task { await run() }
    }

    private func run() async {
        if reduceMotion {
            // Fényérzékenység: semmi villanás/videó, csak nyugodt
            // átmenet; a belépő hang halkabban marad meg.
            CPSound.play(.braindance, volume: 0.5)
            try? await Task.sleep(for: .milliseconds(700))
            withAnimation(.easeOut(duration: 0.3)) { opacity = 0 }
            try? await Task.sleep(for: .milliseconds(320))
            onFinish()
            return
        }
        // A videó és az eredeti belépő hang egyszerre indul (3,4 mp).
        if let url = Bundle.main.url(forResource: "cp_braindance", withExtension: "mp4") {
            let p = AVPlayer(url: url)
            p.isMuted = true
            player = p
            CPSound.play(.braindance)
            p.play()
        } else {
            // Nincs videó a bundle-ben: fekete kitartás a hang hosszáig.
            CPSound.play(.braindance)
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
private struct CPBootVideoView: UIViewRepresentable {
    let player: AVPlayer

    func makeUIView(context: Context) -> CPPlayerLayerView {
        let view = CPPlayerLayerView()
        view.playerLayer.player = player
        view.playerLayer.videoGravity = .resizeAspectFill
        return view
    }

    func updateUIView(_ uiView: CPPlayerLayerView, context: Context) {
        uiView.playerLayer.player = player
    }
}

private final class CPPlayerLayerView: UIView {
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
