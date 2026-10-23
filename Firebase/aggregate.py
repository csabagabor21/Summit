#!/usr/bin/env python3
"""Summit statisztika összesítő — Blaze/KÁRTYA NÉLKÜL futtatható.

Az app iskolaneveket küld (KRÉTA IntezmenyNeve — kódot sosem),
ez a script pedig:
- beolvassa az utolsó 30 nap heartbeatjeit (admin jogosultsággal),
- iskolánként számol, GDPR k-anonimitással: 6 főtől iskola nevével,
  alatta csak városnévvel összevonva (az iskola neve ilyenkor
  a nyilvános dokba sem kerül be),
- helyet rendel az iskolához: meglévő school_pins pin → Nominatim
  (OpenStreetMap) geokódolás a TELJES iskolanévre → végső esetben
  a beépített városlexikon (városnév az iskola nevében),
- a geokódolt pint (koordináta + valódi város) beírja a school_pins-be,
  hogy óránként ne kelljen újra hálózni; a kézzel felvitt pin szent,
  azt sosem írjuk felül,
- megírja a nyilvános public/map dokot,
- törli a 365 napnál régebbi rekordokat (TTL-helyettesítő).

Miért kell a geokódolás: sok magyar iskola a fenntartó szakképzési
centrumáról vagy egy személyről kapja a nevét, nem a saját városáról.
Pl. a "Siófoki SZC Mathiász János Technikum és Gimnázium" fizikailag
Balatonbogláron van — a névből "kitalált" Siófok rossz pin lenne.

Feloldhatatlan iskolákat kilistázza (PIN KELL) — azokat kézzel kell
betenni a school_pins-be (ld. SETUP_HU.md).

Használat:
  python3 Firebase/aggregate.py                # éles futás (írással)
  python3 Firebase/aggregate.py --dry-run      # semmit nem ír, kiírja a leendő public/map-et
  python3 Firebase/aggregate.py --geocode "<iskolanév>"   # csak geokódolás-próba
"""
import json
import re
import subprocess
import sys
import time
import urllib.parse
import urllib.request
from datetime import datetime, timedelta, timezone

PROJECT = "summit-14b74"
ACTIVE_DAYS = 30
RETENTION_DAYS = 365
# GDPR k-anonimitás: 6 főtől (azaz "5 fő felett") kerül ki az iskola
# a saját nevével; 5 fő és alatta csak a város neve jelenik meg,
# összevont létszámmal. Így kis létszámból nem lehet visszakövetkeztetni
# az iskolára, az iskola neve a nyilvános dokba sem kerül be.
SCHOOL_NAME_THRESHOLD = 6
BASE = f"https://firestore.googleapis.com/v1/projects/{PROJECT}/databases/(default)/documents"

# --- Nominatim (OpenStreetMap) geokódolás ---------------------------------
# Usage policy: max 1 kérés/mp, valódi User-Agent kötelező. Csak stdlib.
NOMINATIM_URL = "https://nominatim.openstreetmap.org/search"
USER_AGENT = "Summit-aggregator/1.0 (hello@gaborcsaba.com)"
NOMINATIM_DELAY = 1.1          # mp két kérés között (policy: 1/mp)
NOMINATIM_TIMEOUT = 20         # mp
MAX_GEOCODE_PER_RUN = 12       # futásonkénti kérés-plafon (az óránkénti cron miatt)
# Magyarország nagyjábóli befoglaló doboza (lon_min, lat_min, lon_max, lat_max).
HU_BBOX = (16.1, 45.7, 22.9, 48.6)
# Ezekre a class/type értékekre hisszük el, hogy tényleg iskolát találtunk.
SCHOOL_TYPES = ("school", "college", "university", "kindergarten", "educational_institution")
# Iskolanévben gyakori, nem megkülönböztető szavak (a kereséshez/pontozáshoz).
NAME_STOPWORDS = {
    "szc", "szakképzési", "centrum", "centruma", "technikum", "technikuma", "és", "es",
    "gimnázium", "gimnáziuma", "iskola", "iskolája", "általános", "szakgimnázium",
    "szakközépiskola", "szakiskola", "középiskola", "kollégium", "kollégiuma",
    "alapfokú", "művészeti", "köznevelési", "intézmény", "intézménye", "tagintézmény",
    "tagintézménye", "nyelvoktató", "nemzetiségi", "kéttannyelvű", "két", "tanítási",
    "nyelvű", "óvoda", "bölcsőde", "egységes", "gyógypedagógiai", "módszertani",
    "szakszolgálat", "iskolaközpont", "líceum", "főiskola", "egyetem", "campus",
    "a", "az", "és/vagy", "sz", "számú",
}

