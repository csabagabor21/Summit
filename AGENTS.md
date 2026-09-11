# AGENTS.md — Summit

## Kötelező commit-szabály (minden AI-asszisztensre vonatkozik)
Minden módosítás / user prompt után KÖTELEZŐ:
1. `git add` a változott fájlokra,
2. commit **részletes magyar nyelvű** leírással (mit + miért, fájlonként),
3. `git push origin` (GitHub).

Nincs kivétel: egy soros fix, UI-csiszolás, komment-átírás után is commit + push.
Ne várj a userre, ne gyűjtögess több promptot egy commitba — egy feladat = egy commit.
A commit előtt `xcodebuild ... build` sikerrel kell futhasson (Simulator, Debug).

## Környezet
A gépen Xcode **beta** van: `/Applications/Xcode-beta.app`. Az `xcode-select`
a Command Line Tools-ra mutat, ezért az `xcodebuild` hívások elé MINDIG
`DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer` kell
(vagy `sudo xcode-select -s` egyszer — de azt csak a user állítsa át).

## Release-flow (TestFlight) — "mehet" szóra, kérdés nélkül
Ha a user kiadja a `mehet` (vagy `mehet tovább`, `told ki`) parancsot, az
alábbi teljes flow-t végig kell vinni, köztes kérdések nélkül:
1. `DEVELOPER_DIR=...xcodebuild archive` (Release, `generic/platform=iOS`).
2. Organizer (Xcode-beta) → legfrissebb Summit archive → Distribute App →
   Custom → App Store Connect → Upload (Manage version and build number:
   BE, symbols: BE, internal-only: KI) → Next.
3. Provisionok: fent (Summit.app) `csabav3`, lent (SummitWidgets.appex)
   `wideget` (az egyetlen) → Next, végig.
4. Safari (App Store Connect már nyitva): frissítgetés, amíg az 1.0 alatt
   meg nem jelenik az új build → `+` → External testing → release note
   a lenti formátum-szabály szerint → kitenni.
A Next-gombokra nem kell rákérdezni, csak kattintani; a Manage-verziót a
user kérésére mindig visszakapcsoljuk (BE).

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
