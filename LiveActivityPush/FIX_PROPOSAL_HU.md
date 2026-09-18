# Live Activity óraátmenet + Cloudflare push — hibaelemzés és javítási javaslat

> **Állapot (2026-09-18): a szerver-push két TOVÁBBI, önmagában is halálos
> hibája megvan és javítva** — egy rossz APNs-kulcs a workerben, és egy
> 64-karakteres token-feltétel az appban. Részletek a doksi végén:
> [2026-09-18 — a „minden jó, mégsem vált" kör](#2026-09-18--a-minden-jó-mégsem-vált-kör).
> A kártya tényleges átváltása csukott telefonon MÉG NINCS igazolva.

> **Állapot (2026-09-16):** a Swift-oldali javítások (1., 2., 3., 6. pont)
> BEÉPÍTVE a repóba (`SummitPushSync.swift`, `SummitLiveActivityManager.swift`,
> `LiveActivityBackgroundRefresh.swift`), Simulator Debug build zöld. Ami még
> KÉZI: a worker deploy (`worker.js` → Cloudflare dashboard) és a
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

Kész fájl: **`LiveActivityPush/worker.js`** (2026-09-16 óta ez a rendes worker) — a dashboardon
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
4. Edit code → `worker.js` teljes tartalma → Deploy. `GET /`
   válaszában `"version":"2026-09-16"` kell legyen.
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

---

# 2026-09-18 — a „minden jó, mégsem vált" kör

A 2026-09-16-i javítások után a push **továbbra sem** működött. Ebben a
körben két újabb, egymástól független hiba került elő; mindkettő önmagában
elég volt ahhoz, hogy egyetlen óraváltás se menjen ki, és mindkettő úgy
viselkedett, mintha „minden rendben lenne".

## TL;DR

| # | Hol | Mi történt | Hogyan lett bizonyítva |
|---|-----|-----------|------------------------|
| 8 | Cloudflare secretek | Az APNs **minden** pushra `403 InvalidProviderToken`-t adott, tehát a kulcs/Key ID/Team ID hármas nem állt össze. | Hamis (csupa `ab`) tokenes próba-terv feltöltése a `/plan`-ra, majd `/status`: a cron elindult, `attempts` 1→5-re nőtt, és minden kör `403`-at rögzített. Ehhez nem kellett telefon. |
| 9 | `SummitPushSync` + `SummitLiveActivityManager` + `worker.js` | Három helyen **pontosan 64 hex karakter** volt a push-token feltétele. A 64 hex (32 bájt) a klasszikus device token hossza; a Live Activity tokenje opak, ennél hosszabb. Így egy jó token minden úton „nincs push-token"-ként esett ki, és a terv soha nem ment fel. | A telefon Diagnosztika-exportja: `token=van (1)`, ugyanakkor `feltöltés=–`, a kimaradás-ok `nincs push-token`, a worker `/status` pedig „nincs terv a workerben". |

A kettő sorrendje fontos: a 9. pont miatt a workerre **nem is jutott fel**
valódi terv, tehát a 8. pontot (a kulcsot) valódi forgalommal nem is lehetett
volna észrevenni — csak a szándékosan hamis tokennel injektált próba-tervvel.

## 8. Az APNs-kulcs (worker-oldal)

A privát kulcs bájtjai **érvényesek voltak**: az aláírás megszületett (a
`/status`-ban volt `attempts` és APNs-válasz), tehát nem formátum-hiba,
hanem a kulcs AZONOSÍTÓ-oldala volt rossz — elgépelt vagy másik kulcshoz
tartozó `APNS_KEY_ID`, más csapat kulcsa, visszavont kulcs, vagy olyan
`.p8`, amin nincs APNs szolgáltatás (pl. egy App Store Connect API kulcs,
ami szintén P-256 `.p8`, de az APNs nem fogadja el).

Nehezítés: a gépen lévő `~/Downloads/Apple Auth Key.p8` iMessage-en jött és
át van **nevezve**, márpedig az Apple `AuthKey_<KEYID>.p8` néven adja ki —
a Key ID tehát a fájlból nem visszafejthető, csak a fejlesztői portálról.

Megoldás: a user új APNs-kulcsot generált. A `/selftest` ezután
`400 BadDeviceToken`-t adott (`keyId: 6NDL864PYX`, `teamId: 38DAVMRN66`),
ami azt jelenti, hogy az Apple **elfogadja a JWT-t**, és csak a
szándékosan hamis device tokent dobja el. A `TEAM_ID` eleve helyes volt.

### Worker-változások, hogy ez ne tudjon még egyszer elrejtőzni

- **`GET /selftest[?sandbox=1]`** — a kulcs/Key ID/Team ID hármas
  ellenőrzése telefon és valódi token NÉLKÜL, csupa-nulla device tokennel,
  magyar nyelvű `verdict`-tel. Visszaadja a használt `keyId`/`teamId`/
  `topic` értéket és a nyers vs. trimmelt hosszt.
- **`cleanId()`** — az `APNS_KEY_ID` / `TEAM_ID` / `BUNDLE_ID` trimmelve. A
  dashboardból másolt értékek végén ottmaradó sortörés PONTOSAN ugyanezt a
  403-at okozza, mint egy rossz kulcs; ezért adja vissza a `/selftest` a
  nyers hosszt is (`keyIdRaw > keyId` = whitespace).
- **A JWT-aláírás a `try`-on BELÜL** (`status: -1`) — rossz `.p8` esetén a
  kivétel eddig az egész cron-kört megölte, és az entryn nem lett se
  `attempts`, se `last`. A kulcshiba pont annyira volt néma, mint amit a
  4. pont állítása szerint megszüntetett.
- **403 és JWT-hiba nem fogyasztja a 10-es próba-budgetet** — ezeket a
  dashboardon javítják; ha elfogyasztanák, a határ 10 perc után
  „kiment"-re váltana, és a secret javítása után sem pótolná magát aznap.
- **`jsonRes()`** — minden JSON-válasz `charset=utf-8`-cal. A `/selftest`
  magyar verdiktje nélküle mojibake-ként jött (a `Response.json()` charset
  nélküli `application/json`-t ad, amit a kliens windows-1250-nek hisz).

### `apns_keycheck.mjs` (új)

A `.p8` ellenőrzése a workertől és a dashboardtól **függetlenül**, ES256
(`ieee-p1363`, nyers r||s) aláírással:

```
node LiveActivityPush/apns_keycheck.mjs <kulcs.p8> <KEY_ID> <TEAM_ID> hu.flint prod
```

`400 BadDeviceToken` = ez a hármas jó, ezt kell a secretekbe írni. Ez
választja el, hogy magával a kulcsfájllal van gond, vagy csak azzal, ami a
dashboardba be van írva — érdemes MÉG a beírás előtt lefuttatni.

## 9. A 64-karakteres token-feltétel (app- és worker-oldal)

Ez volt az érdemi, feltöltést ölő hiba:

| Hol | Régi feltétel | Következmény |
|-----|---------------|--------------|
| `SummitPushSync.kick` | `pushToken.count == 64` | a guard eldobta a feltöltést, és „nincs push-token"-t naplózott |
| `SummitLiveActivityManager.ensurePlanUploaded` | `primaryPushToken?.count == 64` | a 12 mp-es várakozás soha nem teljesült, majd a guard kilépett — ezért ismétlődött a „napközbeni feltöltés: nincs push-token" sor egész nap |
| `worker.js` `isHex64` | `/^[0-9a-fA-F]{64}$/` | a valódi tokenes tervet `bad-token`-nel dobta volna vissza → a Swift-oldal javítása EGYEDÜL nem lett volna elég |

Javítás: `SummitPushSync.isValidToken` (nem üres, páros hosszú, csupa hex)
és a workerben `isPushToken` (32..512 hex, páros). A hex-kötés marad, mert a
token az APNs URL path-jába kerül; csak a fix 64-es hossz tűnt el.

Részlet, amit könnyű félreolvasni: a preview-ág (esti teszt-gomb) a
token-várakozásnál csak `primaryPushToken != nil`-t ellenőrzött, a
`kick` 64-es guardja viszont a preview-feltöltést is ugyanúgy eldobta —
tehát a preview SEM működött, csak a várakozása futott le hamarabb.

### Diagnosztika-változások

- A **„Push token" sor mostantól a HOSSZT és a végződést is mutatja**, és
  kiírja, ha a token ÉRVÉNYTELEN. A puszta `van (1)` pont azt fedte el,
  hogy a token megvan, csak a feltöltés hossz-feltétele dobja el. A
  végződés a worker `/status` `tokenSuffix`-ével vethető össze.
- A kimaradás-ok külön szöveget kap, ha VAN token, de nem felel meg:
  `a push-token nem érvényes (N karakter)`. Eddig ez ugyanazt a
  „nincs push-token" sort adta, mint a tényleges hiány.

## Hibakeresési sorrend (ezt kövesd legközelebb)

1. **`GET /selftest`** — kulcs-oldal. `400 BadDeviceToken` = jó, mehetsz a
   2. pontra. `403` = kulcs/Key ID/Team ID. `-1` = rossz `.p8`.
2. **Diagnosztika → „Push token"** — van-e, és mekkora a HOSSZA. Ha van
   token, de „nincs push-token" a kimaradás oka, akkor valahol megint
   hossz-feltétel van.
3. **Diagnosztika → „Utolsó feltöltés"** — ha `–`, a terv soha nem ment
   fel; a workert nincs értelme tovább nyomozni.
4. **`/status`** — entrynkénti `fireAt / sent / attempts / last`.
5. Csak ezután gyanakodj buildre, profilra vagy entitlementre.

## Ami MÉG NYITOTT

- A worker deploy **továbbra is kézi** (dashboard → Edit code → beilleszt).
  A mai `worker.js` (`/selftest`, `isPushToken`, `jsonRes`) deploy nélkül
  nem ér semmit: a régi `isHex64` a valódi tokenes tervet visszadobja.
- **A SZERVER-PUSH tényleges kézbesítése nincs igazolva.** Óvatosan kell
  olvasni, hogy „a kártya egész nap váltott": a user szerint 2026-09-18-án
  a kártya végig rendesen követte az órákat — de ezt a **helyi** út adta
  (előtéri percenkénti sync + BG-ébresztés), nem a push. Bizonyíték: a
  napló csak `update:` sorokat tartalmaz, a workeren aznap egyáltalán nem
  volt terv (`nincs terv a workerben`, `feltöltés=–`), és a kulcs is
  403-at adott délig. **Épp ez a maszkoló hatás rejtette el hetekig a
  push-hibát:** amíg az iOS elég gyakran felébreszti az appot, a kártya
  akkor is jól viselkedik, ha a szerver-oldal halott. A push pont arra a
  helyzetre való, amikor az iOS NEM ébreszt — ezt csak az igazolja, ha a
  friss build telepítése után a Diagnosztikában `Utolsó feltöltés` ≠ `–`,
  a „Worker (mai terv)" alatt `terv fent: prod APNs`, és egy óraváltásnál
  `kiment` + `APNs 200` szerepel.
