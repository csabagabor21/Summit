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

    /// Demo-teszt védelmi ablak: a `startDemoTestNow` állítja be (~15 perc).
    /// Amíg él, a valós órarenddel érkező sync NEM zárhatja le az activityt —
    /// különben a Főoldal percenkénti sync-je (esti, múltbeli órákkal) egy
    /// percen belül megölné a tesztkártyát, és a push-átkapcsolás
    /// tesztelhetetlen lenne ("a tesztgombbal se működik").
    private var demoTestActiveUntil: Date?

    /// Push-képesség nyoma: az activity pushType-tal (.token) indult, vagy
    /// a token-kérés dobott és nil-lel (tisztán helyi módban). Utóbbi azt
    /// jelenti, hogy a build profiljában nincs Push — token sosem jön,
    /// a feltöltés tartósan kimarad (javított profillal újratelepítés kell).
    /// Perzisztens, mert az ok a buildhez kötődik, nem az activityhez
    /// (az app törlése viszi, így a javított build tiszta lappal indul).
    static let pushTypeNilKey = "liveActivity.pushTypeNil.v1"
    var startedWithoutPush: Bool { UserDefaults.standard.bool(forKey: Self.pushTypeNilKey) }
    /// Utolsó activity-kérés időbélyege. A régi (push nélküli) build sosem
    /// írta — hiánya = örökölt, biztosan nil-push activity.
    private static let lastPushRequestAtKey = "liveActivity.pushRequestAt.v1"
    /// Melyik napon volt már kényszer-újraindítás (napi 1-nél több sosem).
    private static let pushRestartDayKey = "liveActivity.pushRestartDay.v1"

    /// Preview-terv feltöltése a worker külön `:preview` kulcsára (Fejlesztői
    /// idő-eltolás, esti push-teszt). A valós tervet nem bántja; az első
    /// valós sync takarítja a nyomot.
    func pushPreviewPlan(lessons: [LessonItem], now: Date, userId: String) async {
        await SummitPushSync.shared.kick(
            today: lessons, now: now, dayKey: Self.dayKey(for: now),
            userId: userId.isEmpty ? "demo" : userId, pushToken: primaryPushToken, preview: true)
    }

    private func observePushTokens(for activity: Activity<SummitLiveActivityAttributes>) {
        guard pushTokenTasks[activity.id] == nil else { return }
        // Szinkron mag: a már futó activity AKTUÁLIS tokenje azonnal a
        // szótárba kerül. App-újraindulás (pl. hideg BG-ébresztés) után a
        // stream aszinkron és csak a változást hozza — addig a sync üres
        // szótárral futott, és hamisan „örökölt, push nélküli” activitynek
        // nézte a sajátját (→ endAll + háttér-request → a kártya meghalt).
        if let data = activity.pushToken {
            pushTokens[activity.id] = Self.hex(data)
            UserDefaults.standard.set(false, forKey: Self.pushTypeNilKey)
        }
        pushTokenTasks[activity.id] = Task { @MainActor [weak self] in
            for await data in activity.pushTokenUpdates {
                guard let self else { return }
                let hex = Self.hex(data)
                let changed = self.pushTokens[activity.id] != hex
                self.pushTokens[activity.id] = hex
                // Token megérkezett: a build tud push-t (a nil-nyom elavult).
                UserDefaults.standard.set(false, forKey: SummitLiveActivityManager.pushTypeNilKey)
                // Token megjött / cserélődött → AZONNALI terv-feltöltés a
                // mentett mai tervből. Enélkül a feltöltés a következő
                // percenkénti előtéri syncre várt: ha a user 60 mp-en belül
                // kilépett, aznap semmi nem ment fel a workerbe.
                if changed { await self.uploadPlanFromCache(now: Date()) }
            }
            self?.pushTokenTasks[activity.id] = nil
        }
    }

    private static func hex(_ data: Data) -> String {
        data.map { String(format: "%02.2hhx", $0) }.joined()
    }

    /// Az ELSŐ (egyetlen érvényes) activity tokenje. Zombi-duplikátum
    /// tokenje sosem kerülhet a workerbe (a `pushTokens.values.first`
    /// bármelyiket adhatta volna).
    var primaryPushToken: String? {
        if let first = Activity<SummitLiveActivityAttributes>.activities.first {
            if let t = pushTokens[first.id] { return t }
            if let d = first.pushToken { return Self.hex(d) }
        }
        return pushTokens.values.first
    }

    /// App-előtérbe kerüléskor: ha van élő activity ÉS push-token, a mai
    /// tervet BIZTOSAN feltöltjük a workerbe — a tokenre várva, a hash-t
    /// érvénytelenítve. A user kifejezetten ezt kérte: napközbeni
    /// megnyitáskor is menjen fel a terv, ne csak reggel.
    ///
    /// Miért kell külön lépés? Meglévő activity mellett a két automata út
    /// elcsúszik: a token-érkezéskori feltöltés (`uploadPlanFromCache`) a
    /// cache-mentés ELŐTT futhat (üres cache → néma kilépés), a cache-es
    /// sync (`syncDayImpl` kick) pedig még token NÉLKÜL (kimarad). Így
    /// egyik ág sem töltött fel — a workeren üres/régi terv maradt, és a
    /// napközbeni megnyitás nem indította el a szerver-oldali átkapcsolást.
    func ensurePlanUploaded(now: Date = Date()) async {
        guard #available(iOS 16.1, *), canStart else { return }
        guard !Activity<SummitLiveActivityAttributes>.activities.isEmpty else { return }
        // A push-token egy meglévő activityhez is a stream-en, aszinkron
        // érkezik app-újraindulás után — várunk rá (max ~12 mp).
        for _ in 0..<12 {
            if primaryPushToken?.count == 64 { break }
            try? await Task.sleep(nanoseconds: 1_000_000_000)
        }
        guard primaryPushToken?.count == 64 else {
            logEvent("napközbeni feltöltés: nincs push-token (kimarad)")
            return
        }
        SummitPushSync.shared.invalidateUploadHash(dayKey: Self.dayKey(for: now))
        await uploadPlanFromCache(now: now)
    }

    /// Terv-feltöltés a mentett mai tervből (token-érkezéskor + app-
    /// megnyitáskor hívjuk). Csak valós cache-ből dolgozik — preview/demo
    /// sosem ír a cache-be.
    func uploadPlanFromCache(now: Date) async {
        guard let cached = cachedLessons(now: now),
              let uid = SessionStore().selectedUser?.id else { return }
        let cal = Calendar.current
        let today = cached.lessons
            .filter { cal.isDate($0.start, inSameDayAs: now) }
            .sorted { $0.start < $1.start }
        guard !today.isEmpty else { return }
        logEvent("push-token megjött → terv feltöltése")
        await SummitPushSync.shared.kick(
            today: today, now: now, dayKey: Self.dayKey(for: now),
            userId: uid, pushToken: primaryPushToken)
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

    /// Cloudflare-push forgalom a Diagnosztika-tabnak (csak érdemi
    /// események: feltöltés, hiba, törlés — a percenkénti rutin-skipek
    /// nem kerülnek bele, lásd a gyűrű-kommentet feljebb).
    /// Perzisztens (UserDefaults-gyűrű, utolsó 30). Korábban csak memóriában
    /// élt, így minden app-újraindulás után üresen indult — a Diagnosztika-
    /// export „--- push ---” szakasza pont akkor volt üres, amikor kellett
    /// volna (a reggeli feltöltés egy korábbi folyamatban történt, vagy egy
    /// változatlan kimaradás-ok némán ismétlődött). Napot is írunk, mert a
    /// gyűrű több napot is átfoghat.
    @Published var pushLog: [String] = []
    private static let pushLogKey = "liveActivity.pushLog.v1"
    private static let pushLogMax = 30
    private static let pushLogTime: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "hu_HU")
        f.dateFormat = "MM.dd HH:mm:ss"
        return f
    }()

    func pushLogEvent(_ msg: String) {
        pushLog.append("\(Self.pushLogTime.string(from: Date())) \(msg)")
        if pushLog.count > Self.pushLogMax { pushLog.removeFirst(pushLog.count - Self.pushLogMax) }
        UserDefaults.standard.set(pushLog, forKey: Self.pushLogKey)
    }

    private static let eventTime: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "hu_HU")
        f.dateFormat = "HH:mm:ss"
        return f
    }()

    static func eventTimeString(_ date: Date = Date()) -> String {
        eventTime.string(from: date)
    }

    private func loadEvents() {
        pushLog = UserDefaults.standard.stringArray(forKey: Self.pushLogKey) ?? []
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

    /// Kényszer-újraindítás kell? Csak ha fut aznapi activity, tokenünk
    /// még sincs, és EZ a build nem vallotta magát push-képtelennek
    /// (különben az újraindítás is nil-lel végződne — végtelen kör).
    /// A friss (< 10 perces) activityt békén hagyjuk: a token tipikusan
    /// másodpercek alatt megérkezik, ne zúzzuk szét a kártyát miatta.
    /// Időbélyeg nélküli (régi buildtől örökölt) activity = 0 → azonnal.
    /// CSAK ELŐTÉRBEN: háttérből az Activity.request mindig
    /// ActivityAuthorizationError.visibility-vel dob, így a lezárt activity
    /// helyére nem indulna új — a kártya eltűnne, és az endAll a
    /// worker-tervet is törölné (a szerver-push is meghalna vele).
    /// Bizonyíték: az activitynek TÉNYLEG nincs tokenje (activity.pushToken
    /// nil), nem csak a memóriabeli szótár üres újraindulás után.
    private func shouldRestartForPush(existing: Activity<SummitLiveActivityAttributes>,
                                      now: Date, dayKey: String) -> Bool {
        guard UIApplication.shared.applicationState == .active else { return false }
        guard existing.pushToken == nil, pushTokens[existing.id] == nil, !startedWithoutPush else { return false }
        guard UserDefaults.standard.string(forKey: Self.pushRestartDayKey) != dayKey else { return false }
        let lastReq = UserDefaults.standard.double(forKey: Self.lastPushRequestAtKey)
        return now.timeIntervalSince1970 - lastReq > 600
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
        // KIVÉTEL: élő demo-teszt — a valós (esti, múltbeli) órarend nem
        // ölheti meg a tesztkártyát a védelmi ablakon belül.
        guard cur != nil || nxt != nil else {
            if let until = demoTestActiveUntil, now < until,
               !Activity<SummitLiveActivityAttributes>.activities.isEmpty {
                lastAction = "Demo teszt fut (valós órarend üres)"
                return true
            }
            // ÜRES today = tipikusan „még nincs betöltve az órarend” (app-
            // indításkor a Főoldal sync-je a refresh ELŐTT is lefut), NEM
            // „vége a napnak”. Ilyenkor SOSEM zárunk/törlünk: a régi hívás az
            // induláskori üres körrel törölte a worker-tervet (üres, token
            // nélküli rekord maradt fent), és az órák közti szerver-push soha
            // nem indult be. A valódi nap-vége ág lentebb: today NEM üres, de
            // minden óra a múltban van.
            if today.isEmpty {
                lastAction = "Nincs betöltött órarend → változatlan"
                return !Activity<SummitLiveActivityAttributes>.activities.isEmpty
            }
            demoTestActiveUntil = nil
            lastAction = "Mai órák vége → lezárva"
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
                pushToken: primaryPushToken)
        }

        // Van futó activity → update (háttérből is engedélyezett).
        // Másik napról maradt activityt előbb zárjuk, csak 1 lehet.
        if let existing = Activity<SummitLiveActivityAttributes>.activities.first {
            if existing.attributes.dayKey != key {
                await endAllImpl(dismissalPolicy: .immediate)
            } else if shouldRestartForPush(existing: existing, now: now, dayKey: key) {
                // Örökölt, push nélküli activity (régi build nil-lel
                // indította, frissítéskor megmaradt): az update-ág sosem
                // kérne újat, token sosem jönne. Zárjuk, és essünk át az
                // új request-ágra — naponta legfeljebb egyszer.
                await endAllImpl(dismissalPolicy: .immediate)
                logEvent("push-restart: örökölt activity újraindítva")
                UserDefaults.standard.set(key, forKey: Self.pushRestartDayKey)
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
            // Push-tokenes indítás a szerver-oldali átkapcsoláshoz. Ha a
            // build profiljában nincs Push, ez dob — ilyenkor helyi
            // módban (pushType nil) indulunk, minden más ugyanúgy megy.
            // A diagnosztikához naplózzuk, melyik ág nyert (a sima
            // "indítás" sor ezt nem árulja el).
            do {
                activity = try Activity.request(attributes: attrs, content: content, pushType: .token)
                UserDefaults.standard.set(false, forKey: Self.pushTypeNilKey)
                logEvent("pushType: token OK")
            } catch {
                activity = try Activity.request(attributes: attrs, content: content, pushType: nil)
                UserDefaults.standard.set(true, forKey: Self.pushTypeNilKey)
                logEvent("pushType NIL (token-kérés dobott: \(error.localizedDescription))")
            }
            UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: Self.lastPushRequestAtKey)
            // Új activity = ÚJ push-token. A workeren lévő korábbi terv (régi
            // tokennel, vagy a nap-eleji üres/lezárt rekord) különben
            // bennragadna, és a token-érkezéskori feltöltés a hash-egyezés
            // miatt némán kimaradna → a szerver rossz/nincs tokenre push-olna
            // (APNs 410), az órák közti átkapcsolás elmaradna. Ezért a
            // feltöltés-hash-t érvénytelenítjük: token megjöttekor biztosan
            // friss terv megy fel az ÚJ tokennel.
            SummitPushSync.shared.invalidateUploadHash(dayKey: key)
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
        // Kézi/teljes zárás oldja a demo-teszt védelmet is (a
        // startDemoTestNow az endAll UTÁN állítja be, így őt nem bántja).
        demoTestActiveUntil = nil
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
            // Demo/push-teszt nyoma: a preview-kulcsot is takarítjuk.
            if UserDefaults.standard.bool(forKey: SummitPushSync.previewUsedKey) {
                await SummitPushSync.shared.clear(userId: uid, dayKey: Self.dayKey(for: Date()), preview: true)
                UserDefaults.standard.set(false, forKey: SummitPushSync.previewUsedKey)
            }
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
    /// A határok (:preview kulcs) ilyenkor a workerbe is felmennek, így
    /// LEZÁRT telefonnal is tesztelhető a push-átkapcsolás, este is.
    /// (Az idő-csúszkás preview erre nem jó: a shift-matek csak aznapi,
    /// előrefelé eltolt időre értelmes — este szétesne.)
    func startDemoTestNow(userId: String = "", label: String = "Matek (teszt)", accentHex: Int = 0x4A90E2) async -> Bool {
        // Gyorsteszt-órarend: 1. óra 2 perc múlva véget ér, 2 perc szünet,
        // aztán 2. óra — a teljes átmenet ~5 perc alatt végignézhető.
        let now = Date()
        // Determinisztikus token-út: a régi (akár push nélküli) activityt
        // előbb zárjuk, így a teszt MINDIG friss .token-kéréssel indul —
        // különben egy örökölt nil-push activity update-ágán ragadnánk,
        // token sosem jönne, és a preview-feltöltés néma maradna.
        await endAll(dismissalPolicy: .immediate)
        demoTestActiveUntil = now.addingTimeInterval(15 * 60)
        let uid = userId.isEmpty ? "demo" : userId
        let demo = LessonItem(
            id: "demo-test", subject: label, room: "A1",
            start: now.addingTimeInterval(-5 * 60),
            end: now.addingTimeInterval(2 * 60),
            teacher: "Teszt Tanár", index: "1"
        )
        let next = LessonItem(
            id: "demo-test-next", subject: "Angol", room: "B2",
            start: now.addingTimeInterval(4 * 60),
            end: now.addingTimeInterval(10 * 60),
            teacher: "Smith", index: "2"
        )
        // Mű órarend: nem kerülhet a napi terv-cache-be (cacheable: false),
        // különben a háttér-ébresztés valós határoknál ezt mutatná.
        let ok = await syncDay(lessons: [demo, next], now: now, accentHex: accentHex, cacheable: false)
        // A token tipikusan másodpercek alatt megérkezik — várjuk meg,
        // különben a preview-feltöltés még token nélkül futna és kimaradna
        // (az esti tesztgomb pont ezért tűnt halottnak).
        for _ in 0..<15 {
            if primaryPushToken != nil { break }
            try? await Task.sleep(nanoseconds: 1_000_000_000)
        }
        await pushPreviewPlan(lessons: [demo, next], now: now, userId: uid)
        return ok
    }

    /// Kézi helyreállítás (Fejlesztő-gomb): a futó activity lezárása és
    /// friss kérése .token-nel — a régi buildtől örökölt push nélküli
    /// activityt is lecseréli. A mentett mai tervből dolgozik (offline is
    /// megy); ha az nincs, false (este: Demo teszt kell helyette).
    @discardableResult
    func restartForPush(now: Date = Date()) async -> Bool {
        await endAll(dismissalPolicy: .immediate)
        guard let cache = cachedLessons(now: now) else { return false }
        UserDefaults.standard.set(Self.dayKey(for: now), forKey: Self.pushRestartDayKey)
        return await syncDay(lessons: cache.lessons, now: now, accentHex: cache.accentHex)
    }

    func openSystemSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }
}
