# FirkaNative

Nem hivatalos e-KRÉTA kliens iOS-re — SwiftUI, iOS 26, Liquid Glass.

## Funkciók
- Valós idejű jegyek, átlagok, súlyozás, tanári kerekítés per-tárgy
- Órarend, házi feladatok, dolgozatok, hiányzások, üzenetek
- Élő órakártya TimelineView-val, következő óra + rögzített dolgozat/házi
- Profilkép per-felhasználó (fotókönyvtár, 512px, Documents tárolás)
- Téma: rendszer / világos / sötét + accent színválasztó, semleges sötét háttér (nem zöld)

## Követelmények
- iOS 26.0+
- Xcode 15+
- XcodeGen (opcionális, `project.yml` -> `FirkaNative.xcodeproj`)

## Telepítés
```bash
# klónozás
git clone <repo-url>
cd FirkaNative

# projekt generálás (ha van xcodegen)
xcodegen generate

# megnyitás
open FirkaNative.xcodeproj
```

`project.yml` a `bundleIdPrefix: hu.firka.native` alatt generálja a projektet.

## Projekt struktúra
```
FirkaNative/
  App/          ContentView, FirkaNativeApp, RootViewModel
  Core/
    Models/     KretaModels, GradingLogic, User
    Networking/ KretaAPI, KretaClient
    Storage/    SessionStore, KeychainHelper, CompletedStore, ProfileImageStore
    Theme/      AppColors, ThemeStore, AppTheme
  Features/
    Auth/       Login, KretaWebView
    Home/       Feed, LiveCard, ProfileImage
    Grades/     SubjectDetail
    Timetable/  Órarend
    ...
  Resources/    ikonok, showcase képek
```

## Jegyzetek
- e-KRÉTA API: `KretaAPI` + `KretaClient` (Bearer token, JWT institute_code)
- Demo mód: 10x tap a login ikonon, offline adatok `DemoData`-ból
