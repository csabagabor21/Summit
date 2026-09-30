import Combine
import Foundation

#if !targetEnvironment(macCatalyst)
import WatchConnectivity
#endif

// MARK: - Óra-elérhetőség a Watch tab láthatóságához
// Helyi párosított óra VAGY szinkronizált órajelenlét esetén látszik
// a Watch tab: Mac Catalysten (ahol párosítás nincs) is lehet tab,
// ha a SummitSync `hasWatch` mezőjéből egy másik eszköz órája átjött —
// így Macről is lehet jegyzetet készíteni, ami átmegy a telefonra
// (és onnan az órára). WCSession-delegate nem kell hozzá (csak
// olvasunk), a delegate továbbra is a WatchSyncSender marad.
final class WatchAvailability: ObservableObject {
    static let shared = WatchAvailability()

    /// Ezen az eszközön párosított óra van-e.
    @Published private(set) var hasWatch: Bool = false
    /// Másik eszköz órája a szinkronból (Macen ez nyitja a tabot).
    @Published private(set) var peerHasWatch: Bool = false
    /// A tab láthatósága: helyi vagy távoli óra.
    var showTab: Bool { hasWatch || peerHasWatch }

    static let peerKey = "sync.peerHasWatch.v1"

    private var cancellables = Set<AnyCancellable>()

    private init() {
        hasWatch = Self.current()
        peerHasWatch = UserDefaults.standard.bool(forKey: Self.peerKey)
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

    /// A szinkronból jövő órajelenlét bejegyzése (SummitSync applyRemote).
    /// Perzisztált, így újraindítás után is megmarad a Mac-tab.
    func setPeerHasWatch(_ v: Bool) {
        if v != peerHasWatch {
            peerHasWatch = v
            UserDefaults.standard.set(v, forKey: Self.peerKey)
        }
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
