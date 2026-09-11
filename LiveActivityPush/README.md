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
3. **Cron:** a worker Settings → Triggers → Add Cron Trigger: `* * * * *`.
4. **Változók:** Settings → Variables:
   - Text: `BUNDLE_ID` = `hu.flint`
   - Secrets → Add: `APNS_KEY` (a `.p8` fájl TARTALMA egyben),
     `APNS_KEY_ID` (10 jegyű), `TEAM_ID` (10 jegyű).
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
  más hiba = következő percben újrapróbálja (max ~10x).
- Health: https://calm-leaf-ff15.gaborcsabusz.workers.dev/ → `{"ok":true,"service":"summit-liveactivity-push"}`
- Esti push-teszt tanítási időn kívül: Fejlesztő → Idő-eltolás csúszka
  délelőttre (pl. 9:40) + bekapcsolás. Az app ilyenkor a `:preview` kulcsra
  tölt (a valós tervet nem bántja), a worker ugyanúgy kiküldi a határokat.
  Zárd le a telefont és várd az átkapcsolást. A csúszka kikapcsolásakor az
  első valós sync törli a preview-nyomot.
- Kézi próba curl-lel:
  `curl -X POST https://calm-leaf-ff15.gaborcsabusz.workers.dev/plan -H 'content-type: application/json' -d '{"userId":"teszt","dayKey":"2026-09-10","pushToken":"...","sandbox":true,"entries":[]}'`
  → `{"ok":true,"entries":0}`.

## Költség

Free tier: napi 100 ezer kérés, percenkénti cron, KV-olvasás bőven elég
(egy felhasználó napi ~15 push + pár tucat KV-művelet). Bankkártya nem kell.
