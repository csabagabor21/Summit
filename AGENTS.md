# AGENTS.md — Summit

## Kötelező commit-szabály (minden AI-asszisztensre vonatkozik)
Minden módosítás / user prompt után KÖTELEZŐ:
1. `git add` a változott fájlokra,
2. commit **részletes magyar nyelvű** leírással (mit + miért, fájlonként),
3. `git push origin` (GitHub).

Nincs kivétel: egy soros fix, UI-csiszolás, komment-átírás után is commit + push.
Ne várj a userre, ne gyűjtögess több promptot egy commitba — egy feladat = egy commit.
A commit előtt `xcodebuild ... build` sikerrel kell futhasson (Simulator, Debug).

## Release notes formátum (kötelező, minden AI-asszisztensre vonatkozik)
Ha a user release note-ot kér, a válasz MINDIG egy angol Summit-szójáték
címsorral kezdődjön — a `To Summit up:` csak egy minta, mindig új, a
tartalomhoz illő szójáték kell (pl. `Summit's fresh peak:`, `Reaching new Summits:`).
A címsor KÖTELEZŐEN tartalmazza a `Summit` szót — enélkül a release note érvénytelen.
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
