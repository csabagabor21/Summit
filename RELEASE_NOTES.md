# Summit release notes

## 1.2 (Build 1)
- Monthly Wrapped now opens on a real mountain photo, with every stat sitting on Liquid Glass.
- 30 famous peaks rotate through your months — yours stays yours, with the photographer's credit under it.
- Shared Wrapped images carry the same mountain background, photographer included.

## Build 62
- Handoff: start on iPhone, continue on Mac (and back) — the other device opens the same tab and position, straight from the Dock icon.
- The Watch tab now appears on Mac too when your iPhone has a paired watch, so study notes can start from the desktop as well.
- The Watch Smart Stack widget is all-in-one now: school-event card in the morning, live lesson view with per-second countdown during class, tomorrow's note in the evening — and the corner complication shows context (subject + time) instead of bare minutes.
- New "Today" Lock Screen widget: today's event, today's exam, remaining lessons — turning into the next-day note after the last lesson.
- Widgets no longer get stuck after lesson transitions: the countdown ticks without reloads, tomorrow's card arrives on time, and days off school get their own card.
- The new-grade celebration is real native Apple confetti now.
- "What if" grades: swipe a grade to swap in a phantom value with a live average preview, discard it with a swipe.
- Study-note AI reads the whole document: every PDF page goes to the model as an image, photos can be attached, no more cut-off text — and without your own key a free shared fallback answers.
- Notes stay readable on the watch: fixed spacing, paragraph gaps, and garbled AI text blocks are cleaned automatically.
- Tapping homework/exam pills without a paired watch now opens Tasks directly, with a close button so you never get stuck.
- Sync is honest now: pull really reads the server (last-writer-wins), and the review account syncs too.
- The Lock Screen card disappears right at the end of the last lesson instead of lingering for hours.

## Build 18
- New Apple Watch Smart Stack widget ("Most"): the current lesson with live progress and remaining time, the next one during breaks, the first one in the morning — plus the day's homework/exam line, all in Hungarian.
- The watch app now runs on older watches too (watchOS 10, Series 4 and up), and widgets keep showing the last known data instead of going blank.
- New study notes: the Watch tab turns your material into per-topic notes with Meta AI (or write your own) — synced to all your devices and readable on the watch's Notes tab, mapped to your exams. The Meta API key lives in Settings, syncs across your devices, and never goes to the watch.
- Notes got simpler: one topic is one note (title + text), topics edit in place, and existing two-level notes migrate automatically.
- The watch timetable now mirrors the phone: green "Felmentett" badge for exempted subjects, smaller status badges, remaining time squeezed next to the progress bar ("35p"), room names in an accent-tinted glass cube, and the day's school events as cards above the lessons.
- Exempted subjects and same-day homework/exams travel to the watch and widgets too, with the phone's green/grey status colors.
- Watch deadlines speak in lessons ("Ma 3. óra") instead of misleading midnight times, task rows expand on tap, and pulling the home screen also pushes tasks to the watch.
- The home screen always shows the "all exams/tasks" links, and the Dynamic Island timer no longer stretches the pill.
- Fixed a crash when tapping a notification onto the new-grade celebration card.
- The Watch tab only shows up if you have a paired Apple Watch — otherwise the tab bar stays clean.

## Build 17
- Empty timetable days now say what KRÉTA says: "Tanítás nélküli munkanap (Nem órarendi nap) (Hétfő)" and friends, instead of a generic day-off text.
- Projected exams finally leave the Exams tab when their lesson is over — even on unnumbered days or when every lesson of the day has ended.
- The average graph on the Grades tab no longer labels September-only data as October: axis ticks come from the actual data now.
- Pull-to-refresh on the home screen also syncs to your other devices, both ways — pending edits left behind by a killed app now flush on the next refresh or foreground, which fixes the flaky Mac round-trip too.

## Build 16
- New timetable widget for the Home Screen (small, medium, large, plus Lock Screen): it always shows the current or next lesson, steps forward on its own when a lesson ends, and the medium list starts at the current lesson instead of the first one.
- New school events calendar: add your school's calendar once — a share link (Google Calendar links work too), pasted text, raw ICS or an .ics file — and it syncs to all your devices, appearing above the timetable as full-width cards.
- Homework and exam pills now show the lesson number they belong to.
- The default theme now follows the system instead of forcing dark.
- The profile photo cropper's buttons no longer slide under the notch.

## Build 15
- Locked-phone lesson flips finally work end to end: the day plan actually reaches the server now, so the next lesson lands on your Lock Screen on its own — app closed, phone in your pocket.
- Diagnostics stopped hiding the problem: the push row shows how long the channel is and how it ends, and says outright when it can't be used — a perfectly good channel can no longer look like a missing one.
- New opt-in usage stats: after login a consent screen spells out exactly what is collected (and what never is); off by default, one tap to turn off in Settings. It powers the school map on the website.
- The school map got real: pins are truly geocoded (Mathiász lands in Balatonboglár, not Siófok), and small schools show only their town until at least 6 students join.
- The Lock Screen card keeps flipping: midday opens also refresh the server plan, an empty timetable no longer kills the day, and the subject list loads again where KRÉTA rejects wide date ranges.
- Messages actually load now (correct mailboxes, Hungarian dates, readable note types), and PDFs open from homework and messages alike.
- Notifications calm down: one refresh, one banner at most — a digest instead of a stack. The inbox moved into the bell on the home screen, with an unread dot.
- Fresh absences without a verdict count as unjustified, not justified; animations are unified and quieter across the app.
- The consent screen no longer ghosts the home screen behind it on Mac.

## Build 14
- The Lock Screen card now flips lessons even with the phone locked in your pocket — the long fight with the server is over, handoffs just arrive.
- The progress bar fills up during lessons and drains during breaks, so you can see at a glance which one is running out.
- New Messages tab: KRÉTA messages open right in the app, attachments included.
- Homework and exams can carry attachments too — PDFs open in a built-in viewer.
- The Today button in the timetable now appears whenever you've swiped away from today, not just when switching weeks.
- The Developer test button waits for the push channel before uploading, so evening lock-screen tests work on the first tap — and Diagnostics no longer shows stale warnings next to a freshly arrived channel.

## Build 13
- If the Lock Screen card ever gets stuck without server updates after an app update, Summit now restarts it by itself (at most once a day) — no reinstall needed.
- New restart button in Developer settings: it revives a stuck card, waits for the push channel, and sends the day plan up right away.
- Diagnostics now says plainly whether this build can't do push at all (then reinstall) or the push channel is just on its way.
- Server-side lesson flips stay dependable all term: the server checks the timetable every few minutes instead of every minute, so updates never run dry (flips may land a few minutes later; the live countdown is unaffected).

## Build 12
- New Push section in Diagnostics: worker status, push token, last upload, and a live log of everything heading to Cloudflare.
- The Developer test button now uploads its boundaries too, so the locked-phone handoff can be verified in the evening.

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
