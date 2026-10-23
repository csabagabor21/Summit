import SwiftUI

struct ContentView: View {
    @EnvironmentObject var session: SessionStore
    @EnvironmentObject var theme: ThemeStore
    @EnvironmentObject var analytics: AnalyticsStore

    var body: some View {
        Group {
            if let cat = theme.sizeCategoryOverride {
                content.environment(\.sizeCategory, cat)
            } else {
                content
            }
        }
        // Minecraft-skin: a kifejezett betűstílus nélküli szövegek (szekció-
        // fejlécek, sima gombfeliratok, mezők) is Monocraftban jelennek meg.
        // Summitban nil = a rendszer alap-környezete, semmi nem változik.
        .environment(\.font, theme.isMinecraft ? MinecraftTheme.font(.body) : nil)
        .animation(SummitMotion.gentle, value: session.isLoggedIn)
        // Skin-váltáskor a nav/tab-sávok betűje is átvált (UIKit-appearance).
        .onChange(of: theme.skin) { _, s in
            MinecraftTheme.applyChromeAppearance(minecraft: s == .minecraft)
        }
        // Continuity (Handoff): a másik eszközön álló Summit átveszi
        // az aktuális tabot + pozíciót (lásd HandoffCenter.handle).
        .onContinueUserActivity(SummitHandoff.activityType) { activity in
            HandoffCenter.handle(activity)
        }
    }

    private var content: some View {
        Group {
            if session.isLoggedIn {
                MainTabView()
                    .transition(.opacity.combined(with: .scale(scale: 0.98)))
                    // Bejelentkezés utáni teljes képernyős választó: amíg nincs
                    // döntés, ez jön fel — konkrét listával, azonnali ki/bekapcsolással.
                    .fullScreenCover(isPresented: Binding(
                        get: { !analytics.hasChosen },
                        set: { if !$0 { analytics.choose(enabled: analytics.isEnabled) } }
                    )) {
                        AnalyticsConsentView()
                            .environmentObject(analytics)
                    }
            } else {
                LoginView()
                    .transition(.opacity)
            }
        }
    }
}

// MARK: - Minecraft-skin segédek
// A kit (MinecraftKit) általános elemein túli, a képernyők közös építőkockái.
// Mind skin-érzékeny: Summitban a gyári vezérlőt adják vissza változatlanul.

/// Mező-helyőrző: Minecraftban a fekete mezőn is olvasható szürke szöveg
/// (a rendszer-helyőrző sötét lenne), Summitban a gyári.
func skinPrompt(_ text: String) -> Text {
    MinecraftTheme.isActive ? Text(text).foregroundStyle(Color(hex: 0x7A7A7A)) : Text(text)
}

/// Egy választható érték a szegmens- és menüválasztókhoz.
struct SkinOption<Value: Hashable>: Identifiable {
    var value: Value
    var title: String
    var icon: String? = nil
    var id: Value { value }
}

/// Gomb-stílus a szegmensekhez: a kijelölt elem a `button_highlighted`
/// (fehér keretes) sprite, sárga felirattal — mint a játék választó-gombjai.
private struct McSegmentStyle: ButtonStyle {
    var selected: Bool
    func makeBody(configuration: Configuration) -> some View {
        let hi = selected || configuration.isPressed
        configuration.label
            .font(MinecraftTheme.font(.callout))
            .foregroundStyle(selected ? Color(hex: 0xFFFF55) : .white)
            .shadow(color: Color(hex: 0x3F3F3F), radius: 0, x: MinecraftTheme.px / 1.5, y: MinecraftTheme.px / 1.5)
            .padding(.horizontal, 6)
            .padding(.vertical, 8)
            .frame(minHeight: 40)
            .background(McNineSlice(hi ? "mc_widget_button_hi" : "mc_widget_button", border: 3))
            .contentShape(Rectangle())
    }
}

