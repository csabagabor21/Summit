import WidgetKit
import SwiftUI

@main
struct FlintWidgetsBundle: WidgetBundle {
    var body: some Widget {
        FlintLiveActivityWidget()
        // Legacy fallback nem kell regisztrálni külön — az ActivityConfiguration
        // az iOS verzió alapján választ.
    }
}
