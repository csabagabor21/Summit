// Summit Live Activity push worker (Cloudflare Workers, free tier)
// ---------------------------------------------------------------
// 2026-09-16 (lásd LiveActivityPush/FIX_PROPOSAL_HU.md) — az előző
// változathoz képest:
//   1. APNs-hibák NEM némák: minden nem-200 válasz törzse a logba kerül, és
//      a tervben entrynként megmarad az utolsó APNs-válasz (`last`).
//   2. 403 (InvalidProviderToken/ExpiredProviderToken) → a JWT-cache-t
//      eldobjuk, a következő kör friss aláírással próbál.
//   3. Az `index` már nem egyetlen igazságforrás: 5 percenként a cron
//      LIST-tel egyezteti (plan:* kulcsok), így egy KV read-modify-write
//      versenyben elvesztett kulcs legfeljebb 5 percet késik, nem tűnik el
//      egész napra. (Free tier: 288 LIST/nap az 1000-es keretből.)
//   4. GET /status?userId=<scoped>&dayKey=YYYY-MM-DD[&tag=preview] →
//      entrynkénti fireAt/sent/attempts/last — a Diagnosztikából vagy
//      curl-lel ellenőrizhető, mi történt a határokkal. (contentState-et
//      nem ad vissza.)
//   5. Utolsó óra vége után `event: "end"` push (dismissal-date = +1 perc),
//      ha az app küld `end: true` entryt — a kártya nem ül 0:00-n a nap
//      végén. (Az app-oldali párja a javaslatban.)
//
// 2026-09-18 — a „minden feltöltés rendben, mégsem vált a kártya” kör után
// (az élő worker APNs 403 InvalidProviderToken-t kapott minden pushra):
//   6. GET /selftest[?sandbox=1] → a kulcs/Key ID/Team ID hármas ellenőrzése
//      telefon és valódi push-token NÉLKÜL, emberi nyelvű verdikttel.
//   7. A Key ID / Team ID / Bundle ID secret trimmelve (`cleanId`): egy
//      odaragadt sortörés ugyanazt a 403-at adta, mint egy rossz kulcs.
//   8. A JWT-aláírás a try-on belül: rossz .p8 esetén eddig a KIVÉTEL ölte
//      meg az egész cron-kört, diagnosztika nélkül (status -1 jelzi).
//   9. 403 és JWT-hiba nem fogyasztja a 10-es próba-budgetet — konfigurációs
//      hibát a dashboardon javítanak, nem kell miatta „kiment”-re váltani.
//
// Működés:
//  - Az app POST /plan hívással feltölti a mai nap hátralévő határait:
//    { userId, dayKey, pushToken, sandbox, entries: [{ fireAt, contentState, staleDate?, end? }] }
//    A contentState-t az app számolja (ő az egyetlen igazságforrás),
//    a worker csak időzítve kézbesíti. FONTOS: a contentState dátumai
//    az Apple default JSON-stratégiával (mp 2001-01-01 óta) érkeznek —
//    a worker NEM nyúl hozzájuk. Az aps-szintű mezők (timestamp,
//    stale-date, dismissal-date) unix mp.
//  - Percenkénti cron végigmegy az esedékes terveken, és ami lejárt
//    (fireAt <= most, még nem küldött), azt POST-olja az Apple APNs-nek.
//
// KV binding neve: PLANS. Secrets: APNS_KEY, APNS_KEY_ID, TEAM_ID.
// Vars: BUNDLE_ID (hu.flint → topic hu.flint.push-type.liveactivity).
// Cron trigger: "* * * * *" (percenként).

const APNS_PROD = "https://api.push.apple.com";
const APNS_SANDBOX = "https://api.sandbox.push.apple.com";

let jwtCache = { token: null, at: 0 };

/// A dashboardból másolt secretek végén gyakran ott marad egy sortörés vagy
/// szóköz. A Key ID / Team ID akkor is „jól néz ki”, de a JWT fejlécébe
/// whitespace-szel kerül → az Apple 403 InvalidProviderToken-t ad, ugyanazt,
/// mint egy teljesen rossz kulcsra. Ezért mindent trimmelünk.
function cleanId(v) {
  return typeof v === "string" ? v.trim() : "";
}

