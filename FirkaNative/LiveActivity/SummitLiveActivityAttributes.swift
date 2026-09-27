import Foundation
#if !targetEnvironment(macCatalyst)
import ActivityKit
#endif

// MARK: - Summit Live Activity Attributes — "napi egy activity" modell
// Shared between main app + Widget extension (Target Membership: both).
// Keep total size < 4 KB (attributes + contentState együtt).
//
// Miért változott? A régi modell óránként ÚJ activityt indított (request)
// és a régit lezárta (end). iOS a háttérben indított új kérést eldobja —
// a régi már zárva, az új el sem indul → az activity az órahatáron meghalt,
// és semmilyen háttér-ébresztési lánc nem tudta megmenteni. Ezért:
//   - EGY activity él egy tanítási napon (attributes = nap-azonosító, immutable).
//   - Órahatárokon csak UPDATE megy ugyanarra az activityre — ez háttérből
//     (BGAppRefreshTask-ból) is engedélyezett, így a lánc végre működik.
//   - staleDate = az UTOLSÓ óra vége, nem az aktuálisé → nincs köztes
//     "stale" hervadás; a timerInterval visszaszámlálók maguktól tickelnek.
//   - A state az egész hátralévő napi tervet hordozza, így egy késve érkező
//     update is pontos órarendből számol, a widget pedig már előre mutatja
//     a következő órákat.
//
// Plist requirement (project.yml):
//   INFOPLIST_KEY_NSSupportsLiveActivities = YES
//
// Rendszer toggle: Settings → Summit → Live Activities
//   -> ActivityAuthorizationInfo().areActivitiesEnabled
//
#if !targetEnvironment(macCatalyst)
struct SummitLiveActivityAttributes: ActivityAttributes {
    // Static — egy tanítási napon belül nem változik.
    /// Nap-azonosító ("2026-09-08"). Másik nap = másik activity (reggel indul).
    var dayKey: String
    /// A Beállításokban választott accent — az app adja át indításkor,
    /// mert az extension nem látja a ThemeStore-t (külön sandbox).
    var accentHex: Int

    struct ContentState: Codable, Hashable {
        // Aktuális nézet — minden update-kor az órarendből újraszámolva.
        // (Az attributes immutable, ezért az aktuális óra adatai is itt élnek.)
        var subject: String
        var room: String
        var teacher: String
        var index: String       // "1", "2" ... / szünetben a következő óráé
        var isCancelled: Bool
        var isSubstituted: Bool
        // Élő visszaszámláló-ablak: óra közben az óra, szünetben a szünet vége.
        // A rendszer Text(timerInterval:)-je magától tickel, app nélkül is.
        var lessonStart: Date
        var lessonEnd: Date
        var nextSubject: String?
        var nextRoom: String?
        var nextStart: Date?
        // Állapot: óra közben / szünet / üres
        var phase: String   // "lesson" | "break" | "empty"
        // Stale jelzés: az UTOLSÓ óra vége (napi egy activity → nap végéig élő).
        var staleDate: Date?
        // Hátralévő napi terv (múltbeli órák nélkül, méret < 4 KB).
        // A widget ebből már előre mutatja a következő órákat is.
        var plan: [PlanLesson]
        /// Az utolsó mai óra vége — eddig él az activity.
        var dayEnd: Date
    }
}
#else
// Mac Catalyst: ActivityKit nincs — a push-terv feltöltéséhez (SummitPushSync)
// csak a ContentState Codable alakja kell, Live Activity indítás nincs.
struct SummitLiveActivityAttributes: Codable, Hashable {
    var dayKey: String
    var accentHex: Int

    struct ContentState: Codable, Hashable {
        var subject: String
        var room: String
        var teacher: String
        var index: String
        var isCancelled: Bool
        var isSubstituted: Bool
        var lessonStart: Date
        var lessonEnd: Date
        var nextSubject: String?
        var nextRoom: String?
        var nextStart: Date?
        var phase: String
        var staleDate: Date?
        var plan: [PlanLesson]
        var dayEnd: Date
    }
}
#endif

/// Egy mai óra kompakt másolata a ContentState számára.
/// ~10 óra is bőven 1 KB alatt marad (a 4 KB-os limit töredéke).
struct PlanLesson: Codable, Hashable {
    var subject: String
    var room: String
    var teacher: String
    var index: String
    var start: Date
    var end: Date
    var isCancelled: Bool
    var isSubstituted: Bool

    /// Szándékosan nem LessonItem-et kap: a Widget extension nem fordítja
    /// a KretaModels-t, így ez a fájl önálló kell maradjon.
    init(subject: String, room: String, teacher: String, index: String,
         start: Date, end: Date, isCancelled: Bool, isSubstituted: Bool) {
        // Timer-szanitálás: fordított intervallumra a widget nem rajzolna.
        self.subject = subject
        self.room = room
        self.teacher = teacher
        self.index = index
        self.start = start
        self.end = end > start ? end : start.addingTimeInterval(45 * 60)
        self.isCancelled = isCancelled
        self.isSubstituted = isSubstituted
    }
}
