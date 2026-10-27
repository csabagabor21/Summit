import SwiftUI

/// Belépés utáni, fülről fülre vezető bemutató a fő képernyőn: minden
/// lépés a VALÓDI tabra vált (a user a saját adatait látja mögötte), az
/// alsó kártya pedig elmondja, mi van ott és milyen rejtett trükkök
/// vannak. A user közben szabadon nyomkodhat; ha maga vált tabot, a
/// túra követi. Egyszer indul magától (a hozzájárulás-választó után),
/// utána a Beállítások ? menüjéből bármikor újraindítható.
enum AppTour {
    static let seenKey = "tour.app.seen.v1"
    /// Újraindítás kérése (Beállítások ? menü) — a MainTabView hallgatja.
    static let startRequest = Notification.Name("summit.appTour.start")

    struct Tip: Hashable {
        let icon: String
        let text: String
    }

    struct Step: Identifiable {
        let id: Int
        /// Melyik tabra vált a lépés; nil = a nyitó lépés (nem vált).
        let tab: Int?
        let icon: String
        let title: String
        let body: String
        var tips: [Tip] = []
    }

    static let steps: [Step] = [
        Step(id: 0, tab: nil, icon: "mountain.2.fill",
             title: "Körbevezetünk?",
             body: "Egy perc, öt fül — megmutatjuk, mit hol találsz, és pár trükköt, amit magadtól nehezen vennél észre."),
        Step(id: 1, tab: 0, icon: "house.fill",
             title: "Főoldal — a napod egy pillantásra",
             body: "Az élő órakártya mutatja, mi megy most, mennyi van hátra, és mi jön utána. Alatta az új jegyek, házik és üzenetek.",
             tips: [Tip(icon: "arrow.down", text: "Húzd le a frissítéshez."),
                    Tip(icon: "person.crop.circle", text: "Jobb felül a profilképed: innen nyílnak a Beállítások.")]),
        Step(id: 2, tab: 1, icon: "star.fill",
             title: "Jegyek — átlag, ahogy a tanár számolja",
             body: "Súlyozott átlag tantárgyanként, havi grafikonnal, félévi és év végi jegyekkel.",
             tips: [Tip(icon: "hand.tap", text: "Koppints egy tárgyra: grafikon, összes jegy, fantom jegy."),
                    Tip(icon: "wand.and.stars", text: "Egy jegyen balra húzva: „Mi lett volna ha”.")]),
        Step(id: 3, tab: 2, icon: "calendar",
             title: "Órarend — helyettesítéssel együtt",
             body: "A heti órarended a házikkal, dolgozatokkal és a változásokkal (elmaradt óra, helyettesítés) együtt.",
             tips: [Tip(icon: "hand.draw", text: "Húzd oldalra a napváltáshoz, a nyilakkal hetet léptetsz."),
                    Tip(icon: "flag", text: "Az iskolai események 0. óraként a nap tetején jelennek meg.")]),
        Step(id: 4, tab: 5, icon: "checklist",
             title: "Feladatok — semmi nem csúszik el",
             body: "Házik és bejelentett dolgozatok határidő szerint. A kipipáltak a Kész fülre kerülnek.",
             tips: [Tip(icon: "checkmark.circle", text: "Pipáld ki, amit megcsináltál — minden eszközödön szinkronban marad."),
                    Tip(icon: "plus", text: "A + gombbal saját feladatot vagy dolgozatot is felvehetsz.")]),
        Step(id: 5, tab: 4, icon: "person.crop.rectangle.stack",
             title: "Hiányzások — igazolt, igazolatlan, késés",
             body: "Egy helyen látod, mennyit hiányoztál, és mi vár még igazolásra.",
             tips: [Tip(icon: "exclamationmark.circle", text: "Az igazolatlanok mindig felül vannak, hogy ne maradjanak el.")]),
        Step(id: 6, tab: 0, icon: "checkmark.seal.fill",
             title: "Készen állsz!",
             body: "A Beállításokban vár még egy rövid túra: téma, kiemelőszín, Live Activity, értesítések, szinkron.",
             tips: [Tip(icon: "questionmark.circle", text: "Ezt a bemutatót a Beállítások ? gombjáról bármikor újraindíthatod."),
                    Tip(icon: "square.grid.2x2", text: "Tedd ki a Summit widgetet a kezdőképernyőre.")]),
    ]

    /// Az a lépés, amelyik az adott tabot mutatja (a záró lépés nem számít).
    static func stepIndex(forTab tab: Int) -> Int? {
        steps.firstIndex { $0.tab == tab && $0.id != steps.count - 1 }
    }
}

