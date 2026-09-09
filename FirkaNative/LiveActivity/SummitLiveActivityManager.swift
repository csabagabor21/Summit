import ActivityKit
import Combine
import Foundation
import UIKit

// MARK: - Live Activity Manager — "napi egy activity" modell
// Minden Live Activity indítás/update/leállítás itt megy át — egy helyen.
//
// A régi modell óránként ÚJ activityt indított (request) és a régit lezárta.
// iOS a háttérben indított új kérést eldobja → a régi már zárva, az új el sem
// indul → az activity az órahatáron meghalt. Ezért most:
//   - NAPONTA EGY activity él (attributes = nap-azonosító, immutable).
//   - Órahatárokon csak UPDATE megy ugyanarra az activityre — ez háttérből
//     (BGAppRefreshTask-ból) is engedélyezett, így a háttérlánc végre működik.
//   - staleDate = az utolsó óra vége → nincs köztes "stale" hervadás.
// Kezeli a "szokásos hibákat":
//   1) Rendszer tiltja → areActivitiesEnabled == false → nem hívunk request-et, hanem jelezzük.
//   2) Max 5 concurrent → ActivityKit dobja → elkapjuk, logoljuk.
//   3) App toggle OFF → minden futó activityt lezárunk.
//   4) 8 óra auto-lejárat → a rendszer zárja, mi csak dismissed-re figyelünk.
//      (Ezért indul az activity az első órához, nem éjfélkor.)
//
@MainActor
final class SummitLiveActivityManager: ObservableObject {
    static let shared = SummitLiveActivityManager()

    @Published private(set) var isSystemEnabled: Bool = true
    @Published private(set) var activeCount: Int = 0
    /// Diagnosztika a UI-nak: miért nem látszik az activity (rendszer tiltás, hiba, stb.)
    @Published private(set) var lastError: String?
    @Published private(set) var lastAction: String = "–"

    private var authTask: Task<Void, Never>?

    // MARK: - Single-flight lánc (duplikátum-védelem)
    // A @MainActor a szinkron szakaszokat sorosítja, de az await-eknél
    // két párhuzamos sync összeakadhatott: mindkettő endAll-t + request-et
    // indított → néha 2 activity jelent meg. Minden sync/end ezen a láncon
    // fut át, így sosem fedik egymást.
    private var serial: Task<Void, Never>?

    private func runSerialized<T>(_ op: @escaping () async -> T) async -> T {
        await serial?.value
        let t = Task<T, Never> { await op() }
        serial = Task<Void, Never> { _ = await t.value }
        return await t.value
    }

    private init() {
        refreshSystemState()
        observeAuthorization()
        refreshActiveCount()
    }

    // MARK: - System state

