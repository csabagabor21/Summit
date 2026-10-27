import SwiftUI

struct LoginView: View {
    @EnvironmentObject var theme: ThemeStore
    @EnvironmentObject var session: SessionStore
    @EnvironmentObject var kreta: KretaClient
    @StateObject private var vm = AuthViewModel()
    @State private var showWeb = false
    @State private var webError: String?
    @State private var showReviewer = false
    /// A bemutató újranyitása a bal felső „Mit tud a Summit?" gombról.
    @State private var showWelcome = false
    @State private var reviewerUser = ""
    @State private var reviewerPass = ""
    @State private var reviewerError: String?
    @Environment(\.colorScheme) var scheme
    @Environment(\.horizontalSizeClass) private var hSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var bgZoom = false
    /// Neon: a „jack in" cím egyszeri glitch-rándulásának kioldója.
    @State private var cpBoot = 0
    private var isPad: Bool { hSize == .regular }
    var colors: AppColors { theme.colors(for: scheme) }

    /// Cím: Summitban nagy lágy-árnyékos felirat, Voxelben a főmenü
    /// logó-szerű, kemény (3 pixeles) árnyékú pixelbetűs címe; Neonban
    /// a HUD boot-képernyő sárga, kromatikus címe kód-sorokkal.
    @ViewBuilder
    private var titleText: some View {
        if theme.isNeon {
            NeonLoginTitle(boot: cpBoot)
        } else if theme.isVoxel {
            Text("Summit")
                .font(VoxelTheme.headerFont(size: 64))
                .foregroundStyle(Color(hex: 0xE0E0E0))
                .shadow(color: Color(hex: 0x3F3F3F), radius: 0, x: 2 * VoxelTheme.px, y: 2 * VoxelTheme.px)
                .minimumScaleFactor(0.5)
                .lineLimit(1)
        } else {
            Text("Summit")
                .voxelDisplay(64)
                .tracking(-1.5)
                .foregroundStyle(.white)
                .shadow(color: .black.opacity(0.4), radius: 8, y: 2)
        }
    }

