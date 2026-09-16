# Live Activity óraátmenet + Cloudflare push — hibaelemzés és javítási javaslat

> **Állapot (2026-09-16):** a Swift-oldali javítások (1., 2., 3., 6. pont)
> BEÉPÍTVE a repóba (`SummitPushSync.swift`, `SummitLiveActivityManager.swift`,
> `LiveActivityBackgroundRefresh.swift`), Simulator Debug build zöld. Ami még
> KÉZI: a worker deploy (`worker.proposed.js` → Cloudflare dashboard) és a
> 7. pont ellenőrzőlistája. A lenti kódrészletek referenciaként maradnak.

Dátum: 2026-09-16. Átnézett fájlok: `FirkaNative/LiveActivity/*.swift`,
`SummitWidgets/SummitLiveActivityWidget.swift`, `LiveActivityPush/worker.js`
(commitolt ÉS a fában lévő, még nem commitolt változat), `project.yml`,
`Summit.xcodeproj`, entitlements. A worker élőben válaszol
(`/` → ok, `/plan` validál), tehát a Cloudflare-oldal él, a hiba nem "nem
fut a worker" jellegű.

## TL;DR — három hiba, ami együtt adja a tünetet

| # | Hol | Mi történik | Következmény |
|---|-----|-------------|--------------|
| 1 | `SummitPushSync.makeEncoder()` | A content-state dátumait `.secondsSince1970`-nel kódolja. Az Apple-doksi szerint a rendszer a Live Activity push-t **mindig a default JSON-stratégiával** dekódolja (dátum = másodperc 2001-01-01 óta), egyedi stratégia „update failures”-t okoz. | Minden pusholt állapot dátuma +31 év (2057). A kártya vagy nem vált, vagy értelmetlen timerrel/progress-szel vált. **Ez önmagában elég, hogy a szerver-push „ne működjön”.** |
| 2 | `SummitLiveActivityManager.shouldRestartForPush` + `observePushTokens` | A push-tokenek csak memóriában vannak (`pushTokens`). Hideg indítás után (iOS kilőtte az appot, majd BGAppRefresh indítja) a szótár üres → a „push nélküli örökölt activity” gyanú **hamisan** igaz → `endAll` (worker-tervet is törli) → `Activity.request` **háttérből** → `ActivityAuthorizationError.visibility` → nincs új activity. | A kártya az első háttér-ébresztéskor eltűnik/beragad, ÉS a worker-terv törlődik → a push is meghal. Naponta egyszer, pont az első órahatár környékén. |
| 3 | `syncDayImpl` sorrend | A worker-feltöltés (`kick`) a request ELŐTT fut, token nélkül → kimarad. A token másodperceken belül megjön, de senki nem tölt fel rá — csak a KÖVETKEZŐ percenkénti előtéri sync. | Ha a user reggel 60 mp-en belül kilép az appból, aznap **semmi nem megy fel** a workerbe (a Diagnosztika „nincs push-token (a token még nem jött meg)”-en ragad). |

Másodlagos, de javítandó:

| # | Hol | Mi | Következmény |
|---|-----|----|--------------|
| 4 | `worker.js` `sendUpdate` | Nem-200 APNs-válasz törzse csak 400/410-nél kerül logba; 403 (`InvalidProviderToken`, rossz TEAM_ID/kulcs) 10× némán retry, aztán `sent=true`. | Kívülről „halott”, de nincs nyoma, mi a baj. |
| 5 | `worker.js` index | Az `index` kulcs read-modify-write a cron és a `/plan` között (KV eventually consistent, ~60 s). Egy elveszett kulcs = aznap nulla push annak az eszköznek. | Ritka egy usernél, több usernél rendszeres. |
| 6 | `LiveActivityBackgroundRefresh.refreshNow` | Ha a `syncDay` bármilyen okból hamisat ad (pl. háttérben nincs activity és a request dob), **holnap reggeli** ébresztőt kér és törli a mai határ-láncot. | A háttér-lánc egy hibától egész napra megszakad. |
| 7 | Cloudflare dashboard | A commitolt worker `*/5 * * * *`-re volt írva, a fában lévő új verzió `* * * * *`-et vár. Nem ellenőrizhető kívülről, melyik van kint és mi a cron. | Akár 5 perc késés vagy semmi, ha a trigger hiányzik. |

---

## 1. Content-state dátumkódolás (BIZTOS hiba — Apple-doksi)

