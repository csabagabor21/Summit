# Flint

Nem hivatalos e-KRÉTA kliens iOS-re — SwiftUI, iOS 26, Liquid Glass.

https://github.com/csabagabor21/Flint

## Funkciók
- Valós idejű jegyek, átlagok, súlyozás, tanári kerekítés per-tárgy
- Órarend, házi feladatok, dolgozatok, hiányzások, üzenetek
- Élő órakártya TimelineView-val, következő óra + rögzített dolgozat/házi
- Helyi értesítések új jegyekről, házikról, dolgozatokról, hiányzásokról (polling-alapú diff — a KRÉTA-nak nincs push API-ja; demo módban tesztgombokkal)
- Profilkép per-felhasználó (fotókönyvtár, 512px, Documents tárolás)
- Téma: rendszer / világos / sötét + accent színválasztó, semleges háttér

## Követelmények
- iOS 26.0+
- Xcode 15+
- XcodeGen (opcionális, `project.yml` -> `Flint.xcodeproj`)

## Telepítés
```bash
# klónozás
git clone https://github.com/csabagabor21/Flint.git
cd Flint

# projekt generálás (ha van xcodegen)
xcodegen generate

# megnyitás
open Flint.xcodeproj
```

`project.yml` a `bundleIdPrefix: hu.flint.app` alatt generálja a projektet.

## Projekt struktúra
```
FirkaNative/
  App/          ContentView, FlintApp, RootViewModel
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
- e-KRÉTA API: `KretaAPI` + `KretaClient` (Bearer access_token, JWT institute_code)
- Demo mód: 10x tap a login ikonon, offline adatok `DemoData`-ból
