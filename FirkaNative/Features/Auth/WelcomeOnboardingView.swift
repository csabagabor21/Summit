import SwiftUI

/// Első indításkor, a belépés ELŐTT látható bemutató: öt lapozható oldal,
/// mindegyiken élő (nem screenshot) mini-illusztráció — így a skin
/// (Summit / Voxel / Neon) és a Dynamic Type is magától érvényes rá.
/// Egyszer jön fel magától (`seenKey`), utána a belépő képernyő
/// „Mit tud a Summit?" gombjáról bármikor újranyitható.
struct WelcomeOnboardingView: View {
    static let seenKey = "onboarding.welcome.seen.v1"

    var onFinish: () -> Void

    @EnvironmentObject var theme: ThemeStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var page = 0
    @State private var bgZoom = false

    private struct Page: Identifiable {
        let id: Int
        let kicker: String
        let title: String
        let body: String
    }

    private let pages: [Page] = [
        Page(id: 0, kicker: "Üdv a Summiton",
             title: "Az e-KRÉTÁD, gyorsan és szépen",
             body: "Jegyek, órarend, házik, dolgozatok, hiányzások és üzenetek — egy helyen, másodpercek alatt."),
        Page(id: 1, kicker: "Jegyek",
             title: "Átlag, ahogy a tanár számolja",
             body: "Súlyozott átlag tantárgyanként, havi grafikonnal és tanári kerekítéssel. A fantom jeggyel kiszámolod, mennyit dobna a következő ötös."),
        Page(id: 2, kicker: "Órarend",
             title: "Mindig tudod, mi jön most",
             body: "Az élő órakártya mutatja, mennyi van hátra az órából és mi a következő — helyettesítéssel, teremmel, a rá eső dolgozattal."),
        Page(id: 3, kicker: "Feladatok",
             title: "Semmi nem csúszik el",
             body: "Házik és dolgozatok határidő szerint, kipipálható listában. Új jegyről, házifeladatról és dolgozatról értesítést kapsz."),
        Page(id: 4, kicker: "Adatvédelem",
             title: "Az adataid nálad maradnak",
             body: "A jegyeid és a belépésed csak a telefonodon vannak. Az iskolai e-KRÉTA-fiókoddal lépsz be — mintha a böngészőben tennéd."),
    ]

    private var isLast: Bool { page == pages.count - 1 }