Apple, *Starting and updating Live Activities with ActivityKit push
notifications*: „don't use any custom JSON encoding strategies to encode
your data, because the system always decodes JSON payloads for Live
Activity updates using its default encoding strategies. Custom encoding
strategies will result in update failures.” A `JSONDecoder` defaultja
(`.deferredToDate`) = másodperc **2001-01-01** óta. A commit `9dfed46`
(„APNs dátumkódolás javítása") pont fordítva javított: unix mp-re.
A különbség 978 307 200 s ≈ 31 év. (Ugyanezt a hibát más projekt is
elkövette és ugyanígy javította: a pusholt visszaszámláló „31 évvel volt
odébb”.)

Az `aps`-szintű mezők (`timestamp`, `stale-date`, `dismissal-date`)
továbbra is unix mp — azokat a worker teszi be, a `PushEntry.staleDate`
(`timeIntervalSince1970`) jó.

### Javítás — `FirkaNative/LiveActivity/SummitPushSync.swift`

```swift
/// A content-state-et a rendszer MINDIG a default JSON-stratégiával
/// dekódolja (Apple: „Custom encoding strategies will result in update
/// failures.”). Default = másodperc 2001-01-01 óta (.deferredToDate).
/// TILOS ide .secondsSince1970-et vagy .iso8601-et tenni — a korábbi
/// .secondsSince1970 minden pusholt dátumot +31 évre tolt (2057).
/// Az aps-szintű unix mp mezőket (fireAt, staleDate) külön Int/Double
/// mezőben visszük, nem a content-state-ben.
private static func makeEncoder() -> JSONEncoder {
    JSONEncoder()
}
```

Semmi más nem kell: a worker a `contentState` objektumot érintetlenül
továbbítja. A hash-őr (`lastUploadKey`) magától újratölt, mert a body
megváltozik.

## 2. Hideg indítás → hamis „push-restart” háttérből (BIZTOS hiba — kódból)

Lánc: `BGAppRefreshTask` hideg indítja az appot → `SummitLiveActivityManager.init`
→ `observePushTokens` **aszinkron** Task-ot indít (a jelenlegi tokent
szinkron nem olvassa) → `refreshNow` → `syncDay(cache)` → `syncDayImpl`
→ `shouldRestartForPush`: `pushTokens.isEmpty` ✓, `!startedWithoutPush` ✓,
ma még nem volt restart ✓, utolsó request > 10 perc ✓ → **true** →
`endAllImpl(.immediate)` (worker-terv `clear`, activity `end`) → átesik a
request-ágra → `Activity.request` háttérből → `ActivityAuthorizationError.visibility`
(Apple: Live Activity **csak előtérből** indítható) → „indítás SIKERTELEN”
→ `refreshNow` `!updated && canStart` → `scheduleMorningFallback` →
a mai lánc törölve. A felhasználó annyit lát: az első óra végén a kártya
eltűnt / nem váltott, és a Cloudflare sem küldött semmit (a terv törölve).

Ha az app csak felfüggesztve volt (nem lőtték ki), a szótár tele van, és
minden működik — ezért „néha jó, néha nem”.

### Javítás — `FirkaNative/LiveActivity/SummitLiveActivityManager.swift`

**a) `observePushTokens` cseréje** (szinkron mag + token-érkezéskor feltöltés,
ez a 3. hibát is javítja):

```swift
private func observePushTokens(for activity: Activity<SummitLiveActivityAttributes>) {
    guard pushTokenTasks[activity.id] == nil else { return }
    // Szinkron mag: a már futó activity AKTUÁLIS tokenje azonnal a
    // szótárba kerül. App-újraindulás után a stream aszinkron és csak
    // a változást hozza — addig a sync üres szótárral futott, és
    // hamisan „örökölt, push nélküli” activitynek nézte a sajátját.
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
            UserDefaults.standard.set(false, forKey: SummitLiveActivityManager.pushTypeNilKey)
            // Token megjött / cserélődött → AZONNALI terv-feltöltés a mentett
            // mai tervből. Enélkül a feltöltés a következő percenkénti
            // előtéri syncre várt: ha a user 60 mp-en belül kilépett,
            // aznap semmi nem ment fel a workerbe.
            if changed { await self.uploadPlanFromCache(now: Date()) }
        }
        self?.pushTokenTasks[activity.id] = nil
    }
}

private static func hex(_ data: Data) -> String {
    data.map { String(format: "%02.2hhx", $0) }.joined()
}

/// Az ELSŐ (egyetlen érvényes) activity tokenje. Zombi-duplikátum tokenje
/// sosem kerülhet a workerbe (a `pushTokens.values.first` bármelyiket adta).
var primaryPushToken: String? {
    if let first = Activity<SummitLiveActivityAttributes>.activities.first {
        if let t = pushTokens[first.id] { return t }
        if let d = first.pushToken { return Self.hex(d) }
    }
    return pushTokens.values.first
}

/// Terv-feltöltés a mentett mai tervből (token-érkezéskor hívjuk).
/// Csak valós cache-ből dolgozik — preview/demo sosem ír a cache-be.
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
```

