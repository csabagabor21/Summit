import ActivityKit
import Combine
import Foundation
import UIKit

// MARK: - Live Activity Manager
// Minden Live Activity indítás/update/leállítás itt megy át — egy helyen.
// Kezeli a "szokásos hibákat":
//   1) Rendszer tiltja → areActivitiesEnabled == false → nem hívunk request-et, hanem jelezzük.
//   2) Max 5 concurrent → ActivityKit dobja → elkapjuk, logoljuk.
//   3) App toggle OFF → minden futó activityt lezárunk.
//   4) 8 óra auto-lejárat → a rendszer zárja, mi csak dismissed-re figyelünk.
//   5) Háttérben nem indítunk újat — csak updateelünk (Apple limit).
//
@MainActor
final class FlintLiveActivityManager: ObservableObject {
    static let shared = FlintLiveActivityManager()

    @Published private(set) var isSystemEnabled: Bool = true
    @Published private(set) var activeCount: Int = 0
    /// Diagnosztika a UI-nak: miért nem látszik az activity (rendszer tiltás, hiba, stb.)
    @Published private(set) var lastError: String?
    @Published private(set) var lastAction: String = "–"

    private var authTask: Task<Void, Never>?

    // MARK: - Single-flight lánc (duplikátum-védelem)
    // A @MainActor a szinkron szakaszokat sorosítja, de az await-eknél
    // két párhuzamos sync összeakadhatott: mindkettő endAll-t + request-et
    // indított → néha 2 activity jelent meg. Minden start/update/end
    // ezen a láncon fut át, így sosem fedik egymást.
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
            activeCount = Activity<FlintLiveActivityAttributes>.activities.count
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

    // MARK: - Start / Update / End

    /// Órarendből vagy Home-ból hívd — minden éles frissítési pont itt fut át.
    /// Ha nincs aktuális óra, next óra info-val "szünet" phase-et indítunk; ha nincs óra egyáltalán, nem indítunk.
    @discardableResult
    func startOrUpdate(current: LessonItem?, next: LessonItem?, now: Date = Date(), accentHex: Int = 0xA7DC22) async -> Bool {
        await runSerialized { await self.startOrUpdateImpl(current: current, next: next, now: now, accentHex: accentHex) }
    }

    private func startOrUpdateImpl(current: LessonItem?, next: LessonItem?, now: Date, accentHex: Int) async -> Bool {
        guard #available(iOS 16.1, *) else { lastError = "iOS 16.1 alatt nem támogatott"; return false }
        guard canStart else {
            // Ha az app kikapcsolta, biztosan zárunk — ne maradjon beragadt activity
            if !isAppEnabled {
                lastError = "App toggle KI — futók lezárva"
                await endAllImpl(dismissalPolicy: .immediate)
            } else {
                lastError = "Rendszer tiltja (Beállítások → Flint → Live Activities)"
            }
            return false
        }
        // Nincs aktuális óra → ha a következő óra MA van, a szünet-activity
        // végig élőben visszaszámol a következő óráig (élő timerInterval miatt
        // ez már nem igényel app-ébresztést, és nem öljük meg lyukasórában sem).
        // Csak akkor zárunk, ha ma már nincs több óra (holnapi órára nincs countdown).
        guard let cur = current else {
            if let nxt = next {
                let cal = Calendar.current
                guard cal.isDate(nxt.start, inSameDayAs: now) else {
                    lastAction = "Mai órák vége → lezárva"
                    await endAllImpl(dismissalPolicy: .default)
                    return false
                }
                return await startBreakImpl(next: nxt, now: now, accentHex: accentHex)
            } else {
                lastAction = "Nincs óra → lezárva"
                await endAllImpl(dismissalPolicy: .default)
                return false
            }
        }
        // Timer-szanitálás: a widget Text(timerInterval:) csak start<end-re rajzol.
        // Előfordulhat fordított intervallum (demo shift kerekítés, hibás KRÉTA adat).
        var lessonEnd = cur.end
        if lessonEnd <= cur.start { lessonEnd = cur.start.addingTimeInterval(45 * 60) }
        let attrs = FlintLiveActivityAttributes(
            subject: cur.subject,
            room: cur.room,
            teacher: cur.teacher,
            index: cur.index,
            isCancelled: cur.isCancelled,
            isSubstituted: cur.isSubstituted,
            accentHex: accentHex
        )
        // staleDate = óra vége: az élő timerInterval magától tickel, így óra közben
        // nincs "stale / lagging behind" halványítás. (A régi now+30p itt járatta le.)
        let state = FlintLiveActivityAttributes.ContentState(
            lessonStart: cur.start,
            lessonEnd: lessonEnd,
            nextSubject: next?.subject,
            nextRoom: next?.room,
            nextStart: next?.start,
            phase: "lesson",
            staleDate: lessonEnd
        )
        // Ha már fut ugyanerre az órára, csak update.
        // FONTOS: az attributes immutable — másik órára NEM szabad update-elni,
        // különben beragadt rossz subject/index marad az Islanden.
        if let existing = Activity<FlintLiveActivityAttributes>.activities.first(where: { $0.attributes.subject == cur.subject && $0.attributes.index == cur.index }) {
            await existing.update(ActivityContent(state: state, staleDate: state.staleDate))
            lastError = nil
            lastAction = "Update: \(cur.subject) \(cur.index). óra"
            refreshActiveCount()
            LiveActivityBackgroundRefresh.scheduleBoundary(lessonEnd: lessonEnd, nextStart: next?.start)
            return true
        }
        // Másik óra/szünet fut → előbb zárjuk, csak 1 activity legyen (különben az Island összeakad).
        // (Sorosítva futunk, így két request sosem indulhat párhuzamosan → nincs duplikátum.)
        if !Activity<FlintLiveActivityAttributes>.activities.isEmpty {
            await endAllImpl(dismissalPolicy: .immediate)
        }
        do {
            let content = ActivityContent(state: state, staleDate: state.staleDate)
            _ = try Activity.request(attributes: attrs, content: content, pushType: nil)
            lastError = nil
            lastAction = "Indítva: \(cur.subject) \(cur.index). óra"
            refreshActiveCount()
            LiveActivityBackgroundRefresh.scheduleBoundary(lessonEnd: lessonEnd, nextStart: next?.start)
            return true
        } catch {
            // Gyakori hiba: "maximum 5", "not enabled", "background" — ne crash-eljünk
            lastError = "Indítás sikertelen: \(error.localizedDescription)"
            debugPrint("[LiveActivity] request failed: \(error.localizedDescription)")
            return false
        }
    }

