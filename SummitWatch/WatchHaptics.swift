import SwiftUI
#if os(watchOS)
import WatchKit
#endif

// MARK: - WatchHaptics — az óra egyetlen haptikus belépője
//
// Az órán CSAK ez az egyféle rezzenés van: halk `.click` a saját
// koppintásra (napléptetés). A sor-lenyitások a beépített
// `.sensoryFeedback(.selection, …)`-et használják közvetlenül.
// Szinkron-érkezéskor, navigációkor, tabváltáskor NINCS haptika —
// a csukló erősít, a Taptic Engine itt hamar "földrengés".
#if os(watchOS)
enum WatchHaptics {
    /// Egyetlen halk tick — csak a user saját koppintására hívd,
    /// soha programozott állapotváltozásra (szinkron, smartSelect).
    static func tick() {
        WKInterfaceDevice.current().play(.click)
    }
}
#endif