    var body: some View {
        VStack(spacing: 0) {
            topBar
            TabView(selection: $page) {
                ForEach(pages) { p in
                    pageView(p).tag(p.id)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            bottomBar
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // Háttérként (nem ZStack-testvérként): a `scaledToFill` kép így
        // nem tolja a képernyőn túlra a tartalom szélességét.
        .background { background }
        // Mindhárom skin háttere sötét: világos szöveg, a rendszer-
        // vezérlők is sötét sémában.
        .environment(\.colorScheme, .dark)
        .onChange(of: page) { _, _ in SummitHaptics.selection() }
        .onAppear {
            guard !reduceMotion, !theme.isNeon, !theme.isVoxel else { return }
            withAnimation(.easeOut(duration: 14)) { bgZoom = true }
        }
    }

    // MARK: - Keret

    @ViewBuilder
    private var background: some View {
        if theme.isNeon {
            NeonBackdrop()
        } else if theme.isVoxel {
            VoxelMenuBackground()
        } else {
            // Ugyanaz a gleccser, mint a belépésnél — a bemutató
            // észrevétlenül megy át a belépő képernyőbe.
            GeometryReader { geo in
                Image("Glacier")
                    .resizable()
                    .scaledToFill()
                    .scaleEffect(bgZoom ? 1.07 : 1.0)
                    .frame(width: geo.size.width, height: geo.size.height)
                    .clipped()
            }
            .ignoresSafeArea()
            .overlay {
                LinearGradient(colors: [.black.opacity(0.5), .black.opacity(0.35), .black.opacity(0.8)],
                               startPoint: .top, endPoint: .bottom)
                    .ignoresSafeArea()
            }
        }
    }

    private var topBar: some View {
        HStack {
            if theme.isNeon {
                NeonLabel(String(format: "Bemutató // %02d/%02d", page + 1, pages.count),
                          color: NeonTheme.cyan, bracketed: false, size: 10)
            } else {
                Text("Summit")
                    .skinFont(.headline, weight: .bold)
                    .foregroundStyle(.white.opacity(0.9))
            }
            Spacer()
            if !isLast {
                Button("Kihagyás") { finish() }
                    .skinFont(.subheadline, weight: .semibold)
                    .foregroundStyle(.white.opacity(0.85))
                    .voxelInlineButton()
                    .accessibilityHint("A bemutató bezárása, ugrás a belépéshez")
            }
        }
        .frame(minHeight: 44)
        .padding(.horizontal, 24)
        .padding(.top, 8)
    }

    private var bottomBar: some View {
        VStack(spacing: 18) {
            PageDots(count: pages.count, current: page)
            Button {
                if isLast {
                    finish()
                } else {
                    withAnimation(reduceMotion ? nil : SummitMotion.page) { page += 1 }
                }
            } label: {
                primaryLabel(isLast ? "Kezdjük" : "Tovább")
            }
            .onboardingPrimaryButton()
        }
        .frame(maxWidth: 440)
        .padding(.horizontal, 28)
        .padding(.bottom, 20)
    }

    @ViewBuilder
    private func primaryLabel(_ title: String) -> some View {
        if theme.isVoxel || theme.isNeon {
            Text(title).frame(maxWidth: .infinity)
        } else {
            Text(title)
                .skinFont(.headline, weight: .semibold)
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .functionalGlass(cornerRadius: 14, tint: Color.blue.opacity(0.55))
        }
    }

    private func finish() {
        SummitHaptics.light()
        onFinish()
    }

    // MARK: - Oldalak

    private func pageView(_ p: Page) -> some View {
        ScrollView {
            VStack(spacing: 28) {
                illustration(for: p.id)
                    .frame(maxWidth: 360)
                    .padding(.top, 12)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 10) {
                    if theme.isNeon {
                        NeonLabel(p.kicker, color: NeonTheme.yellow, size: 10)
                    } else {
                        Text(p.kicker.uppercased())
                            .skinFont(.caption, weight: .bold)
                            .tracking(1.2)
                            .foregroundStyle(theme.isVoxel ? Color(hex: 0xFFFF55) : Color.white.opacity(0.7))
                    }
                    Text(p.title)
                        .voxelDisplay(32)
                        .foregroundStyle(.white)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(p.body)
                        .skinFont(.body)
                        .foregroundStyle(.white.opacity(0.8))
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: 440, alignment: .leading)
                .accessibilityElement(children: .combine)
            }
            .padding(.horizontal, 28)
            .padding(.bottom, 16)
            .frame(maxWidth: .infinity)
        }
        .scrollBounceBehavior(.basedOnSize)
    }

    @ViewBuilder
    private func illustration(for id: Int) -> some View {
        switch id {
        case 0: HeroIllustration()
        case 1: GradesIllustration()
        case 2: LiveLessonIllustration()
        case 3: TasksIllustration()
        default: PrivacyIllustration()
        }
    }
}

// MARK: - Lapjelző

/// Lapjelző: Summitban nyúló kapszula, Voxelben/Neonban szögletes
/// pöttyök (a skin formanyelve szerint).
private struct PageDots: View {
    var count: Int
    var current: Int

    var body: some View {
        HStack(spacing: 8) {
            ForEach(0..<count, id: \.self) { i in
                let on = i == current
                Group {
                    if VoxelTheme.isActive || NeonTheme.isActive {
                        Rectangle()
                            .fill(on ? dotColor : Color.white.opacity(0.3))
                            .frame(width: on ? 18 : 6, height: 6)
                    } else {
                        Capsule()
                            .fill(on ? Color.white : Color.white.opacity(0.35))
                            .frame(width: on ? 22 : 7, height: 7)
                    }
                }
                .animation(SummitMotion.snappy, value: current)
            }
        }
        .accessibilityElement()
        .accessibilityLabel("\(current + 1). oldal a \(count)-ból")
    }

    private var dotColor: Color {
        NeonTheme.isActive ? NeonTheme.yellow : Color(hex: 0xFFFF55)
    }
}

// MARK: - Illusztrációk

/// Az illusztráció-kártyák közös felülete: Summitban Liquid Glass,
/// Voxelben a játék dialógus-panelje, Neonban HUD-panel.
private struct OnboardPanel: ViewModifier {
    var accent: Color = NeonTheme.cyan
    var radius: CGFloat = 22

    func body(content: Content) -> some View {
        if NeonTheme.isActive {
            content.background { NeonPanelBackground(accent: accent) }
        } else if VoxelTheme.isActive {
            content.padding(VoxelTheme.px).background { VoxelBlockPanel(face: VoxelTheme.panelFace) }
        } else {
            content.functionalGlass(cornerRadius: radius)
        }
    }
}

private extension View {
    func onboardPanel(accent: Color = NeonTheme.cyan, radius: CGFloat = 22) -> some View {
        modifier(OnboardPanel(accent: accent, radius: radius))
    }

    /// Fő gomb: Neonban sárga teljes szélességű CP-gomb, Voxelben
    /// kő-gomb, Summitban a címkén lévő glass (plain stílus).
    @ViewBuilder
    func onboardingPrimaryButton() -> some View {
        if NeonTheme.isActive {
            self.buttonStyle(NeonButtonStyle(kind: .primary, fullWidth: true))
        } else if VoxelTheme.isActive {
            self.buttonStyle(VoxelButtonStyle(prominent: true))
        } else {
            self.buttonStyle(SummitPressStyle())
        }
    }
}

/// Kiemelő szín az illusztrációkban skinenként.
private var illoAccent: Color {
    NeonTheme.isActive ? NeonTheme.yellow : VoxelTheme.isActive ? VoxelTheme.grass : Color(hex: 0x4A90E2)
}

private func illoGradeColor(_ v: Int) -> Color {
    if NeonTheme.isActive { return NeonTheme.gradeColor(for: v) }
    if VoxelTheme.isActive { return VoxelTheme.gradeColor(for: v) }
    switch v {
    case 5: return .green
    case 4: return Color(hex: 0x8BC34A)
    case 3: return .yellow
    case 2: return .orange
    default: return .red
    }
}

/// 0. oldal: hegycsúcs-jelvény és körülötte az app öt területe.
private struct HeroIllustration: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var float = false

    private let chips: [(String, String)] = [
        ("star.fill", "Jegyek"), ("calendar", "Órarend"), ("checklist", "Feladatok"),
        ("person.crop.rectangle.stack", "Hiányzások"), ("envelope.fill", "Üzenetek"),
    ]

    var body: some View {
        VStack(spacing: 22) {
            ZStack {
                if !VoxelTheme.isActive && !NeonTheme.isActive {
                    Circle()
                        .fill(illoAccent.opacity(0.35))
                        .frame(width: 150, height: 150)
                        .blur(radius: 40)
                }
                SkinIcon("mountain.2.fill", size: 72)
                    .font(.system(size: 64, weight: .semibold))
                    .foregroundStyle(NeonTheme.isActive ? NeonTheme.yellow : .white)
                    .frame(width: 128, height: 128)
                    .onboardPanel(accent: NeonTheme.yellow, radius: 36)
                    .offset(y: float ? -6 : 0)
            }
            .frame(height: 160)

            FlowChips(items: chips)
        }
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 2.4).repeatForever(autoreverses: true)) { float = true }
        }
    }
}

