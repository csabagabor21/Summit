# Summit statisztika — Firebase állapot (summit-14b74)

## Ami már él (Spark-csomagon, kész)

- Firestore adatbázis: `(default)`, `eur3`, `FIRESTORE_NATIVE` — létrehozva.
- Rules: [`firestore.rules`](firestore.rules)
  (heartbeats: csak létrehozás szigorú sémával, UUID-alakú install_id-vel;
  `public/map`: nyilvános olvasás, a `public` többi doca nem olvasható;
  `sync2`: titkosított beállítás-szinkron; `sync`: legacy, 2. fázisban
  törlendő; minden más: tiltva). Emulátoros tesztek:
  [`rules-tests/`](rules-tests/README.md) — deploy előtt futtatandók.
- Web app (`Summit web`) létrehozva — az API-kulcs publikus, a rules véd.
- `public/map` demo dok feltöltve — a weboldal térképe **ezt most élőben olvassa**.
- Az app közvetlenül ír a Firestore-ba (nincs köztes backend) —
  lásd `AnalyticsStore.deliver(schoolHash:day:)`.

## Kártya nélkül is megy (ajánlott út): GitHub Actions, óránként

Blaze helyett az `aggregate.py` fut **a GitHub szerverein, óránként**
(`.github/workflows/aggregate.yml`, `:07`-kor + kézzel is indítható).
Semmi nem fut a saját gépeden. Hozzáférés: `summit-aggregator`
service account (`roles/datastore.user` — csak Firestore-olvasás/írás),
kulcsa `GCP_SA_KEY` repo-secretként tárolva, sehol máshol nincs meg.
Összesítés + 365 napnál régebbi rekordok törlése (TTL-helyettesítő).

Kézi futtatás helyben (gcloud-belépéssel):

```bash
python3 Firebase/aggregate.py
```

## Megőrzés (TTL) Blaze nélkül

Cloud Functions nincs (Sparkon nem deployolható; a régi `functions/`
mappát az `aggregate.py` váltotta ki, ezért törölve). A 365 napnál régebbi
heartbeat-rekordokat az `aggregate.py` törli óránként. Ha egyszer Blaze-re
vált a projekt, a natív TTL is bekapcsolható — minden rekord eleve
`expiresAt`-tel (createdAt + 365 nap) íródik:

```bash
gcloud firestore fields ttls update expiresAt \
  --collection-group=heartbeats --enable-ttl \
  --project=summit-14b74 --database='(default)'
```

## Közös Gemini-tartalék — már NEM a Firestore-ban

A korábbi `public/ai_fallback` doc (`geminiKey`, `geminiModel`) bárki által
olvasható volt, vagyis a közös Gemini-kulcs gyakorlatilag publikus volt.
Mostantól:

- A kulcs a Cloudflare worker `GEMINI_KEY` secretje (modell: `GEMINI_MODEL`
  var), lásd [`LiveActivityPush/README.md`](../LiveActivityPush/README.md).
- Az app a worker `POST /ai/generate` végpontját hívja, Firebase App
  Check-tokennel (`X-Firebase-AppCheck`); token nélkül a worker 401-et ad.
  A kulcs és a modellnév sosem jut el a klienshez.
- Teendő egyszer: a régi kulcs **visszavonása** a Google AI Studióban, a
  `public/ai_fallback` doc **törlése** a konzolból, új kulcs a workerbe.
  (A rules már akkor sem engedné olvasni, ha a doc megmaradna.)

## Szabálytesztek és deploy

```bash
cd Firebase/rules-tests && npm install && cd ..
firebase emulators:exec --only firestore --project demo-summit "npm --prefix rules-tests test"
```

Az emulátorhoz Java 21 kell. A tesztek a `demo-summit` projekten futnak,
az éles adatbázishoz nem nyúlnak.

## Iskolanevek → térkép (automatikus, rád nem vár semmi)

Az app az iskola KRÉTA-beli nevét küldi (a nyers kód nem hagyja el a telefont),
az `aggregate.py` pedig **magától megkeresi, hol van valójában az iskola**.
A feloldás sorrendje (az első találat nyer):

1. **`school_pins` meglévő pin** — ez a stabil, kézzel felülírható szótár.
   Ha egy név már szerepel benne, azt semmi nem írja felül.
2. **Nominatim (OpenStreetMap) geokódolás a teljes iskolanévre** —
   `https://nominatim.openstreetmap.org/search` (csak stdlib, saját
   `User-Agent`, max 1 kérés/mp, futásonként max 12 iskola). Ha a teljes név
   nem hoz találatot, egyre egyszerűbb kérdések következnek: SZC-előtag
   nélkül, majd csak a tulajdonnévi rész. A találat csak akkor fogadható el,
   ha iskola-jellegű (`amenity=school` stb.) vagy a névbeli kulcsszavak
   egyeznek, **és** Magyarország befoglaló dobozában van
   (lon 16.1–22.9, lat 45.7–48.6).
