import SwiftUI

struct ContentView: View {
    @EnvironmentObject var session: SessionStore
    @EnvironmentObject var theme: ThemeStore
    @EnvironmentObject var analytics: AnalyticsStore
    /// A rendszer szövegmérete (felülírás nélkül ez megy tovább változatlanul).
    @Environment(\.sizeCategory) private var systemSizeCategory
    /// Neonra váltáskor egyszer lejátszott belépő átmenet.
    @State private var neonBoot = false
    /// Első indításkori bemutató (belépés előtt) — egyszer jön fel.
    @AppStorage(WelcomeOnboardingView.seenKey) private var welcomeSeen = false

    var body: some View {
        // NEM `if let felülírás { content.environment } else { content }`:
        // az ág-váltás új nézet-identitást adott, így a Szövegméret
        // „Rendszer" ↔ fix váltása eldobta az összes NavigationStacket és a
        // kiválasztott tabot (a user a Főoldal gyökerén találta magát).
        content
            .environment(\.sizeCategory, theme.sizeCategoryOverride ?? systemSizeCategory)
        // Voxel-skin: a kifejezett betűstílus nélküli szövegek (szekció-
        // fejlécek, sima gombfeliratok, mezők) is Monocraftban jelennek meg.
        // Summitban nil = a rendszer alap-környezete, semmi nem változik.
        // Neonban ugyanígy Rajdhani.
        .environment(\.font, theme.isVoxel ? VoxelTheme.font(.body)
                     : theme.isNeon ? NeonTheme.font(.body) : nil)
        .animation(SummitMotion.gentle, value: session.isLoggedIn)
        .animation(SummitMotion.gentle, value: welcomeSeen)
        // Neonra váltás a felület-választóból: rövid „boot"-átmenet.
        .overlay {
            if neonBoot {
                NeonBootOverlay { neonBoot = false }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NeonTheme.bootRequest)) { _ in
            neonBoot = true
        }
        // Skin-váltáskor a nav/tab-sávok betűje is átvált (UIKit-appearance).
        .onChange(of: theme.skin) { _, s in
            s.applyChromeAppearance()
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
                            // Hidegindításkor a cover az első layout-körben
                            // nyílik, amikor az örökölt environment még nem ér
                            // le (lásd a GradeCelebrationView-nál a MainTabView-
                            // ban) — a nézet a témát is olvassa, explicit inject.
                            .environmentObject(theme)
                    }
            } else if !welcomeSeen {
                WelcomeOnboardingView { welcomeSeen = true }
                    .transition(.opacity)
            } else {
                LoginView()
                    .transition(.opacity)
            }
        }
    }
}

// MARK: - Voxel-skin segédek
// A kit (VoxelKit) általános elemein túli, a képernyők közös építőkockái.
// Mind skin-érzékeny: Summitban a gyári vezérlőt adják vissza változatlanul.

