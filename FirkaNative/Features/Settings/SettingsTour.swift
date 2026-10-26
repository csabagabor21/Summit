import SwiftUI

/// Belépés utáni, Photoshop-szerű végigvezetés a Beállításokban:
/// az aktív szigetet görgetve fókuszba hozza, accent-kerettel
/// highlightolja, alul pedig egy kártya mondja el, mit tud az adott
/// feature. Egyszer indul magától, utána a toolbar ? gombjával
/// bármikor újraindítható.
enum SettingsTour {
    enum Anchor: String, Hashable {
        case profile, rounding, live, events, notifications, appearance, account, diagnostics, sync
    }

    struct Step: Identifiable {
        let anchor: Anchor
        var id: String { anchor.rawValue }
        let title: String
        let body: String
    }

    static let steps: [Step] = [
        Step(anchor: .profile, title: "Profilkép",
             body: "Koppints a képre a cseréhez, a Módosítás gombbal újat tölthetsz fel. Eszközök között szinkronizálódik."),
        Step(anchor: .rounding, title: "Tanári kerekítés",
             body: "Tantárgyanként állíthatod, mikortól kerekít fel a tanár — ez dobja át az átlagot a határon."),
        Step(anchor: .live, title: "Live Activity",
             body: "Lock Screen + Dynamic Island: szünetben a következő órát mutatja. Ha a rendszer tiltja, az iOS Beállításokban kell bekapcsolni."),
        Step(anchor: .events, title: "Iskolai események",
             body: "Tannaptár linkből, szövegből vagy .ics fájlból — az órarend tetején 0. óraként jelenik meg. Amit kézzel beállítasz, sosem íródik felül."),
        Step(anchor: .notifications, title: "Értesítések",
             body: "A KRÉTA nem küld push-t: az app adatfrissítéskor nézi meg, mi az új, és arra küld helyi értesítést."),
        Step(anchor: .appearance, title: "Megjelenés",
             body: "Téma, kiemelőszín és szövegméret — minden eszközödre szinkronizálódik."),
        Step(anchor: .account, title: "Fiók — iskola kód",
             body: "Ha minden lista üres, ez a kód a rossz: a böngészős e-KRÉTA cím eleje kell ide. Előbb próbáld az Automatikus javítást."),
        Step(anchor: .diagnostics, title: "Diagnosztika",
             body: "Ha valami nem frissül, itt látszik a hiba és a napló — hibajelentésnél ez az első megálló."),
        Step(anchor: .sync, title: "Szinkron",
             body: "Egy jelmondat köti össze az eszközeidet: témát, színt, kerekítést, pipákat és képet visz át. Maga a jelmondat sosem hagyja el a telefont."),
    ]
}

/// Accent-kiemelés az épp magyarázott szigetre. Reduce Motion mellett
/// csak a keret jelenik meg, pulzálás nélkül.
private struct TourHighlightModifier: ViewModifier {
    var active: Bool
    var accent: Color
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pulse = false

    func body(content: Content) -> some View {
        content
            .overlay {
                if active {
                    if NeonTheme.isActive {
                        // HUD-célkereszt: levágott sarkú 1,5 px-es sárga keret,
                        // a két ép sarkon rövid konzol-jelekkel; pulzálás nélkül.
                        NeonChamferShape(cut: 14, corners: .diagonal)
                            .strokeBorder(NeonTheme.yellow, lineWidth: 1.5)
                            .overlay(NeonTourBrackets())
                            .allowsHitTesting(false)
                    } else if VoxelTheme.isActive {
                        // Pixel-keret (a játék kijelölés-sárgája), puha ragyogás nélkül.
                        VoxelPixelShape(steps: 2)
                            .strokeBorder(Color(hex: 0xFFFF55), lineWidth: VoxelTheme.px)
                            .allowsHitTesting(false)
                    } else {
                        RoundedRectangle(cornerRadius: 20)
                            .strokeBorder(accent, lineWidth: 2.5)
                            .shadow(color: accent.opacity(0.5), radius: reduceMotion ? 0 : (pulse ? 10 : 4))
                            .allowsHitTesting(false)
                    }
                }
            }
            .onChange(of: active) { _, on in
                guard on, !reduceMotion else { return }
                withAnimation(.easeInOut(duration: 1.0).repeatForever(autoreverses: true)) {
                    pulse = true
                }
            }
    }
}

