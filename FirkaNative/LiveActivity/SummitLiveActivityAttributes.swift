import ActivityKit
import Foundation

// MARK: - Summit Live Activity Attributes
// Shared between main app + Widget extension (Target Membership: both).
// Keep total size < 4 KB (attributes + contentState együtt).
//
// Plist requirement (project.yml):
//   INFOPLIST_KEY_NSSupportsLiveActivities = YES
//   // csak ha push-on keresztül is frissítenéd másodpercenként:
//   // INFOPLIST_KEY_NSSupportsLiveActivitiesFrequentUpdates = YES
//
// Rendszer toggle: Settings → Summit → Live Activities
//   -> ActivityAuthorizationInfo().areActivitiesEnabled
//   Ha OFF, a rendszer nem indít activityt — nem hibázunk, hanem jelezzük.
//   Heti "szokásos hibák" ezért vannak: app toggle ON, de rendszer OFF → csend.
//   Ezért külön kezeljük a kettőt (lásd SettingsView + Manager).
//
struct SummitLiveActivityAttributes: ActivityAttributes {
    // Static — nem változik az activity élete alatt.
    var subject: String
    var room: String
    var teacher: String
    var index: String       // "1", "2" ...
    var isCancelled: Bool
    var isSubstituted: Bool
    /// A Beállításokban választott accent — az app adja át indításkor,
    /// mert az extension nem látja a ThemeStore-t (külön sandbox).
    var accentHex: Int

    struct ContentState: Codable, Hashable {
        // Dynamic — minden update-nél frissül.
        var lessonStart: Date
        var lessonEnd: Date
        var nextSubject: String?
        var nextRoom: String?
        var nextStart: Date?
        // Állapot: óra közben / szünet / üres (utóbbi 2-nél a Lock Screen kompakt marad)
        var phase: String   // "lesson" | "break" | "empty"
        // Stale jelzés: ha nem frissítünk, a rendszer halványítja (WWDC23)
        // A manager minden update-nél beállítja.
        var staleDate: Date?
    }
}