# város -> (lon, lat). Az illesztés a névben szereplő "Budapesti", "Debreceni"
# stb. alakokra is működik (ld. aliases()). Ez már csak VÉGSŐ mentsvár:
# elsődlegesen a school_pins és a geokódolás dönt.
GAZETTEER = {
    "Budapest": (19.04, 47.50), "Debrecen": (21.63, 47.53), "Szeged": (20.15, 46.25),
    "Miskolc": (20.78, 48.10), "Pécs": (18.23, 46.07), "Győr": (17.63, 47.68),
    "Nyíregyháza": (21.72, 47.95), "Kecskemét": (19.69, 46.90), "Székesfehérvár": (18.41, 47.19),
    "Szombathely": (16.62, 47.23), "Szolnok": (20.18, 47.17), "Tatabánya": (18.42, 47.57),
    "Kaposvár": (17.79, 46.36), "Békéscsaba": (21.09, 46.68), "Veszprém": (17.91, 47.09),
    "Zalaegerszeg": (16.84, 46.84), "Eger": (20.37, 47.90), "Nagykanizsa": (16.99, 46.45),
    "Dunaújváros": (18.93, 46.96), "Hódmezővásárhely": (20.52, 46.42), "Dunakeszi": (19.13, 47.63),
    "Cegléd": (19.80, 47.17), "Baja": (18.95, 46.18), "Salgótarján": (19.67, 48.08),
    "Ózd": (20.29, 48.22), "Vác": (19.13, 47.78), "Gödöllő": (19.35, 47.60),
    "Siófok": (18.05, 46.91), "Hajdúböszörmény": (21.51, 47.67), "Kiskunfélegyháza": (19.85, 46.71),
    "Gyula": (21.28, 46.65), "Esztergom": (18.74, 47.79), "Ajka": (17.56, 47.10),
    "Pápa": (17.47, 47.33), "Keszthely": (17.24, 46.77), "Szekszárd": (18.70, 46.35),
    "Jászberény": (19.92, 47.50), "Gyöngyös": (19.93, 47.78), "Hatvan": (19.67, 47.67),
    "Kazincbarcika": (20.62, 48.25), "Dombóvár": (18.13, 46.38), "Mohács": (18.65, 45.94),
    "Paks": (18.86, 46.62), "Balassagyarmat": (19.29, 48.07), "Sátoraljaújhely": (21.66, 48.39),
    "Kisvárda": (22.08, 48.36), "Sopron": (16.59, 47.69), "Mosonmagyaróvár": (17.27, 47.88),
    "Kőszeg": (16.54, 47.39), "Sárvár": (16.94, 47.25), "Balatonfüred": (17.87, 46.96),
    "Tapolca": (17.44, 46.88), "Szigetvár": (17.92, 46.05), "Kalocsa": (18.98, 46.53),
    "Kiskőrös": (19.29, 46.62), "Monor": (19.45, 47.35), "Vecsés": (19.27, 47.41),
    "Veresegyház": (19.29, 47.65), "Szarvas": (20.55, 46.86), "Mezőkövesd": (20.58, 47.81),
    "Tiszaújváros": (21.02, 47.92), "Komló": (18.26, 46.19), "Siklós": (18.30, 45.86),
    "Balatonboglár": (17.65, 46.77),
    # rendhagyó melléknévi alakok:
    "Egri": (20.37, 47.90), "Fővárosi": (19.04, 47.50),
}
EXTRA_ALIASES = {"egri": "Eger", "fővárosi": "Budapest"}

