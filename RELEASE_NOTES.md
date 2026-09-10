# Summit release notes

## Build 11
- Live Activity flips lessons via server push now: even if the phone stays locked and the system never wakes the app, the next lesson arrives on time.
- The progress bar animates live on its own, like Maps navigation — no more frozen bar between updates.
- A stuck duplicate card left behind by earlier versions closes itself automatically.
- Developer time-shift now drives the push path too (on a separate channel that never touches the real plan), so handoffs can be verified in the evening; the event log shows recent switches and errors with timestamps.

## Build 10
- Live Activity now switches to the next lesson with the phone locked and even without signal: it flips instantly from the saved day plan and only refines from the network afterwards.
- No more stuck 0:00 countdown between lessons: the wake-up comes right after the bell, and the card only refreshes when something actually changes.
- Developer Settings gained a "Jump to end of lesson" fast-forward (1–15 minutes, your pick) to watch the handoff live on the Lock Screen and Dynamic Island.
- New event log in Developer Settings shows recent Live Activity switches and errors with timestamps.

## Build 9
- Live Activity túléli az órahatárokat: naponta már egyetlen activity él, az óra- és szünetváltások csak frissítések (update) — ezek háttérből is engedélyezettek, szemben a korábbi óránkénti újraindítással, amit az iOS háttérben eldobott. A visszaszámlálók maguktól tickelnek, a halványodás csak a nap végén jön.
- Demo mód rendes felhasználóként: a Demo gombbal belépve ugyanaz az adatsáv szolgál ki, mint élesben — csak a háttérben helyi adatokból, KRÉTA-szerver nélkül. Nincs több párhuzamos demo-logika, a demo pont úgy viselkedik, mint egy valós fiók.
- Fejlesztői mód: a Beállítások alján a „Summit • Gábor Csaba" sor 10x megnyomására feloldható, kikapcsolható tesztelőfelület (idő-eltolás csúszka, értesítés-tesztek, Live Activity teszt) saját hegycsúcs-háttérképpel. A tesztelőeszközök kikerültek a demo nézetekből.
- MOST-kártya: a dolgozat- és házi-feliratokban már nem látszanak nyers HTML-tagek — ugyanaz a takarítás fut mindenhol (főoldal, órarend, feladatok, jegyek, értesítések).
- Live Activity app-megnyitás nélkül is: háttérbe vonuláskor biztonsági ébresztés kérése, a mai órák végén pedig holnap reggeli ébresztő — a következő tanítási napon magától elindul.
- Dynamic Island: a kinyitott nézetben az időzítő középre igazítva.
- Beállítások: gleccser-háttérkép mögött liquid glass szigetek — az egész szekció egy üvegkártya, nem soronkénti csíkok.

## Build 8
- Summit rebrand: új név mindenhol az appban (a bundle ID maradt, a TestFlight-frissítés zökkenőmentes).
- Megújult belépőképernyő: gleccser-panoráma háttér, nagy Summit felirat, üveg Bejelentkezés gomb alul.
- Új alapértelmezett kiemelőszín: Summit-kék.
- Órarend: visszafelé lapozáskor már nem dob vissza a jövő hétre — csak a Ma gomb ugrik a következő tanítási napra.
- Dolgozatok: ha a KRÉTA tudja az óraszámot, a dolgozat már csak annál az óránál jelenik meg, nem minden azonos tárgyú óránál.
- Mac: az iPad-app ablaka nem mehet olvashatatlanul kicsire, plusz új Szövegméret beállítás a Megjelenésben.
- Beállítások: letisztult Live Activity kapcsoló, értesítés-tesztgombok már csak demóban, dupla nyíl javítva a tanári kerekítésnél.

## Build 7
- Dolgozatok végre teljesen beolvasva: leírás/téma (pl. MEMORITER), tanár, hányadik óra, bejelentés dátuma és csoport — úgy, ahogy a KRÉTA mutatja.
- Dolgozatkártya: dátum mellett „(n. óra)", kinyitva tanár + bejelentve-dátum + csoport.
- Főoldali és iPad-es dolgozatsorok is kiírják az óraszámot.
- Egy hibás dolgozat-elem már nem törli a teljes listát; a módnevek a KRÉTA szép neveit használják.

## Build 6
- Órarend: a tabra lépve már a következő tanítási napot mutatja, ha a mai utolsó óra lement vagy hétvége van.
- Új jegy ünneplő kártya: új jegynél fullscreen kártya konfettival, százalékkal — értesítés-koppintásra és lehúzásos frissítéskor is.
- Dolgozatok az órarendben: narancs pill az órán, koppintásra átvisz a Feladatokba és kiemeli a sort.
- Feladatok tab: Feladatok | Dolgozatok | Kész szegmensek. A dolgozat lenyitható és kipipálható (a listában marad), a kész házik visszahozhatók.
- Oda-vissza ugrálás: Főoldalról és órarendből is átvisz a másik nézetbe, kiemelőszínű villantással.
- Profilkép mentés előtt kivágható (húzás + csippentés).
- Jegy- és óraszámok: már nem az üveg mögött, élesen látszanak (órarend, jegyek, hiányzások).
- Light mode javítások: hiányzások-főkártya árnyék, feladatos órasorok kontrasztja.
- Dolgozatok rendes magyar nevei („Szóbeli felelet" stb.) és magyar dátumok.
