// Summit Live Activity push worker (Cloudflare Workers, free tier)
// ---------------------------------------------------------------
// Feladata: tanítási napokon, órahatárokon APNs Live Activity update
// pushokat küld — akkor is átkapcsol a kártya, ha az appot az iOS
// egyáltalán nem ébreszti fel (a BGAppRefresh best-effort).
//
// Működés:
//  - Az app POST /plan hívással feltölti a mai nap hátralévő határait:
//    { userId, dayKey, pushToken, sandbox, entries: [{ fireAt, contentState }] }
//    A contentState-t az app számolja (ő az egyetlen igazságforrás),
//    a worker csak időzítve kézbesíti.
//  - Percenkénti cron végigmegy a mára szóló terveken, és ami lejárt
//    (fireAt <= most, még nem küldött), azt POST-olja az Apple APNs-nek.
//
// KV binding neve: PLANS (KV namespace, key: "plan:<dayKey>:<userId>").
// Secrets (dashboard: Settings → Variables → Secrets):
//   APNS_KEY    — a .p8 kulcs TARTALMA (-----BEGIN PRIVATE KEY----- ...)
//   APNS_KEY_ID — a kulcs 10 jegyű azonosítója (Key ID)
//   TEAM_ID     — 10 jegyű csapat-azonosító (Team ID)
// Vars (Text variables):
//   BUNDLE_ID   — pl. hu.flint (topic: <BUNDLE_ID>.push-type.liveactivity)
// Cron trigger: "* * * * *" (percenként).
//
// Megjegyzés: a .p8-at EGYSZER kell elkérni annak, aki Admin a fejlesztői
// csapatban (az app bundle-jának gazdája). Ugyanaz a kulcs jó sandboxra
// és productionre is — a végpontot terv-szinten választjuk (az app
// DEBUG buildje sandbox=true-t küld).

const APNS_PROD = "https://api.push.apple.com";
const APNS_SANDBOX = "https://api.sandbox.push.apple.com";

// Provider JWT cache (max ~50 percig érvényes, az Apple 60-at enged).
let jwtCache = { token: null, at: 0 };

function b64url(bytes) {
  let s = "";
  for (let i = 0; i < bytes.length; i++) s += String.fromCharCode(bytes[i]);
  return btoa(s).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}

async function apnsJwt(env) {
  const now = Math.floor(Date.now() / 1000);
  if (jwtCache.token && now - jwtCache.at < 50 * 60) return jwtCache.token;
  const enc = (o) => b64url(new TextEncoder().encode(JSON.stringify(o)));
  const unsigned = `${enc({ alg: "ES256", kid: env.APNS_KEY_ID })}.${enc({ iss: env.TEAM_ID, iat: now })}`;
  const pem = env.APNS_KEY.replace(/\\n/g, "\n");
  const b64 = pem.replace(/-----.*?-----/gs, "").replace(/\s/g, "");
  const raw = Uint8Array.from(atob(b64), (c) => c.charCodeAt(0));
  const key = await crypto.subtle.importKey("pkcs8", raw.buffer, { name: "ECDSA", namedCurve: "P-256" }, false, ["sign"]);
  const sig = new Uint8Array(await crypto.subtle.sign({ name: "ECDSA", hash: "SHA-256" }, key, new TextEncoder().encode(unsigned)));
  jwtCache = { token: `${unsigned}.${b64url(sig)}`, at: now };
  return jwtCache.token;
}

// Egy update push. Vissza: "sent" (többet nem próbáljuk) vagy "retry".
async function sendUpdate(env, host, pushToken, contentState, staleDate) {
  const jwt = await apnsJwt(env);
  const aps = { timestamp: Math.floor(Date.now() / 1000), event: "update", "content-state": contentState };
  if (staleDate) aps["stale-date"] = staleDate;
  let res;
  try {
    res = await fetch(`${host}/3/device/${pushToken}`, {
      method: "POST",
      headers: {
        authorization: `bearer ${jwt}`,
        "apns-topic": `${env.BUNDLE_ID}.push-type.liveactivity`,
        "apns-push-type": "liveactivity",
        "apns-priority": "10",
        "content-type": "application/json",
      },
      body: JSON.stringify({ aps }),
    });
  } catch (e) {
    console.log(`APNs hálózati hiba: ${e && e.message ? e.message : e}`);
    return "retry";
  }
  if (res.status === 200) return "sent";
  if (res.status === 400 || res.status === 410) {
    // Halott token / rossz kérés — újrapróbálni felesleges.
    const body = await res.text().catch(() => "");
    console.log(`APNs terminal (${res.status}): ${body.slice(0, 200)}`);
    return "sent";
  }
  console.log(`APNs retry (${res.status})`);
  return "retry";
}

