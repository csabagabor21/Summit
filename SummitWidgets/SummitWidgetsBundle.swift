import WidgetKit
import SwiftUI

@main
struct SummitWidgetsBundle: WidgetBundle {
    var body: some Widget {
        #if !targetEnvironment(macCatalyst)
        SummitLiveActivityWidget()
        #endif
        // Legacy fallback nem kell regisztrálni külön — az ActivityConfiguration
        // az iOS verzió alapján választ.
        TimetableWidget()
        SchoolDayWidget()
        VacationWidget()
    }
}