# Institut-kód -> megjelenő név. Ha az app nem tud nevet (üres adatlap),
# a kódot küldi — a NÉV feloldása itt történik, kézzel bővíthető.
# Koordináta itt NINCS: a helyet ugyanaz a lánc adja, mint a többi
# iskolánál (school_pins → geokódolás → városlexikon).
CODEBOOK = {
    "siszc-mathiasz": "Siófoki SZC Mathiász János Technikum és Gimnázium",
}


def aliases():
    out = {}
    for city in GAZETTEER:
        if len(city) <= 5 and city not in ("Pécs", "Eger", "Vác", "Ózd"):
            continue
        out[city.lower()] = city
        out[(city + "i").lower()] = city
    out.update(EXTRA_ALIASES)
    return out


def token():
    """Access token: service-account kulcsfájlból (CI), különben gcloud CLI."""
    import os
    keyfile = os.environ.get("GOOGLE_APPLICATION_CREDENTIALS")
    if keyfile:
        from google.auth.transport.requests import Request
        from google.oauth2 import service_account
        creds = service_account.Credentials.from_service_account_file(
            keyfile, scopes=["https://www.googleapis.com/auth/datastore"])
        creds.refresh(Request())
        return creds.token
    out = subprocess.run(
        ["gcloud", "auth", "print-access-token"],
        capture_output=True, text=True, check=True,
        env={"PATH": "/opt/homebrew/share/google-cloud-sdk/bin:/opt/homebrew/bin:/usr/bin:/bin"},
    )
    return out.stdout.strip()


def req(tok, method, path, body=None):
    r = urllib.request.Request(
        BASE + path, method=method,
        data=json.dumps(body).encode() if body is not None else None,
        headers={"Content-Type": "application/json", "Authorization": f"Bearer {tok}"},
    )
    try:
        with urllib.request.urlopen(r) as x:
            return x.status, json.loads(x.read() or b"{}")
    except Exception as e:  # HTTPError
        return getattr(e, "code", "?"), ""


def list_all(tok, collection):
    docs, page = [], None
    while True:
        q = f"/{collection}?pageSize=300" + (f"&pageToken={page}" if page else "")
        st, data = req(tok, "GET", q)
        assert st == 200, f"list {collection}: HTTP {st}"
        docs += data.get("documents", [])
        page = data.get("nextPageToken")
        if not page:
            return docs


def parse_ts(s):
    try:
        return datetime.fromisoformat(s.replace("Z", "+00:00"))
    except ValueError:
        return None


def shows_school_name(count):
    """Saját nevével kerül-e ki az iskola (6 főtől igen, alatta csak
    a város neve, összevonva)."""
    return count >= SCHOOL_NAME_THRESHOLD


# --- pin-szerkezet ---------------------------------------------------------
# Egy "pin" dict: {"lon": float, "lat": float, "city": str|None,
#                  "source": "manual"|"nominatim"|"gazetteer"}


def make_pin(lon, lat, city, source):
    return {"lon": float(lon), "lat": float(lat), "city": city or None, "source": source}


def num(v):
    """Firestore szám-mező -> float (doubleValue vagy integerValue)."""
    if not isinstance(v, dict):
        return None
    for k in ("doubleValue", "integerValue"):
        if k in v:
            try:
                return float(v[k])
            except (TypeError, ValueError):
                return None
    return None


def legacy_source(lon, lat):
    """Régi (source nélküli) pin besorolása. A korábbi aggregate a névből
    tippelt várost automatikusan beírta a school_pins-be — az ilyen pin
    koordinátája PONTOSAN egy lexikon-város pontja. Ez nem kézi döntés,
    hanem a rossz heurisztika lenyomata (pl. Mathiász → Siófok, valójában
    Balatonboglár), ezért "gazetteer"-nek vesszük, hogy a geokódolás
    felülírhassa. Minden más régi pin kézi marad."""
    for city, (glon, glat) in GAZETTEER.items():
        if abs(lon - glon) < 1e-6 and abs(lat - glat) < 1e-6:
            return "gazetteer", city
    return "manual", None


