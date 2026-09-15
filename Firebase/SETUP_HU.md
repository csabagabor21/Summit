# Summit statisztika — Firebase állapot (summit-14b74)

## Ami már él (Spark-csomagon, kész)

- Firestore adatbázis: `(default)`, `eur3`, `FIRESTORE_NATIVE` — létrehozva.
- Rules deployolva: [`firestore.rules`](firestore.rules)
  (heartbeats: csak létrehozás szigorú sémával; public/*: nyilvános olvasás;
  minden más: tiltva). Élőben tesztelve: jó írás 200, rossz 403, lista 403.
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

## Amihez Blaze kell (opcionális: számlázás bekapcsolása a konzolban)

Blaze nélkül a Cloud Functions / Scheduler / TTL API tiltott
(`billingEnabled: false`). A használatunk bőven az ingyenes keretben van
(napi pár száz írás + 1 összesítés), de a kártyát egyszer hozzá kell adni:
Firebase Console → summit-14b74 → Upgrade (vagy Cloud Console → Billing).

Ha megvan, innen folytatjuk:

```bash
cd Firebase
npm --prefix functions install
firebase deploy --only functions --project summit-14b74   # submitHeartbeat + aggregateMap
```

majd TTL:

```bash
gcloud firestore fields ttls update expiresAt \
  --collection-group=heartbeats --enable-ttl \
  --project=summit-14b74 --database='(default)'
```

Addig: minden rekord `expiresAt`-tel (createdAt + 365 nap) íródik, tehát a
TTL-policy utólag is érvényesül a meglévő rekordokra. Az `aggregateMap`
első lefutása után a `public/map` `demo: false`-ra vált, és a térkép
felirata magától átáll élőre.

## Iskolanevek → térkép (automatikus, rád nem vár semmi)

Az app az iskola KRÉTA-beli nevét küldi (a nyers kód nem hagyja el a telefont),
az `aggregate.py` pedig a beépített városlexikon alapján magától teszi ki
a pineket a `school_pins`-be. Új, ismeretlen városú iskola esetén kiírja:
`PIN KELL (N fő): <név>` — azt egy gyors kereséssel pótoljuk a lexikonban.
Kézzel feltöltendő szótár nincs; GDPR k-anonimitás van: 6 főtől
az iskola a saját nevével kerül ki, 5 fő és alatta csak a város neve
jelenik meg, összevont létszámmal (az iskola neve ilyenkor a nyilvános
`public/map` dokba sem kerül be).