/// Gombnak látszó felirat-keret (nem ButtonStyle: Menu / DatePicker
/// címkéjén is használható, ahol a rendszer saját stílust húzna rá).
private struct McButtonLook: ViewModifier {
    func body(content: Content) -> some View {
        content
            .font(MinecraftTheme.font(.body))
            .foregroundStyle(.white)
            .shadow(color: Color(hex: 0x3F3F3F), radius: 0, x: MinecraftTheme.px / 1.5, y: MinecraftTheme.px / 1.5)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .frame(minHeight: 36)
            .background(McNineSlice("mc_widget_button", border: 3))
            .contentShape(Rectangle())
    }
}

/// Szegmentált választó: Summitban a gyári `.segmented` Picker,
/// Minecraftban egymás melletti kő-gombok (a kijelölt kiemelve).
struct SkinSegmented<Value: Hashable>: View {
    var title: String = ""
    @Binding var selection: Value
    var options: [SkinOption<Value>]

    var body: some View {
        if MinecraftTheme.isActive {
            HStack(spacing: MinecraftTheme.px) {
                ForEach(options) { opt in
                    let on = selection == opt.value
                    Button { selection = opt.value } label: {
                        HStack(spacing: 6) {
                            if let icon = opt.icon { SkinIcon(icon, size: 18) }
                            Text(opt.title).lineLimit(1).minimumScaleFactor(0.6)
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(McSegmentStyle(selected: on))
                    .accessibilityAddTraits(on ? .isSelected : [])
                }
            }
        } else {
            Picker(title, selection: $selection) {
                ForEach(options) { opt in
                    if let icon = opt.icon {
                        Label(opt.title, systemImage: icon).tag(opt.value)
                    } else {
                        Text(opt.title).tag(opt.value)
                    }
                }
            }
            .pickerStyle(.segmented)
        }
    }
}

/// Lenyíló választó: Summitban a gyári Picker (`.menu` vagy
/// `.navigationLink`), Minecraftban kő-gomb a kiválasztott értékkel
/// (a lenyíló lista maga a rendszer menüje).
struct SkinMenuPicker<Value: Hashable>: View {
    var title: String
    @Binding var selection: Value
    var options: [SkinOption<Value>]
    var navigationStyle = false

    var body: some View {
        if MinecraftTheme.isActive {
            HStack(spacing: 8) {
                Text(title)
                Spacer(minLength: 8)
                Menu {
                    ForEach(options) { opt in
                        Button(opt.title) { selection = opt.value }
                    }
                } label: {
                    HStack(spacing: 8) {
                        Text(options.first { $0.value == selection }?.title ?? "—").lineLimit(1)
                        McGlyph(kind: .chevronDown, size: 14)
                    }
                    .modifier(McButtonLook())
                }
                .buttonStyle(.plain)
            }
        } else if navigationStyle {
            Picker(title, selection: $selection) {
                ForEach(options) { Text($0.title).tag($0.value) }
            }
            .pickerStyle(.navigationLink)
        } else {
            Picker(title, selection: $selection) {
                ForEach(options) { Text($0.title).tag($0.value) }
            }
            .pickerStyle(.menu)
        }
    }
}

/// Csúszka: Summitban a gyári `Slider`, Minecraftban az igazi
/// `widget/slider` sötét sáv + `slider_handle` fogantyú.
struct SkinSlider: View {
    @Binding var value: Double
    var range: ClosedRange<Double>
    var step: Double

    var body: some View {
        if MinecraftTheme.isActive {
            McSliderControl(value: $value, range: range, step: step)
        } else {
            Slider(value: $value, in: range, step: step)
        }
    }
}

private struct McSliderControl: View {
    @Binding var value: Double
    var range: ClosedRange<Double>
    var step: Double
    @State private var dragging = false

    var body: some View {
        GeometryReader { geo in
            let handleW = 8 * MinecraftTheme.px
            let travel = max(1, geo.size.width - handleW)
            let frac = (value - range.lowerBound) / (range.upperBound - range.lowerBound)
            ZStack(alignment: .leading) {
                McNineSlice("mc_widget_slider", border: 1)
                McNineSlice(dragging ? "mc_widget_slider_handle_hi" : "mc_widget_slider_handle",
                            top: 2, left: 2, bottom: 3, right: 2)
                    .frame(width: handleW)
                    .offset(x: CGFloat(min(1, max(0, frac))) * travel)
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { g in
                        dragging = true
                        let f = min(1, max(0, Double((g.location.x - handleW / 2) / travel)))
                        let raw = range.lowerBound + f * (range.upperBound - range.lowerBound)
                        let snapped = (raw / step).rounded() * step
                        value = min(range.upperBound, max(range.lowerBound, snapped))
                    }
                    .onEnded { _ in dragging = false }
            )
        }
        .frame(height: 12 * MinecraftTheme.px)
        .accessibilityElement()
        .accessibilityValue(String(format: "%.2f", value))
        .accessibilityAdjustableAction { dir in
            let next = value + (dir == .increment ? step : -step)
            value = min(range.upperBound, max(range.lowerBound, next))
        }
    }
}

/// Léptető: Summitban a gyári `Stepper`, Minecraftban −/+ kő-gombok.
struct SkinStepper: View {
    var title: String
    @Binding var value: Int
    var range: ClosedRange<Int>

    var body: some View {
        if MinecraftTheme.isActive {
            HStack(spacing: 8) {
                Text(title)
                Spacer(minLength: 8)
                Button { value = max(range.lowerBound, value - 1) } label: { McGlyph(kind: .minus, size: 16) }
                    .buttonStyle(McButtonStyle(compact: true))
                    .disabled(value <= range.lowerBound)
                    .accessibilityLabel("Csökkentés")
                Button { value = min(range.upperBound, value + 1) } label: { McGlyph(kind: .plus, size: 16) }
                    .buttonStyle(McButtonStyle(compact: true))
                    .disabled(value >= range.upperBound)
                    .accessibilityLabel("Növelés")
            }
            .accessibilityElement(children: .contain)
        } else {
            Stepper(title, value: $value, in: range)
        }
    }
}

/// Dátumválasztó sor: Summitban a gyári kompakt `DatePicker`, Minecraftban
/// kő-gomb a dátummal. A rendszer-naptárat egy átlátszatlanná tett
/// (színszorzóval kioltott) DatePicker nyitja a gomb fölött.
struct SkinDateRow: View {
    var title: String
    @Binding var date: Date
    var minDate: Date? = nil

    var body: some View {
        if MinecraftTheme.isActive {
            HStack(spacing: 8) {
                Text(title)
                Spacer(minLength: 8)
                Text(date.formatted(date: .abbreviated, time: .omitted))
                    .modifier(McButtonLook())
                    .overlay { picker(label: false).colorMultiply(.clear) }
            }
        } else {
            picker(label: true)
        }
    }

    @ViewBuilder
    private func picker(label: Bool) -> some View {
        if let minDate {
            if label { DatePicker(title, selection: $date, in: minDate..., displayedComponents: .date) }
            else { DatePicker(title, selection: $date, in: minDate..., displayedComponents: .date).labelsHidden() }
        } else {
            if label { DatePicker(title, selection: $date, displayedComponents: .date) }
            else { DatePicker(title, selection: $date, displayedComponents: .date).labelsHidden() }
        }
    }
}

/// Betöltésjelző: Summitban a gyári `ProgressView`, Minecraftban három
/// pixelnégyzet, amelyek közül egy világít (léptetve, nem simán forogva).
struct SkinProgress: View {
    var color: Color? = nil

    var body: some View {
        if MinecraftTheme.isActive {
            McPixelSpinner(color: color ?? .primary)
        } else {
            ProgressView()
        }
    }
}

private struct McPixelSpinner: View {
    var color: Color
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.25)) { ctx in
            let phase = reduceMotion ? 0 : Int(ctx.date.timeIntervalSinceReferenceDate / 0.25) % 4
            HStack(spacing: MinecraftTheme.px) {
                ForEach(0..<3, id: \.self) { i in
                    Rectangle()
                        .fill(i == phase ? color : color.opacity(0.28))
                        .frame(width: 2 * MinecraftTheme.px, height: 2 * MinecraftTheme.px)
                }
            }
        }
        .accessibilityLabel("Betöltés")
    }
}