/// Mező-helyőrző: Voxelben a fekete mezőn is olvasható szürke szöveg
/// (a rendszer-helyőrző sötét lenne), Summitban a gyári.
func skinPrompt(_ text: String) -> Text {
    VoxelTheme.isActive ? Text(text).foregroundStyle(Color(hex: 0x7A7A7A))
        : NeonTheme.isActive ? Text(text).foregroundStyle(NeonTheme.dim) : Text(text)
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
private struct VoxelSegmentStyle: ButtonStyle {
    var selected: Bool
    func makeBody(configuration: Configuration) -> some View {
        let hi = selected || configuration.isPressed
        configuration.label
            .font(VoxelTheme.font(.callout))
            .foregroundStyle(selected ? Color(hex: 0xFFFF55) : .white)
            .shadow(color: Color(hex: 0x3F3F3F), radius: 0, x: VoxelTheme.px / 1.5, y: VoxelTheme.px / 1.5)
            .padding(.horizontal, 6)
            .padding(.vertical, 8)
            .frame(minHeight: 40)
            .background(VoxelNineSlice(hi ? "img_blk_widget_button_hi" : "img_blk_widget_button", border: 3))
            .contentShape(Rectangle())
    }
}

/// Gombnak látszó felirat-keret (nem ButtonStyle: Menu / DatePicker
/// címkéjén is használható, ahol a rendszer saját stílust húzna rá).
private struct VoxelButtonLook: ViewModifier {
    func body(content: Content) -> some View {
        content
            .font(VoxelTheme.font(.body))
            .foregroundStyle(.white)
            .shadow(color: Color(hex: 0x3F3F3F), radius: 0, x: VoxelTheme.px / 1.5, y: VoxelTheme.px / 1.5)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .frame(minHeight: 36)
            .background(VoxelNineSlice("img_blk_widget_button", border: 3))
            .contentShape(Rectangle())
    }
}

/// Szegmentált választó: Summitban a gyári `.segmented` Picker,
/// Voxelben egymás melletti kő-gombok (a kijelölt kiemelve).
struct SkinSegmented<Value: Hashable>: View {
    var title: String = ""
    @Binding var selection: Value
    var options: [SkinOption<Value>]

    var body: some View {
        if VoxelTheme.isActive {
            HStack(spacing: VoxelTheme.px) {
                ForEach(options) { opt in
                    let on = selection == opt.value
                    Button { selection = opt.value } label: {
                        HStack(spacing: 6) {
                            if let icon = opt.icon { SkinIcon(icon, size: 18) }
                            Text(opt.title).lineLimit(1).minimumScaleFactor(0.6)
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(VoxelSegmentStyle(selected: on))
                    .accessibilityAddTraits(on ? .isSelected : [])
                }
            }
        } else if NeonTheme.isActive {
            NeonSegmentedPicker(selection: $selection, options: options.map { ($0.value, $0.title) }, accessibilityTitle: title)
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
/// `.navigationLink`), Voxelben kő-gomb a kiválasztott értékkel
/// (a lenyíló lista maga a rendszer menüje).
struct SkinMenuPicker<Value: Hashable>: View {
    var title: String
    @Binding var selection: Value
    var options: [SkinOption<Value>]
    var navigationStyle = false

    var body: some View {
        if VoxelTheme.isActive {
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
                        SkinChevron(direction: .down, size: 14)
                    }
                    .modifier(VoxelButtonLook())
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

/// Csúszka: Summitban a gyári `Slider`, Voxelben az igazi
/// `widget/slider` sötét sáv + `slider_handle` fogantyú.
struct SkinSlider: View {
    @Binding var value: Double
    var range: ClosedRange<Double>
    var step: Double

    var body: some View {
        if VoxelTheme.isActive {
            VoxelSliderControl(value: $value, range: range, step: step)
        } else {
            Slider(value: $value, in: range, step: step)
        }
    }
}

private struct VoxelSliderControl: View {
    @Binding var value: Double
    var range: ClosedRange<Double>
    var step: Double
    @State private var dragging = false
    /// Az aktuális húzás függőlegesnek bizonyult (görgetés) — nem állít.
    @State private var rejected = false

    /// Érték egy x-pozícióból (fogantyú-középre igazítva, lépésre kerekítve).
    private func set(from x: CGFloat, handleW: CGFloat, travel: CGFloat) {
        let f = min(1, max(0, Double((x - handleW / 2) / travel)))
        let raw = range.lowerBound + f * (range.upperBound - range.lowerBound)
        let snapped = (raw / step).rounded() * step
        value = min(range.upperBound, max(range.lowerBound, snapped))
    }

    var body: some View {
        GeometryReader { geo in
            let handleW = 8 * VoxelTheme.px
            let travel = max(1, geo.size.width - handleW)
            let frac = (value - range.lowerBound) / (range.upperBound - range.lowerBound)
            ZStack(alignment: .leading) {
                VoxelNineSlice("img_blk_widget_slider", border: 1)
                VoxelNineSlice(dragging ? "img_blk_widget_slider_handle_hi" : "img_blk_widget_slider_handle",
                            top: 2, left: 2, bottom: 3, right: 2)
                    .frame(width: handleW)
                    .offset(x: CGFloat(min(1, max(0, frac))) * travel)
            }
            .contentShape(Rectangle())
            // Koppintás: azonnal oda ugrik (mint a rendszer-csúszka).
            .onTapGesture { location in set(from: location.x, handleW: handleW, travel: travel) }
            // Húzás: csak vízszintes túlsúlynál fog meg — a csúszkán induló
            // függőleges görgetés (DeveloperView, kerekítés-részlet) eddig az
            // értéket állította a lista görgetése helyett.
            // Egyidejű gesztus: a lista görgetése sem blokkolódik; az irányt
            // az első mozdulat dönti el, függőleges húzás végig figyelmen kívül.
            .simultaneousGesture(
                DragGesture(minimumDistance: 6)
                    .onChanged { g in
                        if rejected { return }
                        if !dragging {
                            guard abs(g.translation.width) > abs(g.translation.height) else { rejected = true; return }
                            dragging = true
                        }
                        set(from: g.location.x, handleW: handleW, travel: travel)
                    }
                    .onEnded { _ in dragging = false; rejected = false }
            )
        }
        .frame(height: 12 * VoxelTheme.px)
        .accessibilityElement()
        .accessibilityValue(String(format: "%.2f", value))
        .accessibilityAdjustableAction { dir in
            let next = value + (dir == .increment ? step : -step)
            value = min(range.upperBound, max(range.lowerBound, next))
        }
    }
}

/// Léptető: Summitban a gyári `Stepper`, Voxelben −/+ kő-gombok.
struct SkinStepper: View {
    var title: String
    @Binding var value: Int
    var range: ClosedRange<Int>

    var body: some View {
        if VoxelTheme.isActive {
            HStack(spacing: 8) {
                Text(title)
                Spacer(minLength: 8)
                Button { value = max(range.lowerBound, value - 1) } label: { VoxelGlyph(kind: .minus, size: 16) }
                    .buttonStyle(VoxelButtonStyle(compact: true))
                    .disabled(value <= range.lowerBound)
                    .accessibilityLabel("Csökkentés")
                Button { value = min(range.upperBound, value + 1) } label: { VoxelGlyph(kind: .plus, size: 16) }
                    .buttonStyle(VoxelButtonStyle(compact: true))
                    .disabled(value >= range.upperBound)
                    .accessibilityLabel("Növelés")
            }
            .accessibilityElement(children: .contain)
        } else {
            Stepper(title, value: $value, in: range)
        }
    }
}

/// Dátumválasztó sor: Summitban a gyári kompakt `DatePicker`, Voxelben
/// kő-gomb a dátummal. A rendszer-naptárat egy átlátszatlanná tett
/// (színszorzóval kioltott) DatePicker nyitja a gomb fölött.
struct SkinDateRow: View {
    var title: String
    @Binding var date: Date
    var minDate: Date? = nil

    var body: some View {
        if VoxelTheme.isActive {
            HStack(spacing: 8) {
                Text(title)
                Spacer(minLength: 8)
                Text(date.formatted(date: .abbreviated, time: .omitted))
                    .modifier(VoxelButtonLook())
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

/// Betöltésjelző: Summitban a gyári `ProgressView`, Voxelben három
/// pixelnégyzet, amelyek közül egy világít (léptetve, nem simán forogva).
struct SkinProgress: View {
    var color: Color? = nil

    var body: some View {
        if VoxelTheme.isActive {
            VoxelPixelSpinner(color: color ?? .primary)
        } else if NeonTheme.isActive {
            NeonSpinner(color: color ?? NeonTheme.yellow)
        } else {
            ProgressView()
        }
    }
}

private struct VoxelPixelSpinner: View {
    var color: Color
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.25)) { ctx in
            let phase = reduceMotion ? 0 : Int(ctx.date.timeIntervalSinceReferenceDate / 0.25) % 4
            HStack(spacing: VoxelTheme.px) {
                ForEach(0..<3, id: \.self) { i in
                    Rectangle()
                        .fill(i == phase ? color : color.opacity(0.28))
                        .frame(width: 2 * VoxelTheme.px, height: 2 * VoxelTheme.px)
                }
            }
        }
        .accessibilityLabel("Betöltés")
    }
}

/// Neon-betöltésjelző: öt keskeny sáv, amelyeken egy fényes szakasz
/// fut végig (léptetve, 0,12 mp-enként). Reduce Motion mellett álló sávok.
private struct NeonSpinner: View {
    var color: Color
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.12)) { ctx in
            let phase = reduceMotion ? -1 : Int(ctx.date.timeIntervalSinceReferenceDate / 0.12) % 7
            HStack(spacing: 2) {
                ForEach(0..<5, id: \.self) { i in
                    Rectangle()
                        .fill(i == phase || i == phase - 1 ? color : color.opacity(reduceMotion ? 0.6 : 0.22))
                        .frame(width: 3, height: 12)
                }
            }
        }
        .accessibilityLabel("Betöltés")
    }
}

/// Üres állapot: Summitban a gyári `ContentUnavailableView`, Voxelben
/// nagy item-ikon + pixelbetűs cím és leírás.
struct SkinEmptyState: View {
    var title: String
    var systemImage: String
    var description: Text? = nil

    var body: some View {
        if VoxelTheme.isActive {
            VStack(spacing: 12) {
                SkinIcon(systemImage, size: 6 * VoxelTheme.px * 3)
                Text(title).voxelTitle().multilineTextAlignment(.center)
                if let description {
                    description
                        .font(VoxelTheme.font(.callout))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 16)
            .accessibilityElement(children: .combine)
        } else if NeonTheme.isActive {
            VStack(spacing: 10) {
                Image(systemName: systemImage)
                    .font(.system(size: 40, weight: .light))
                    .foregroundStyle(NeonTheme.cyan)
                NeonLabel("NO DATA", color: NeonTheme.red)
                Text(title.uppercased())
                    .font(NeonTheme.font(.title3, weight: .bold))
                    .tracking(1.2)
                    .foregroundStyle(NeonTheme.text)
                    .multilineTextAlignment(.center)
                if let description {
                    description
                        .font(NeonTheme.font(.callout))
                        .foregroundStyle(NeonTheme.dim)
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

/// Állapotjelző pötty: Summitban kör, Voxelben négyzet.
struct SkinDot: View {
    var color: Color
    var size: CGFloat = 6

    var body: some View {
        if VoxelTheme.isActive || NeonTheme.isActive {
            Rectangle().fill(color).frame(width: max(size, VoxelTheme.px), height: max(size, VoxelTheme.px))
        } else {
            Circle().fill(color).frame(width: size, height: size)
        }
    }
}

/// Navigációs sor listában: Summitban a gyári `NavigationLink`, Voxelben
/// a rendszer-nyíl helyett pixel-chevron (a rejtett link adja a koppintást).
struct SkinNavLink<Destination: View, Label: View>: View {
    var destination: () -> Destination
    var label: () -> Label

    init(@ViewBuilder destination: @escaping () -> Destination, @ViewBuilder label: @escaping () -> Label) {
        self.destination = destination
        self.label = label
    }

    var body: some View {
        if VoxelTheme.isActive || NeonTheme.isActive {
            ZStack {
                NavigationLink { destination().voxelBackButton().voxelPushClick() } label: { EmptyView() }.opacity(0)
                HStack(spacing: 8) {
                    label()
                    SkinChevron()
                        .foregroundStyle(.secondary)
                }
            }
        } else {
            NavigationLink { destination() } label: { label() }
        }
    }
}

/// Toolbar-elem skin-érzékenyen: Voxelben a rendszer Liquid Glass
/// kapszulája nélkül, kő-gombbal; Summitban a gyári elem.
struct SkinToolbarItem<Content: View>: ToolbarContent {
    var placement: ToolbarItemPlacement
    @ViewBuilder var content: () -> Content

    var body: some ToolbarContent {
        ToolbarItem(placement: placement) { content().voxelFixedSize().skinToolbarItem() }
            .sharedBackgroundVisibility(VoxelTheme.isActive || NeonTheme.isActive ? .hidden : .automatic)
    }
}

extension View {
    /// Voxelben a gomb kő-gomb (kompakt), Summitban a `.plain` stílus —
    /// a koppintható, saját keret nélküli sorok / csíkok gombjához.
    @ViewBuilder
    func voxelButtonOrPlain(compact: Bool = true) -> some View {
        if VoxelTheme.isActive {
            self.buttonStyle(VoxelButtonStyle(compact: compact))
        } else if NeonTheme.isActive {
            self.buttonStyle(NeonButtonStyle(kind: .secondary, compact: compact))
        } else {
            self.buttonStyle(.plain)
        }
    }

    /// Körvonalas kapszula-gomb felirata: Summitban akcentszín + vékony
    /// kapszula-keret, Voxelben a kő-gomb adja a keretet (itt nincs
    /// külön díszítés).
    @ViewBuilder
    func skinOutlinePill(_ accent: Color) -> some View {
        if VoxelTheme.isActive {
            self
        } else if NeonTheme.isActive {
            // HUD-címke: nagybetűs, ritkított, levágott sarkú körvonal.
            self
                .textCase(.uppercase)
                .tracking(1)
                .foregroundStyle(accent)
                .padding(.horizontal, 12).padding(.vertical, 7)
                .background(NeonChamferShape(cut: 6, corners: [.topLeft, .bottomRight]).fill(accent.opacity(0.08)))
                .overlay(NeonChamferShape(cut: 6, corners: [.topLeft, .bottomRight]).strokeBorder(accent.opacity(0.7), lineWidth: 1))
        } else {
            self
                .foregroundStyle(accent)
                .padding(.horizontal, 12).padding(.vertical, 8)
                .background(Capsule().strokeBorder(accent.opacity(0.35), lineWidth: 1))
        }
    }

    /// Voxelben a címke nem törik/vágódik (toolbar-gombok szélessége).
    @ViewBuilder
    func voxelFixedSize() -> some View {
        if VoxelTheme.isActive { self.fixedSize() } else { self }
    }

    /// Lista-sor több soros tartalomhoz: Voxelben pixel-panel háttér,
    /// rejtett elválasztó, a `summitRowSurface`-szel egyező kényelmes
    /// margó; Summitban semmi.
    @ViewBuilder
    func voxelListRowComfy(fill: Color) -> some View {
        if VoxelTheme.isActive || NeonTheme.isActive {
            self.listRowBackground(VoxelTheme.skinRowBackground(fill))
                .listRowSeparator(.hidden)
                .listRowInsets(VoxelTheme.rowInsets(nil))
        } else {
            self
        }
    }

    /// Akcentszínű felirat: Summitban a megadott előtér-szín, Voxelben
    /// nem nyúl hozzá (a gomb/panel saját felirat-színe él, nem a kiemelő).
    @ViewBuilder
    func skinAccent(_ color: Color) -> some View {
        if VoxelTheme.isActive { self } else { self.foregroundStyle(color) }
    }

    /// Szövegmező Form-sorban: Voxelben a játék szövegmező-kerete,
    /// Summitban a gyári (keret nélküli) sor.
    @ViewBuilder
    func voxelInput() -> some View {
        if VoxelTheme.isActive || NeonTheme.isActive { self.summitInput() } else { self }
    }

    /// Szövegsor-gomb (Mentés, Törlés…) kő-gombként Voxelben; Summitban
    /// változatlan marad.
    @ViewBuilder
    func voxelInlineButton(prominent: Bool = false) -> some View {
        if VoxelTheme.isActive {
            self.buttonStyle(VoxelButtonStyle(prominent: prominent, compact: true))
        } else if NeonTheme.isActive {
            self.buttonStyle(NeonButtonStyle(kind: prominent ? .primary : .secondary, compact: true))
        } else {
            self
        }
    }

    /// Voxelben a megadott pixelbetű-stílus; Summitban nem nyúl semmihez
    /// (olyan helyre, ahol a gyári betű nincs kifejezetten megadva).
    func voxelFont(_ style: Font.TextStyle) -> some View {
        self.transformEnvironment(\.font) {
            if VoxelTheme.isActive { $0 = VoxelTheme.font(style) }
            else if NeonTheme.isActive { $0 = NeonTheme.font(style) }
        }
    }

    /// Kerek/kapszula háttér helyett: Summitban a kapszula (kitöltés és/vagy
    /// körvonal), Voxelben pixel-panel.
    @ViewBuilder
    func skinPill(fill: Color? = nil, stroke: Color? = nil, lineWidth: CGFloat = 1) -> some View {
        if VoxelTheme.isActive || NeonTheme.isActive {
            self.padding(VoxelTheme.px)
                .background {
                    if NeonTheme.isActive {
                        NeonChamferShape(cut: 6).fill(fill ?? .clear)
                            .overlay(NeonChamferShape(cut: 6).strokeBorder(stroke ?? .clear, lineWidth: lineWidth))
                    } else {
                        VoxelBlockPanel(face: fill ?? .clear, castsShadow: false)
                    }
                }
        } else {
            self
                .background { if let fill { Capsule().fill(fill) } }
                .background { if let stroke { Capsule().strokeBorder(stroke, lineWidth: lineWidth) } }
        }
    }

    /// Lista-sor kiegészítés a `summitRowSurface` mellé: Voxelben rejtett
    /// elválasztó + a panel-behúzásnak megfelelő sor-margó; Summitban semmi.
    @ViewBuilder
    func voxelRowChrome() -> some View {
        if VoxelTheme.isActive || NeonTheme.isActive {
            self.listRowSeparator(.hidden).listRowInsets(VoxelTheme.rowInsets(nil))
        } else {
            self
        }
    }

    /// Alap (nem `summitListChrome`-os) lista mögé a Voxel-égbolt;
    /// Summitban nem csinál semmit.
    @ViewBuilder
    func voxelListChrome() -> some View {
        if VoxelTheme.isActive || NeonTheme.isActive {
            self.scrollContentBackground(.hidden).background {
                if NeonTheme.isActive { NeonBackdrop() } else { VoxelBackdrop(ground: false) }
            }
        } else {
            self
        }
    }

    /// Kártya-háttér: Summitban a megadott színű lekerekített doboz,
    /// Voxelben sötét pixel-panel (a játék sötét dialógusa, a menü-háttéren).
    @ViewBuilder
    func skinCard(fill: Color, cornerRadius: CGFloat = 16) -> some View {
        if VoxelTheme.isActive || NeonTheme.isActive {
            self.background {
                if NeonTheme.isActive { NeonPanelBackground() } else { VoxelBlockPanel(face: Color(hex: 0x2E2E33)) }
            }
        } else {
            self.background(fill, in: RoundedRectangle(cornerRadius: cornerRadius))
        }
    }

    /// Form / List sheet-ben: a rendszer-hátterek helyett a játék menü-
    /// háttere. Summitban nem csinál semmit.
    @ViewBuilder
    func skinFormChrome() -> some View {
        if VoxelTheme.isActive || NeonTheme.isActive {
            self.scrollContentBackground(.hidden).skinSheetBackground()
        } else {
            self
        }
    }
}

/// Vékony elválasztó: Summitban a gyári `Divider`, Voxelben 3 pt-os
/// sötét csík.
struct SkinDivider: View {
    var body: some View {
        if VoxelTheme.isActive {
            Rectangle().fill(Color.black.opacity(0.22)).frame(height: VoxelTheme.px)
        } else if NeonTheme.isActive {
            NeonDivider(showsTick: false)
        } else {
            Divider()
        }
    }
}