    private func startBreakImpl(next: LessonItem, now: Date, accentHex: Int) async -> Bool {
        guard #available(iOS 16.1, *) else { return false }
        // Szünet Live Activity — statikus a "Szünet", dinamikus a következő óra.
        // Az attributes itt is immutable: csak egyező Szünet+index activity update-elhető.
        var breakEnd = next.start
        if breakEnd <= now { breakEnd = now.addingTimeInterval(60) }
        let attrs = FlintLiveActivityAttributes(
            subject: "Szünet",
            room: next.room,
            teacher: next.teacher,
            index: next.index,
            isCancelled: false,
            isSubstituted: false,
            accentHex: accentHex
        )
        // staleDate = szünet vége (következő óra kezdete): a countdown végig élő,
        // a rendszer nem halványítja "stale"-re szünet közben sem.
        let state = FlintLiveActivityAttributes.ContentState(
            lessonStart: now,
            lessonEnd: breakEnd,
            nextSubject: next.subject,
            nextRoom: next.room,
            nextStart: next.start,
            phase: "break",
            staleDate: breakEnd
        )
        if let existing = Activity<FlintLiveActivityAttributes>.activities.first(where: { $0.attributes.subject == "Szünet" && $0.attributes.index == next.index }) {
            await existing.update(ActivityContent(state: state, staleDate: state.staleDate))
            lastError = nil
            lastAction = "Update: Szünet → \(next.subject)"
            refreshActiveCount()
            LiveActivityBackgroundRefresh.scheduleBoundary(lessonEnd: breakEnd, nextStart: next.start)
            return true
        }
        if !Activity<FlintLiveActivityAttributes>.activities.isEmpty {
            await endAllImpl(dismissalPolicy: .immediate)
        }
        do {
            _ = try Activity.request(attributes: attrs, content: ActivityContent(state: state, staleDate: state.staleDate), pushType: nil)
            lastError = nil
            lastAction = "Indítva: Szünet → \(next.subject)"
            refreshActiveCount()
            LiveActivityBackgroundRefresh.scheduleBoundary(lessonEnd: breakEnd, nextStart: next.start)
            return true
        } catch {
            lastError = "Szünet indítás sikertelen: \(error.localizedDescription)"
            debugPrint("[LiveActivity] break request failed: \(error)")
            return false
        }
    }

    func endAll(dismissalPolicy: ActivityUIDismissalPolicy = .default) async {
        await runSerialized { await self.endAllImpl(dismissalPolicy: dismissalPolicy) }
    }

    private func endAllImpl(dismissalPolicy: ActivityUIDismissalPolicy) async {
        guard #available(iOS 16.1, *) else { return }
        // Záráskor a függő háttér-ébresztést is töröljük; sikeres új
        // start/update úgyis újraütemezi a következő határra.
        LiveActivityBackgroundRefresh.cancel()
        let had = !Activity<FlintLiveActivityAttributes>.activities.isEmpty
        for act in Activity<FlintLiveActivityAttributes>.activities {
            let final = act.content.state
            await act.end(ActivityContent(state: final, staleDate: nil), dismissalPolicy: dismissalPolicy)
        }
        if had { lastAction = "Lezárva" }
        refreshActiveCount()
    }

    /// Demo teszt: órarendtől független, valós időre horgonyzott activity.
    /// Este is működik — a widget renderelés önmagában tesztelhető vele.
    func startDemoTestNow(label: String = "Matek (teszt)", accentHex: Int = 0xA7DC22) async -> Bool {
        guard #available(iOS 16.1, *) else { return false }
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
        return await startOrUpdate(current: demo, next: next, now: now, accentHex: accentHex)
    }

    func openSystemSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }
}
