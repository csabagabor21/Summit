import SwiftUI
import WidgetKit

// MARK: - Summit watch widget bundle — Smart Stack
// Egy widget: a telefonos Főoldal MOST-kártyájának órai tükre.
// Adat: a WatchSyncStore UserDefaults-gyorsítótára (az óra app-pal közös
// sandbox), hálózat és bejelentkezés nélkül.
@main
struct SummitWatchWidgetsBundle: WidgetBundle {
    var body: some Widget {
        WatchNowWidget()
    }
}