def read_pins(docs):
    """school_pins dokumentumok -> {név: pin}. Régi dok (nincs source):
    lexikon-koordinátán → "gazetteer" (újra-geokódolható), különben kézi."""
    out = {}
    for d in docs:
        f = d.get("fields", {})
        name = f.get("name", {}).get("stringValue")
        lon, lat = num(f.get("lon")), num(f.get("lat"))
        if not isinstance(name, str) or lon is None or lat is None:
            continue
        source = f.get("source", {}).get("stringValue") or None
        city = f.get("city", {}).get("stringValue") or None
        if not source:
            source, legacy_city = legacy_source(lon, lat)
            city = city or legacy_city
        out[name] = make_pin(lon, lat, city, source)
    return out


def pin_body(name, pin):
    """school_pins dok törzse (a régi {name, lon, lat} sémával felfelé
    kompatibilis, csak bővül city/source mezővel)."""
    fields = {
        "name": {"stringValue": name},
        "lon": {"doubleValue": pin["lon"]},
        "lat": {"doubleValue": pin["lat"]},
        "source": {"stringValue": pin.get("source") or "manual"},
    }
    if pin.get("city"):
        fields["city"] = {"stringValue": pin["city"]}
    return {"fields": fields}


# --- geokódolás ------------------------------------------------------------

_last_call = 0.0


def in_hungary(lon, lat):
    """Józansági szűrő: a találat Magyarország befoglaló dobozában van-e."""
    lo_min, la_min, lo_max, la_max = HU_BBOX
    return lo_min <= lon <= lo_max and la_min <= lat <= la_max


def key_words(name):
    """Az iskolanév megkülönböztető szavai (eredeti kis/nagybetűvel):
    típusszavak (SZC, technikum, gimnázium...) és városnevek nélkül.
    "Siófoki SZC Mathiász János Technikum és Gimnázium" -> ["Mathiász", "János"]."""
    city_words = set(aliases())
    out = []
    for raw in re.split(r"[\s,\-–—/()\.]+", name or ""):
        w = raw.strip("'\"")
        low = w.lower()
        if len(w) < 2 or low in NAME_STOPWORDS or low in city_words:
            continue
        if not re.search(r"[A-Za-zÁÉÍÓÖŐÚÜŰáéíóöőúüű]", w):
            continue
        out.append(w)
    return out


def geocode_queries(name):
    """Egyre egyszerűbb keresőkifejezések: teljes név → SZC-előtag nélkül →
    csak a megkülönböztető (tulajdonnévi) rész."""
    qs = [(name or "").strip()]
    m = re.search(r"(?:\bSZC\b|Szakképzési\s+Centrum(?:a)?)\s+(.+)", name or "", re.IGNORECASE)
    if m:
        qs.append(m.group(1).strip())
    core = key_words(name)
    if core:
        qs.append(" ".join(core))
    seen, out = set(), []
    for q in qs:
        if len(q) >= 4 and q.lower() not in seen:
            seen.add(q.lower())
            out.append(q)
    return out


def nominatim_fetch(query):
    """Nyers Nominatim-találatok (lista). Hálózat, max 1 kérés/mp."""
    global _last_call
    wait = NOMINATIM_DELAY - (time.monotonic() - _last_call)
    if wait > 0:
        time.sleep(wait)
    url = NOMINATIM_URL + "?" + urllib.parse.urlencode({
        "q": query, "format": "jsonv2", "countrycodes": "hu",
        "limit": 3, "addressdetails": 1})
    r = urllib.request.Request(url, headers={
        "User-Agent": USER_AGENT, "Accept": "application/json",
        "Accept-Language": "hu"})
    try:
        with urllib.request.urlopen(r, timeout=NOMINATIM_TIMEOUT) as x:
            data = json.loads(x.read() or b"[]")
            return data if isinstance(data, list) else []
    except Exception:
        return []
    finally:
        _last_call = time.monotonic()


def score_hit(hit, words):
    """Mennyire hihető, hogy ez a találat a keresett iskola.
    Iskola-jellegű objektum sokat ér, a névbeli kulcsszavak is."""
    cls = (hit.get("class") or hit.get("category") or "").lower()
    typ = (hit.get("type") or "").lower()
    score = 0
    if cls == "amenity" and typ in SCHOOL_TYPES:
        score += 10
    elif typ in SCHOOL_TYPES or cls in SCHOOL_TYPES:
        score += 6
    disp = (hit.get("display_name") or "").lower()
    score += 2 * sum(1 for w in words if w in disp)
    return score