    @ViewBuilder
    private func errorText(_ e: String) -> some View {
        if theme.isNeon {
            VStack(alignment: .leading, spacing: 6) {
                NeonLabel("Hiba // belépés", color: NeonTheme.red, bracketed: false, size: 10)
                Text(e).skinFont(.footnote).foregroundStyle(NeonTheme.text)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .cpPanel(accent: NeonTheme.red, padding: 12)
            .padding(.bottom, 12)
        } else if theme.isVoxel {
            Text(e).skinFont(.footnote).foregroundStyle(Color(hex: 0xFF5555)).multilineTextAlignment(.center).padding(.bottom, 12)
                .shadow(color: Color(hex: 0x3F3F3F), radius: 0, x: VoxelTheme.px / 1.5, y: VoxelTheme.px / 1.5)
        } else {
            Text(e).skinFont(.footnote).foregroundStyle(.white).multilineTextAlignment(.center).padding(.bottom, 12).shadow(color: .black.opacity(0.5), radius: 4)
        }
    }

    var body: some View {
        ZStack {
            // Gleccser háttérkép (asset katalógus) — sötét átmenettel az olvashatóságért.
            // Alig észrevehető, lassú közelítés (ken-burns): életet ad a belépésnek,
            // de nem mozog "önmagáért". Reduce Motion mellett áll.
            // Voxel-skin: a játék főmenüje — föld-csempe háttér, kő-gombok.
            // Neon-skin: statikus HUD-háttér (rács, scanline), zoom nélkül.
            if theme.isNeon {
                NeonBackdrop()
            } else if theme.isVoxel {
                VoxelMenuBackground()
            } else {
                Image("Glacier")
                    .resizable()
                    .scaledToFill()
                    .scaleEffect(bgZoom ? 1.07 : 1.0)
                    .ignoresSafeArea()
                LinearGradient(
                    colors: [.black.opacity(0.55), .black.opacity(0.2), .black.opacity(0.7)],
                    startPoint: .top, endPoint: .bottom
                )
                .ignoresSafeArea()
            }

            VStack {
                Spacer()
                titleText
                    .summitEntrance(delay: 0.05)
                Spacer()
                if vm.isLoading {
                    if theme.isNeon {
                        NeonLoginLoading().padding(.bottom, 12)
                    } else {
                        SkinProgress(color: .white).tint(.white).padding(.bottom, 12)
                    }
                }
                if let e = vm.error { errorText(e) }
            }
            .padding(.horizontal, 32)
            // Sikertelen belépés = hibás kimenet: a VStack végig él, így a
            // nil → üzenet váltás egyszeri error-rezzenést ad a szöveggel együtt.
            .summitErrorHaptic(trigger: vm.error ?? "")
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .overlay(alignment: .topTrailing) {
            Button { showWelcome = true } label: {
                if theme.isVoxel || theme.isNeon {
                    Text("Mit tud a Summit?")
                } else {
                    Label("Mit tud a Summit?", systemImage: "sparkles")
                        .skinFont(.subheadline, weight: .semibold)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 9)
                        .functionalGlass(cornerRadius: 18)
                }
            }
            .voxelInlineButton()
            .padding(.trailing, 20)
            .padding(.top, 8)
            .summitEntrance(delay: 0.3)
        }
        .fullScreenCover(isPresented: $showWelcome) {
            WelcomeOnboardingView { showWelcome = false }
                // Cover: az örökölt environment hidegindításkor nem mindig
                // ér le (lásd AnalyticsConsentView) — explicit inject.
                .environmentObject(theme)
        }
        .tint(colors.accent)
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 10) {
                if theme.isNeon {
                    NeonLabel("Azonosítás // e-KRÉTA", color: NeonTheme.dim, size: 10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                Button { webError = nil; showWeb = true } label: {
                    if VoxelTheme.isActive || NeonTheme.isActive {
                        Text("Bejelentkezés E.KRÉTÁVAL")
                            .frame(maxWidth: .infinity)
                    } else {
                        Text("Bejelentkezés E.KRÉTÁVAL")
                            .skinFont(.headline, weight: .semibold)
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .functionalGlass(cornerRadius: 14)
                    }
                }
                .cpLoginButton(.primary)
                Button { reviewerError = nil; showReviewer = true } label: {
                    if VoxelTheme.isActive || NeonTheme.isActive {
                        Text("Bejelentkezés felhasználónévvel és jelszóval")
                            .multilineTextAlignment(.center)
                            .modifier(NeonTwoLineLabel())
                            .frame(maxWidth: .infinity)
                    } else {
                        Text("Bejelentkezés felhasználónévvel és jelszóval")
                            .skinFont(.headline, weight: .semibold)
                            .foregroundStyle(.white)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .functionalGlass(cornerRadius: 14, tint: colors.accent.opacity(0.45))
                    }
                }
                .cpLoginButton(.secondary)
            }
            .frame(maxWidth: isPad ? 440 : .infinity)
            .padding(.horizontal, 32)
            .padding(.bottom, 24)
            .summitEntrance(delay: 0.2)
        }
        .onAppear {
            cpBoot += 1
            guard !reduceMotion else { return }
            withAnimation(.easeOut(duration: 14)) { bgZoom = true }
        }
        .sheet(isPresented: $showWeb) {
            NavigationStack {
                VStack(spacing: 0) {
                    KretaWebView(onCode: { code, verifier in showWeb=false; Task { await vm.handleCode(code, codeVerifier: verifier, kreta: kreta, session: session) } }, onDemo: { showWeb=false; vm.loginDemo(session: session) }, onError: { msg in webError = msg })
                        .ignoresSafeArea()
                    if let err = webError {
                        VStack(spacing: 8) {
                            Text("A KRÉTA-oldal nem tölthető be itt (\(err)). Ez külföldről előfordulhat.")
                                .skinFont(.footnote).multilineTextAlignment(.center).foregroundStyle(.secondary)
                            Button("Folytatás demo módban") { showWeb=false; webError=nil; vm.loginDemo(session: session) }
                                .skinBorderedButton(prominent: true)
                        }
                        .padding()
                        .modifier(WebErrorSurface())
                    }
                }
                .navigationTitle("e-KRÉTA").navigationBarTitleDisplayMode(.inline)
                .toolbar { SkinToolbarItem(placement: .cancellationAction) { Button("Mégse"){ webError=nil; showWeb=false } }; SkinToolbarItem(placement: .primaryAction){ Button("Demo"){ showWeb=false; webError=nil; vm.loginDemo(session:session)} } }
            }.presentationDetents([.large]).presentationDragIndicator(.visible).skinSheetBackground()
        }
        .sheet(isPresented: $showReviewer) {
            NavigationStack {
                VStack(spacing: 16) {
                    Text("Add meg a felhasználóneved és a jelszavad.")
                        .skinFont(.subheadline).foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                    TextField("Felhasználónév", text: $reviewerUser, prompt: skinPrompt("Felhasználónév"))
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .textContentType(.username)
                        .summitInput()
                    SecureField("Jelszó", text: $reviewerPass, prompt: skinPrompt("Jelszó"))
                        .textContentType(.password)
                        .summitInput()
                    if let err = reviewerError {
                        Text(err).skinFont(.footnote).foregroundStyle(theme.isNeon ? NeonTheme.red : .red)
                    }
                    Button {
                        if vm.loginReviewer(username: reviewerUser, password: reviewerPass, session: session) {
                            reviewerPass = ""
                            showReviewer = false
                        } else {
                            reviewerError = vm.error
                        }
                    } label: {
                        Text("Bejelentkezés")
                            .skinFont(.headline, weight: .semibold)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, theme.isNeon ? 2 : 14)
                    }
                    .skinBorderedButton(prominent: true)
                    .disabled(reviewerUser.isEmpty || reviewerPass.isEmpty)
                    Spacer()
                }
                .padding()
                // Hibás jelszó = hibás kimenet: a sheet-tartalom végig él.
                .summitErrorHaptic(trigger: reviewerError ?? "")
                .navigationTitle("Bejelentkezés").navigationBarTitleDisplayMode(.inline)
                .toolbar { SkinToolbarItem(placement: .cancellationAction) { Button("Mégse") { reviewerPass = ""; showReviewer = false } } }
            }.presentationDetents([.medium]).presentationDragIndicator(.visible).skinSheetBackground()
        }
    }
}

