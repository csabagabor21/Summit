# Summit Live Activity push (Cloudflare Worker)

Szerver-oldali óraátmenet: ha az iOS egyáltalán nem ébreszti fel az appot,
a kártyát ilyenkor is átkapcsolja egy Apple-push. Az app induláskor kér
push-tokent, és feltölti a workerbe a mai határokhoz tartozó kész
állapotokat — a worker percenként megnézi, mi járt le, és kiküldi.

## Egyszeri Cloudflare-beállítás (dashboard, ~10 perc)

1. **Worker létrehozása:** Workers & Pages → Create → Hello World sablon →
   Deploy. Utána Edit code → a `LiveActivityPush/worker.js` teljes tartalmát
   bemásolni → Deploy.
2. **KV:** Workers & Pages → KV → Create namespace (pl. `summit-plans`) →
   vissza a workerre: Settings → Bindings → Add → KV namespace, neve
   pontosan `PLANS`.
3. **Cron:** a worker Settings → Triggers → Add Cron Trigger: `* * * * *`
    (percenként — de a körök olcsók: a worker körönként csak az `index`-et
    olvassa, és csak azt a tervet tölti be, amelynél tényleg esedékes egy
    határ (az index tervenként a következő határt is tárolja). Éjjel,
    hétvégén, lyukasórában egy kör = 1 KV-olvasás. A push legfeljebb
    ~1 percet késik a határhoz képest; az élő visszaszámlálót a widget
    magától tickeli, a push csak az állapotot fordítja).
4. **Változók:** Settings → Variables:
   - Text: `BUNDLE_ID` = `hu.flint`
   - Secrets → Add: `APNS_KEY` (a `.p8` fájl TARTALMA egyben),
     `APNS_KEY_ID` (10 jegyű), `TEAM_ID` (10 jegyű).
   A cron 5 percenként (`perc % 5 == 0`) LIST-tel is egyezteti az indexet,
   így egy KV-verseny miatt kimaradt terv legfeljebb 5 percet késik.
5. **App-oldal:** `SummitPushSync.swift`-ben a `baseURL`-t átírni a worker
   címére (`https://valami.workers.dev`). Amíg ez nincs kitöltve, az app
   csendben helyi módban marad (a push-feltöltés kimarad).
6. **TestFlight-profile:** az App ID-n a Push Notifications capability
   bekapcsolása után ÚJ profilt kell generálni (a régi, push nélküli
   profillal aláírt build sosem kap tokent — az app ezt azóta ki is
   írja). A repo a `csabav3` profilt és a két entitlements-fájlt
   használja: Debug → `Summit.entitlements` (`development`), Release →
   `SummitRelease.entitlements` (`production`); mindkettő a `project.yml`
   `configs`-jában is rögzítve van, hogy az xcodegen-regen se dobja el.

## Amit mástól kell kérni (egyszer)

Az APNs `.p8` kulcsot az generálja le, aki **Admin** a fejlesztői csapatban
(az app bundle-jának gazdája): Certificates, Identifiers & Profiles →
Keys → + → Apple Push Notifications Service (APNs) → letöltés. A letöltött
fájlt csak egyszer adják ki — eltenni! Ugyanaz a kulcs jó sandboxra és
élesre is. (Az appban a Push Notifications capability bekapcsolása is az
App ID gazdájánál történik — különben a tokenkérés néma marad, de a helyi
Live Activity ettől még működik.)

## Tesztelés

- Dev (Xcode-ból futtatott) build → sandbox APNs-re megy magától
  (`sandbox: true`), éles/TestFlight → productionre. A kettő tokenje nem
  csereszabatos — a worker terven tárolja, melyik hova tartozik.
- Bejövő terv ellenőrzése: a worker logban (Observability → Logs) látszik
  minden küldés; `400/410` = halott token (a worker leveszi a listáról),
  más hiba = következő percben újrapróbálja (max ~10x). A 403 és a
  JWT-hiba kivétel: ezek konfigurációs gondok, nem fogyasztják a 10 próbát,
  így a secret javítása után a nap hátralévő határai maguktól kimennek.
