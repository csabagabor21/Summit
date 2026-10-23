// Futtatás: node --test LiveActivityPush/
// Függőség nélkül (Node beépített WebCrypto + fetch-típusok). Az élő
// workert és a Google-t SOHA nem hívja: a fetch és a JWKS mockolt.

import { test, beforeEach, afterEach } from "node:test";
import assert from "node:assert/strict";
import worker, { verifyAppCheck, setJwksFetcher, resetAppCheckCache } from "./worker.js";

const PN = "738331591118";
const APP_ID = "1:738331591118:ios:0ebfbe4dcd35f7b922eb9f";
const BASE = "https://worker.test";

const enc = new TextEncoder();
const b64url = (bytes) => Buffer.from(bytes).toString("base64url");
const b64urlJson = (o) => b64url(enc.encode(JSON.stringify(o)));

async function makeKey(kid) {
  const pair = await crypto.subtle.generateKey(
    { name: "RSASSA-PKCS1-v1_5", modulusLength: 2048, publicExponent: new Uint8Array([1, 0, 1]), hash: "SHA-256" },
    true, ["sign", "verify"],
  );
  const jwk = await crypto.subtle.exportKey("jwk", pair.publicKey);
  return { kid, privateKey: pair.privateKey, jwk: { kty: "RSA", n: jwk.n, e: jwk.e, alg: "RS256", use: "sig", kid } };
}

const keyA = await makeKey("kid-a");
const keyB = await makeKey("kid-b"); // NINCS a JWKS-ben

async function mint(key, { header = {}, claims = {} } = {}) {
  const now = Math.floor(Date.now() / 1000);
  const h = { alg: "RS256", typ: "JWT", kid: key.kid, ...header };
  const p = {
    iss: `https://firebaseappcheck.googleapis.com/${PN}`,
    aud: [`projects/${PN}`, "projects/summit-14b74"],
    sub: APP_ID, iat: now - 5, exp: now + 3600, ...claims,
  };
  const unsigned = `${b64urlJson(h)}.${b64urlJson(p)}`;
  const sig = await crypto.subtle.sign({ name: "RSASSA-PKCS1-v1_5" }, key.privateKey, enc.encode(unsigned));
  return `${unsigned}.${b64url(new Uint8Array(sig))}`;
}

let jwksCalls = 0;
function installJwks(keys = [keyA.jwk]) {
  jwksCalls = 0;
  setJwksFetcher(async () => {
    jwksCalls++;
    return new Response(JSON.stringify({ keys }), { status: 200 });
  });
}

function kv() {
  const m = new Map();
  return {
    m,
    async get(k, type) { const v = m.get(k); if (v === undefined) return null; return type === "json" ? JSON.parse(v) : v; },
    async put(k, v) { m.set(k, v); },
    async delete(k) { m.delete(k); },
    async list({ prefix = "" } = {}) { return { keys: [...m.keys()].filter((k) => k.startsWith(prefix)).map((name) => ({ name })), list_complete: true }; },
  };
}

const logs = [];
const realLog = console.log;
const realFetch = globalThis.fetch;
let fetchCalls = [];

beforeEach(() => {
  resetAppCheckCache();
  installJwks();
  logs.length = 0;
  console.log = (...a) => logs.push(a.join(" "));
  fetchCalls = [];
  globalThis.fetch = async () => { throw new Error("váratlan hálózati hívás"); };
});
afterEach(() => {
  console.log = realLog;
  globalThis.fetch = realFetch;
  setJwksFetcher(null);
});

const req = (path, { method = "GET", headers = {}, body } = {}) =>
  new Request(BASE + path, { method, headers, body, ...(body ? { duplex: "half" } : {}) });
const withToken = (t, extra = {}) => ({ "X-Firebase-AppCheck": t, ...extra });
const env0 = (extra = {}) => ({ FIREBASE_PROJECT_NUMBER: PN, PLANS: kv(), ...extra });

// ---------------- verifyAppCheck ----------------

test("érvényes token → ok, appId", async () => {
  const v = await verifyAppCheck(req("/", { headers: withToken(await mint(keyA)) }), env0());
  assert.equal(v.status, "ok");
  assert.equal(v.appId, APP_ID);
});

test("hiányzó fejléc → missing", async () => {
  assert.equal((await verifyAppCheck(req("/"), env0())).status, "missing");
});

test("projektszám nélkül → unconfigured", async () => {
  const v = await verifyAppCheck(req("/", { headers: withToken(await mint(keyA)) }), { PLANS: kv() });
  assert.equal(v.status, "unconfigured");
});

