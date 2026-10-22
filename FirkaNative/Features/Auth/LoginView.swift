import SwiftUI

struct LoginView: View {
    @EnvironmentObject var theme: ThemeStore
    @EnvironmentObject var session: SessionStore
    @EnvironmentObject var kreta: KretaClient
    @StateObject private var vm = AuthViewModel()
    @State private var showWeb = false
    @State private var webError: String?
    @State private var showReviewer = false
    @State private var reviewerUser = ""
    @State private var reviewerPass = ""
    @State private var reviewerError: String?
    @Environment(\.colorScheme) var scheme
    @Environment(\.horizontalSizeClass) private var hSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var bgZoom = false
    private var isPad: Bool { hSize == .regular }
    var colors: AppColors { theme.colors(for: scheme) }

    var body: some View {
        ZStack {
            // Gleccser háttérkép (asset katalógus) — sötét átmenettel az olvashatóságért.
            // Alig észrevehető, lassú közelítés (ken-burns): életet ad a belépésnek,
            // de nem mozog "önmagáért". Reduce Motion mellett áll.
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

            VStack {
                Spacer()
                Text("Summit")
                    .mcDisplay(64)
                    .tracking(-1.5)
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.4), radius: 8, y: 2)
                    .summitEntrance(delay: 0.05)
                Spacer()
                if vm.isLoading { ProgressView().tint(.white).padding(.bottom, 12) }
                if let e = vm.error { Text(e).font(.footnote).foregroundStyle(.white).multilineTextAlignment(.center).padding(.bottom, 12).shadow(color: .black.opacity(0.5), radius: 4) }
            }
            .padding(.horizontal, 32)
            // Sikertelen belépés = hibás kimenet: a VStack végig él, így a
            // nil → üzenet váltás egyszeri error-rezzenést ad a szöveggel együtt.
            .summitErrorHaptic(trigger: vm.error ?? "")
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .tint(colors.accent)
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 10) {
                Button { webError = nil; showWeb = true } label: {
                    if MinecraftTheme.isActive {
                        Text("Bejelentkezés E.KRÉTÁVAL")
                            .frame(maxWidth: .infinity)
                            .minecraftButton()
                    } else {
                        Text("Bejelentkezés E.KRÉTÁVAL")
                            .font(.headline.weight(.semibold))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .functionalGlass(cornerRadius: 14)
                    }
                }
                .buttonStyle(.plain)
                Button { reviewerError = nil; showReviewer = true } label: {
                    if MinecraftTheme.isActive {
                        Text("Bejelentkezés felhasználónévvel és jelszóval")
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                            .frame(maxWidth: .infinity)
                            .minecraftButton()
                    } else {
                        Text("Bejelentkezés felhasználónévvel és jelszóval")
                            .font(.headline.weight(.semibold))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .functionalGlass(cornerRadius: 14, tint: colors.accent.opacity(0.45))
                    }
                }
                .buttonStyle(.plain)
            }
            .frame(maxWidth: isPad ? 320 : .infinity)
            .padding(.horizontal, 32)
            .padding(.bottom, 24)
            .summitEntrance(delay: 0.2)
        }
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeOut(duration: 14)) { bgZoom = true }
        }
        .sheet(isPresented: $showWeb) {
            NavigationStack {
                VStack(spacing: 0) {
                    KretaWebView(onCode: { code in showWeb=false; Task { await vm.handleCode(code, kreta: kreta, session: session) } }, onDemo: { showWeb=false; vm.loginDemo(session: session) }, onError: { msg in webError = msg })
                        .ignoresSafeArea()
                    if let err = webError {
                        VStack(spacing: 8) {
                            Text("A KRÉTA-oldal nem tölthető be itt (\(err)). Ez külföldről előfordulhat.")
                                .font(.footnote).multilineTextAlignment(.center).foregroundStyle(.secondary)
                            Button("Folytatás demo módban") { showWeb=false; webError=nil; vm.loginDemo(session: session) }
                                .buttonStyle(.borderedProminent)
                        }
                        .padding()
                        .background(.thinMaterial)
                    }
                }
                .navigationTitle("e-KRÉTA").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Mégse"){ webError=nil; showWeb=false } }; ToolbarItem(placement: .primaryAction){ Button("Demo"){ showWeb=false; webError=nil; vm.loginDemo(session:session)} } }
            }.presentationDetents([.large]).presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showReviewer) {
            NavigationStack {
                VStack(spacing: 16) {
                    Text("Add meg a felhasználóneved és a jelszavad.")
                        .font(.subheadline).foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                    TextField("Felhasználónév", text: $reviewerUser)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .textContentType(.username)
                        .summitInput()
                    SecureField("Jelszó", text: $reviewerPass)
                        .textContentType(.password)
                        .summitInput()
                    if let err = reviewerError {
                        Text(err).font(.footnote).foregroundStyle(.red)
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
                            .font(.headline.weight(.semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(reviewerUser.isEmpty || reviewerPass.isEmpty)
                    Spacer()
                }
                .padding()
                // Hibás jelszó = hibás kimenet: a sheet-tartalom végig él.
                .summitErrorHaptic(trigger: reviewerError ?? "")
                .navigationTitle("Bejelentkezés").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Mégse") { reviewerPass = ""; showReviewer = false } } }
            }.presentationDetents([.medium]).presentationDragIndicator(.visible)
        }
    }
}