/// A `jsonRes()` charset NÉLKÜLI `application/json`-t ad, amit több
/// kliens (pl. a Safari nyers JSON-nézete) windows-1250-ként dekódol — a
/// magyar /selftest verdikt így „ĂŠ"-foltokban jön. Explicit UTF-8 kell.
function jsonRes(obj, init) {
  return new Response(JSON.stringify(obj), {
    ...(init || {}),
    headers: { "content-type": "application/json; charset=utf-8" },
  });
}

function b64url(bytes) {
  let s = "";
  for (let i = 0; i < bytes.length; i++) s += String.fromCharCode(bytes[i]);
  return btoa(s).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}

function isDerSequence(sig) {
  if (sig.length < 8 || sig[0] !== 0x30) return -1;
  let total = sig[1], hdr = 2;
  if ((total & 0x80) !== 0) {
    const n = total & 0x7f;
    if (n === 0 || n > 2 || sig.length < 2 + n) return -1;
    total = 0; for (let i = 0; i < n; i++) total = (total << 8) | sig[2 + i];
    hdr = 2 + n;
  }
  return hdr + total === sig.length ? hdr : -1;
}

function ecdsaSigToRaw(sig) {
  const hdr = isDerSequence(sig);
  if (hdr < 0) {
    if (sig.length === 64) return sig;
    throw new Error("Ismeretlen ECDSA alairas-formatum");
  }
  let o = hdr;
  const takeInt = () => {
    if (sig[o++] !== 0x02) throw new Error("Hibas DER INTEGER");
    let len = sig[o++];
    if ((len & 0x80) !== 0) { const n = len & 0x7f; len = 0; for (let i = 0; i < n; i++) len = (len << 8) | sig[o++]; }
    let v = sig.slice(o, o + len); o += len;
    while (v.length > 1 && v[0] === 0x00) v = v.slice(1);
    if (v.length > 32) throw new Error("Tul hosszu DER INTEGER");
    const out = new Uint8Array(32); out.set(v, 32 - v.length);
    return out;
  };
  const r = takeInt(), s = takeInt();
  const raw = new Uint8Array(64); raw.set(r, 0); raw.set(s, 32);
  return raw;
}

async function apnsJwt(env) {
  const now = Math.floor(Date.now() / 1000);
  if (jwtCache.token && now - jwtCache.at < 50 * 60) return jwtCache.token;
  const enc = (o) => b64url(new TextEncoder().encode(JSON.stringify(o)));
  const unsigned = `${enc({ alg: "ES256", kid: cleanId(env.APNS_KEY_ID) })}.${enc({ iss: cleanId(env.TEAM_ID), iat: now })}`;
  const pem = env.APNS_KEY.replace(/\\n/g, "\n");
  const b64 = pem.replace(/-----.*?-----/gs, "").replace(/\s/g, "");
  const raw = Uint8Array.from(atob(b64), (c) => c.charCodeAt(0));
  const key = await crypto.subtle.importKey("pkcs8", raw.buffer, { name: "ECDSA", namedCurve: "P-256" }, false, ["sign"]);
  const sig = new Uint8Array(await crypto.subtle.sign({ name: "ECDSA", hash: "SHA-256" }, key, new TextEncoder().encode(unsigned)));
  jwtCache = { token: `${unsigned}.${b64url(ecdsaSigToRaw(sig))}`, at: now };
  return jwtCache.token;
}

