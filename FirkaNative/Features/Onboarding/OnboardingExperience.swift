import SwiftUI

/// Első letöltés utáni, teljes képernyős bemutató — KIZÁRÓLAG az app
/// valódi elemeiből: a nyitó lap a belépő képernyő gleccsere és címe,
/// utána minden lépés az igazi képernyő (natív nagy címsor, Summit-lista,
/// a valódi kártyák/sorok demo adatokkal, animálva), alul a Beállítások-
/// túrából ismert kártya magyarázattal. Egyszer jön fel (`seenKey`), a
/// belépő képernyő „Mit tud a Summit?" gombjáról újranyitható.
struct OnboardingExperience: View {
    static let seenKey = "onboarding.experience.seen.v2"

    var onFinish: () -> Void

    @EnvironmentObject var theme: ThemeStore
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// 0 = nyitó lap, 1… = a képernyők.
    @State private var step = 0
    @State private var forward = true

    struct Step {
        let title: String
        let headline: String
        let body: String
    }

    static let steps: [Step] = [
        Step(title: "Főoldal", headline: "A napod egy pillantásra",
             body: "Az élő órakártya mutatja, mi megy most, mennyi van hátra és mi jön utána. Alatta a közelgő házik és dolgozatok."),
        Step(title: "Jegyek", headline: "Átlag, ahogy a tanár számolja",
             body: "Súlyozott átlag tantárgyanként, havi grafikonnal és tanári kerekítéssel. Egy tárgyra koppintva a fantom jeggyel előre számolhatsz."),
        Step(title: "Órarend", headline: "Helyettesítéssel együtt",
             body: "A napod órái teremmel, a házikkal és dolgozatokkal; az elmaradt órát és a helyettesítést is jelöli. Oldalra húzva napot váltasz."),
        Step(title: "Feladatok", headline: "Semmi nem csúszik el",
             body: "Házik és bejelentett dolgozatok határidő szerint. Pipáld ki, amit megcsináltál — új jegyről, házifeladatról és dolgozatról értesítést kapsz."),
        Step(title: "Hiányzások", headline: "Igazolt, igazolatlan, késés",
             body: "Egy helyen látod, mennyit hiányoztál és mi vár még igazolásra. Az adataid a telefonodon maradnak."),
    ]

    private var colors: AppColors { theme.colors(for: scheme) }
    private var lastStep: Int { Self.steps.count }

    var body: some View {
        ZStack {
            if step == 0 {
                welcome
                    .transition(.opacity)
            } else {
                screen(step)
                    .id(step)
                    .transition(stepTransition)
            }
        }
        .animation(reduceMotion ? .easeInOut(duration: 0.25) : SummitMotion.gentle, value: step)
        .tint(colors.accent)
    }

    private var stepTransition: AnyTransition {
        if reduceMotion { return .opacity }
        let edge: Edge = forward ? .trailing : .leading
        return .asymmetric(insertion: .move(edge: edge).combined(with: .opacity),
                           removal: .move(edge: forward ? .leading : .trailing).combined(with: .opacity))
    }

    // MARK: - Nyitó lap (a belépő képernyő elemei)