/// A web-bejelentkezés hibasávjának háttere: Summitban a vékony anyag,
/// Voxelben a játék dialógus-panelje, Neonban vörös keretes HUD-panel.
private struct WebErrorSurface: ViewModifier {
    func body(content: Content) -> some View {
        if NeonTheme.isActive {
            content.background { NeonPanelBackground(accent: NeonTheme.red, corners: .none, showsTab: true) }
        } else if VoxelTheme.isActive {
            content.background { VoxelBlockPanel(face: VoxelTheme.panelFace, castsShadow: false) }
        } else {
            content.background(.thinMaterial)
        }
    }
}

// MARK: - Neon belépés ("jack in")

/// A boot-képernyő címblokkja: cián rendszer-kód, nagy sárga SUMMIT
/// statikus kromatikus szellemképpel, alatta vékony HUD-vonal és állapot-kód.
/// A glitch csak egyszer, megjelenéskor fut (Reduce Motion mellett sosem).
private struct NeonLoginTitle: View {
    var boot: Int

    var body: some View {
        VStack(spacing: 12) {
            NeonLabel("Summit//OS · e-KRÉTA kliens", color: NeonTheme.cyan, size: 11)
            Text("SUMMIT")
                .font(NeonTheme.display(size: 76, weight: .bold, relativeTo: .largeTitle))
                .tracking(8)
                .foregroundStyle(NeonTheme.yellow)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
                .cpChromatic(1.5)
                .cpGlitch(trigger: boot)
                .accessibilityLabel("Summit")
            HStack(spacing: 8) {
                Rectangle().fill(NeonTheme.yellow).frame(width: 22, height: 2)
                Rectangle().fill(NeonTheme.yellow.opacity(0.35)).frame(height: 1)
                Text("NEURAL LINK // KÉSZ")
                    .font(NeonTheme.mono(size: 10, relativeTo: .caption2))
                    .foregroundStyle(NeonTheme.dim)
                    .lineLimit(1)
                    .fixedSize()
            }
            .frame(maxWidth: 280)
            .accessibilityHidden(true)
        }
    }
}

/// Belépés közbeni állapotsor: pörgő + egyenközű „kapcsolódás" kód.
private struct NeonLoginLoading: View {
    var body: some View {
        HStack(spacing: 10) {
            SkinProgress(color: NeonTheme.cyan).tint(NeonTheme.cyan)
            Text("> KAPCSOLÓDÁS A KRÉTÁHOZ…")
                .font(NeonTheme.mono(size: 11, relativeTo: .caption))
                .foregroundStyle(NeonTheme.cyan)
        }
        .accessibilityElement(children: .combine)
    }
}

/// Neonban a hosszú gombfelirat két sorba törhet (a CP-gomb alapból
/// egysoros); a többi skinben nem nyúl semmihez.
private struct NeonTwoLineLabel: ViewModifier {
    func body(content: Content) -> some View {
        if NeonTheme.isActive {
            content.lineLimit(2).minimumScaleFactor(0.85)
        } else {
            content
        }
    }
}

private extension View {
    /// Belépő-gomb stílusa: Neonban teljes szélességű CP-gomb (sárga
    /// fő / cián másodlagos), egyébként a meglévő kő-gomb vagy sima gomb.
    @ViewBuilder
    func cpLoginButton(_ kind: NeonButtonStyle.Kind) -> some View {
        if NeonTheme.isActive {
            self.buttonStyle(NeonButtonStyle(kind: kind, fullWidth: true))
        } else {
            self.voxelButtonOrPlain(compact: false)
        }
    }
}
