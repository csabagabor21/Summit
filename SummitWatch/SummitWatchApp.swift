import SwiftUI

// MARK: - Summit Watch — belépő
// Három tab: Órarend + Jegyek + Feladatok. Adat az iPhone-os Summitból jön
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
    var body: some View {
        TabView {
            TimetableWatchView()
                .tabItem { Label("Órarend", systemImage: "clock") }
            GradesWatchView()
                .tabItem { Label("Jegyek", systemImage: "list.number") }
            TasksWatchView()
                .tabItem { Label("Feladatok", systemImage: "checklist") }
        }
    }
}
