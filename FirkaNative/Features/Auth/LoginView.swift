import SwiftUI

struct LoginView: View {
    @EnvironmentObject var theme: ThemeStore
    @EnvironmentObject var session: SessionStore
    @EnvironmentObject var kreta: KretaClient
    @StateObject private var vm = AuthViewModel()
    @State private var showWeb = false
    @State private var tapCount = 0
    @Environment(\.colorScheme) var scheme
    @Environment(\.horizontalSizeClass) private var hSize
    private var isPad: Bool { hSize == .regular }
    var colors: AppColors { theme.colors(for: scheme) }

    var body: some View {
        VStack {
            Spacer()
            // Rejtett demo-belépés: 10 koppintás az ikonon
            Image("ic_rounded", bundle: nil).resizable().frame(width: 72, height: 72).clipShape(Circle())
                .onTapGesture { tapCount+=1; if tapCount>=10 { vm.loginDemo(session: session); tapCount=0 } }
                .padding(.bottom, 24)
            Text("Hi.").font(.system(size: 64, weight: .bold, design: .rounded)).tracking(-1.5)
                .padding(.bottom, 48)
            Button { showWeb = true } label: {
                Text("Bejelentkezés").font(.headline.weight(.semibold)).frame(maxWidth: .infinity).padding(.vertical, 6)
            }
            .buttonStyle(.glassProminent).tint(colors.accent)
            .frame(maxWidth: isPad ? 320 : 280)
            if vm.isLoading { ProgressView().padding(.top, 16) }
            if let e = vm.error { Text(e).font(.footnote).foregroundStyle(.red).multilineTextAlignment(.center).padding(.top, 16) }
            Spacer()
        }
        .padding(.horizontal, 32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(colors.background)
        .tint(colors.accent)
        .sheet(isPresented: $showWeb) {
            NavigationStack {
                KretaWebView(onCode: { code in showWeb=false; Task { await vm.handleCode(code, kreta: kreta, session: session) } }, onDemo: { showWeb=false; vm.loginDemo(session: session) })
                    .ignoresSafeArea().navigationTitle("e-KRÉTA").navigationBarTitleDisplayMode(.inline)
                    .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Mégse"){ showWeb=false } }; ToolbarItem(placement: .primaryAction){ Button("Demo"){ showWeb=false; vm.loginDemo(session:session)} } }
            }.presentationDetents([.large]).presentationDragIndicator(.visible)
        }
    }
}
