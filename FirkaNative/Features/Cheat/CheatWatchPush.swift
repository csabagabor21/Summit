import Foundation

// MARK: - Cheat → óra tolás (platform-biztos kapu)
// Mac (Catalyst) alatt nincs WatchConnectivity — ott néma no-op,
// iPhone-on a WatchSyncSender viszi át a lapokat az órára.
enum CheatWatchPush {
    static func push(_ sheets: [CheatSheet]) {
        WatchSyncSender.pushCheat(sheets)
    }
}