const invalidCases = [
  ["lejárt", { claims: { exp: Math.floor(Date.now() / 1000) - 1 } }, "expired"],
  ["rossz iss", { claims: { iss: "https://firebaseappcheck.googleapis.com/111" } }, "iss"],
  ["rossz aud", { claims: { aud: ["projects/111"] } }, "aud"],
  ["aud string (nem tömb)", { claims: { aud: `projects/${PN}` } }, "aud"],
  ["jövőbeli iat", { claims: { iat: Math.floor(Date.now() / 1000) + 600 } }, "iat"],
  ["alg none", { header: { alg: "none" } }, "alg"],
  ["HS256", { header: { alg: "HS256" } }, "alg"],
  ["typ hiányzik", { header: { typ: undefined } }, "typ"],
];
for (const [name, opts, reason] of invalidCases) {
  test(`érvénytelen: ${name} → ${reason}`, async () => {
    const v = await verifyAppCheck(req("/", { headers: withToken(await mint(keyA, opts)) }), env0());
    assert.deepEqual([v.status, v.reason], ["invalid", reason]);
  });
}

test("ismeretlen kid → unknown-kid, és fojtott újrakérés", async () => {
  const t = await mint(keyB);
  const v1 = await verifyAppCheck(req("/", { headers: withToken(t) }), env0());
  assert.deepEqual([v1.status, v1.reason], ["invalid", "unknown-kid"]);
  assert.equal(jwksCalls, 1, "az első lekérés után az újrakérés még fojtott");
  await verifyAppCheck(req("/", { headers: withToken(t) }), env0());
  assert.equal(jwksCalls, 1, "hamis kid-ekkel nem lehet JWKS-lekérést generálni");
});

test("kulcsrotáció: új kid a JWKS-ben az 5 perces fojtás után", async () => {
  // Első kérés a régi listával tölti a cache-t.
  await verifyAppCheck(req("/", { headers: withToken(await mint(keyA)) }), env0());
  installJwks([keyA.jwk, keyB.jwk]);
  const realNow = Date.now;
  try {
    Date.now = () => realNow() + 6 * 60 * 1000;
    const v = await verifyAppCheck(req("/", { headers: withToken(await mint(keyB)) }), env0());
    assert.equal(v.status, "ok");
  } finally {
    Date.now = realNow;
  }
});

test("rossz aláírás (másik kulcs ugyanazzal a kid-del) → signature", async () => {
  const forged = await mint({ ...keyB, kid: "kid-a" });
  const v = await verifyAppCheck(req("/", { headers: withToken(forged) }), env0());
  assert.deepEqual([v.status, v.reason], ["invalid", "signature"]);
});

test("módosított payload → signature", async () => {
  const [h, , s] = (await mint(keyA)).split(".");
  const p = b64urlJson({ iss: `https://firebaseappcheck.googleapis.com/${PN}`, aud: [`projects/${PN}`], sub: "x", iat: 1, exp: 9e9 });
  const v = await verifyAppCheck(req("/", { headers: withToken(`${h}.${p}.${s}`) }), env0());
  assert.deepEqual([v.status, v.reason], ["invalid", "signature"]);
});

test("szemét token → decode/format", async () => {
  assert.equal((await verifyAppCheck(req("/", { headers: withToken("abc") }), env0())).reason, "format");
  assert.equal((await verifyAppCheck(req("/", { headers: withToken("a.b!.c") }), env0())).reason, "decode");
});

test("app-ID allowlist", async () => {
  const t = await mint(keyA);
  assert.equal((await verifyAppCheck(req("/", { headers: withToken(t) }), env0({ FIREBASE_APP_IDS: `x, ${APP_ID}` }))).status, "ok");
  const v = await verifyAppCheck(req("/", { headers: withToken(t) }), env0({ FIREBASE_APP_IDS: "1:1:ios:other" }));
  assert.deepEqual([v.status, v.reason], ["invalid", "app-id"]);
});

test("JWKS nem érhető el → invalid jwks-unavailable", async () => {
  setJwksFetcher(async () => new Response("no", { status: 500 }));
  const v = await verifyAppCheck(req("/", { headers: withToken(await mint(keyA)) }), env0());
  assert.deepEqual([v.status, v.reason], ["invalid", "jwks-unavailable"]);
});

// ---------------- /plan, /status ----------------

const planBody = JSON.stringify({ userId: "u.12345678", dayKey: "2026-10-23", entries: [] });
const planReq = (headers = {}) =>
  req("/plan", { method: "POST", headers: { "content-type": "application/json", ...headers }, body: planBody });

test("/plan monitor módban token nélkül is átmegy, és naplóz", async () => {
  const res = await worker.fetch(planReq(), env0());
  assert.equal(res.status, 200);
  assert.equal((await res.json()).ok, true);
  assert.ok(logs.includes("appcheck=missing path=/plan"), logs.join("\n"));
});

