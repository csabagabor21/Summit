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
        shape.fill(fill)
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

/// Teljes képernyős Night City-háttér: majdnem fekete alap, a sarkokban
/// halvány vörös és cián derengés, finom raszter-rács és scanline.
/// Statikus (nincs TimelineView / animáció): a Canvas csak méretváltáskor
/// rajzol újra. Reduce Transparency mellett tömör háttér, emelt
/// kontrasztnál rács/derengés nélkül.
struct CPBackdrop: View {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        if reduceTransparency || contrast == .increased {
            CyberpunkTheme.bg.ignoresSafeArea()
        } else {
            ZStack {
                CyberpunkTheme.bg
                RadialGradient(colors: [CyberpunkTheme.red.opacity(0.16), .clear],
                               center: .topLeading, startRadius: 0, endRadius: 420)
                RadialGradient(colors: [CyberpunkTheme.cyan.opacity(0.10), .clear],
                               center: .bottomTrailing, startRadius: 0, endRadius: 460)
                CPGridLayer()
                    .drawingGroup()
            }
            .ignoresSafeArea()
            .accessibilityHidden(true)
        }
    }
}

/// Raszter-rács (40 pt) + scanline (3 pt) egyetlen statikus Canvasban.
private struct CPGridLayer: View, Equatable {
    var body: some View {
        Canvas(rendersAsynchronously: true) { ctx, size in
            var scan = Path()
            var y: CGFloat = 0
            while y < size.height {
                scan.addRect(CGRect(x: 0, y: y, width: size.width, height: 1))
                y += 3
            }
            ctx.fill(scan, with: .color(Color.white.opacity(0.018)))
            var grid = Path()
            var x: CGFloat = 0
            while x < size.width {
                grid.addRect(CGRect(x: x, y: 0, width: 0.5, height: size.height))
                x += 40
            }
            y = 0
            while y < size.height {
                grid.addRect(CGRect(x: 0, y: y, width: size.width, height: 0.5))
                y += 40
            }
            ctx.fill(grid, with: .color(CyberpunkTheme.cyan.opacity(0.045)))
        }
    }
}

// MARK: - Gomb

