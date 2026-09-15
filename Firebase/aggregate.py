#!/usr/bin/env python3
"""Summit statisztika összesítő — Blaze/KÁRTYA NÉLKÜL futtatható.

Az app iskolaneveket küld (KRÉTA IntezmenyNeve — kódot sosem),
ez a script pedig:
- beolvassa az utolsó 30 nap heartbeatjeit (admin jogosultsággal),
- iskolánként számol, küszöb nélkül (1 fős iskola is kikerül),
- városhoz rendeli a beépített városlexikon alapján, a pint beírja
  a school_pins-be (stabil, kézzel felülírható),
- megírja a nyilvános public/map dokot,
- törli a 365 napnál régebbi rekordokat (TTL-helyettesítő).

Ismeretlen városú iskolákat kilistázza (PIN KELL) —
azokat egy gyors kereséssel be kell tenni a GAZETTEER-be vagy
kézzel a school_pins-be.

Használat:  python3 Firebase/aggregate.py
(Időzítve: launchd / cron, pl. naponta egyszer. Addig kézzel is futtatható.)
"""
import json
import subprocess
import sys
import urllib.request
from datetime import datetime, timedelta, timezone

PROJECT = "summit-14b74"
ACTIVE_DAYS = 30
RETENTION_DAYS = 365
# Nincs küszöb: 1 fős iskola is kikerül a térképre. Ez a fejlesztő
# kifejezett kérése ("minden fő számít"); a térkép csak iskolanevet
# és létszámot mutat, egyént nem beazonosít.
PUBLIC_THRESHOLD = 1
BASE = f"https://firestore.googleapis.com/v1/projects/{PROJECT}/databases/(default)/documents"

# város -> (lon, lat). Az illesztés a névben szereplő "Budapesti", "Debreceni"
# stb. alakokra is működik (ld. aliases()).
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
    # rendhagyó melléknévi alakok:
    "Egri": (20.37, 47.90), "Fővárosi": (19.04, 47.50),
}
EXTRA_ALIASES = {"egri": "Eger", "fővárosi": "Budapest"}

# Institut-kód -> (megjelenő név, (lon, lat)). Ha az app nem tud nevet
# (üres adatlap), a kódot küldi — a feloldás itt történik, kézzel
# bővíthető. Ismeretlen kód "KÓD KELL" sorral jelentkezik a logban.
CODEBOOK = {
    "siszc-mathiasz": (
        "Siófoki SZC Mathiász János Technikum és Gimnázium",
        (18.05, 46.91),  # Siófok
    ),
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


def passes_threshold(ids):
    """Kikerül-e az iskola a nyilvános térképre (1 főtől igen)."""
    return len(ids) >= PUBLIC_THRESHOLD


def resolve_pin(name, pin_by_name, alias):
    """(lon, lat) az iskola nevéhez, hálózat nélkül — None, ha ismeretlen."""
    if name in pin_by_name:
        return pin_by_name[name]
    low = name.lower()
    city = next((c for a, c in alias.items() if a in low), None)
    return GAZETTEER[city] if city else None


def usable_name(name):
    """Küldhető-e térképre a név, vagy kód/demo/üres (az app szűrőjével
    összhangban)."""
    t = (name or "").strip()
    if len(t) < 2:
        return None
    low = t.lower()
    if low in ("demo", "unknown", "demo iskola", "diák"):
        return None
    if " " not in t and t == low and not any(c in t for c in "áéíóöőúüű"):
        return None
    return t


def resolve_school(name, code, pin_by_name, alias):
    """(megjelenő név, lon, lat) név+kód alapján — None, ha feloldhatatlan.
    Sorrend: valódi név (városlexikon) → név/kód a CODEBOOK-ban."""
    u = usable_name(name)
    if u is not None:
        if u in CODEBOOK:
            disp, (lon, lat) = CODEBOOK[u][0], CODEBOOK[u][1]
            return disp, lon, lat
        hit = resolve_pin(u, pin_by_name, alias)
        if hit is None:
            return None
        return u, hit[0], hit[1]
    c = (code or "").strip()
    if c and c in CODEBOOK:
        disp, (lon, lat) = CODEBOOK[c][0], CODEBOOK[c][1]
        return disp, lon, lat
    return None


def main():
    import hashlib
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

    pins = {}
    for d in list_all(tok, "school_pins"):
        f = d.get("fields", {})
        pins[d["name"].rsplit("/", 1)[-1]] = d
    pin_by_name = {}
    for d in pins.values():
        f = d.get("fields", {})
        if isinstance(f.get("name", {}).get("stringValue"), str):
            pin_by_name[f["name"]["stringValue"]] = (
                f.get("lon", {}).get("doubleValue", 0),
                f.get("lat", {}).get("doubleValue", 0))

    alias = aliases()
    schools, need_pin = [], []
    for key in sorted(groups, key=lambda k: -len(groups[k]["ids"])):
        g = groups[key]
        ids = g["ids"]
        if not passes_threshold(ids):
            continue
        res = resolve_school(g["name"], g["code"], pin_by_name, alias)
        if res is None:
            need_pin.append(((g["code"] or g["name"] or "?"), len(ids)))
            continue
        display, lon, lat = res
        if display not in pin_by_name:
            pid = hashlib.sha256(display.encode()).hexdigest()[:32]
            st, _ = req(tok, "PATCH", f"/school_pins/{pid}", {"fields": {
                "name": {"stringValue": display},
                "lon": {"doubleValue": lon}, "lat": {"doubleValue": lat}}})
            assert st == 200, f"pin {display}: HTTP {st}"
        schools.append({"name": display, "lon": lon, "lat": lat, "count": len(ids)})

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
    st, _ = req(tok, "PATCH", "/public/map", body)
    print(f"public/map frissítve ({len(schools)} iskola): HTTP {st}")

    for doc_id in old:
        st, _ = req(tok, "DELETE", f"/heartbeats/{doc_id}")
        assert st == 200, f"delete {doc_id}: HTTP {st}"
    print(f"heartbeat olvasva: {len(beats)}, iskolák: {len(groups)}, lejárt törölve: {len(old)}")
    for name, cnt in need_pin:
        print(f"PIN KELL ({cnt} fő): {name}")


if __name__ == "__main__":
    sys.exit(main())
