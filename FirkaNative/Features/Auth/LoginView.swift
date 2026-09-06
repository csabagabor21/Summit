import SwiftUI

struct LoginView: View {
    @EnvironmentObject var theme: ThemeStore
    @EnvironmentObject var session: SessionStore
    @EnvironmentObject var kreta: KretaClient
    @StateObject private var vm = AuthViewModel()
    @State private var showWeb = false
    @Environment(\.colorScheme) var scheme
    @Environment(\.horizontalSizeClass) private var hSize
    private var isPad: Bool { hSize == .regular }
    var colors: AppColors { theme.colors(for: scheme) }

    var body: some View {
        ZStack {
            // Gleccser háttérkép (asset katalógus) — sötét átmenettel az olvashatóságért
            Image("Glacier")
                .resizable()
                .scaledToFill()
                .ignoresSafeArea()
            LinearGradient(
                colors: [.black.opacity(0.55), .black.opacity(0.2), .black.opacity(0.7)],
                startPoint: .top, endPoint: .bottom
            )
            .ignoresSafeArea()

            VStack {
                Spacer()
                Text("Summit")
                    .font(.system(size: 64, weight: .bold, design: .rounded))
                    .tracking(-1.5)
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.4), radius: 8, y: 2)
                Spacer()
                if vm.isLoading { ProgressView().tint(.white).padding(.bottom, 12) }
                if let e = vm.error { Text(e).font(.footnote).foregroundStyle(.white).multilineTextAlignment(.center).padding(.bottom, 12).shadow(color: .black.opacity(0.5), radius: 4) }
            }
            .padding(.horizontal, 32)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .tint(colors.accent)
        .safeAreaInset(edge: .bottom) {
            Button { showWeb = true } label: {
                Text("Bejelentkezés")
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .functionalGlass(cornerRadius: 14)
            }
            .buttonStyle(.plain)
            .frame(maxWidth: isPad ? 320 : .infinity)
            .padding(.horizontal, 32)
            .padding(.bottom, 24)
        }
        .sheet(isPresented: $showWeb) {
            NavigationStack {
                KretaWebView(onCode: { code in showWeb=false; Task { await vm.handleCode(code, kreta: kreta, session: session) } }, onDemo: { showWeb=false; vm.loginDemo(session: session) })
                    .ignoresSafeArea().navigationTitle("e-KRÉTA").navigationBarTitleDisplayMode(.inline)
                    .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Mégse"){ showWeb=false } }; ToolbarItem(placement: .primaryAction){ Button("Demo"){ showWeb=false; vm.loginDemo(session:session)} } }
            }.presentationDetents([.large]).presentationDragIndicator(.visible)
        }
    }
}