/// Egy APNs Live Activity push (update vagy end).
/// Vissza: { r: "sent" | "retry", status, body } — a `last` diagnosztikához.
async function sendPush(env, host, pushToken, entry) {
  // Az aláírás a try-on BELÜL: rossz formátumú APNS_KEY esetén korábban
  // kivétel szállt ki egészen a cronig, így a kör MEGHALT — az entryn nem
  // lett se `attempts`, se `last`, a /status pedig úgy nézett ki, mintha
  // semmi sem történt volna. A kulcshiba pont annyira volt néma, mint amit
  // ez a fájl állítása szerint megszüntetett.
  let jwt;
  try {
    jwt = await apnsJwt(env);
  } catch (e) {
    const msg = e && e.message ? e.message : String(e);
    console.log(`APNs JWT-aláírás hiba (APNS_KEY?): ${msg}`);
    return { r: "retry", status: -1, body: `jwt: ${msg}`.slice(0, 200) };
  }
  const nowS = Math.floor(Date.now() / 1000);
  const aps = { timestamp: nowS, event: entry.end ? "end" : "update", "content-state": entry.contentState };
  if (entry.staleDate && !entry.end) aps["stale-date"] = Math.floor(entry.staleDate);
  if (entry.end) aps["dismissal-date"] = nowS + 60;
  let res;
  try {
    res = await fetch(`${host}/3/device/${pushToken}`, {
      method: "POST",
      headers: {
        authorization: `bearer ${jwt}`,
        "apns-topic": `${cleanId(env.BUNDLE_ID)}.push-type.liveactivity`,
        "apns-push-type": "liveactivity",
        "apns-priority": "10",
        "apns-expiration": String(nowS + 15 * 60),
        "content-type": "application/json",
      },
      body: JSON.stringify({ aps }),
    });
  } catch (e) {
    const msg = e && e.message ? e.message : String(e);
    console.log(`APNs hálózati hiba: ${msg}`);
    return { r: "retry", status: 0, body: msg.slice(0, 200) };
  }
  if (res.status === 200) return { r: "sent", status: 200, body: "" };
  const body = (await res.text().catch(() => "")).slice(0, 200);
  console.log(`APNs ${res.status} (${host === APNS_SANDBOX ? "sandbox" : "prod"}): ${body}`);
  // 403 = provider token gond (InvalidProviderToken / ExpiredProviderToken):
  // a cache-elt JWT-t eldobjuk, a következő próbálkozás frissen ír alá.
  if (res.status === 403) jwtCache = { token: null, at: 0 };
  // 400 BadDeviceToken/DeviceTokenNotForTopic, 410 Unregistered: halott
  // token — ismételni felesleges, az app friss tokennel újratölt.
  if (res.status === 400 || res.status === 410) return { r: "sent", status: res.status, body };
  return { r: "retry", status: res.status, body };
}

const INDEX_KEY = "index";

function normIndex(idx) {
  if (!Array.isArray(idx)) return null;
  const out = [];
  for (const e of idx) {
    if (typeof e === "string") out.push({ k: e, next: 0 });
    else if (e && typeof e.k === "string") {
      out.push({ k: e.k, next: (typeof e.next === "number" || e.next === null) ? e.next : 0 });
    }
  }
  return out;
}

async function readIndex(env) {
  return normIndex(await env.PLANS.get(INDEX_KEY, "json"));
}

async function writeIndex(env, entries) {
  const seen = new Set();
  const out = [];
  for (const e of entries) {
    if (!e || typeof e.k !== "string" || seen.has(e.k)) continue;
    seen.add(e.k);
    out.push({ k: e.k, next: (typeof e.next === "number" || e.next === null) ? e.next : 0 });
  }
  await env.PLANS.put(INDEX_KEY, JSON.stringify(out.slice(0, 500)));
}

function minFireAt(entries) {
  let m = null;
  for (const e of entries || []) {
    if (e && typeof e.fireAt === "number" && !e.sent && (m === null || e.fireAt < m)) m = e.fireAt;
  }
  return m;
}

/// Minden plan:* kulcs a KV-ból (LIST). Csak egyeztetésre, 5 percenként.
async function listPlanKeys(env) {
  const keys = [];
  let cursor = undefined;
  for (;;) {
    const page = await env.PLANS.list({ prefix: "plan:", cursor });
    for (const k of page.keys) keys.push(k.name);
    if (page.list_complete) break;
    cursor = page.cursor;
  }
  return keys;
}