async function handleCron(env) {
  const now = Math.floor(Date.now() / 1000);
  const todayUTC = new Date().toISOString().slice(0, 10); // csak takarításhoz
  let cursor = undefined;
  for (;;) {
    const page = await env.PLANS.list({ prefix: "plan:", cursor });
    for (const k of page.keys) {
      const dayKey = k.name.split(":")[1] || "";
      if (dayKey && dayKey < todayUTC) { await env.PLANS.delete(k.name); continue; }
      const rec = await env.PLANS.get(k.name, "json");
      if (!rec || !rec.pushToken || !Array.isArray(rec.entries)) continue;
      const host = rec.sandbox ? APNS_SANDBOX : APNS_PROD;
      let dirty = false;
      for (const e of rec.entries) {
        if (e.sent || typeof e.fireAt !== "number" || e.fireAt > now || !e.contentState) continue;
        const r = await sendUpdate(env, host, rec.pushToken, e.contentState, e.staleDate);
        e.attempts = (e.attempts || 0) + 1;
        if (r === "sent" || e.attempts > 10) { e.sent = true; dirty = true; }
        else dirty = true; // attempts mentése
      }
      if (dirty) await env.PLANS.put(k.name, JSON.stringify(rec));
    }
    if (page.list_complete) break;
    cursor = page.cursor;
  }
}

function isHex64(s) {
  return typeof s === "string" && /^[0-9a-fA-F]{64}$/.test(s);
}

async function handlePlan(request, env) {
  let body;
  try {
    body = await request.json();
  } catch {
    return Response.json({ ok: false, error: "bad-json" }, { status: 400 });
  }
  const dayOk = typeof body.dayKey === "string" && /^\d{4}-\d{2}-\d{2}$/.test(body.dayKey);
  const userOk = typeof body.userId === "string" && body.userId.length > 0 && body.userId.length < 128;
  const entries = Array.isArray(body.entries) ? body.entries.slice(0, 40) : null;
  if (!dayOk || !userOk || !entries) return Response.json({ ok: false, error: "bad-fields" }, { status: 400 });
  if (entries.length > 0 && !isHex64(body.pushToken)) {
    return Response.json({ ok: false, error: "bad-token" }, { status: 400 });
  }
  for (const e of entries) {
    if (typeof e.fireAt !== "number" || typeof e.contentState !== "object" || !e.contentState) {
      return Response.json({ ok: false, error: "bad-entry" }, { status: 400 });
    }
  }
  await env.PLANS.put(`plan:${body.dayKey}:${body.userId}`, JSON.stringify({
    pushToken: body.pushToken || "",
    sandbox: body.sandbox === true,
    entries: entries.map((e) => ({ fireAt: e.fireAt, contentState: e.contentState, staleDate: e.staleDate || null })),
    updatedAt: Math.floor(Date.now() / 1000),
  }));
  return Response.json({ ok: true, entries: entries.length });
}

export default {
  async fetch(request, env) {
    const url = new URL(request.url);
    if (request.method === "POST" && url.pathname === "/plan") return handlePlan(request, env);
    return Response.json({ ok: true, service: "summit-liveactivity-push" });
  },
  async scheduled(_event, env, _ctx) {
    if (!env.APNS_KEY || !env.APNS_KEY_ID || !env.TEAM_ID || !env.BUNDLE_ID) {
      console.log("Hiányzó secret/var: APNS_KEY, APNS_KEY_ID, TEAM_ID, BUNDLE_ID");
      return;
    }
    await handleCron(env);
  },
};