/// Üres állapot: Summitban a gyári `ContentUnavailableView`, Minecraftban
/// nagy item-ikon + pixelbetűs cím és leírás.
struct SkinEmptyState: View {
    var title: String
    var systemImage: String
    var description: Text? = nil

    var body: some View {
        if MinecraftTheme.isActive {
            VStack(spacing: 12) {
                SkinIcon(systemImage, size: 6 * MinecraftTheme.px * 3)
                Text(title).mcTitle().multilineTextAlignment(.center)
                if let description {
                    description
                        .font(MinecraftTheme.font(.callout))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 16)
            .accessibilityElement(children: .combine)
        } else {
            ContentUnavailableView(title, systemImage: systemImage, description: description)
        }
    }
}

/// Állapotjelző pötty: Summitban kör, Minecraftban négyzet.
struct SkinDot: View {
    var color: Color
    var size: CGFloat = 6

    var body: some View {
        if MinecraftTheme.isActive {
            Rectangle().fill(color).frame(width: max(size, MinecraftTheme.px), height: max(size, MinecraftTheme.px))
        } else {
            Circle().fill(color).frame(width: size, height: size)
        }
    }
}

/// Navigációs sor listában: Summitban a gyári `NavigationLink`, Minecraftban
/// a rendszer-nyíl helyett pixel-chevron (a rejtett link adja a koppintást).
struct SkinNavLink<Destination: View, Label: View>: View {
    var destination: () -> Destination
    var label: () -> Label