/// Egyszerű, két soros címke-elrendezés (öt elemre ennyi elég).
private struct FlowChips: View {
    var items: [(String, String)]

    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) { ForEach(items.prefix(3), id: \.1) { chip($0) } }
            HStack(spacing: 10) { ForEach(items.dropFirst(3), id: \.1) { chip($0) } }
        }
    }

    private func chip(_ item: (String, String)) -> some View {
        HStack(spacing: 6) {
            SkinIcon(item.0, size: 16)
                .foregroundStyle(illoAccent)
            Text(item.1)
                .skinFont(.footnote, weight: .semibold)
                .foregroundStyle(.white)
                .lineLimit(1)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .onboardPanel(radius: 16)
    }
}

/// 1. oldal: három tantárgy-sor átlaggal + egy fantom-jegy buborék.
private struct GradesIllustration: View {
    private let rows: [(String, String, [Int])] = [
        ("Matematika", "4,38", [5, 4, 5]),
        ("Történelem", "4,71", [5, 5, 4]),
        ("Fizika", "3,92", [4, 3, 5]),
    ]

    var body: some View {
        VStack(spacing: 12) {
            VStack(spacing: 0) {
                ForEach(Array(rows.enumerated()), id: \.offset) { i, r in
                    HStack(spacing: 10) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(r.0).skinFont(.subheadline, weight: .semibold).foregroundStyle(.white)
                            HStack(spacing: 4) {
                                ForEach(Array(r.2.enumerated()), id: \.offset) { _, g in
                                    Text("\(g)")
                                        .skinFontDigits(.caption2, weight: .bold)
                                        .foregroundStyle(illoGradeColor(g))
                                        .frame(width: 20, height: 20)
                                        .background(illoGradeColor(g).opacity(0.16), in: RoundedRectangle(cornerRadius: VoxelTheme.isActive || NeonTheme.isActive ? 0 : 6))
                                }
                            }
                        }
                        Spacer()
                        Text(r.1)
                            .skinFontDigits(.title3, weight: .bold)
                            .foregroundStyle(.white)
                    }
                    .padding(.vertical, 10)
                    if i < rows.count - 1 { Rectangle().fill(.white.opacity(0.12)).frame(height: 1) }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 6)
            .onboardPanel()

            HStack(spacing: 10) {
                SkinIcon("wand.and.stars", size: 18).foregroundStyle(illoAccent)
                Text("Ha kapnék egy 5-öst matekból…")
                    .skinFont(.footnote, weight: .semibold)
                    .foregroundStyle(.white)
                    .lineLimit(2)
                Spacer(minLength: 4)
                Text("4,38 → 4,51")
                    .skinFontDigits(.footnote, weight: .bold)
                    .foregroundStyle(illoGradeColor(5))
                    .lineLimit(1)
                    .fixedSize()
            }
            .padding(14)
            .onboardPanel(accent: NeonTheme.yellow, radius: 18)
        }
    }
}