async function handleCron(env, nowMs = Date.now()) {
  const now = Math.floor(nowMs / 1000);
  const todayUTC = new Date(nowMs).toISOString().slice(0, 10);
  const minute = new Date(nowMs).getUTCMinutes();
  let entries = await readIndex(env);
  let indexDirty = false;
  if (!entries) {
    entries = [];
    indexDirty = true;
  }
  // Egyeztetés LIST-tel 5 percenként (és ha az index hiányzott): az
  // indexből kimaradt kulcs (KV read-modify-write verseny handlePlan és
  // cron között) next=0-val bekerül → a következő sorban betöltődik.
  if (minute % 5 === 0 || entries.length === 0) {
    const known = new Set(entries.map((e) => e.k));
    for (const k of await listPlanKeys(env)) {
      if (!known.has(k)) { entries.push({ k, next: 0 }); indexDirty = true; }
    }
  }
  const live = [];
  for (const e of entries) {
    const dayKey = e.k.split(":")[1] || "";
    if (dayKey && dayKey < todayUTC) { await env.PLANS.delete(e.k); indexDirty = true; continue; }
    if (e.next === null || e.next > now) { live.push(e); continue; }
    const rec = await env.PLANS.get(e.k, "json");
    if (!rec || !rec.pushToken || !Array.isArray(rec.entries)) {
      indexDirty = true; continue;
    }
    const host = rec.sandbox ? APNS_SANDBOX : APNS_PROD;
    let dirty = false;
    for (const en of rec.entries) {
      if (en.sent || typeof en.fireAt !== "number" || en.fireAt > now || !en.contentState) continue;
      const out = await sendPush(env, host, rec.pushToken, en);
      en.attempts = (en.attempts || 0) + 1;
      en.last = { at: now, status: out.status, body: out.body };
      // 403 (InvalidProviderToken) és -1 (JWT/kulcs) NEM átmeneti zaj, hanem
      // konfigurációs hiba, amit a dashboardon javítanak. Ha ezek is
      // elfogyasztanák a 10 próbát, a határ 10 perc után „kiment”-re
      // váltana, és a kulcs javítása után sem pótolná magát aznap.
      const configError = out.status === 403 || out.status === -1;
      if (out.r === "sent" || (en.attempts > 10 && !configError)) en.sent = true;
      dirty = true;
    }
    if (dirty) await env.PLANS.put(e.k, JSON.stringify(rec));
    const next = minFireAt(rec.entries);
    if (next !== e.next) { e.next = next; indexDirty = true; }
    live.push(e);
  }
  if (indexDirty || live.length !== entries.length) await writeIndex(env, live);
}

/// A Live Activity push-token hossza NEM fix 64 hex karakter — az a
/// klasszikus 32 bájtos device token. Az Apple opak értéknek tekinti, a
/// hosszára nem szabad építeni, és a gyakorlatban jóval hosszabb. A korábbi
/// {64}-es regex ezért `bad-token`-nel dobta volna vissza a valódi tervet.
/// Hex-only marad (a token az APNs URL path-jába kerül), csak a fix hossz
/// szabadul fel; a felső korlát a védelem miatt van.
function isPushToken(s) {
  return typeof s === "string" && s.length >= 32 && s.length <= 512 &&
    s.length % 2 === 0 && /^[0-9a-fA-F]+$/.test(s);
}

function planKey(dayKey, userId, tag) {
  return tag ? `plan:${dayKey}:${userId}:${tag}` : `plan:${dayKey}:${userId}`;
}

function parseTag(t) {
  return typeof t === "string" && /^[a-z-]{1,16}$/.test(t) ? t : "";
}