**b) `shouldRestartForPush` cseréje** (csak előtérben, csak valódi bizonyítékra):

```swift
/// Kényszer-újraindítás kell? CSAK ELŐTÉRBEN: háttérből az
/// Activity.request mindig ActivityAuthorizationError.visibility-vel
/// dob, így a lezárt activity helyére nem indulna új — a kártya eltűnne,
/// és az endAll a worker-tervet is törölné (push is meghal).
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
```

Hívóhely `syncDayImpl`-ben:

```swift
} else if shouldRestartForPush(existing: existing, now: now, dayKey: key) {
```

**c) `pushTokens.values.first` → `primaryPushToken`** három helyen:

```swift
// pushPreviewPlan(...)
userId: userId.isEmpty ? "demo" : userId, pushToken: primaryPushToken, preview: true)

// syncDayImpl, a kick hívásban
pushToken: primaryPushToken)

// startDemoTestNow, a várakozó ciklusban
if primaryPushToken != nil { break }
```

## 3. Token érkezésekor azonnali feltöltés

A 2/a) pontban benne van (`uploadPlanFromCache`). Ettől egy 10 másodperces
reggeli app-megnyitás is elég: activity indul → token jön → terv fel.

## 4–5. Worker: hangos hibák, önjavító index, `/status`, `end` push

Kész fájl: **`LiveActivityPush/worker.proposed.js`** — a dashboardon
Edit code → teljes tartalom bemásolása → Deploy. (Node-dal mock KV + mock
APNs ellen 22 ellenőrzés zöld: időzítés, index-léptetés, 403-retry,
LIST-egyeztetés, sandbox/prod host, `/status`, törlés, takarítás, JWS
64 bájtos aláírás.) Változások a jelenlegihez képest:

- Minden nem-200 APNs-válasz törzse logba (`APNs 403 (prod): {"reason":"InvalidProviderToken"}`)
  és entrynként `last: {at, status, body}` a tervben.
- 403 → a cache-elt JWT eldobása (friss aláírás a következő körben).
- `apns-expiration` = +15 perc (elavult határ-állapot ne érkezzen órákkal később).
- 5 percenként (`minute % 5 == 0`) LIST-egyeztetés: az indexből kimaradt
  `plan:*` kulcs `next=0`-val bekerül → következő körben betöltődik.
  Free tier: 288 LIST/nap az 1000-es keretből.
- `GET /status?userId=<scoped>&dayKey=YYYY-MM-DD[&tag=preview]` →
  `{found, sandbox, tokenSuffix, indexNext, entries:[{fireAt, sent, attempts, last}]}`.
  A `<scoped>` = `<KRÉTA userId>.<identifierForVendor első 8>` (lásd
  `SummitPushSync.scopedUserId`). contentState-et nem ad vissza.
- `end: true` entry → `event: "end"` + `dismissal-date: +60 s` — az utolsó
  óra után a kártya nem ül 0:00-n. Az app-oldali párja:

`SummitPushSync.swift`:

```swift
struct PushEntry: Encodable {
    var fireAt: Int
    var contentState: SummitLiveActivityAttributes.ContentState
    var staleDate: Double?
    /// true → a worker `event: "end"`-et küld (utolsó óra vége).
    var end: Bool?
}

static func buildEntries(today: [LessonItem], now: Date) -> [PushEntry] {
    let bounds = Set(today.flatMap { [$0.start, $0.end] }.filter { $0 > now }).sorted()
    var out: [PushEntry] = []
    for b in bounds.prefix(30) {
        let at = b.addingTimeInterval(10)
        let cur = today.first { $0.start <= at && $0.end >= at }
        let nxt = today.first { $0.start > at }
        guard cur != nil || nxt != nil else { continue }
        let state = SummitLiveActivityManager.makeState(today: today, current: cur, next: nxt, now: at)
        out.append(PushEntry(fireAt: Int(at.timeIntervalSince1970), contentState: state,
                             staleDate: state.staleDate?.timeIntervalSince1970, end: nil))
    }
    // Utolsó óra vége: záró push (a fenti ciklus erre a határra nem ad
    // entryt, mert cur és nxt is nil). A rendszer 1 perc múlva leveszi.
    if let last = today.max(by: { $0.end < $1.end }), last.end > now {
        let at = last.end.addingTimeInterval(10)
        let final = SummitLiveActivityManager.makeState(today: today, current: last, next: nil, now: at)
        out.append(PushEntry(fireAt: Int(at.timeIntervalSince1970), contentState: final,
                             staleDate: nil, end: true))
    }
    return out
}
```