/// 2. oldal: élő órakártya — folyamatosan fogyó hátralévő idővel.
private struct LiveLessonIllustration: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 12) {
            TimelineView(.periodic(from: .now, by: 1)) { ctx in
                // 45 perces óra, végtelenítve: a bemutató alatt is lássa,
                // hogy a kártya „él".
                let secs = reduceMotion ? 0 : Int(ctx.date.timeIntervalSinceReferenceDate) % 60
                let left = 12 * 60 - secs
                let progress = 1 - Double(left) / Double(45 * 60)
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        HStack(spacing: 6) {
                            SkinDot(color: .green, size: 8)
                            Text("MOST • 3. ÓRA").skinFont(.caption2, weight: .bold).foregroundStyle(.white.opacity(0.7))
                        }
                        Spacer()
                        Text("204-es terem").skinFont(.caption, weight: .semibold).foregroundStyle(.white.opacity(0.7))
                    }
                    Text("Matematika").skinFont(.title2, weight: .bold).foregroundStyle(.white)
                    HStack(alignment: .firstTextBaseline) {
                        Text(String(format: "%d:%02d", left / 60, left % 60))
                            .skinFontDigits(.title, weight: .bold)
                            .foregroundStyle(illoAccent)
                            .contentTransition(.numericText(countsDown: true))
                        Text("van hátra").skinFont(.subheadline).foregroundStyle(.white.opacity(0.7))
                    }
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Rectangle().fill(.white.opacity(0.15))
                            Rectangle().fill(illoAccent).frame(width: geo.size.width * progress)
                        }
                        .clipShape(RoundedRectangle(cornerRadius: VoxelTheme.isActive || NeonTheme.isActive ? 0 : 3))
                    }
                    .frame(height: 6)
                }
                .padding(18)
                .onboardPanel(accent: NeonTheme.yellow)
            }

            HStack(spacing: 12) {
                SkinIcon("arrow.turn.down.right", size: 18).foregroundStyle(.white.opacity(0.7))
                VStack(alignment: .leading, spacing: 2) {
                    Text("Következő: Történelem").skinFont(.subheadline, weight: .semibold).foregroundStyle(.white)
                    Text("9:50 • helyettesít: Kovács T.").skinFont(.caption).foregroundStyle(.white.opacity(0.7))
                }
                Spacer()
                Text("Dolgozat")
                    .skinFont(.caption2, weight: .bold)
                    .foregroundStyle(.orange)
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .skinPill(fill: Color.orange.opacity(0.18))
            }
            .padding(14)
            .onboardPanel(radius: 18)
        }
    }
}