    func refreshSystemState() {
        if #available(iOS 16.2, *) {
            isSystemEnabled = ActivityAuthorizationInfo().areActivitiesEnabled
        } else if #available(iOS 16.1, *) {
            isSystemEnabled = ActivityAuthorizationInfo().areActivitiesEnabled
        } else {
            isSystemEnabled = false
        }
        refreshActiveCount()
    }

    private func observeAuthorization() {
        if #available(iOS 16.2, *) {
            authTask?.cancel()
            authTask = Task { @MainActor in
                for await enabled in ActivityAuthorizationInfo().activityEnablementUpdates {
                    isSystemEnabled = enabled
                    refreshActiveCount()
                    // Ha a felhasználó kikapcsolta rendszer szinten, zárjuk a futókat (tisztább UX)
                    if !enabled {
                        await endAll(dismissalPolicy: .immediate)
                    }
                }
            }
        }
    }

    private func refreshActiveCount() {
        if #available(iOS 16.1, *) {
            activeCount = Activity<SummitLiveActivityAttributes>.activities.count
        }
    }

    // MARK: - App toggle gate (UserDefaults: liveActivity.enabled)

    var isAppEnabled: Bool {
        UserDefaults.standard.object(forKey: "liveActivity.enabled") as? Bool ?? true // default ON
    }

    func setAppEnabled(_ enabled: Bool) {
        UserDefaults.standard.set(enabled, forKey: "liveActivity.enabled")
        objectWillChange.send()
        if !enabled {
            Task { await endAll(dismissalPolicy: .immediate) }
        }
    }

    /// Teljes gate: app toggle ÉS rendszer toggle együtt.
    var canStart: Bool {
        isAppEnabled && isSystemEnabled
    }

    // MARK: - Napi sync (egyetlen belépési pont)

    static func dayKey(for date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: date)
    }

    // MARK: - Napi terv-cache (háttér-ébresztés hálózat nélkül)
    //
    // A háttér-refresh ~30 mp-es ablaka 2-3 szekvenciális hálózati kört
    // (token → órarend → jegyek) nem bír el megbízhatóan: lassú hálózaton
    // lejárt, és az óraátmenet elmaradt — a kártyán lejárt 0:00-s timer
    // maradt a régi órával. Ezért minden sikeres előtéri sync elmenti a
    // mai tervet; a háttér-ébresztés ELŐSZÖR ebből kapcsol (azonnal,
    // offline is), és csak utána pontosít hálózatból.

    struct CachedDayPlan: Codable {
        var dayKey: String
        var accentHex: Int
        var lessons: [PlanLesson]
    }

    private static let dayCacheKey = "liveActivity.dayPlan.v1"

    private static func saveDayCache(dayKey: String, lessons: [PlanLesson], accentHex: Int) {
        let cache = CachedDayPlan(dayKey: dayKey, accentHex: accentHex, lessons: lessons)
        if let data = try? JSONEncoder().encode(cache) {
            UserDefaults.standard.set(data, forKey: dayCacheKey)
        }
    }

    func loadDayCache() -> CachedDayPlan? {
        guard let data = UserDefaults.standard.data(forKey: Self.dayCacheKey),
              let cache = try? JSONDecoder().decode(CachedDayPlan.self, from: data) else { return nil }
        return cache
    }

    /// A cache-elt mai terv LessonItem-ként, ha az a mai napra szól.
    /// Idegen nap cache-e (pl. tegnapi) sosem jön vissza — abból rossz
    /// határra ütemeznénk és rossz órát mutatnánk.
    func cachedLessons(now: Date = Date()) -> (lessons: [LessonItem], accentHex: Int)? {
        guard let cache = loadDayCache(), cache.dayKey == Self.dayKey(for: now), !cache.lessons.isEmpty else { return nil }
        let items = cache.lessons.map { p in
            LessonItem(id: "cache-\(p.index)-\(p.start.timeIntervalSince1970)",
                       subject: p.subject, room: p.room, start: p.start, end: p.end,
                       teacher: p.teacher, index: p.index,
                       isSubstituted: p.isSubstituted, isCancelled: p.isCancelled,
                       originalTeacher: nil)
        }
        return (items, cache.accentHex)
    }

    /// A HomeView és a háttér-refresh is EZT hívja a teljes mai órarenddel.
    /// Napi egy activity: határokon csak update (háttérből is megy),
    /// új request csak akkor, ha még nincs mai activity (tipikusan előtérben).
    /// - Parameter cacheable: hamis a fejlesztői idő-csúszkás preview-nál és
    ///   a demo-tesztnél — azok eltolt/mű órarendje sosem kerülhet a napi
    ///   terv-cache-be, mert a háttér-ébresztés valós kapcsoláshoz használná.
    @discardableResult
    func syncDay(lessons: [LessonItem], now: Date = Date(), accentHex: Int = 0x4A90E2, cacheable: Bool = true) async -> Bool {
        await runSerialized { await self.syncDayImpl(lessons: lessons, now: now, accentHex: accentHex, cacheable: cacheable) }
    }

    private func syncDayImpl(lessons: [LessonItem], now: Date, accentHex: Int, cacheable: Bool) async -> Bool {
        guard #available(iOS 16.1, *) else { lastError = "iOS 16.1 alatt nem támogatott"; return false }
        guard canStart else {
            // Ha az app kikapcsolta, biztosan zárunk — ne maradjon beragadt activity
            if !isAppEnabled {
                lastError = "App toggle KI — futók lezárva"
                await endAllImpl(dismissalPolicy: .immediate)
            } else {
                lastError = "Rendszer tiltja (Beállítások → Summit → Live Activities)"
            }
            return false
        }
        let cal = Calendar.current
        let today = lessons
            .filter { cal.isDate($0.start, inSameDayAs: now) }
            .sorted { $0.start < $1.start }
        let cur = today.first { $0.start <= now && $0.end >= now }
        let nxt = today.first { $0.start > now }
        // Ma már nincs több óra (vagy ma nincs iskola): a futót zárjuk,
        // a holnap reggeli ébresztőt a háttér-refresh teszi fel.
        guard cur != nil || nxt != nil else {
            lastAction = today.isEmpty ? "Ma nincs óra → lezárva" : "Mai órák vége → lezárva"
            await endAllImpl(dismissalPolicy: .default)
            return false
        }
        let state = Self.makeState(today: today, current: cur, next: nxt, now: now)
        let key = Self.dayKey(for: now)
        // Napi terv-cache: a háttér-ébresztés ebből kapcsol azonnal,
        // hálózat nélkül is. Üres `today`-jel sosem írjuk felül a cache-t
        // (az fetch-hiba is lehetne), és a mű/eltolt adatok sem kerülnek bele.
        if cacheable, !today.isEmpty {
            let snap = today.map {
                PlanLesson(subject: $0.subject, room: $0.room, teacher: $0.teacher,
                           index: $0.index, start: $0.start, end: $0.end,
                           isCancelled: $0.isCancelled, isSubstituted: $0.isSubstituted)
            }
            Self.saveDayCache(dayKey: key, lessons: snap, accentHex: accentHex)
        }

        // Van futó activity → update (háttérből is engedélyezett).
        // Másik napról maradt activityt előbb zárjuk, csak 1 lehet.
        if let existing = Activity<SummitLiveActivityAttributes>.activities.first {
            if existing.attributes.dayKey != key {
                await endAllImpl(dismissalPolicy: .immediate)
            } else {
                await existing.update(ActivityContent(state: state, staleDate: state.staleDate))
                lastError = nil
                lastAction = Self.actionLabel(current: cur, next: nxt)
                refreshActiveCount()
                LiveActivityBackgroundRefresh.scheduleBoundary(lessonEnd: state.lessonEnd, nextStart: nxt?.start)
                return true
            }
        }
        // Nincs futó mai activity → request. Előtérben megbízható; háttérből
        // a rendszer eldobhatja — ilyenkor a BG-lánc (keepalive) újrapróbálja.
        do {
            let attrs = SummitLiveActivityAttributes(dayKey: key, accentHex: accentHex)
            _ = try Activity.request(attributes: attrs, content: ActivityContent(state: state, staleDate: state.staleDate), pushType: nil)
            lastError = nil
            lastAction = "Napi activity indítva (\(today.count) óra)"
            refreshActiveCount()
            LiveActivityBackgroundRefresh.scheduleBoundary(lessonEnd: state.lessonEnd, nextStart: nxt?.start)
            return true
        } catch {
            // Gyakori hiba: "maximum 5", "not enabled", háttérből indítás — ne crash-eljünk
            lastError = "Indítás sikertelen: \(error.localizedDescription)"
            debugPrint("[LiveActivity] request failed: \(error.localizedDescription)")
            return false
        }
    }

    @available(iOS 16.1, *)
    private static func makeState(today: [LessonItem], current: LessonItem?, next: LessonItem?, now: Date) -> SummitLiveActivityAttributes.ContentState {
        // Hátralévő terv: múltbeli órák nélkül (méret-takarékosság, < 4 KB).
        let plan = today
            .filter { $0.end > now }
            .map {
                PlanLesson(subject: $0.subject, room: $0.room, teacher: $0.teacher,
                           index: $0.index, start: $0.start, end: $0.end,
                           isCancelled: $0.isCancelled, isSubstituted: $0.isSubstituted)
            }
        let dayEnd = plan.last?.end ?? now.addingTimeInterval(60)
        if let cur = current {
            var lessonEnd = cur.end
            if lessonEnd <= cur.start { lessonEnd = cur.start.addingTimeInterval(45 * 60) }
            return SummitLiveActivityAttributes.ContentState(
                subject: cur.subject, room: cur.room, teacher: cur.teacher, index: cur.index,
                isCancelled: cur.isCancelled, isSubstituted: cur.isSubstituted,
                lessonStart: cur.start, lessonEnd: lessonEnd,
                nextSubject: next?.subject, nextRoom: next?.room, nextStart: next?.start,
                phase: "lesson",
                // Nap végéig élő: óra közben nincs "stale" hervadás.
                staleDate: dayEnd,
                plan: plan, dayEnd: dayEnd
            )
        } else if let nxt = next {
            var breakEnd = nxt.start
            if breakEnd <= now { breakEnd = now.addingTimeInterval(60) }
            return SummitLiveActivityAttributes.ContentState(
                subject: "Szünet", room: nxt.room, teacher: nxt.teacher, index: nxt.index,
                isCancelled: false, isSubstituted: false,
                lessonStart: now, lessonEnd: breakEnd,
                nextSubject: nxt.subject, nextRoom: nxt.room, nextStart: nxt.start,
                phase: "break",
                staleDate: dayEnd,
                plan: plan, dayEnd: dayEnd
            )
        } else {
            // Ide a guard miatt nem jutunk (nincs cur és nincs nxt), de a
            // típus teljessége miatt lefedjük: üres záró állapot.
            return SummitLiveActivityAttributes.ContentState(
                subject: "–", room: "", teacher: "", index: "",
                isCancelled: false, isSubstituted: false,
                lessonStart: now, lessonEnd: now.addingTimeInterval(60),
                nextSubject: nil, nextRoom: nil, nextStart: nil,
                phase: "empty", staleDate: dayEnd, plan: plan, dayEnd: dayEnd
            )
        }
    }

    private static func actionLabel(current: LessonItem?, next: LessonItem?) -> String {
        if let cur = current { return "Update: \(cur.subject) \(cur.index). óra" }
        if let nxt = next { return "Update: Szünet → \(nxt.subject)" }
        return "Update"
    }

    func endAll(dismissalPolicy: ActivityUIDismissalPolicy = .default) async {
        await runSerialized { await self.endAllImpl(dismissalPolicy: dismissalPolicy) }
    }

    private func endAllImpl(dismissalPolicy: ActivityUIDismissalPolicy) async {
        guard #available(iOS 16.1, *) else { return }
        // Záráskor a függő háttér-ébresztést is töröljük; sikeres új
        // sync úgyis újraütemezi a következő határra.
        LiveActivityBackgroundRefresh.cancel()
        let had = !Activity<SummitLiveActivityAttributes>.activities.isEmpty
        for act in Activity<SummitLiveActivityAttributes>.activities {
            let final = act.content.state
            await act.end(ActivityContent(state: final, staleDate: nil), dismissalPolicy: dismissalPolicy)
        }
        if had { lastAction = "Lezárva" }
        refreshActiveCount()
    }

    /// Demo teszt: órarendtől független, valós időre horgonyzott activity.
    /// Este is működik — a widget renderelés önmagában tesztelhető vele.
    func startDemoTestNow(label: String = "Matek (teszt)", accentHex: Int = 0x4A90E2) async -> Bool {
        let now = Date()
        let demo = LessonItem(
            id: "demo-test", subject: label, room: "A1",
            start: now.addingTimeInterval(-5 * 60),
            end: now.addingTimeInterval(40 * 60),
            teacher: "Teszt Tanár", index: "1"
        )
        let next = LessonItem(
            id: "demo-test-next", subject: "Angol", room: "B2",
            start: now.addingTimeInterval(50 * 60),
            end: now.addingTimeInterval(95 * 60),
            teacher: "Smith", index: "2"
        )
        // Mű órarend: nem kerülhet a napi terv-cache-be (cacheable: false),
        // különben a háttér-ébresztés valós határoknál ezt mutatná.
        return await syncDay(lessons: [demo, next], now: now, accentHex: accentHex, cacheable: false)
    }

    func openSystemSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }
}