- Health: https://calm-leaf-ff15.gaborcsabusz.workers.dev/ → `{"ok":true,"service":"summit-liveactivity-push","version":"2026-09-18"}`
  (ha a `version` régebbi, a dashboardon még a korábbi kód fut — újra kell deployolni).
- **ELSŐ LÉPÉS push-hiba esetén — kulcs-ellenőrzés telefon nélkül:**
  `GET /selftest` (vagy `/selftest?sandbox=1`). Csupa-nulla device tokennel
  bekopogtat az APNs-nél, tehát senkinek semmi nem megy ki, de a válaszban
  ott van a használt `keyId`/`teamId`/`topic`, a nyers vs. trimmelt hossz
  (ha `keyIdRaw` > `keyId`, whitespace ragadt a secretbe), és egy magyar
  `verdict`. `400 BadDeviceToken` = a kulcs-oldal rendben, a hibát az app
  oldalán kell keresni; `403 InvalidProviderToken` = a Key ID / Team ID /
  .p8 hármas nem áll össze. Ez a végpont szűri ki azt az esetet, amikor a
  feltöltés és a cron is hibátlan, csak az Apple dobja el minden pusht.
- A `.p8` külön, a workertől függetlenül is ellenőrizhető — ez mondja meg,
  hogy magával a kulcsfájllal van gond, vagy csak azzal, ami a dashboardba
  be van írva:
  `node apns_keycheck.mjs <kulcs.p8> <KEY_ID> <TEAM_ID> hu.flint prod`
  (`400 BadDeviceToken` = ez a hármas jó, ezt írd a secretekbe).
- Státusz egy tervről: `GET /status?userId=<KRÉTA-userId>.<identifierForVendor első 8>&dayKey=YYYY-MM-DD[&tag=preview]`
  → entrynként `fireAt / sent / attempts / last{status, body}`. `last.status`
  403 = kulcs/csapat gond (TEAM_ID, .p8) → futtasd a `/selftest`-et,
  `-1` = az APNS_KEY nem értelmezhető .p8 (a JWT-aláírás dőlt el),
  400 BadDeviceToken vagy
  DeviceTokenNotForTopic = sandbox/prod keveredés vagy rossz BUNDLE_ID,
  `indexNext: "NOT-IN-INDEX"` = 5 percen belül a LIST-egyeztetés beteszi.
- Az utolsó óra végére az app `end: true` entryt küld → a worker
  `event: "end"` + `dismissal-date` (+1 perc) pusht küld, a kártya lekerül.
- Esti push-teszt tanítási időn kívül: Fejlesztő → Idő-eltolás csúszka
  délelőttre (pl. 9:40) + bekapcsolás. Az app ilyenkor a `:preview` kulcsra
  tölt (a valós tervet nem bántja), a worker ugyanúgy kiküldi a határokat.
  Zárd le a telefont és várd az átkapcsolást. A csúszka kikapcsolásakor az
  első valós sync törli a preview-nyomot.
- Kézi próba curl-lel:
  `curl -X POST https://calm-leaf-ff15.gaborcsabusz.workers.dev/plan -H 'content-type: application/json' -d '{"userId":"teszt","dayKey":"2026-09-10","pushToken":"...","sandbox":true,"entries":[]}'`
  → `{"ok":true,"entries":0}`.

## Költség

Free tier: napi 100 ezer kérés és KV-olvasás, a percenkénti cron ennek
töredéke — körönként 1 index-olvasás (~1440/nap), terv-olvasás csak esedékes
határnál (felhasználónként napi ~15 push + pár tucat KV-művelet). Írás napi
pár tucat (hash-őr + határonkénti jelölés). Bankkártya nem kell.