    private var welcome: some View {
        ZStack {
            if theme.isNeon {
                NeonBackdrop()
            } else if theme.isVoxel {
                VoxelMenuBackground()
            } else {
                GeometryReader { geo in
                    Image("Glacier")
                        .resizable()
                        .scaledToFill()
                        .frame(width: geo.size.width, height: geo.size.height)
                        .clipped()
                }
                .ignoresSafeArea()
                LinearGradient(colors: [.black.opacity(0.55), .black.opacity(0.2), .black.opacity(0.7)],
                               startPoint: .top, endPoint: .bottom)
                    .ignoresSafeArea()
            }

            VStack(spacing: 14) {
                Spacer()
                Text("Summit")
                    .voxelDisplay(64)
                    .tracking(-1.5)
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.4), radius: 8, y: 2)
                    .summitEntrance(delay: 0.05)
                Text("Az e-KRÉTÁD gyorsan, szépen, egy helyen.\nNézd meg egy perc alatt, mit tud.")
                    .skinFont(.body)
                    .foregroundStyle(.white.opacity(0.85))
                    .multilineTextAlignment(.center)
                    .summitEntrance(delay: 0.15)
                Spacer()
            }
            .padding(.horizontal, 32)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 10) {
                Button { go(1) } label: {
                    glassLabel("Mutasd", tint: colors.accent.opacity(0.45))
                }
                .welcomeButton(.primary)
                Button { finish() } label: {
                    glassLabel("Kihagyom, belépek", tint: nil)
                }
                .welcomeButton(.secondary)
            }
            .frame(maxWidth: 440)
            .padding(.horizontal, 32)
            .padding(.bottom, 24)
            .summitEntrance(delay: 0.25)
        }
    }

    /// A belépő képernyő gombjainak felirata (Liquid Glass Summitban,
    /// a többi skinben a gombstílus adja a keretet).
    @ViewBuilder
    private func glassLabel(_ title: String, tint: Color?) -> some View {
        if theme.isVoxel || theme.isNeon {
            Text(title).frame(maxWidth: .infinity)
        } else {
            Text(title)
                .skinFont(.headline, weight: .semibold)
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .functionalGlass(cornerRadius: 14, tint: tint)
        }
    }

    // MARK: - Képernyő-lépések (valódi nézetek demo adatokkal)

    private func screen(_ i: Int) -> some View {
        let s = Self.steps[i - 1]
        return NavigationStack {
            stepContent(i)
                .navigationTitle(s.title)
                .navigationBarTitleDisplayMode(.large)
                .summitToolbarBackground()
                .toolbar {
                    SkinToolbarItem(placement: .primaryAction) {
                        Button("Kihagyás") { finish() }
                    }
                }
                .safeAreaInset(edge: .bottom) {
                    OnboardingStepCard(index: i, total: Self.steps.count, step: s, accent: colors.accent,
                                       onBack: { go(i - 1) },
                                       onNext: { i == lastStep ? finish() : go(i + 1) })
                }
        }
    }

    @ViewBuilder
    private func stepContent(_ i: Int) -> some View {
        switch i {
        case 1: OnboardingHomeStep()
        case 2: OnboardingGradesStep()
        case 3: OnboardingTimetableStep()
        case 4: OnboardingTasksStep()
        default: OnboardingAbsencesStep()
        }
    }

    private func go(_ target: Int) {
        guard (0...lastStep).contains(target), target != step else { return }
        SummitHaptics.selection()
        forward = target > step
        step = target
    }

    private func finish() {
        SummitHaptics.light()
        onFinish()
    }
}

/// A lépés magyarázó kártyája — a Beállítások-túra kártyájának
/// (`SettingsTourCard`) felépítése és felülete (`TourCardSurface`).
private struct OnboardingStepCard: View {
    let index: Int
    let total: Int
    let step: OnboardingExperience.Step
    let accent: Color
    var onBack: () -> Void
    var onNext: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            counter
            Text(step.headline).skinFont(.headline)
            Text(step.body).skinFont(.subheadline).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Button("Vissza") { onBack() }
                    .skinFont(.subheadline, weight: .semibold)
                    .voxelInlineButton()
                Spacer()
                Button(index == total ? "Belépés" : "Tovább") { onNext() }
                    .skinFont(.subheadline, weight: .bold)
                    .voxelInlineButton(prominent: NeonTheme.isActive)
            }
            .tint(accent)
        }
        .padding(16)
        .modifier(TourCardSurface(accent: accent))
        .frame(maxWidth: 560)
        .padding(.horizontal, 16)
        .padding(.bottom, 12)
    }

    @ViewBuilder
    private var counter: some View {
        if NeonTheme.isActive {
            NeonLabel(String(format: "Bemutató // %02d/%02d", index, total),
                      color: NeonTheme.yellow, bracketed: false, size: 10)
                .accessibilityLabel("Bemutató, \(index). lépés a \(total)-ból")
        } else {
            Text("Bemutató • \(index)/\(total)")
                .skinFont(.caption2, weight: .bold).foregroundStyle(.secondary)
        }
    }
}

private extension View {
    /// A belépő képernyő gombstílusa (lásd `LoginView.cpLoginButton`).
    @ViewBuilder
    func welcomeButton(_ kind: NeonButtonStyle.Kind) -> some View {
        if NeonTheme.isActive {
            self.buttonStyle(NeonButtonStyle(kind: kind, fullWidth: true))
        } else {
            self.voxelButtonOrPlain(compact: false)
        }
    }
}