test("/plan enforce módban token nélkül 401", async () => {
  const res = await worker.fetch(planReq(), env0({ APPCHECK_ENFORCE: "1" }));
  assert.equal(res.status, 401);
  assert.deepEqual(await res.json(), { ok: false, error: "app-check" });
});

test("/plan enforce módban érvényes tokennel 200", async () => {
  const res = await worker.fetch(planReq(withToken(await mint(keyA))), env0({ APPCHECK_ENFORCE: "1" }));
  assert.equal(res.status, 200);
});

test("/plan enforce módban lejárt tokennel 401", async () => {
  const t = await mint(keyA, { claims: { exp: 1 } });
  const res = await worker.fetch(planReq(withToken(t)), env0({ APPCHECK_ENFORCE: "1" }));
  assert.equal(res.status, 401);
});

test("/status enforce: token nélkül 401, tokennel a régi formátum", async () => {
  const e = env0({ APPCHECK_ENFORCE: "1" });
  const path = "/status?userId=u.12345678&dayKey=2026-10-23";
  assert.equal((await worker.fetch(req(path), e)).status, 401);
  const res = await worker.fetch(req(path, { headers: withToken(await mint(keyA)) }), e);
  assert.equal(res.status, 200);
  assert.deepEqual(await res.json(), { ok: true, found: false, key: "plan:2026-10-23:u.12345678" });
});

// ---------------- /selftest ----------------

test("/selftest ADMIN_TOKEN nélkül 404", async () => {
  const res = await worker.fetch(req("/selftest"), env0());
  assert.equal(res.status, 404);
});

test("/selftest rossz vagy hiányzó tokennel 401", async () => {
  const e = env0({ ADMIN_TOKEN: "s3cret-admin" });
  assert.equal((await worker.fetch(req("/selftest"), e)).status, 401);
  assert.equal((await worker.fetch(req("/selftest", { headers: { Authorization: "Bearer nope" } }), e)).status, 401);
  assert.equal((await worker.fetch(req("/selftest", { headers: { Authorization: "s3cret-admin" } }), e)).status, 401);
});

test("/selftest jó tokennel lefut (hiányzó APNs-secretnél verdikttel)", async () => {
  const e = env0({ ADMIN_TOKEN: "s3cret-admin" });
  const res = await worker.fetch(req("/selftest", { headers: { Authorization: "Bearer s3cret-admin" } }), e);
  assert.equal(res.status, 200);
  const j = await res.json();
  assert.equal(j.ok, false);
  assert.ok(j.missing.includes("APNS_KEY"));
});

// ---------------- /ai/generate ----------------

const aiEnv = (extra = {}) => env0({ GEMINI_KEY: "gem-key", GEMINI_MODEL: "gemini-test-lite", ...extra });
const aiBody = JSON.stringify({ contents: [{ role: "user", parts: [{ text: "szia" }] }], model: "gemini-ultra-expensive" });
const aiReq = (headers = {}, body = aiBody) =>
  req("/ai/generate", {
    method: "POST",
    headers: { "content-type": "application/json", "content-length": String(enc.encode(body).length), ...headers },
    body,
  });

function mockUpstream(status, body = "{}") {
  globalThis.fetch = async (url, init) => {
    fetchCalls.push({ url: String(url), init, body: init.body ? await new Response(init.body).text() : "" });
    return new Response(body, { status, headers: { "content-type": "application/json" } });
  };
}

test("/ai konfiguráció nélkül 503", async () => {
  const res = await worker.fetch(aiReq(withToken(await mint(keyA))), env0());
  assert.equal(res.status, 503);
  assert.equal((await res.json()).error, "not-configured");
});

test("/ai token nélkül 401 — monitor módban is", async () => {
  mockUpstream(200);
  const res = await worker.fetch(aiReq(), aiEnv());
  assert.equal(res.status, 401);
  assert.equal(fetchCalls.length, 0);
});

test("/ai GET → 405", async () => {
  assert.equal((await worker.fetch(req("/ai/generate"), aiEnv())).status, 405);
});

test("/ai Content-Length nélkül 411", async () => {
  // A Request konstruktor stream-törzsnél nem tesz Content-Length-et.
  const stream = new ReadableStream({ start(c) { c.enqueue(enc.encode(aiBody)); c.close(); } });
  const r = new Request(BASE + "/ai/generate", {
    method: "POST", headers: withToken(await mint(keyA)), body: stream, duplex: "half",
  });
  assert.equal(r.headers.get("content-length"), null);
  const res = await worker.fetch(r, aiEnv());
  assert.equal(res.status, 411);
});