/// A túra kártyája. A nyitó lépésnél sötétített háttér előtt középen
/// kérdez (Mutasd / Most nem), utána alul ül, a tabsáv fölött.
struct AppTourOverlay: View {
    @Binding var step: Int?
    var accent: Color
    /// A saját dock / rendszer-tabsáv magassága — a kártya fölötte ül.
    var bottomClearance: CGFloat
    var onFinish: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        if let i = step, AppTour.steps.indices.contains(i) {
            let s = AppTour.steps[i]
            ZStack(alignment: s.tab == nil ? .center : .bottom) {
                if s.tab == nil {
                    // Csak a nyitó kérdésnél takar: utána a valódi
                    // képernyő látszik és nyomkodható.
                    Color.black.opacity(0.55)
                        .ignoresSafeArea()
                        .onTapGesture {}
                        .transition(.opacity)
                }
                card(s, index: i)
                    .frame(maxWidth: 520)
                    .padding(.horizontal, 16)
                    .padding(.bottom, s.tab == nil ? 0 : bottomClearance + 8)
                    .id(i)
                    .transition(reduceMotion ? .opacity : .move(edge: .bottom).combined(with: .opacity))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: s.tab == nil ? .center : .bottom)
            .animation(reduceMotion ? nil : SummitMotion.snappy, value: i)
        }
    }

    private var lastIndex: Int { AppTour.steps.count - 1 }

    private func card(_ s: AppTour.Step, index i: Int) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                SkinIcon(s.icon, size: 18)
                    .skinFont(.subheadline, weight: .semibold)
                    .foregroundStyle(NeonTheme.isActive ? NeonTheme.yellow : VoxelTheme.isActive ? .white : accent)
                    .frame(width: 30, height: 30)
                    .background {
                        if !VoxelTheme.isActive && !NeonTheme.isActive {
                            Circle().fill(accent.opacity(0.15))
                        }
                    }
                    .accessibilityHidden(true)
                if s.tab != nil { counter(i) }
                Spacer()
                if i < lastIndex {
                    Button(s.tab == nil ? "Most nem" : "Kihagyás") { finish() }
                        .skinFont(.caption, weight: .semibold)
                        .voxelInlineButton()
                }
            }

            Text(s.title)
                .skinFont(.headline)
                .fixedSize(horizontal: false, vertical: true)
            Text(s.body)
                .skinFont(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if !s.tips.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(s.tips, id: \.self) { tip in
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            SkinIcon(tip.icon, size: 14)
                                .skinFont(.caption, weight: .semibold)
                                .foregroundStyle(NeonTheme.isActive ? NeonTheme.cyan : accent)
                                .frame(width: 18)
                                .accessibilityHidden(true)
                            Text(tip.text)
                                .skinFont(.footnote)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                .padding(.top, 2)
            }

            HStack {
                if s.tab != nil {
                    Button("Vissza") { go(i - 1) }
                        .skinFont(.subheadline, weight: .semibold)
                        .disabled(i <= 1)
                        .voxelInlineButton()
                }
                Spacer()
                if s.tab == nil {
                    Button("Mutasd") { go(1) }
                        .skinFont(.subheadline, weight: .bold)
                        .tourPrimary()
                } else if i < lastIndex {
                    Button("Tovább") { go(i + 1) }
                        .skinFont(.subheadline, weight: .bold)
                        .tourPrimary()
                } else {
                    Button("Kész") { finish() }
                        .skinFont(.subheadline, weight: .bold)
                        .tourPrimary()
                }
            }
            .tint(accent)
            .padding(.top, 2)
        }
        .padding(16)
        .modifier(TourCardSurface(accent: accent))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Bemutató")
    }

    @ViewBuilder
    private func counter(_ i: Int) -> some View {
        let total = AppTour.steps.count - 1
        if NeonTheme.isActive {
            NeonLabel(String(format: "Bemutató // %02d/%02d", i, total),
                      color: NeonTheme.yellow, bracketed: false, size: 10)
                .accessibilityLabel("Bemutató, \(i). lépés a \(total)-ból")
        } else {
            Text("Bemutató • \(i)/\(total)")
                .skinFont(.caption2, weight: .bold)
                .foregroundStyle(.secondary)
        }
    }

    private func go(_ i: Int) {
        guard AppTour.steps.indices.contains(i) else { return }
        SummitHaptics.selection()
        step = i
    }

    private func finish() {
        SummitHaptics.light()
        step = nil
        onFinish()
    }
}

private extension View {
    /// A túra fő gombja: Summitban kitöltött kapszula, a többi skinben
    /// a kiemelt inline gomb.
    @ViewBuilder
    func tourPrimary() -> some View {
        if VoxelTheme.isActive || NeonTheme.isActive {
            self.voxelInlineButton(prominent: true)
        } else {
            self.buttonStyle(.borderedProminent).buttonBorderShape(.capsule)
        }
    }
}