async function handlePlan(request, env) {
  let body;
  try {
    body = await request.json();
  } catch {
    return jsonRes({ ok: false, error: "bad-json" }, { status: 400 });
  }
  const dayOk = typeof body.dayKey === "string" && /^\d{4}-\d{2}-\d{2}$/.test(body.dayKey);
  const userOk = typeof body.userId === "string" && body.userId.length > 0 && body.userId.length < 128;
  const entries = Array.isArray(body.entries) ? body.entries.slice(0, 40) : null;
  if (!dayOk || !userOk || !entries) return jsonRes({ ok: false, error: "bad-fields" }, { status: 400 });
  if (entries.length > 0 && !isPushToken(body.pushToken)) {
    return jsonRes({ ok: false, error: "bad-token" }, { status: 400 });
  }
  for (const e of entries) {
    if (typeof e.fireAt !== "number" || typeof e.contentState !== "object" || !e.contentState) {
      return jsonRes({ ok: false, error: "bad-entry" }, { status: 400 });
    }
  }
  const key = planKey(body.dayKey, body.userId, parseTag(body.tag));
  await env.PLANS.put(key, JSON.stringify({
    pushToken: body.pushToken || "",
    sandbox: body.sandbox === true,
    entries: entries.map((e) => ({
      fireAt: e.fireAt, contentState: e.contentState,
      staleDate: typeof e.staleDate === "number" ? e.staleDate : null,
      end: e.end === true,
    })),
    updatedAt: Math.floor(Date.now() / 1000),
  }));
  let next = null;
  for (const e of entries) {
    if (typeof e.fireAt === "number" && (next === null || e.fireAt < next)) next = e.fireAt;
  }
  const prev = (await readIndex(env)) || [];
  if (entries.length === 0) {
    const kept = prev.filter((en) => en.k !== key);
    if (kept.length !== prev.length) await writeIndex(env, kept);
  } else {
    const found = prev.find((en) => en.k === key);
    if (found) {
      if (found.next !== next) { found.next = next; await writeIndex(env, prev); }
    } else {
      prev.push({ k: key, next });
      await writeIndex(env, prev);
    }
  }
  return jsonRes({ ok: true, entries: entries.length });
}

/// GET /status?userId=<scoped userId>&dayKey=YYYY-MM-DD[&tag=preview]
/// Diagnosztika: mi van a tervben, mi ment ki, mit válaszolt az APNs.
async function handleStatus(url, env) {
  const userId = url.searchParams.get("userId") || "";
  const dayKey = url.searchParams.get("dayKey") || "";
  if (!userId || !/^\d{4}-\d{2}-\d{2}$/.test(dayKey)) {
    return jsonRes({ ok: false, error: "bad-fields" }, { status: 400 });
  }
  const key = planKey(dayKey, userId, parseTag(url.searchParams.get("tag")));
  const rec = await env.PLANS.get(key, "json");
  if (!rec) return jsonRes({ ok: true, found: false, key });
  const idx = (await readIndex(env)) || [];
  const inIndex = idx.find((e) => e.k === key) || null;
  return jsonRes({
    ok: true, found: true, key,
    sandbox: rec.sandbox === true,
    tokenSuffix: (rec.pushToken || "").slice(-6),
    updatedAt: rec.updatedAt || null,
    indexNext: inIndex ? inIndex.next : "NOT-IN-INDEX",
    now: Math.floor(Date.now() / 1000),
    entries: (rec.entries || []).map((e) => ({
      fireAt: e.fireAt, end: e.end === true, sent: e.sent === true,
      attempts: e.attempts || 0, last: e.last || null,
    })),
  });
}

/// A /selftest verdiktje emberi nyelven — ne kelljen APNs reason-kódokat
/// fejben tartani.
function selfTestVerdict(out) {
  if (out.status === -1) {
    return "Az APNS_KEY secret tartalma nem értelmezhető PKCS8 EC (P-256) kulcsként — a .p8 fájl TELJES tartalmát kell bemásolni, a BEGIN/END sorokkal együtt.";
  }
  if (out.status === 400 && /BadDeviceToken/.test(out.body)) {
    return "A kulcs-oldal RENDBEN: az Apple elfogadta a JWT-t, és csak a szándékosan hamis device tokent dobta el. Ha a kártya mégsem vált, a hiba az app oldalán van (token/terv-feltöltés) — nézd a /status-t.";
  }
  if (out.status === 403 && /Expired/.test(out.body)) {
    return "ExpiredProviderToken: a JWT `iat`-ja kívül van az Apple által elfogadott 1 órás ablakon (worker-óra vagy cache-gond).";
  }
  if (out.status === 403) {
    return "InvalidProviderToken: az Apple elutasítja a kulcsot. A .p8 privát kulcs formátuma önmagában jó (az aláírás megszületett), tehát a hármas nem áll össze — rossz vagy elgépelt APNS_KEY_ID, rossz TEAM_ID, más csapat kulcsa, visszavont kulcs, vagy a kulcson nincs bekapcsolva az APNs szolgáltatás.";
  }
  if (out.status === 400 && /TopicDisallowed|DeviceTokenNotForTopic|MissingTopic/.test(out.body)) {
    return "A topic nem stimmel: a BUNDLE_ID var vagy a kulcs hatóköre (topic-ra korlátozott kulcs) nem ehhez az apphoz tartozik.";
  }
  return "Váratlan APNs válasz, lásd apns.status / apns.body.";
}

