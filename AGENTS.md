# AGENTS.md — Summit

## Kötelező commit-szabály (minden AI-asszisztensre vonatkozik)
Minden módosítás / user prompt után KÖTELEZŐ:
1. `git add` a változott fájlokra,
2. commit **részletes magyar nyelvű** leírással (mit + miért, fájlonként),
3. `git push origin` (GitHub).

Nincs kivétel: egy soros fix, UI-csiszolás, komment-átírás után is commit + push.
Ne várj a userre, ne gyűjtögess több promptot egy commitba — egy feladat = egy commit. ez azért kell, hogyha a következő promt kinyír valamit, azonnal vissza tudjuk csinálni. Nem kell megvárni az engedélyt mivel ezzel rosszat nem tudsz tenni.
A commit előtt `xcodebuild ... build` sikerrel kell futhasson (Simulator, Debug).

## UI-tesztek (minden AI-asszisztensre vonatkozik)
UI-teszt cuccot NE csináljatok, mert nem kell: se új UI-tesztet ne írjatok
a `SummitUITests`-be, se a meglévőket ne futtassátok (`xcodebuild test`
tilos erre a targetre). A meglévő UI-tesztfájlt csak akkor érintsétek, ha
egy UI-változás miatt muszáj (pl. megszűnt tabra koppintana) — de új
teszt-metódus, bootstrap-login vagy screenshot-kör nem kerül bele.
Ellenőrzés = sima `xcodebuild ... build` (Simulator, Debug), az elég.

## Környezet
A gépen már NEM beta, hanem rendes Xcode van: `/Applications/Xcode.app`
(Xcode 27), az `xcode-select` is oda mutat — az `xcodebuild` hívások elé
SEMILYEN `DEVELOPER_DIR` nem kell, sima `xcodebuild ...` megy közvetlenül.
(Régi parancsokban még szerepelhet `DEVELOPER_DIR=...Xcode-beta...` — az
halott, törlendő.)

## Kötelező Firebase-deploy (minden AI-asszisztensre vonatkozik)
Ha BÁRMIT változtatsz a `Firebase/` könyvtárban (`firestore.rules`,
`functions/`, `firestore.indexes.json`, `firebase.json`), a commit + push
MELLÉ KÖTELEZŐ az éles deploy is ugyanabban a körben, kérdés nélkül:
`firebase deploy --only firestore:rules --project summit-14b74`
(illetve az adott cél: `--only functions`, `--only firestore:indexes`).
Szabály-/function-változtatás deploy nélkül HALOTT: az app az új mezőket
nem tudja szinkronizálni (a kliens legfeljebb legacy-visszalépéssel
túlél, de az új feature szerver-oldala nem él). A deploy sikerét a
terminál-kimenetben ellenőrizd (`Deploy complete!`), és a commit-üzenetben
jelezd, hogy deploy is volt.

## Release-flow (TestFlight) — "mehet" szóra, kérdés nélkül
Ha a user kiadja a `mehet` (vagy `mehet tovább`, `told ki`) parancsot, az
alábbi teljes flow-t végig kell vinni, köztes kérdések nélkül:
1. `xcodebuild archive` (Release, `generic/platform=iOS`).
2. Organizer (Xcode) → legfrissebb Summit archive → Distribute App →
   Custom → App Store Connect → Upload (Manage version and build number:
   BE, symbols: BE, internal-only: KI) → Next.
3. Provisionok: fent (Summit.app) `csabav3`, lent (SummitWidgets.appex)
   `wideget` (az egyetlen) → Next, végig.
4. Safari (App Store Connect már nyitva): frissítgetés, amíg az 1.0 alatt
   meg nem jelenik az új build → `+` → External testing → release note
   a lenti formátum-szabály szerint → kitenni.
A Next-gombokra nem kell rákérdezni, csak kattintani; a Manage-verziót a
user kérésére mindig visszakapcsoljuk (BE).