    init(@ViewBuilder destination: @escaping () -> Destination, @ViewBuilder label: @escaping () -> Label) {
        self.destination = destination
        self.label = label
    }

    var body: some View {
        if MinecraftTheme.isActive {
            ZStack {
                NavigationLink { destination() } label: { EmptyView() }.opacity(0)
                HStack(spacing: 8) {
                    label()
                    McGlyph(kind: .chevronRight, size: 16)
                        .foregroundStyle(.secondary)
                }
            }
        } else {
            NavigationLink { destination() } label: { label() }
        }
    }
}

/// Toolbar-elem skin-érzékenyen: Minecraftban a rendszer Liquid Glass
/// kapszulája nélkül, kő-gombbal; Summitban a gyári elem.
struct SkinToolbarItem<Content: View>: ToolbarContent {
    var placement: ToolbarItemPlacement
    @ViewBuilder var content: () -> Content

    var body: some ToolbarContent {
        ToolbarItem(placement: placement) { content().mcFixedSize().skinToolbarItem() }
            .sharedBackgroundVisibility(MinecraftTheme.isActive ? .hidden : .automatic)
    }
}

extension View {
    /// Minecraftban a gomb kő-gomb (kompakt), Summitban a `.plain` stílus —
    /// a koppintható, saját keret nélküli sorok / csíkok gombjához.
    @ViewBuilder
    func mcButtonOrPlain(compact: Bool = true) -> some View {
        if MinecraftTheme.isActive {
            self.buttonStyle(McButtonStyle(compact: compact))
        } else {
            self.buttonStyle(.plain)
        }
    }

    /// Körvonalas kapszula-gomb felirata: Summitban akcentszín + vékony
    /// kapszula-keret, Minecraftban a kő-gomb adja a keretet (itt nincs
    /// külön díszítés).
    @ViewBuilder
    func skinOutlinePill(_ accent: Color) -> some View {
        if MinecraftTheme.isActive {
            self
        } else {
            self
                .foregroundStyle(accent)
                .padding(.horizontal, 12).padding(.vertical, 8)
                .background(Capsule().strokeBorder(accent.opacity(0.35), lineWidth: 1))
        }
    }

    /// Minecraftban a címke nem törik/vágódik (toolbar-gombok szélessége).
    @ViewBuilder
    func mcFixedSize() -> some View {
        if MinecraftTheme.isActive { self.fixedSize() } else { self }
    }

    /// Lista-sor több soros tartalomhoz: Minecraftban pixel-panel háttér,
    /// rejtett elválasztó, a `summitRowSurface`-szel egyező kényelmes
    /// margó; Summitban semmi.
    @ViewBuilder
    func mcListRowComfy(fill: Color) -> some View {
        if MinecraftTheme.isActive {
            self.listRowBackground(MinecraftTheme.skinRowBackground(fill))
                .listRowSeparator(.hidden)
                .listRowInsets(MinecraftTheme.rowInsets(nil))
        } else {
            self
        }
    }

