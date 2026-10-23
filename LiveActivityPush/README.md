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
   - Text: `FIREBASE_PROJECT_NUMBER` = `738331591118` (a `summit-14b74`
     projektszáma — az App Check-token `iss`/`aud` mezőjét ehhez vetjük).
   - Text (opcionális): `FIREBASE_APP_IDS` = vesszővel elválasztott Firebase
     app ID-k (pl. `1:738331591118:ios:…`). Ha meg van adva, más app
     tokenje nem jó; üresen a projekt bármelyik appja elfogadott.
   - Text: `APPCHECK_ENFORCE` — üresen hagyva **monitor mód** (lásd lent),
     `1` = a `/plan` és a `/status` App Check nélkül 401-et ad.
   - Secret: `ADMIN_TOKEN` — hosszú véletlen string (pl.
     `openssl rand -hex 32`). Enélkül a `/selftest` nem létezik (404).
   - Secret: `GEMINI_KEY` — a közös AI-tartalék Gemini-kulcsa (Google AI
     Studio). SOHA ne kerüljön Firestore-ba vagy az appba.
   - Text (opcionális): `GEMINI_MODEL` — alapértelmezés
     `gemini-3.5-flash-lite`. Csak ez dönti el a modellt, a kliens nem.
   - Binding (opcionális): Settings → Bindings → Add → **Rate limiting**,
     neve pontosan `AI_LIMITER` (pl. 10 kérés / 60 mp) — IP-nként fojtja
     az `/ai/generate`-et. Nélküle csak az App Check véd.
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

## App Check és a közös AI-tartalék (2026-10-23)

A repo nyilvános, így a worker címe és a kérésformátum is az: auth nélkül
bárki feltölthetne/törölhetne terveket, olvashatná a `/status`-t, és
rángathatná az APNs-t a `/selftest`-tel. Ezért:

- **`/plan`, `/status`** — Firebase App Check (`X-Firebase-AppCheck`
  fejléc, RS256 JWT, a Google JWKS-ével ellenőrizve). Bevezetés két
  lépésben, hogy a régi appverziók ne haljanak meg a deploytól:
  1. **Monitor mód** (`APPCHECK_ENFORCE` üres): minden kérés átmegy, de a
     log soronként írja: `appcheck=ok path=/plan`, `appcheck=missing …`
     (régi app), `appcheck=invalid:<ok> …`. Observability → Logs → szűrés
     `appcheck=`-re.
  2. **Éles mód** (`APPCHECK_ENFORCE` = `1`): ha a `missing` sorok
     gyakorlatilag eltűntek (a userek frissítettek), átkapcsolni. Innen a
     token nélküli kérés 401 `{"ok":false,"error":"app-check"}`.
- **`/selftest`** — csak `Authorization: Bearer <ADMIN_TOKEN>`-nel.
- **`POST /ai/generate`** — Gemini-proxy a közös, ingyenes AI-tartalékhoz
  (saját Meta-kulcs nélküli jegyzetgenerálás). App Check itt MINDIG
  kötelező (monitor módban is), a törzs a Gemini natív `generateContent`
  alakja modell nélkül; a worker streamként, parse nélkül továbbítja a
  `GEMINI_MODEL`-re a `GEMINI_KEY`-jel, max 20 MB. Válaszok: 200 = a Gemini
  válasza változatlanul, 401 = App Check, 411/413 = hiányzó/túl nagy
  Content-Length, 429 = keret (saját `AI_LIMITER` vagy a Gemini), 502
  `upstream-auth` = a `GEMINI_KEY` rossz/visszavont, 503 = nincs beállítva.
  A tananyag sosem kerül a logba.

Az App Check-token csak akkor érvényes, ha a Firebase konzolban
(App Check → Apps) az iOS app regisztrálva van App Attest (és DeviceCheck)
szolgáltatóval; szimulátoros/Debug buildhez a konzolban debug tokent kell
felvenni (az app a Xcode-konzolra írja ki első induláskor).

Tesztek (élő worker és Google nélkül, mockolt fetch/KV/JWKS):
`node --test LiveActivityPush/`

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
  így a secret javítása után a nap hátralévő határai maguktól kimennek —
  viszont backoff-fal (5p, 15p, 30p, 60p...), hogy egy rossz kulcs ne egye
  meg a napi KV-íráskeretet (2026-10-15). Azonos tartalmú re-upload
  (pl. minden app-megnyitás) 0 KV-írással megúszható (`uploadHash`).
- Health: https://calm-leaf-ff15.gaborcsabusz.workers.dev/ → `{"ok":true,"service":"summit-liveactivity-push","version":"2026-10-23"}`
  (ha a `version` régebbi, a dashboardon még a korábbi kód fut — újra kell deployolni).
- **ELSŐ LÉPÉS push-hiba esetén — kulcs-ellenőrzés telefon nélkül:**
  `curl -H "Authorization: Bearer $ADMIN_TOKEN" https://calm-leaf-ff15.gaborcsabusz.workers.dev/selftest`
  (vagy `/selftest?sandbox=1`; `ADMIN_TOKEN` nélkül 404, rossz tokennel 401). Csupa-nulla device tokennel
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
  Éles App Check módban (`APPCHECK_ENFORCE=1`) curl-lel már nem hívható
  (401) — onnan az app Diagnosztika-tabja mutatja, ami érvényes tokent küld.
- Az utolsó óra végére az app `end: true` entryt küld → a worker
  `event: "end"` + `dismissal-date` (+1 perc) pusht küld, a kártya lekerül.
- Esti push-teszt tanítási időn kívül: Fejlesztő → Idő-eltolás csúszka
  délelőttre (pl. 9:40) + bekapcsolás. Az app ilyenkor a `:preview` kulcsra
  tölt (a valós tervet nem bántja), a worker ugyanúgy kiküldi a határokat.
  Zárd le a telefont és várd az átkapcsolást. A csúszka kikapcsolásakor az
  első valós sync törli a preview-nyomot.
- A végpontok viselkedése (App Check, `/selftest`-kapu, AI-proxy) az élő
  worker hívása nélkül, helyben ellenőrizhető: `node --test LiveActivityPush/`.
  Az élő `/plan`-t ne curl-özd kamu adattal — monitor módban az is valódi
  KV-írás a napi keretből.

## Költség

Free tier: napi 100 ezer kérés és KV-olvasás, a percenkénti cron ennek
töredéke — körönként 1 index-olvasás (~1440/nap), terv-olvasás csak esedékes
határnál (felhasználónként napi ~15 push + pár tucat KV-művelet). Írás napi
pár tucat (hash-őr + határonkénti jelölés). Bankkártya nem kell.