## Buildszám-szabály (user-döntés, 2026-10-17)
Buildszámot (`CURRENT_PROJECT_VERSION`) MANUÁLISAN SOHA nem léptetünk —
azt a kiadási folyamat intézi automatikusan (Organizer „Manage version
and build number", illetve az App Store Connect oldali verziókezelés).
Kivétel csak a user kifejezett, egyszeri kérése (pl. verzió-összehangolás
iPhone és Mac között). A `MARKETING_VERSION` is csak user-kérésre változik.

## Release notes formátum (kötelező, minden AI-asszisztensre vonatkozik)
Ha a user release note-ot kér, a válasz MINDIG egy angol Summit-szójáték
címsorral kezdődjön — a `To Summit up:` csak egy minta, mindig új, a
tartalomhoz illő szójáték kell
A címsor KÖTELEZŐEN tartalmazza a `Summit` szót — enélkül a release note érvénytelen.
A címsor RÖVID legyen: pár szavas szójáték, nem méteres vers — pl. `Summit on bell time`, nem egy egész mondat.
Utána csak bulletpointok (`- `), egy commitot vagy többet is egyben, egyetlen
listába sűrítve. A release note nyelve MINDIG angol. Felhasználóbarát, tömör
megfogalmazás — belső fájlnevek, API-részletek és commit-technikalitások
nélkül, csak az, amit a user észrevesz.

## Projekt-gyorstalpaló
- SwiftUI, iOS 26+, Liquid Glass. `Summit.xcodeproj` a mérvadó (XcodeGen-regen
  kidobja az `AppIcon.icon`-t a pbxproj-ból — regen után kézzel vissza kell tenni).
- e-KRÉTA kliens: `FirkaNative/Core/Networking/` (`KretaAPI`, `KretaClient`).
  Institut-kód: a tokenben rövid kód is lehet (nem host!) — a login
  végigpróbálja a jelölteket (`probeInstitute`) és az első MŰKÖDŐT tartja meg.
- Liquid Glass: CSAK valódi `.glassEffect(.regular...)` (AppTheme helperjei).
  Kézi opacity/blur-hack tilos — az iOS 27 rendszer-csúszkával (ultra clear ↔
  fully tinted) harcolna. Saját rétegek (pl. `SummitBackdrop`) kötelesek
  tisztelni `accessibilityReduceTransparency`-t és `colorSchemeContrast`-ot.
- Hibaüzenet sosem némulhat el: minden fetch-hiba naplóz (`KretaClient.diag`)
  és látszik a Beállítások → Diagnosztika tabon.

## Beállítás-szinkron (kötelező minden új user-állítható feature-re)
Ha új, a user által állítható állapotot vezetsz be (kapcsoló, csúszka, pipa,
választás — BÁRMIT), azt KÖTELEZŐ bekötni a `SummitSync`-szinkronba (`sync2`
Firestore-collection, végponttól végpontig titkosított, Blaze-mentes; a régi
nyílt `sync` csak az átálláshoz él, új mező oda NEM kerül). Kivétel csak az alábbi listán szerepelhet;
minden más szinkronizálandó:
- Szinkronizálandó minta: téma, kiemelőszín, szövegméret, profilkép,
  tanári kerekítés, felmentések, házi/dolgozat pipák, értesítési kapcsolók,
  Live Activity kapcsoló, iskolai események (+ mutatás-kapcsoló és mentett
  naptár-link).
- SOHA nem szinkronizálunk: hozzájárulás/analitika (`AnalyticsStore`,
  install-ID), belépési adatok (tokenek, `StoredUsers`, fiók-ID),
  fejlesztői/teszt flagok (`developer.enabled`, demo-preview),
  gyorsítótárak és eszköz-helyi műkődési állapot (Live Activity push-logok,
  napiterv, tantárgy-cache).
- Hogyan: a store írása postoljon `NotificationCenter`-dirty-t (minta:
  `GradingLogic.changedNotification`) VAGY a szerkesztő nézet hívja a
  `summitSync.markDirty(<mező>)`-t — a `SummitSync` 2 mp-es összevonással, csak a megjelölt mezőket tölti fel.
  Új mező = új eset a `SummitSyncField`-ben + kulcs a `Payload`-ban +
  `pushNow`/`parse` + `applyRemote` + a titkosított méretkorlát a
  `SummitSyncKey.maxCipherChars`-ban ÉS a `Firebase/firestore.rules`-ben
  (`sync2Fields`, `sync2TsFields`, `encOk(...)` az `isValidSync2Doc`-ban —
  a kettőnek egyeznie kell), plusz rules-teszt a `Firebase/rules-tests`-ben.
- A `sync2` docban minden mezőérték AES-GCM-mel titkosított (a kulcs a
  jelmondatból PBKDF2-vel, csak az eszközön képződik); nyíltan csak a
  doc-ID, a `v`, az `updatedAt` és a `ts_*` bélyegek mennek fel.
  Titkosítatlan mezőt a `sync2`-be írni TILOS.
- Személyes adat (név, OM, e-mail, token, jegy) a sync docba SEMMILYEN
  formában nem kerülhet.

## Backend-biztonság (minden AI-asszisztensre vonatkozik)
A repo nyilvános: minden kulcs, végpont és séma, ami itt van, mindenki
számára látszik. Ezért:
- Titok (API-kulcs, jelszó, `.p8`, service-account) SOHA nem kerülhet se
  a repóba, se az appba, se nyilvánosan olvasható Firestore-docba. A közös
  Gemini-kulcs csak a Cloudflare-workerben él (`GEMINI_KEY` secret), az app
  a `/ai/generate` proxyn át éri el.
- Minden új Summit-backend hívás (Firestore REST, worker) kapjon App Check
  tokent: `await SummitAppCheck.attach(to: &request)`. A Firestore-SDK ezt
  magától teszi.
- Belépési adat és felhasználói kulcs Keychainbe megy
  (`KeychainHelper`, `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`),
  nem UserDefaultsba.
- A KRÉTA-belépés PKCE-anyaga (verifier, nonce, state) belépésenként friss
  (`KretaAPI.makeAuthorizationRequest`) — fix érték nem kerülhet vissza.