test("/ai túl nagy kérés 413", async () => {
  const t = await mint(keyA);
  const res = await worker.fetch(aiReq(withToken(t, { "content-length": "20000001" })), aiEnv());
  assert.equal(res.status, 413);
});

test("/ai limiter → 429, a Gemini nem hívódik", async () => {
  mockUpstream(200);
  const seen = [];
  const e = aiEnv({ AI_LIMITER: { limit: async ({ key }) => { seen.push(key); return { success: false }; } } });
  const res = await worker.fetch(aiReq(withToken(await mint(keyA), { "CF-Connecting-IP": "203.0.113.9" })), e);
  assert.equal(res.status, 429);
  assert.deepEqual(seen, ["203.0.113.9"]);
  assert.equal(fetchCalls.length, 0);
});

test("/ai 200: törzs változatlanul át, env-modell, kliens-fejlécek nem mennek tovább", async () => {
  const answer = JSON.stringify({ candidates: [{ content: { parts: [{ text: "{\"topics\":[]}" }] } }] });
  mockUpstream(200, answer);
  const e = aiEnv({ AI_LIMITER: { limit: async () => ({ success: true }) } });
  const res = await worker.fetch(aiReq(withToken(await mint(keyA), { Authorization: "Bearer user-meta-key", Cookie: "x=1" })), e);
  assert.equal(res.status, 200);
  assert.equal(await res.text(), answer);
  assert.equal(fetchCalls.length, 1);
  const call = fetchCalls[0];
  assert.equal(call.url, "https://generativelanguage.googleapis.com/v1beta/models/gemini-test-lite:generateContent");
  assert.equal(call.init.method, "POST");
  assert.deepEqual(Object.keys(call.init.headers).sort(), ["content-type", "x-goog-api-key"]);
  assert.equal(call.init.headers["x-goog-api-key"], "gem-key");
  assert.equal(call.body, aiBody, "a törzs bájtra azonos (a worker nem nyúl hozzá)");
});

test("/ai alapértelmezett modell GEMINI_MODEL nélkül", async () => {
  mockUpstream(200);
  await worker.fetch(aiReq(withToken(await mint(keyA))), aiEnv({ GEMINI_MODEL: undefined }));
  assert.equal(fetchCalls[0].url, "https://generativelanguage.googleapis.com/v1beta/models/gemini-3.5-flash-lite:generateContent");
});

test("/ai hibás GEMINI_MODEL (útvonal-injekció) → 503", async () => {
  mockUpstream(200);
  const res = await worker.fetch(aiReq(withToken(await mint(keyA))), aiEnv({ GEMINI_MODEL: "../x" }));
  assert.equal(res.status, 503);
  assert.equal(fetchCalls.length, 0);
});

test("/ai upstream 403 → 502 upstream-auth", async () => {
  mockUpstream(403, "{\"error\":{\"message\":\"API key not valid\"}}");
  const res = await worker.fetch(aiReq(withToken(await mint(keyA))), aiEnv());
  assert.equal(res.status, 502);
  assert.deepEqual(await res.json(), { ok: false, error: "upstream-auth" });
  assert.ok(!logs.some((l) => l.includes("szia")), "a tananyag nem kerülhet a logba");
});

test("/ai upstream 401 → 502 upstream-auth", async () => {
  mockUpstream(401);
  assert.equal((await worker.fetch(aiReq(withToken(await mint(keyA))), aiEnv())).status, 502);
});

test("/ai upstream 429 → 429 rate-limited", async () => {
  mockUpstream(429);
  const res = await worker.fetch(aiReq(withToken(await mint(keyA))), aiEnv());
  assert.equal(res.status, 429);
  assert.equal((await res.json()).error, "rate-limited");
});

test("/ai upstream 400 → 400, törzs átmegy", async () => {
  mockUpstream(400, "{\"error\":{\"message\":\"bad\"}}");
  const res = await worker.fetch(aiReq(withToken(await mint(keyA))), aiEnv());
  assert.equal(res.status, 400);
  assert.equal(await res.text(), "{\"error\":{\"message\":\"bad\"}}");
});

test("/ai upstream 500 → 502 status-szal", async () => {
  mockUpstream(500);
  const res = await worker.fetch(aiReq(withToken(await mint(keyA))), aiEnv());
  assert.equal(res.status, 502);
  assert.deepEqual(await res.json(), { ok: false, error: "upstream", status: 500 });
});

test("/ai hálózati hiba → 502", async () => {
  globalThis.fetch = async () => { throw new Error("down"); };
  const res = await worker.fetch(aiReq(withToken(await mint(keyA))), aiEnv());
  assert.equal(res.status, 502);
});

test("health a friss verzióval", async () => {
  const j = await (await worker.fetch(req("/"), env0())).json();
  assert.equal(j.version, "2026-10-23");
});