/// CP2077-gomb: levágott sarok, nagybetűs, ritkított Rajdhani felirat.
/// - `.primary`: sárga kitöltés, fekete felirat (a játék fő akció-gombja).
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
            case .primary: return CyberpunkTheme.yellow
            case .secondary: return CyberpunkTheme.cyan
            case .destructive: return CyberpunkTheme.red
            }
        }()
        let fg: Color = {
            guard isEnabled else { return CyberpunkTheme.dim }
            switch kind {
            case .primary: return pressed ? CyberpunkTheme.yellow : Color.black
            default: return pressed ? Color.black : accent
            }
        }()
        let fill: Color = {
            guard isEnabled else { return CyberpunkTheme.panel }
            switch kind {
            case .primary: return pressed ? CyberpunkTheme.panelRaised : CyberpunkTheme.yellow
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
            .background(shape.fill(fill))
            .overlay(shape.strokeBorder(isEnabled ? accent.opacity(contrast == .increased ? 1 : 0.85) : CyberpunkTheme.dim.opacity(0.5), lineWidth: 1))
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
            Rectangle().fill(accent.opacity(0.35)).frame(height: 1)
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
/// a kijelölt sárga kitöltésű fekete felirattal, a többi halvány
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
                    if !on { CPSound.play(.tab) }
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
                        .background(shape.fill(on ? CyberpunkTheme.yellow : CyberpunkTheme.panel))
                        .overlay(shape.strokeBorder(on ? CyberpunkTheme.yellow : CyberpunkTheme.dim.opacity(0.45), lineWidth: 1))
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

/// Szögletes HUD-kapcsoló: bekapcsolva sárga, kikapcsolva halvány keret.
struct CPToggleStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        let on = configuration.isOn
        HStack(spacing: 10) {
            configuration.label
            Spacer(minLength: 8)
            Button {
                CPSound.play(.click)
                configuration.isOn.toggle()
            } label: {
                ZStack(alignment: on ? .trailing : .leading) {
                    CPChamferShape(cut: 5, corners: [.topLeft, .bottomRight])
                        .fill(on ? CyberpunkTheme.yellow.opacity(0.18) : CyberpunkTheme.panel)
                        .overlay(CPChamferShape(cut: 5, corners: [.topLeft, .bottomRight])
                            .strokeBorder(on ? CyberpunkTheme.yellow : CyberpunkTheme.dim.opacity(0.6), lineWidth: 1))
                    Rectangle()
                        .fill(on ? CyberpunkTheme.yellow : CyberpunkTheme.dim)
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

// MARK: - Hangok (procedurálisan szintetizált blipek)

/// UI-hangok, futásidőben generált PCM-pufferekből (nincs játék-asset).
/// `.ambient` audio-session: a némító kapcsoló elnémítja, más app zenéjét
/// nem állítja le. Csak Cyberpunk-skinben szól.
enum CPSound: CaseIterable {
    /// Rövid, magas blip (gomb-lenyomás).
    case click
    /// Dupla blip (fül-/szegmensváltás).
    case tab
    /// Emelkedő csipogás (megerősítés, mentés).
    case confirm
    /// Mély, kettős zúgás (hiba).
    case error
    /// Két hangú „adat érkezett" (toast).
    case toast
    /// Zajos, bitzúzott reccs (glitch-kiemelés).
    case glitch

    private static let sampleRate: Double = 44_100
    private static var engine: AVAudioEngine?
    private static var players: [AVAudioPlayerNode] = []
    private static var nextPlayer = 0
    private static var buffers: [CPSound: AVAudioPCMBuffer] = [:]
    private static var format: AVAudioFormat?
    private static var lastPlay: [CPSound: CFTimeInterval] = [:]
    private static var failed = false

    /// Lejátszás (Cyberpunk-skinen kívül néma). Ugyanaz a hang 60 ms-on
    /// belül nem indul kétszer (gombstílus + akció egy koppintásra).
    static func play(_ sound: CPSound, volume: Float = 1) {
        guard CyberpunkTheme.isActive, !failed else { return }
        let now = CACurrentMediaTime()
        if let last = lastPlay[sound], now - last < 0.06 { return }
        lastPlay[sound] = now
        guard let engine = prepareEngine(), let buffer = buffer(for: sound) else { return }
        if !engine.isRunning {
            do { try engine.start() } catch { return }
        }
        let player = players[nextPlayer]
        nextPlayer = (nextPlayer + 1) % players.count
        player.volume = volume * sound.gain
        player.scheduleBuffer(buffer, at: nil, options: .interrupts, completionHandler: nil)
        if !player.isPlaying { player.play() }
    }

    private var gain: Float {
        switch self {
        case .click: return 0.35
        case .tab: return 0.45
        case .confirm, .toast: return 0.5
        case .error: return 0.55
        case .glitch: return 0.3
        }
    }

    private static func prepareEngine() -> AVAudioEngine? {
        if let engine { return engine }
        do {
            try AVAudioSession.sharedInstance().setCategory(.ambient, mode: .default, options: [.mixWithOthers])
            let e = AVAudioEngine()
            guard let fmt = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1) else {
                failed = true
                return nil
            }
            var nodes: [AVAudioPlayerNode] = []
            for _ in 0..<4 {
                let p = AVAudioPlayerNode()
                e.attach(p)
                e.connect(p, to: e.mainMixerNode, format: fmt)
                nodes.append(p)
            }
            e.prepare()
            try e.start()
            engine = e
            players = nodes
            format = fmt
            return e
        } catch {
            #if DEBUG
            print("CPSound: audio-engine hiba: \(error)")
            #endif
            failed = true
            return nil
        }
    }

    private static func buffer(for sound: CPSound) -> AVAudioPCMBuffer? {
        if let b = buffers[sound] { return b }
        guard let format else { return nil }
        let samples = synthesize(sound)
        guard let buf = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(samples.count)),
              let ch = buf.floatChannelData?[0] else { return nil }
        buf.frameLength = AVAudioFrameCount(samples.count)
        for i in 0..<samples.count { ch[i] = samples[i] }
        buffers[sound] = buf
        return buf
    }

    /// Hang-receptek: rövid szinusz/négyszög-blipek exponenciális
    /// lecsengéssel, 1 ms-os felfutással (kattanásmentes eleje).
    private static func synthesize(_ sound: CPSound) -> [Float] {
        let sr = sampleRate
        func tone(_ dur: Double, f0: Double, f1: Double? = nil, decay: Double, square: Double = 0, start: Double = 0, into out: inout [Float]) {
            let n = Int(dur * sr), off = Int(start * sr)
            if out.count < off + n { out += [Float](repeating: 0, count: off + n - out.count) }
            var phase = 0.0
            for i in 0..<n {
                let t = Double(i) / sr
                let f = f1.map { f0 + ($0 - f0) * (t / dur) } ?? f0
                phase += 2 * .pi * f / sr
                let s = sin(phase)
                let sq = s >= 0 ? 1.0 : -1.0
                let wave = s * (1 - square) + sq * square
                let env = min(1, t / 0.001) * exp(-t / decay)
                out[off + i] += Float(wave * env)
            }
        }
        var out: [Float] = []
        switch sound {
        case .click:
            tone(0.022, f0: 2600, decay: 0.006, square: 0.25, into: &out)
        case .tab:
            tone(0.03, f0: 1900, decay: 0.008, square: 0.2, into: &out)
            tone(0.035, f0: 2850, decay: 0.009, square: 0.2, start: 0.038, into: &out)
        case .confirm:
            tone(0.12, f0: 900, f1: 2300, decay: 0.05, square: 0.15, into: &out)
        case .error:
            tone(0.08, f0: 170, decay: 0.05, square: 0.6, into: &out)
            tone(0.1, f0: 140, decay: 0.06, square: 0.6, start: 0.1, into: &out)
        case .toast:
            tone(0.08, f0: 1320, decay: 0.03, square: 0.1, into: &out)
            tone(0.14, f0: 1980, decay: 0.05, square: 0.1, start: 0.07, into: &out)
        case .glitch:
            // Determinisztikus LCG-zaj, 8-asával tartva (bitzúzás-hatás).
            let n = Int(0.09 * sr)
            var seed: UInt32 = 0x9E3779B9
            var held: Float = 0
            out = [Float](repeating: 0, count: n)
            for i in 0..<n {
                if i % 8 == 0 {
                    seed = seed &* 1_664_525 &+ 1_013_904_223
                    held = Float(Int32(bitPattern: seed)) / Float(Int32.max)
                }
                let t = Double(i) / sr
                out[i] = held * Float(min(1, t / 0.001) * exp(-t / 0.03))
            }
        }
        // Csúcs-normalizálás 0,9-re (a hangerőt a `gain` adja).
        let peak = out.map { abs($0) }.max() ?? 1
        if peak > 0 { out = out.map { $0 / peak * 0.9 } }
        return out
    }
}

/// Cyberpunkban minden stílus nélküli gomb halk blipet ad (az app gyökerére
/// tett `McClickButtonStyle` mintájára — azt ki is egészíti: a kettő
/// skinje kizárja egymást, mindkét `play` némán tér vissza a másik skinben).
struct CPClickButtonStyle: PrimitiveButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        Button(role: configuration.role) {
            CPSound.play(.click)
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

/// Rövid (~1 mp) belépő átmenet Cyberpunkra váltáskor: fekete képernyő
/// scanline-nal, végigfutó fényes pásztázó sáv, kromatikusan elcsúszó
/// „NIGHT CITY" felirat, töltődő HUD-sáv, glitch-reccs és megerősítő blip,
/// majd elhalványul. Nem fogja meg az érintést. Reduce Motion mellett nincs
/// mozgás/glitch: a felirat fél mp-ig áll, aztán elhalványul.
struct CPBootOverlay: View {
    var onFinish: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var scan: CGFloat = 0
    @State private var opacity: Double = 1
    @State private var glitchTick = 0

    var body: some View {
        GeometryReader { geo in
            ZStack {
                CPBackdrop()
                if !reduceMotion {
                    LinearGradient(colors: [.clear, CyberpunkTheme.cyan.opacity(0.35), CyberpunkTheme.yellow.opacity(0.9),
                                            CyberpunkTheme.cyan.opacity(0.35), .clear],
                                   startPoint: .top, endPoint: .bottom)
                        .frame(height: 46)
                        .position(x: geo.size.width / 2, y: scan * (geo.size.height + 46) - 23)
                        .blendMode(.screen)
                }
                VStack(spacing: 12) {
                    CPLabel("SYS_BOOT // NC-2077", color: CyberpunkTheme.red)
                    Text("NIGHT CITY")
                        .font(CyberpunkTheme.display(size: 46, weight: .bold, relativeTo: .largeTitle))
                        .tracking(4)
                        .foregroundStyle(CyberpunkTheme.yellow)
                        .cpChromatic(reduceMotion ? 0 : 2)
                        .cpGlitch(trigger: glitchTick)
                    CPLabel("NEURAL LINK ESTABLISHED", color: CyberpunkTheme.cyan, bracketed: false)
                    ZStack(alignment: .leading) {
                        Rectangle().fill(CyberpunkTheme.yellow.opacity(0.15))
                        Rectangle().fill(CyberpunkTheme.yellow)
                            .scaleEffect(x: max(0.001, scan), anchor: .leading)
                    }
                    .frame(width: 200, height: 4)
                }
                .position(x: geo.size.width / 2, y: geo.size.height / 2)
            }
        }
        .ignoresSafeArea()
        .opacity(opacity)
        .allowsHitTesting(false)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Cyberpunk felület bekapcsolva")
        .task {
            CPSound.play(.glitch)
            if reduceMotion {
                scan = 1
                try? await Task.sleep(for: .milliseconds(550))
                withAnimation(.easeOut(duration: 0.25)) { opacity = 0 }
                try? await Task.sleep(for: .milliseconds(260))
                onFinish()
                return
            }
            glitchTick += 1
            withAnimation(.easeInOut(duration: 0.75)) { scan = 1 }
            try? await Task.sleep(for: .milliseconds(760))
            CPSound.play(.confirm)
            glitchTick += 1
            try? await Task.sleep(for: .milliseconds(180))
            withAnimation(.easeOut(duration: 0.3)) { opacity = 0 }
            try? await Task.sleep(for: .milliseconds(320))
            onFinish()
        }
    }
}