## 6. Háttér-lánc ne haljon meg egy sikertelen synctől

`LiveActivityBackgroundRefresh.refreshNow` vége:

```swift
let updated = await mgr.syncDay(lessons: lessons, now: now, accentHex: accent)
// Reggeli ébresztő CSAK akkor, ha mára tényleg nincs több óra — nem
// akkor, ha a sync más okból hamis (pl. háttérben nincs activity és a
// request dob). Utóbbinál a runRefresh 15 perces pót-ébresztése él.
let hasRemaining = lessons.contains { cal.isDate($0.start, inSameDayAs: now) && $0.end > now }
if !hasRemaining && SummitLiveActivityManager.shared.canStart {
    scheduleMorningFallback(now: now)
    return true
}
return updated
```

## 7. Cloudflare dashboard — ellenőrzőlista (5 perc)

1. Workers & Pages → `calm-leaf-ff15` → **Settings → Triggers**: pontosan
   egy Cron Trigger legyen, `* * * * *`. Ha `*/5 * * * *` vagy nincs: javítani.
2. **Settings → Variables**: `BUNDLE_ID` = `hu.flint` (a fő app bundle ID-ja,
   NEM a widgeté). Secrets: `TEAM_ID` = `38DAVMRN66` (a pbxproj
   `DEVELOPMENT_TEAM`-je — a .p8 kulcsnak **ehhez** a csapathoz kell
   tartoznia, különben 403 `InvalidProviderToken`). `APNS_KEY_ID` = a kulcs
   10 jegyű ID-ja, `APNS_KEY` = a .p8 teljes tartalma a BEGIN/END sorokkal.
3. **Bindings**: KV namespace, változónév pontosan `PLANS`.
4. Edit code → `worker.proposed.js` teljes tartalma → Deploy. `GET /`
   válaszában `"version":"2026-09-16-proposed"` kell legyen.
5. **Observability → Logs** bekapcsolva; tanítási időben az órahatár utáni
   percben vagy semmi (200, nincs log), vagy `APNs 4xx ...` sor — az
   utóbbi megmondja a valódi okot.

## Ellenőrzés a javítás után (TestFlight buildben)

1. Beállítások → Fejlesztő → **Demo teszt**. Diagnosztika → Push:
   „feltöltve (preview): 3 határ” **azonnal** (nem 1 perc múlva).
2. Telefon lezárva. ~2 perc + max 70 s: kártya → „Szünet”, majd ~4 perc
   után „Angol”, végül ~10 perc után lekerül (end push).
3. `curl "https://calm-leaf-ff15.gaborcsabusz.workers.dev/status?userId=<scoped>&dayKey=<ma>&tag=preview"`
   → minden entry `sent: true`, `last.status: 200`. Ha `last.status: 403`
   → 7/2 pont (kulcs/csapat). Ha `400 BadDeviceToken`/`DeviceTokenNotForTopic`
   → sandbox/prod keveredés vagy rossz `BUNDLE_ID`. Ha `indexNext:
   "NOT-IN-INDEX"` → 5 percen belül a LIST-egyeztetés beteszi.
4. Éles nap: reggel megnyitni az appot 10 mp-re, lezárni. Első órahatáron
   a kártya váltson; Diagnosztika → Live Activity napló: **ne** legyen
   „push-restart” sor; Push napló: „push-token megjött → terv feltöltése”.

## Miért nem elég a jelenlegi kód akkor sem, ha a 7. pont rendben van

A 1. hiba miatt a pusholt állapot dátumai 2057-be esnek; a widget
`Text(timerInterval:)`/`ProgressView(timerInterval:)` értelmezhetetlen
tartományt kap. A 2. hiba miatt az első háttér-ébresztés (hideg indításnál)
lezárja az activityt és törli a worker-tervet — utána nincs mit pusholni.
A 3. hiba miatt egy rövid reggeli app-megnyitás után egyáltalán nincs terv
a workerben. A három együtt fedi le a „nem lapoz és a Cloudflare se
működik” teljes tünetét; a javítások egymástól függetlenül beépíthetők,
de mind a három kell.