extension View {
    func tourHighlight(active: Bool, accent: Color) -> some View {
        modifier(TourHighlightModifier(active: active, accent: accent))
    }
}

/// Alsó magyarázókártya a túra lépéseivel: számláló + Vissza /
/// Tovább / Kihagyás / Kész.
struct SettingsTourCard: View {
    @Binding var step: Int?
    var accent: Color
    var onFinish: () -> Void

    var body: some View {
        if let i = step, SettingsTour.steps.indices.contains(i) {
            let s = SettingsTour.steps[i]
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    tourCounter(i)
                    Spacer()
                    Button("Kihagyás") { step = nil; onFinish() }
                        .skinFont(.caption, weight: .semibold)
                        .voxelInlineButton()
                }
                Text(s.title).skinFont(.headline)
                Text(s.body).skinFont(.subheadline).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                HStack {
                    Button("Vissza") { step = max(0, i - 1) }
                        .skinFont(.subheadline, weight: .semibold)
                        .disabled(i == 0)
                        .voxelInlineButton()
                    Spacer()
                    if i < SettingsTour.steps.count - 1 {
                        Button("Tovább") { step = i + 1 }
                            .skinFont(.subheadline, weight: .bold)
                            .voxelInlineButton(prominent: NeonTheme.isActive)
                    } else {
                        Button("Kész") { step = nil; onFinish() }
                            .skinFont(.subheadline, weight: .bold)
                            .voxelInlineButton(prominent: NeonTheme.isActive)
                    }
                }
                .tint(accent)
            }
            .padding(16)
            .modifier(TourCardSurface(accent: accent))
            .padding(.horizontal, 16)
            .padding(.bottom, 12)
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }

    /// Lépésszámláló: Neonban sárga HUD-kód (`TÚRA // 03/09`),
    /// egyébként a meglévő szürke felirat.
    @ViewBuilder
    private func tourCounter(_ i: Int) -> some View {
        if NeonTheme.isActive {
            NeonLabel(String(format: "Túra // %02d/%02d", i + 1, SettingsTour.steps.count),
                    color: NeonTheme.yellow, bracketed: false, size: 10)
                .accessibilityLabel("Beállítások túra, \(i + 1). lépés a \(SettingsTour.steps.count)-ból")
        } else {
            Text("Beállítások túra • \(i + 1)/\(SettingsTour.steps.count)")
                .skinFont(.caption2, weight: .bold).foregroundStyle(.secondary)
        }
    }
}

/// A túra-kártya felülete: Summitban az átlátszó anyag + akcentkeret,
/// Voxelben a játék dialógus-panelje kemény árnyékkal.
private struct TourCardSurface: ViewModifier {
    var accent: Color

    func body(content: Content) -> some View {
        if NeonTheme.isActive {
            // Emelt HUD-panel sárga akcenttel + bal oldali sárga jelzősáv.
            content
                .background { NeonPanelBackground(accent: NeonTheme.yellow, fill: NeonTheme.panelRaised) }
                .overlay(alignment: .leading) {
                    Rectangle().fill(NeonTheme.yellow).frame(width: 3).padding(.vertical, 16)
                        .accessibilityHidden(true)
                }
        } else if VoxelTheme.isActive {
            content
                .padding(VoxelTheme.px)
                .background { VoxelBlockPanel(face: VoxelTheme.panelFace) }
        } else {
            content
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20))
                .overlay(RoundedRectangle(cornerRadius: 20).strokeBorder(accent.opacity(0.4)))
                .shadow(radius: 12)
        }
    }
}

/// A túra-kiemelés konzol-jelei a keret két ép (jobb felső, bal alsó)
/// sarkán — statikus, olcsó Path.
private struct NeonTourBrackets: View {
    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width, h = geo.size.height, l: CGFloat = 14
            Path { p in
                p.move(to: CGPoint(x: w - l, y: -3)); p.addLine(to: CGPoint(x: w + 3, y: -3)); p.addLine(to: CGPoint(x: w + 3, y: l))
                p.move(to: CGPoint(x: -3, y: h - l)); p.addLine(to: CGPoint(x: -3, y: h + 3)); p.addLine(to: CGPoint(x: l, y: h + 3))
            }
            .stroke(NeonTheme.yellow, lineWidth: 2)
        }
        .accessibilityHidden(true)
    }
}
