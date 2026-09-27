#if targetEnvironment(macCatalyst)
import Combine
import Foundation

// MARK: - Mac Catalyst stubok: Live Activity nem létezik Mac-en
//
// Az ActivityKit / BackgroundTasks framework iOS-only, ezért a valódi
// implementációk (SummitLiveActivityManager, LiveActivityBackgroundRefresh)
// ezen a platformon nem fordulnak. Hogy az egy kódbázis mindkét helyen
// változtatás nélkül forduljon, itt ugyanazzal a publikus API-val rendelkező
// no-op változatok élnek — a hívóhelyeken (SummitApp, HomeView, Settings)
// emiatt semmit nem kellett átírni, Mac-en az activity-szinkron csendben kimarad.

enum LiveActivityBackgroundRefresh {
    static let taskIdentifier = "hu.flint.app.Flint.liveactivity-refresh"

    static func register() {}
    static func scheduleBoundary(lessonEnd: Date?, nextStart: Date?, now: Date = Date()) {}
    static func cancel() {}
    static func scheduleKeepaliveIfNeeded() {}
    static func scheduleMorningFallback(now: Date = Date()) {}
}

@MainActor
final class SummitLiveActivityManager: ObservableObject {
    static let shared = SummitLiveActivityManager()

    @Published private(set) var isSystemEnabled: Bool = false
    @Published private(set) var activeCount: Int = 0
    @Published private(set) var lastError: String?
    @Published private(set) var lastAction: String = "Mac-en nem elérhető"
    @Published var recentEvents: [String] = []
    @Published var pushLog: [String] = []

    private(set) var pushTokens: [String: String] = [:]

    var isAppEnabled: Bool { false }
    var canStart: Bool { false }
    var startedWithoutPush: Bool { false }
    var primaryPushToken: String? { nil }

    struct CachedDayPlan: Codable {
        var dayKey: String
        var accentHex: Int
        var lessons: [PlanLesson]
    }

    func setAppEnabled(_ enabled: Bool) {}
    func refreshSystemState() {}
    func openSystemSettings() {}

    func ensurePlanUploaded(now: Date = Date()) async {}
    func uploadPlanFromCache(now: Date) async {}

    func cachedLessons(now: Date = Date()) -> (lessons: [LessonItem], accentHex: Int)? { nil }
    func loadDayCache() -> CachedDayPlan? { nil }

    @discardableResult
    func syncDay(lessons: [LessonItem], now: Date = Date(), accentHex: Int = 0x4A90E2, cacheable: Bool = true) async -> Bool { false }

    func pushPreviewPlan(lessons: [LessonItem], now: Date, userId: String) async {}

    func logEvent(_ msg: String) {
        recentEvents.append("\(Self.eventTimeString()) • \(msg)")
    }

    func pushLogEvent(_ msg: String) {
        pushLog.append("\(Self.eventTimeString()) • \(msg)")
    }

    static func dayKey(for date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: date)
    }

    static func eventTimeString(_ date: Date = Date()) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "HH:mm:ss"
        return f.string(from: date)
    }

    @discardableResult
    func startDemoTestNow(userId: String = "", label: String = "Matek (teszt)", accentHex: Int = 0x4A90E2) async -> Bool { false }

    func endAll() async {}

    @discardableResult
    func restartForPush(now: Date = Date()) async -> Bool { false }
}
#endif