    /// Akcentszínű felirat: Summitban a megadott előtér-szín, Minecraftban
    /// nem nyúl hozzá (a gomb/panel saját felirat-színe él, nem a kiemelő).
    @ViewBuilder
    func skinAccent(_ color: Color) -> some View {
        if MinecraftTheme.isActive { self } else { self.foregroundStyle(color) }
    }

    /// Szövegmező Form-sorban: Minecraftban a játék szövegmező-kerete,
    /// Summitban a gyári (keret nélküli) sor.
    @ViewBuilder
    func mcInput() -> some View {
        if MinecraftTheme.isActive { self.summitInput() } else { self }
    }

    /// Szövegsor-gomb (Mentés, Törlés…) kő-gombként Minecraftban; Summitban
    /// változatlan marad.
    @ViewBuilder
    func mcInlineButton(prominent: Bool = false) -> some View {
        if MinecraftTheme.isActive {
            self.buttonStyle(McButtonStyle(prominent: prominent, compact: true))
        } else {
            self
        }
    }

    /// Minecraftban a megadott pixelbetű-stílus; Summitban nem nyúl semmihez
    /// (olyan helyre, ahol a gyári betű nincs kifejezetten megadva).
    @ViewBuilder
    func mcFont(_ style: Font.TextStyle) -> some View {
        if MinecraftTheme.isActive { self.font(MinecraftTheme.font(style)) } else { self }
    }

    /// Kerek/kapszula háttér helyett: Summitban a kapszula (kitöltés és/vagy
    /// körvonal), Minecraftban pixel-panel.
    @ViewBuilder
    func skinPill(fill: Color? = nil, stroke: Color? = nil, lineWidth: CGFloat = 1) -> some View {
        if MinecraftTheme.isActive {
            self.padding(MinecraftTheme.px)
                .background { McBlockPanel(face: fill ?? .clear, castsShadow: false) }
        } else {
            self
                .background { if let fill { Capsule().fill(fill) } }
                .background { if let stroke { Capsule().strokeBorder(stroke, lineWidth: lineWidth) } }
        }
    }

    /// Lista-sor kiegészítés a `summitRowSurface` mellé: Minecraftban rejtett
    /// elválasztó + a panel-behúzásnak megfelelő sor-margó; Summitban semmi.
    @ViewBuilder
    func mcRowChrome() -> some View {
        if MinecraftTheme.isActive {
            self.listRowSeparator(.hidden).listRowInsets(MinecraftTheme.rowInsets(nil))
        } else {
            self
        }
    }

    /// Alap (nem `summitListChrome`-os) lista mögé a Minecraft-égbolt;
    /// Summitban nem csinál semmit.
    @ViewBuilder
    func mcListChrome() -> some View {
        if MinecraftTheme.isActive {
            self.scrollContentBackground(.hidden).background { MinecraftBackdrop(ground: false) }
        } else {
            self
        }
    }

    /// Kártya-háttér: Summitban a megadott színű lekerekített doboz,
    /// Minecraftban sötét pixel-panel (a játék sötét dialógusa, a menü-háttéren).
    @ViewBuilder
    func skinCard(fill: Color, cornerRadius: CGFloat = 16) -> some View {
        if MinecraftTheme.isActive {
            self.background { McBlockPanel(face: Color(hex: 0x2E2E33)) }
        } else {
            self.background(fill, in: RoundedRectangle(cornerRadius: cornerRadius))
        }
    }

    /// Form / List sheet-ben: a rendszer-hátterek helyett a játék menü-
    /// háttere. Summitban nem csinál semmit.
    @ViewBuilder
    func skinFormChrome() -> some View {
        if MinecraftTheme.isActive {
            self.scrollContentBackground(.hidden).skinSheetBackground()
        } else {
            self
        }
    }
}

/// Vékony elválasztó: Summitban a gyári `Divider`, Minecraftban 3 pt-os
/// sötét csík.
struct SkinDivider: View {
    var body: some View {
        if MinecraftTheme.isActive {
            Rectangle().fill(Color.black.opacity(0.22)).frame(height: MinecraftTheme.px)
        } else {
            Divider()
        }
    }
}