def hit_city(hit):
    """Település a találat address-blokkjából. A "... járás"/"... vármegye"
    alakok nem városnevek, azokat kihagyjuk."""
    addr = hit.get("address") or {}
    for k in ("city", "town", "village", "suburb", "municipality", "county"):
        v = addr.get(k)
        if v and not re.search(r"\b(járás|vármegye|megye)$", v.strip()):
            return v.strip()
    return None


def pick_pin(hits, name, min_score=4):
    """A legjobb találatból pin — None, ha nincs elég hihető, magyarországi."""
    words = [w.lower() for w in key_words(name)]
    best, best_score = None, 0
    for hit in hits or []:
        try:
            lon, lat = float(hit.get("lon")), float(hit.get("lat"))
        except (TypeError, ValueError):
            continue
        if not in_hungary(lon, lat):
            continue
        score = score_hit(hit, words)
        if score > best_score:
            best, best_score = (hit, lon, lat), score
    if best is None or best_score < min_score:
        return None
    hit, lon, lat = best
    return make_pin(lon, lat, hit_city(hit), "nominatim")


def geocode_school(name, fetch=nominatim_fetch):
    """Iskolanév -> pin a Nominatim alapján (None, ha nincs hihető találat)."""
    for q in geocode_queries(name):
        pin = pick_pin(fetch(q), name)
        if pin is not None:
            return pin
    return None


def make_geocoder(limit=MAX_GEOCODE_PER_RUN, fetch=nominatim_fetch, log=print):
    """Geokódoló futásonkénti kéréskorláttal (óránként fut, a Nominatim
    policy miatt keveset hálózunk; a találatok school_pins-be kerülnek)."""
    left = [limit]

    def geocode(name):
        if left[0] <= 0:
            return None
        left[0] -= 1
        pin = geocode_school(name, fetch=fetch)
        if pin:
            log(f"geokódolva: {name} → {pin.get('city') or '?'} "
                f"({pin['lon']:.4f}, {pin['lat']:.4f})")
        else:
            log(f"geokódolás sikertelen: {name}")
        return pin

    return geocode


# --- feloldás --------------------------------------------------------------


def resolve_pin(name, pin_by_name, alias, geocode=None):
    """Pin a névhez. Sorrend: meglévő school_pins (kézi felülírás is itt
    nyer) → Nominatim geokódolás → városlexikon a névben (végső mentsvár)."""
    if name in pin_by_name:
        cur = pin_by_name[name]
        # Lexikonos (névből tippelt) pin nem végleges: ha van geokódoló,
        # megpróbáljuk a valódi helyet. Kézi és nominatim pint sosem bántunk.
        if cur.get("source") == "gazetteer" and geocode is not None:
            hit = geocode(name)
            if hit is not None:
                return hit
        return cur
    if geocode is not None:
        hit = geocode(name)
        if hit is not None:
            return hit
    low = (name or "").lower()
    city = next((c for a, c in alias.items() if a in low), None)
    if city is None:
        return None
    lon, lat = GAZETTEER[city]
    return make_pin(lon, lat, city, "gazetteer")


MAX_NAME_LEN = 120
UNSAFE_NAME_CHARS = set('<>"\'`{}\\')
UNSAFE_NAME_PARTS = ("://", "www.", "http")


def is_safe_name(t):
    """Kliens-oldalról jött iskolanév kerülhet-e a nyilvános térképre és a
    Nominatim-lekérdezésbe. A `school_name` bárki által írható (heartbeat),
    ezért a jelölő-, idéző- és vezérlőkarakteres, link-szerű vagy túl hosszú
    nevet eldobjuk: így a weboldalon nem lehet belőle HTML/JS-befecskendezés
    vagy reklámlink, és a geokódolót sem etetjük szeméttel."""
    if len(t) > MAX_NAME_LEN:
        return False
    if any(c in UNSAFE_NAME_CHARS or ord(c) < 32 or ord(c) == 127
           or 0x80 <= ord(c) < 0xA0 for c in t):
        return False
    low = t.lower()
    return not any(p in low for p in UNSAFE_NAME_PARTS)


