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
        loadEvents()
        // Már futó activityk push-token figyelése (pl. app-újraindulás után).
        if #available(iOS 16.1, *) {
            for a in Activity<SummitLiveActivityAttributes>.activities { observePushTokens(for: a) }
        }
    }

    // MARK: - Push tokenek (szerver-oldali átkapcsoláshoz)
    // Activitynként egy figyelő Task: amíg az activity él, jönnek a tokenek.
    // Ha az App ID-n nincs Push capability, token sosem jön — ilyenkor az app
    // csendben tisztán helyi módban marad (a feltöltés token nélkül kimarad).
    private var pushTokenTasks: [String: Task<Void, Never>] = [:]
    private(set) var pushTokens: [String: String] = [:]

    /// Preview-terv feltöltése a worker külön `:preview` kulcsára (Fejlesztői
    /// idő-eltolás, esti push-teszt). A valós tervet nem bántja; az első
    /// valós sync takarítja a nyomot.
    func pushPreviewPlan(lessons: [LessonItem], now: Date, userId: String) async {
        await SummitPushSync.shared.kick(
            today: lessons, now: now, dayKey: Self.dayKey(for: now),
            userId: userId, pushToken: pushTokens.values.first, preview: true)
    }

    private func observePushTokens(for activity: Activity<SummitLiveActivityAttributes>) {
        guard pushTokenTasks[activity.id] == nil else { return }
        pushTokenTasks[activity.id] = Task { @MainActor [weak self] in
            for await data in activity.pushTokenUpdates {
                let hex = data.map { String(format: "%02.2hhx", $0) }.joined()
                self?.pushTokens[activity.id] = hex
            }
            self?.pushTokenTasks[activity.id] = nil
        }
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

    // MARK: - Eseménynapló (perzisztens diagnosztika)
    //
    // Az óraátmenet-hibák háttérben történnek, a debugPrint elveszik —
    // ezért az érdemi események (indítás/update/lezárás/BG-ébresztés/hiba)
    // UserDefaults-gyűrűbe (utolsó 15) kerülnek, és a Fejlesztő képernyő
    // Live Activity szigete mutatja őket. Így készüléken is látszik,
    // HOL akad el a lánc: fel sem ébred, cache/hálózat hibázik, vagy az
    // update nem megy ki.

    struct LiveEvent: Codable {
        var at: Date
        var msg: String
    }

    private static let eventLogKey = "liveActivity.eventLog.v1"
    private static let eventLogMax = 15

    /// Formázott sorok a UI-nak ("09:44:58 BG-ébresztés: ..."), időrendben.
    @Published var recentEvents: [String] = []

    private static let eventTime: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "hu_HU")
        f.dateFormat = "HH:mm:ss"
        return f
    }()

    private func loadEvents() {
        guard let data = UserDefaults.standard.data(forKey: Self.eventLogKey),
              let events = try? JSONDecoder().decode([LiveEvent].self, from: data) else {
            recentEvents = []
            return
        }
        recentEvents = events.map { "\(Self.eventTime.string(from: $0.at)) \($0.msg)" }
    }

    func logEvent(_ msg: String) {
        var events = (try? JSONDecoder().decode([LiveEvent].self,
            from: UserDefaults.standard.data(forKey: Self.eventLogKey) ?? Data())) ?? []
        events.append(LiveEvent(at: Date(), msg: msg))
        if events.count > Self.eventLogMax { events.removeFirst(events.count - Self.eventLogMax) }
        if let data = try? JSONEncoder().encode(events) {
            UserDefaults.standard.set(data, forKey: Self.eventLogKey)
        }
        recentEvents = events.map { "\(Self.eventTime.string(from: $0.at)) \($0.msg)" }
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
            // Szerver-oldali push-terv feltöltése (csak valós syncből —
            // preview/demo a cache-hez hasonlóan itt sem írhat).
            await SummitPushSync.shared.kick(
                today: today, now: now, dayKey: key,
                userId: SessionStore().selectedUser?.id ?? "",
                pushToken: pushTokens.values.first)
        }

        // Van futó activity → update (háttérből is engedélyezett).
        // Másik napról maradt activityt előbb zárjuk, csak 1 lehet.
        if let existing = Activity<SummitLiveActivityAttributes>.activities.first {
            if existing.attributes.dayKey != key {
                await endAllImpl(dismissalPolicy: .immediate)
            } else {
                // Zombi-duplikátumok lezárása: a régi stackelős bugból
                // maradhatott több aznapi activity — ilyenkor a sync csak az
                // elsőt frissítette, a többi fagyottan, lejárt 0:00-s
                // timerrel ott maradt (pont a "nem vált" tünete). Csak az
                // elsőt tartjuk meg, a többit azonnal zárjuk.
                let zombies = Array(Activity<SummitLiveActivityAttributes>.activities.dropFirst())
                for dup in zombies {
                    await dup.end(ActivityContent(state: dup.content.state, staleDate: nil), dismissalPolicy: .immediate)
                }
                if !zombies.isEmpty { logEvent("zombi-duplikátum lezárva (\(zombies.count) db)") }
                // Csak VALÓDI változásra update-elünk: az előtéri percenkénti
                // sync több száz azonos tartalmú update-et küldene naponta, és
                // a rendszer az ilyen spammelést throttlinggal bünteti — a
                // fontos (óraátmeneti) update is eldobódhat. Így napi ~10-15
                // update megy ki, csak határokon.
                if existing.content.state == state {
                    lastError = nil
                    lastAction = Self.actionLabel(current: cur, next: nxt) + " (változatlan)"
                    // Szándékosan nincs logEvent: a percenkénti "változatlan"
                    // sorok 15 percen belül kiszorítanák a ritka, érdemi
                    // bejegyzéseket (indítás, átkapcsolás, hibák) a gyűrűből.
                    refreshActiveCount()
                    LiveActivityBackgroundRefresh.scheduleBoundary(lessonEnd: state.lessonEnd, nextStart: nxt?.start)
                    return true
                }
                await existing.update(ActivityContent(state: state, staleDate: state.staleDate))
                lastError = nil
                lastAction = Self.actionLabel(current: cur, next: nxt)
                logEvent("update: " + Self.actionLabel(current: cur, next: nxt))
                refreshActiveCount()
                LiveActivityBackgroundRefresh.scheduleBoundary(lessonEnd: state.lessonEnd, nextStart: nxt?.start)
                return true
            }
        }
        // Nincs futó mai activity → request. Előtérben megbízható; háttérből
        // a rendszer eldobhatja — ilyenkor a BG-lánc (keepalive) újrapróbálja.
        do {
            let attrs = SummitLiveActivityAttributes(dayKey: key, accentHex: accentHex)
            let content = ActivityContent(state: state, staleDate: state.staleDate)
            let activity: Activity<SummitLiveActivityAttributes>
            do {
                // Push-tokenes indítás a szerver-oldali átkapcsoláshoz. Ha az
                // App ID-n nincs Push capability, ez dob — ilyenkor helyi
                // módban (pushType nil) indulunk, minden más ugyanúgy megy.
                activity = try Activity.request(attributes: attrs, content: content, pushType: .token)
            } catch {
                activity = try Activity.request(attributes: attrs, content: content, pushType: nil)
            }
            observePushTokens(for: activity)
            lastError = nil
            lastAction = "Napi activity indítva (\(today.count) óra)"
            logEvent("indítás: \(today.count) óra, " + Self.actionLabel(current: cur, next: nxt))
            refreshActiveCount()
            LiveActivityBackgroundRefresh.scheduleBoundary(lessonEnd: state.lessonEnd, nextStart: nxt?.start)
            return true
        } catch {
            // Gyakori hiba: "maximum 5", "not enabled", háttérből indítás — ne crash-eljünk
            lastError = "Indítás sikertelen: \(error.localizedDescription)"
            logEvent("indítás SIKERTELEN: \(error.localizedDescription)")
            debugPrint("[LiveActivity] request failed: \(error.localizedDescription)")
            return false
        }
    }

    @available(iOS 16.1, *)
    static func makeState(today: [LessonItem], current: LessonItem?, next: LessonItem?, now: Date) -> SummitLiveActivityAttributes.ContentState {
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
            // A szünet kezdete az előző óra vége (nem a sync pillanata!):
            // így a break-állapot syncről syncre azonos, amíg a határok nem
            // változnak — enélkül a változás-figyelés sosem találna egyezést,
            // és minden percben kimenne egy felesleges update. A progress
            // csík is így értelmes (szünet eleje → következő óra kezdete).
            let breakStart = today.last(where: { $0.end <= now })?.end ?? now
            return SummitLiveActivityAttributes.ContentState(
                subject: "Szünet", room: nxt.room, teacher: nxt.teacher, index: nxt.index,
                isCancelled: false, isSubstituted: false,
                lessonStart: min(breakStart, breakEnd), lessonEnd: breakEnd,
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
        // Push-token figyelők leállítása + szerver-oldali terv törlése
        // (különben a worker szellem-pushokat küldene a lezárt napra).
        for (_, t) in pushTokenTasks { t.cancel() }
        pushTokenTasks = [:]
        pushTokens = [:]
        if let uid = SessionStore().selectedUser?.id {
            await SummitPushSync.shared.clear(userId: uid, dayKey: Self.dayKey(for: Date()))
        }
        let had = !Activity<SummitLiveActivityAttributes>.activities.isEmpty
        for act in Activity<SummitLiveActivityAttributes>.activities {
            let final = act.content.state
            await act.end(ActivityContent(state: final, staleDate: nil), dismissalPolicy: dismissalPolicy)
        }
        if had {
            lastAction = "Lezárva"
            logEvent("lezárva")
        }
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
