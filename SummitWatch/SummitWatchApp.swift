import SwiftUI

// MARK: - Summit Watch — belépő
// Három tab: Órarend + Jegyek + Jegyzet. Adat az iPhone-os Summitból jön
// WatchConnectivity applicationContext-tel (WatchSyncStore) —
// az órán nincs bejelentkezés, nincs KRÉTA-hívás, nincs Live Activity
// (az átmegy iPhone-ról).
@main
struct SummitWatchApp: App {
    @StateObject private var store = WatchSyncStore()

    var body: some Scene {
        WindowGroup {
            WatchContentView()
                .environmentObject(store)
        }
    }
}

struct WatchContentView: View {
    @State private var selectedTab = 0

    var body: some View {
        // Rendszer-pöttyök helyett saját, nagyobb körök: látszik,
        // hogy arrébb lehet húzni. Csak kijelzés, nem fogad tapot.
        // ZStack-ben (nem .overlay-jel), hogy minden watchOS-verzión
        // biztosan a lapok fölött legyen.
        ZStack(alignment: .bottom) {
            TabView(selection: $selectedTab) {
                TimetableWatchView()
                    .tag(0)
                    .tabItem { Label("Órarend", systemImage: "clock") }
                GradesWatchView()
                    .tag(1)
                    .tabItem { Label("Jegyek", systemImage: "list.number") }
                CheatWatchView()
                    .tag(2)
                    .tabItem { Label("Jegyzet", systemImage: "doc.text") }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            HStack(spacing: 7) {
                ForEach(0..<3, id: \.self) { i in
                    Circle()
                        .fill(i == selectedTab ? Color.white : Color.white.opacity(0.35))
                        .frame(width: 8, height: 8)
                }
            }
            .padding(.bottom, 3)
            .allowsHitTesting(false)
        }
        .ignoresSafeArea(edges: .bottom)
    }
}
