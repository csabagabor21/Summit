# Summit

Nem hivatalos e-KRÉTA kliens iOS-re — SwiftUI, iOS 26, Liquid Glass.

https://github.com/csabagabor21/Summit

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
- XcodeGen (opcionális, `project.yml` -> `Summit.xcodeproj`)

## Telepítés
```bash
# klónozás
git clone https://github.com/csabagabor21/Summit.git
cd Summit

# projekt generálás (ha van xcodegen)
xcodegen generate

# megnyitás
open Summit.xcodeproj
```

`project.yml` a `bundleIdPrefix: hu.flint.app` alatt generálja a projektet.

## Projekt struktúra
```
FirkaNative/
  App/          ContentView, SummitApp, RootViewModel
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

## AI-munka szabály (kötelező, minden AI-ra vonatkozik)
Minden módosítás / prompt után KÖTELEZŐ commitolni és pusholni GitHubra,
részletes magyar nyelvű leírással. Nincs kivétel: kisebb javítás, UI-matrica,
egysoros fix után is. A commit message sorolja fel a változott fájlokat és a
miértet. Lásd még: `AGENTS.md`.