def usable_name(name):
    """Küldhető-e térképre a név, vagy kód/demo/üres/veszélyes (az app
    szűrőjével összhangban, plusz `is_safe_name`)."""
    t = (name or "").strip()
    if len(t) < 2:
        return None
    if not is_safe_name(t):
        return None
    low = t.lower()
    if low in ("demo", "unknown", "demo iskola", "diák"):
        return None
    if " " not in t and t == low and not any(c in t for c in "áéíóöőúüű"):
        return None
    return t


def resolve_display(name, code):
    """Megjelenő iskolanév név/kód alapján — None, ha nincs használható."""
    u = usable_name(name)
    if u is not None:
        return CODEBOOK.get(u, u)
    c = (code or "").strip()
    return CODEBOOK.get(c)


def resolve_school(name, code, pin_by_name, alias, geocode=None):
    """(megjelenő név, pin) név+kód alapján — None, ha feloldhatatlan.
    A helyet kódos és nevesített esetben is ugyanaz a lánc adja."""
    display = resolve_display(name, code)
    if display is None:
        return None
    pin = resolve_pin(display, pin_by_name, alias, geocode)
    if pin is None:
        return None
    return display, pin


def resolve_city(name, pin, alias):
    """A csoporthoz tartozó város (6 fő alatt EZ látszik a térképen) —
    elsősorban a feloldott pin városa (geokódolt, valódi hely), csak
    utána a névben szereplő városnév."""
    if pin and pin.get("city"):
        return pin["city"]
    u = usable_name(name)
    if u is None:
        return None
    low = u.lower()
    return next((city for a, city in alias.items() if a in low), None)


def build_public_entries(items, city_pos=None):
    """K-anonimizált nyilvános lista feloldott csoportokból.

    items: [{"display", "city" (vagy None), "lon", "lat", "count"}].
    city_pos: város -> (lon, lat) a GAZETTEER-en túli (geokódolt) városokhoz.
    A 6+ fős iskola saját névvel + saját pinnel; az 5 fő alattiak
    városonként összevonva, a város nevével + város-koordinátával.
    Város (vagy város-koordináta) nélküli kis csoport nem kerül ki."""
    pos = dict(GAZETTEER)
    pos.update(city_pos or {})
    named, buckets = [], {}
    for it in items:
        if shows_school_name(it["count"]):
            named.append({"name": it["display"], "lon": it["lon"],
                          "lat": it["lat"], "count": it["count"]})
        elif it["city"] and it["city"] in pos:
            buckets[it["city"]] = buckets.get(it["city"], 0) + it["count"]
    out = list(named)
    for city in sorted(buckets, key=lambda c: -buckets[c]):
        lon, lat = pos[city]
        out.append({"name": city, "lon": lon, "lat": lat,
                    "count": buckets[city]})
    return out