/// 3. oldal: értesítés-banner + kipipálható feladatlista.
private struct TasksIllustration: View {
    @State private var done: Set<Int> = [0]

    private let tasks: [(String, String)] = [
        ("Biológia", "Tankönyv 42. oldal, 3–5. feladat"),
        ("Angol", "Unit 6 szavak — holnapra"),
        ("Kémia", "Témazáró dolgozat • péntek"),
    ]

    var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                SkinIcon("mountain.2.fill", size: 20)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 38, height: 38)
                    .background(illoAccent, in: RoundedRectangle(cornerRadius: VoxelTheme.isActive || NeonTheme.isActive ? 0 : 9))
                VStack(alignment: .leading, spacing: 2) {
                    HStack {
                        Text("Új jegy • Fizika").skinFont(.subheadline, weight: .semibold).foregroundStyle(.white)
                        Spacer()
                        Text("most").skinFont(.caption2).foregroundStyle(.white.opacity(0.6))
                    }
                    Text("5-öst kaptál: Elektromosság témazáró").skinFont(.caption).foregroundStyle(.white.opacity(0.75)).lineLimit(1)
                }
            }
            .padding(12)
            .onboardPanel(accent: NeonTheme.green, radius: 20)

            VStack(spacing: 0) {
                ForEach(Array(tasks.enumerated()), id: \.offset) { i, t in
                    // Kipróbálható: a pipa itt is koppintható.
                    Button {
                        SummitHaptics.selection()
                        if done.contains(i) { done.remove(i) } else { done.insert(i) }
                    } label: {
                        HStack(spacing: 12) {
                            SkinIcon(done.contains(i) ? "checkmark.circle.fill" : "circle", size: 22)
                                .font(.title3)
                                .foregroundStyle(done.contains(i) ? illoAccent : .white.opacity(0.6))
                            VStack(alignment: .leading, spacing: 2) {
                                Text(t.0).skinFont(.subheadline, weight: .semibold).foregroundStyle(.white)
                                    .strikethrough(done.contains(i))
                                Text(t.1).skinFont(.caption).foregroundStyle(.white.opacity(0.7)).lineLimit(1)
                            }
                            Spacer()
                        }
                        .padding(.vertical, 10)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    if i < tasks.count - 1 { Rectangle().fill(.white.opacity(0.12)).frame(height: 1) }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 4)
            .onboardPanel()
        }
    }
}

/// 4. oldal: mi marad a telefonon — három sor + lakat.
private struct PrivacyIllustration: View {
    private let rows: [(String, String, String)] = [
        ("lock.fill", "Belépés a Keychainben", "A tokened titkosítva, csak ezen az eszközön."),
        ("iphone", "Jegyek a telefonodon", "A KRÉTA-adataidat nem töltjük fel sehova."),
        ("key.fill", "Titkosított szinkron", "Eszközök között csak a beállításaid, jelmondattal védve."),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            ForEach(rows, id: \.1) { r in
                HStack(alignment: .top, spacing: 12) {
                    SkinIcon(r.0, size: 20)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(NeonTheme.isActive ? NeonTheme.green : illoAccent)
                        .frame(width: 26)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(r.1).skinFont(.subheadline, weight: .semibold).foregroundStyle(.white)
                        Text(r.2).skinFont(.caption).foregroundStyle(.white.opacity(0.7))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .onboardPanel(accent: NeonTheme.green)
    }
}