/// GET /selftest[?sandbox=1] — a kulcs-oldal ellenőrzése TELEFON NÉLKÜL.
/// Aláír egy JWT-t és egy csupa-nulla device tokennel bekopogtat az APNs-nél;
/// a hamis token miatt semmi nem megy ki senkinek, de az Apple válaszából
/// kiderül, hogy a kulcs/Key ID/Team ID hármas rendben van-e.
///
/// A visszaadott keyId/teamId/topic NEM titok: a Key ID minden APNs-kérésben
/// kimegy a JWT fejlécében, a Team ID pedig az app aláírásában van — a .p8
/// privát kulcs nélkül önmagában használhatatlan. Viszont pont ezek kellenek
/// ahhoz, hogy egy elgépelés vagy egy odaragadt sortörés egy pillantásból
/// látszódjon, ezért a nyers hosszt is megadjuk (raw != clean = whitespace).
async function handleSelfTest(url, env) {
  const missing = ["APNS_KEY", "APNS_KEY_ID", "TEAM_ID", "BUNDLE_ID"].filter((k) => !env[k]);
  if (missing.length) {
    return jsonRes({ ok: false, missing, verdict: `Hiányzó secret/var: ${missing.join(", ")}` });
  }
  const sandbox = url.searchParams.get("sandbox") === "1";
  const keyId = cleanId(env.APNS_KEY_ID);
  const teamId = cleanId(env.TEAM_ID);
  // Friss aláírás kell: egy korábbi kör cache-elt (esetleg rossz) JWT-je
  // félrevezető eredményt adna.
  jwtCache = { token: null, at: 0 };
  const out = await sendPush(env, sandbox ? APNS_SANDBOX : APNS_PROD, "0".repeat(64), {
    contentState: { selftest: 1 },
  });
  return jsonRes({
    ok: true,
    env: sandbox ? "sandbox" : "prod",
    keyId,
    teamId,
    topic: `${cleanId(env.BUNDLE_ID)}.push-type.liveactivity`,
    // 10-nek kell lennie mindkettőnek; ha raw > clean, whitespace ragadt bele.
    lengths: {
      keyId: keyId.length, keyIdRaw: String(env.APNS_KEY_ID).length,
      teamId: teamId.length, teamIdRaw: String(env.TEAM_ID).length,
    },
    apns: { status: out.status, body: out.body },
    verdict: selfTestVerdict(out),
  });
}

export { ecdsaSigToRaw, handleCron, handlePlan, handleSelfTest, handleStatus };

export default {
  async fetch(request, env) {
    const url = new URL(request.url);
    if (request.method === "POST" && url.pathname === "/plan") return handlePlan(request, env);
    if (request.method === "GET" && url.pathname === "/status") return handleStatus(url, env);
    if (request.method === "GET" && url.pathname === "/selftest") return handleSelfTest(url, env);
    return jsonRes({ ok: true, service: "summit-liveactivity-push", version: "2026-09-18" });
  },
  async scheduled(_event, env, _ctx) {
    if (!env.APNS_KEY || !env.APNS_KEY_ID || !env.TEAM_ID || !env.BUNDLE_ID) {
      console.log("Hiányzó secret/var: APNS_KEY, APNS_KEY_ID, TEAM_ID, BUNDLE_ID");
      return;
    }
    await handleCron(env);
  },
};
