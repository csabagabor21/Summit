import WidgetKit
import SwiftUI

@main
struct SummitWidgetsBundle: WidgetBundle {
    var body: some Widget {
        SummitLiveActivityWidget()
        // Legacy fallback nem kell regisztrálni külön — az ActivityConfiguration
        // az iOS verzió alapján választ.
        TimetableWidget()
    }
}
