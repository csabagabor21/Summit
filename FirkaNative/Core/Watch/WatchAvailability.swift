import Combine
import Foundation

#if !targetEnvironment(macCatalyst)
import WatchConnectivity
#endif

// MARK: - Óra-elérhetőség a Watch tab láthatóságához
// Csak párosított óra esetén látszik a Watch tab — óra nélkül nincs
// mit az órára tolni. WCSession-delegate nem kell hozzá (csak olvasunk),
// a delegate továbbra is a WatchSyncSender marad.
// Mac Catalysten és órát párosítani nem tudó eszközön (iPad) sosem látszik.
final class WatchAvailability: ObservableObject {
    static let shared = WatchAvailability()

    @Published private(set) var hasWatch: Bool = false

    private var cancellables = Set<AnyCancellable>()

    private init() {
        hasWatch = Self.current()
        // Aktiválás/push után a watch-riport frissül — arra újraszámolunk,
        // így a párosítás után magától megjelenik a tab, alkalmazás-újraindítás nélkül.
        NotificationCenter.default.publisher(for: WatchSyncSender.reportChanged)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.refresh() }
            .store(in: &cancellables)
    }

    /// Előtérbe hozáskor / megjelenéskor hívandó (a párosítás az app
    /// futása közben is változhat — pl. Watch appban párosítasz).
    func refresh() {
        let v = Self.current()
        if v != hasWatch { hasWatch = v }
    }

    private static func current() -> Bool {
        #if targetEnvironment(macCatalyst)
        return false
        #else
        guard WCSession.isSupported() else { return false }
        return WCSession.default.isPaired
        #endif
    }
}