def main():
    import hashlib
    argv = sys.argv[1:]
    if "--geocode" in argv:  # egyszeri próba: python3 aggregate.py --geocode "<név>"
        i = argv.index("--geocode")
        q = argv[i + 1] if len(argv) > i + 1 else ""
        print(json.dumps({"name": q, "pin": geocode_school(q),
                          "queries": geocode_queries(q)},
                         ensure_ascii=False, indent=2))
        return 0
    dry = "--dry-run" in argv

    tok = token()
    now = datetime.now(timezone.utc)
    since = now - timedelta(days=ACTIVE_DAYS)
    cutoff = now - timedelta(days=RETENTION_DAYS)

    beats = list_all(tok, "heartbeats")
    groups, old = {}, []
    for d in beats:
        f = d.get("fields", {})
        name = (f.get("school_name", {}).get("stringValue") or "").strip()
        code = (f.get("institute_code", {}).get("stringValue") or "").strip()
        inst = f.get("install_id", {}).get("stringValue")
        created = parse_ts(f.get("createdAt", {}).get("timestampValue", ""))
        if created and created < cutoff:
            old.append(d["name"].rsplit("/", 1)[-1])
        if inst and created and created >= since and (name or code):
            key = ("n", name) if usable_name(name) else ("c", code or name)
            g = groups.setdefault(key, {"name": name, "code": code, "ids": set()})
            g["ids"].add(inst)
            if name:
                g["name"] = name
            if code:
                g["code"] = code

    pin_by_name = read_pins(list_all(tok, "school_pins"))
    alias = aliases()
    geocode = make_geocoder()
    new_pins = {}  # név -> pin (amit ebben a futásban oldottunk fel)

    def remember(name, pin):
        """Frissen feloldott pin gyorsítótárazása a school_pins-be, hogy a
        következő futás már ne hálózzon. Kézi/nominatim pint SOSEM írunk
        felül; a lexikonos (tippelt) pint csak jobbra (geokódoltra) cseréljük."""
        old = pin_by_name.get(name)
        if name in new_pins or (old is not None and (old is pin or old.get("source") != "gazetteer")):
            return
        new_pins[name] = pin
        pin_by_name[name] = pin
        if dry:
            print(f"[dry-run] pin lenne: {name} → {pin}")
            return
        pid = hashlib.sha256(name.encode()).hexdigest()[:32]
        st, _ = req(tok, "PATCH", f"/school_pins/{pid}", pin_body(name, pin))
        assert st == 200, f"pin {name}: HTTP {st}"

    items, need_pin = [], []
    for key in sorted(groups, key=lambda k: -len(groups[k]["ids"])):
        g = groups[key]
        n = len(g["ids"])
        res = resolve_school(g["name"], g["code"], pin_by_name, alias, geocode)
        if res is None:
            need_pin.append(((g["code"] or g["name"] or "?"), n))
            continue
        display, pin = res
        remember(display, pin)
        city = resolve_city(g["name"], pin, alias)
        if not shows_school_name(n) and city is None:
            need_pin.append(((g["code"] or g["name"] or "?"), n))
            continue
        items.append({"display": display, "city": city,
                      "lon": pin["lon"], "lat": pin["lat"], "count": n})

    # A 6 fő alatti csoportok a VÁROS koordinátájával kerülnek ki (nem az
    # iskoláéval) — a lexikonon kívüli városokat is feloldjuk + pineljük.
    city_pos = {}
    for it in items:
        c = it["city"]
        if shows_school_name(it["count"]) or not c or c in GAZETTEER or c in city_pos:
            continue
        cp = resolve_pin(c, pin_by_name, alias, geocode)
        if cp is None:
            need_pin.append((f"város: {c}", it["count"]))
            continue
        remember(c, cp)
        city_pos[c] = (cp["lon"], cp["lat"])

    n_named = sum(1 for i in items if shows_school_name(i["count"]))
    schools = build_public_entries(items, city_pos)

    # Mindig írunk — 0 iskola esetén is: az oldal 0-t mutat, nem demót.
    body = {"fields": {
        "demo": {"booleanValue": False},
        "updated": {"timestampValue": now.replace(microsecond=0).isoformat().replace("+00:00", "Z")},
        "schools": {"arrayValue": {"values": [
            {"mapValue": {"fields": {
                "name": {"stringValue": s["name"]},
                "lon": {"doubleValue": s["lon"]},
                "lat": {"doubleValue": s["lat"]},
                "count": {"integerValue": str(s["count"])}}}}
            for s in schools]}}}}
    if dry:
        print("[dry-run] public/map lenne:")
        print(json.dumps(schools, ensure_ascii=False, indent=2))
        st = "-"
    else:
        st, _ = req(tok, "PATCH", "/public/map", body)
    print(f"public/map frissítve ({len(schools)} pont: "
          f"{n_named} iskola + {len(schools) - n_named} város): HTTP {st}")

    if dry:
        print(f"[dry-run] lejárt rekord törlés nélkül: {len(old)}")
    else:
        for doc_id in old:
            st, _ = req(tok, "DELETE", f"/heartbeats/{doc_id}")
            assert st == 200, f"delete {doc_id}: HTTP {st}"
    print(f"heartbeat olvasva: {len(beats)}, iskolák: {len(groups)}, "
          f"lejárt törölve: {0 if dry else len(old)}, új pin: {len(new_pins)}")
    for name, cnt in need_pin:
        print(f"PIN KELL ({cnt} fő): {name}")


if __name__ == "__main__":
    sys.exit(main())
