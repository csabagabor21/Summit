// Summit névtelen statisztika — Cloud Functions (Node 20).
// submitHeartbeat: az app ide POSTol (napi max 1 szívdobbanás).
// aggregateMap:   naponta összesíti -> public/map (ezt olvassa a weboldal).
const { onRequest } = require("firebase-functions/v2/https");
const { onSchedule } = require("firebase-functions/v2/scheduler");
const admin = require("firebase-admin");

admin.initializeApp();
const db = admin.firestore();
const TTL_DAYS = 365;
const ACTIVE_WINDOW_DAYS = 30;

function bad(res, msg) { res.status(400).json({ ok: false, error: msg }); }

exports.submitHeartbeat = onRequest({ region: "europe-west1", cors: true }, async (req, res) => {
  if (req.method !== "POST") { res.status(405).end(); return; }
  const b = req.body || {};
  const { install_id, school_hash, app_version, platform, day } = b;
  if (typeof install_id !== "string" || install_id.length < 8 || install_id.length > 64) return bad(res, "install_id");
  if (typeof school_hash !== "string" || !/^[0-9a-f]{64}$/.test(school_hash)) return bad(res, "school_hash");
  if (typeof day !== "string" || !/^\d{4}-\d{2}-\d{2}$/.test(day)) return bad(res, "day");

  const now = admin.firestore.Timestamp.now();
  const expiresAt = admin.firestore.Timestamp.fromMillis(Date.now() + TTL_DAYS * 86400 * 1000);
  const docId = `${install_id}_${day}`; // upsert: ugyanaz az app ugyanazon a napon csak 1x számít
  await db.collection("heartbeats").doc(docId).set({
    install_id,
    school_hash,
    app_version: String(app_version || "?").slice(0, 32),
    platform: String(platform || "?").slice(0, 32),
    day,
    createdAt: now,
    expiresAt, // Firestore TTL-policy erre a mezőre (konzolban bekapcsolandó)
  }, { merge: true });
  res.json({ ok: true });
});

exports.aggregateMap = onSchedule({ region: "europe-west1", schedule: "15 3 * * *" }, async () => {
  const since = new Date(Date.now() - ACTIVE_WINDOW_DAYS * 86400 * 1000);
  const snap = await db.collection("heartbeats")
    .where("createdAt", ">=", admin.firestore.Timestamp.fromDate(since))
    .get();

  // hash -> distinct install_id (utolsó 30 nap aktív appjai)
  const perHash = new Map();
  snap.forEach((d) => {
    const v = d.data();
    if (!v.school_hash || !v.install_id) return;
    if (!perHash.has(v.school_hash)) perHash.set(v.school_hash, new Set());
    perHash.get(v.school_hash).add(v.install_id);
  });

  const schools = [];
  for (const [hash, ids] of perHash) {
    const dir = await db.collection("hash_directory").doc(hash).get();
    if (!dir.exists) continue; // ismeretlen hash nem kerül ki a publikus térképre
    const { city, lon, lat } = dir.data();
    if (typeof city !== "string" || typeof lon !== "number" || typeof lat !== "number") continue;
    schools.push({ name: city, lon, lat, count: ids.size });
  }
  schools.sort((a, b) => b.count - a.count);

  await db.collection("public").doc("map").set({
    demo: false,
    updated: admin.firestore.Timestamp.now(),
    schools,
  });
});