3. **Városlexikon (GAZETTEER) a névben** — végső mentsvár, csak akkor,
   ha a geokódolás nem hozott semmit.
4. Ha egyik sem sikerül: `PIN KELL (N fő): <név>` sor a logban.

Miért kell mindez: sok iskola a fenntartó szakképzési centrumáról vagy egy
személyről kapja a nevét, nem a saját városáról. A
*Siófoki SZC Mathiász János Technikum és Gimnázium* például
**Balatonbogláron** van (17.658, 46.775) — a névből „kitalált” Siófok
rossz pin lenne.

A geokódolt találat (koordináta + **valódi város**) bekerül a `school_pins`-be,
így óránként nem megyünk újra a Nominatimra: normál esetben **nulla** hálózati
kérés fut. Ez a város fontos a k-anonimitás miatt is: 6 fő alatt csak ez a
városnév jelenik meg a térképen, az iskola neve nem.

### Pin mezői (`school_pins`, csak a service account éri el)

| mező | jelentés |
| --- | --- |
| `name` | az iskola (vagy város) neve, ehhez illeszkedik a feloldás |
| `lon`, `lat` | koordináta |
| `city` | a település neve (a 6 fő alatti, összevont megjelenítéshez) |
| `source` | `manual` / `nominatim` / `gazetteer` — honnan jött a pin |

A régi, `city`/`source` nélküli dokumentumok is működnek. Besorolásuk:
ha a koordináta pontosan egy lexikon-város pontja (a régi aggregate a
névből tippelte, pl. Mathiász → Siófok), az `gazetteer`-nek számít, és a
következő futás geokódolással felülírja; minden más régi pin kézinek
számít, és sosem íródik felül. Ha egy tippelt pint mégis meg akarsz
tartani, írd bele: `source: manual`.

### Kézi felülírás (ha egy pin rossz helyre került)

Firebase Console → Firestore → `school_pins` → keresd meg a dokumentumot a
`name` mező alapján (a dok-azonosító a név SHA-256 lenyomatának eleje) →
írd át a `lon`/`lat`/`city` mezőt, és a `source`-ot állítsd `manual`-ra.
Ettől kezdve a script hozzá sem nyúl. Új pin kézzel: hozz létre egy
dokumentumot tetszőleges azonosítóval, `name` + `lon` + `lat` (+ `city`,
`source: manual`) mezőkkel.
Ha inkább újra geokódoltatnád: **töröld** a dokumentumot, a következő
futás újra megkeresi.

### Ellenőrzés futtatás nélkül

```bash
# egy iskola geokódolása (csak Nominatim, semmit nem ír)
python3 Firebase/aggregate.py --geocode "Siófoki SZC Mathiász János Technikum és Gimnázium"

# teljes összesítés szárazon: mindent kiszámol, de semmit nem ír Firestore-ba
python3 Firebase/aggregate.py --dry-run

# tesztek (hálózat nélkül, mockolt Nominatim-válasszal)
python3 -m unittest discover -s Firebase -p "test_*.py"
```

GDPR k-anonimitás: 6 főtől az iskola a saját nevével kerül ki, 5 fő és alatta
csak a (geokódolt) város neve jelenik meg, összevont létszámmal és a város
koordinátájával — az iskola neve ilyenkor a nyilvános `public/map` dokba sem
kerül be.

## Iskolai naptár admin-adatbázis (`school_calendars`)

Belépéskor az app az institut-kód alapján (kisbetűsen, pl. `siszc-mathiasz`)
megnézi ezt a collectiont, és ha talál bejegyzést, **csak akkor** tölti le
automatikusan az iskola naptár-linkjét, ha az eszközön még nincs kézi
beállítás (nincs esemény és nincs mentett link) — a kézi felülírás mindig
nyer, az admin sosem tapossa el. Ha nincs bejegyzés, marad a kézi bevitel
(link / szöveg / .ics), ami a SummitSync-kel átmegy a többi eszközre is.

Felvitel (kliensből írni tilos — a rules `read: true, write: false`):

1. Firebase Console → Firestore Database → `school_calendars` → Add document.
2. Document ID = a kisbetűs institut-kód (az app a Beállítások → Fiók sorban
   mutatja az `e-KRÉTA • <kód>` értéket — azt kell ide kisbetűsen).
3. Mezők: `calendarUrl` (string — Google-megosztólink vagy ICS-link),
   `name` (string — az iskola megjelenő neve).
4. Minta-bejegyzések: [`school_calendars.seed.json`](school_calendars.seed.json)
   (első: `siszc-mathiasz`).

Rules-deploy a módosított [`firestore.rules`](firestore.rules) után:

```bash
npx -y firebase-tools@latest deploy --only firestore:rules --project summit-14b74
```
