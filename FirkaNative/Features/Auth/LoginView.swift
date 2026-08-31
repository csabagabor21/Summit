import SwiftUI

struct LoginView: View {
    @EnvironmentObject var theme: ThemeStore
    @EnvironmentObject var session: SessionStore
    @EnvironmentObject var kreta: KretaClient
    @StateObject private var vm = AuthViewModel()
    @State private var showWeb = false
    @State private var tapCount = 0
    @Environment(\.colorScheme) var scheme
    var colors: AppColors { theme.colors(for: scheme) }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(spacing: 8) {
                            Image("ic_rounded", bundle: nil).resizable().frame(width: 28, height: 28).clipShape(Circle())
                                .onTapGesture { tapCount+=1; if tapCount>=10 { vm.loginDemo(session: session); tapCount=0 } }
                            Text("Flint").font(.headline.weight(.bold))
                        }
                        Text("Üdv a Flintben!").font(.largeTitle.weight(.bold)).tracking(-0.5)
                        Text("A nem hivatalos e-KRÉTA kliens diákoktól diákoknak. Valós idejű jegyek, órarend és feladatok — minimalista, Apple-szerű élményben.")
                            .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    }
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets(top: 20, leading: 16, bottom: 12, trailing: 16))
                    .listRowSeparator(.hidden)
                }

                Section {
                    TabView {
                        ForEach(1...4, id: \.self) { i in
                            VStack(alignment: .leading, spacing: 10) {
                                Text(welcomeTitle(i)).font(.headline)
                                Text(welcomeText(i)).font(.subheadline).foregroundStyle(.secondary)
                                Image("showcase\(i)", bundle: nil).resizable().scaledToFit().clipShape(RoundedRectangle(cornerRadius: 12))
                            }.padding(.vertical, 8)
                        }
                    }
                    .frame(height: 320)
                    .tabViewStyle(.page(indexDisplayMode: .always))
                    .listRowInsets(EdgeInsets(top: 0, leading: 8, bottom: 0, trailing: 8))
                }

                Section {
                    Button { showWeb = true } label: {
                        Text("Bejelentkezés e-KRÉTA fiókkal").font(.headline.weight(.semibold)).frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.glassProminent).tint(colors.accent).listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 4, trailing: 16)).listRowBackground(Color.clear).listRowSeparator(.hidden)
                    Button("Adatkezelési tájékoztató") { if let u=URL(string:"https://flint.app/privacy"){ UIApplication.shared.open(u)} }
                        .font(.caption.weight(.medium)).foregroundStyle(.secondary).frame(maxWidth:.infinity).listRowBackground(Color.clear).listRowSeparator(.hidden)
                    if let e = vm.error { Text(e).font(.footnote).foregroundStyle(.red).listRowBackground(Color.clear) }
                    if vm.isLoading { ProgressView().frame(maxWidth:.infinity).listRowBackground(Color.clear).listRowSeparator(.hidden) }
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(colors.background)
            .navigationBarHidden(true)
        }
        .tint(colors.accent)
        .sheet(isPresented: $showWeb) {
            NavigationStack {
                KretaWebView(onCode: { code in showWeb=false; Task { await vm.handleCode(code, kreta: kreta, session: session) } }, onDemo: { showWeb=false; vm.loginDemo(session: session) })
                    .ignoresSafeArea().navigationTitle("e-KRÉTA").navigationBarTitleDisplayMode(.inline)
                    .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Mégse"){ showWeb=false } }; ToolbarItem(placement: .primaryAction){ Button("Demo"){ showWeb=false; vm.loginDemo(session:session)} } }
            }.presentationDetents([.large]).presentationDragIndicator(.visible)
        }
    }
    func welcomeTitle(_ i:Int)->String{ switch i{case 1:return "Minden jegyed egy helyen";case 2:return "Órarend, házik, hiányzások";case 3:return "Átlátható statisztikák";case 4:return "Üzenetek tanároktól";default:return""}}
    func welcomeText(_ i:Int)->String{ switch i{case 1:return "Valós idejű jegyek, átlagok és súlyok.";case 2:return "Kövesd az óráidat és határidőidet.";case 3:return "Letisztult, editorial hierarchia.";case 4:return "Olvasd közvetlenül az appból.";default:return""}}
}
