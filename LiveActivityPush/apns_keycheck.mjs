#!/usr/bin/env node
// Lokális APNs kulcs-ellenőrzés — a workertől és a Cloudflare dashboardtól
// FÜGGETLENÜL. Ez válaszolja meg a kérdést, hogy magával a .p8-cal van gond,
// vagy csak azzal, ami a dashboardba be van írva.
//
// Használat:
//   node apns_keycheck.mjs <kulcs.p8> <KEY_ID> <TEAM_ID> [BUNDLE_ID] [prod|sandbox]
//   (BUNDLE_ID alapból hu.flint, környezet alapból prod)
//
// Szándékosan hamis, csupa-nulla device tokent küld: senkinek semmi nem megy
// ki, de az Apple válasza megmondja, hogy a JWT-t elfogadja-e.
//   400 BadDeviceToken       → a kulcs + Key ID + Team ID hármas RENDBEN
//   403 InvalidProviderToken → a hármas nem áll össze (vagy visszavont kulcs,
//                              vagy nincs a kulcson APNs szolgáltatás)
//   400 TopicDisallowed      → a kulcs nem ehhez a bundle ID-hoz tartozik

import { readFileSync } from "node:fs";
import { createSign } from "node:crypto";

const [p8Path, keyId, teamId, bundleId = "hu.flint", envName = "prod"] = process.argv.slice(2);
if (!p8Path || !keyId || !teamId) {
  console.error("Használat: node apns_keycheck.mjs <kulcs.p8> <KEY_ID> <TEAM_ID> [BUNDLE_ID] [prod|sandbox]");
  process.exit(2);
}
for (const [name, v] of [["KEY_ID", keyId], ["TEAM_ID", teamId]]) {
  if (v.trim().length !== 10) console.error(`FIGYELEM: a ${name} nem 10 karakter ("${v}" → ${v.trim().length})`);
}

const b64url = (buf) => Buffer.from(buf).toString("base64url");
const header = b64url(JSON.stringify({ alg: "ES256", kid: keyId.trim() }));
const payload = b64url(JSON.stringify({ iss: teamId.trim(), iat: Math.floor(Date.now() / 1000) }));

let jwt;
try {
  const signer = createSign("SHA256");
  signer.update(`${header}.${payload}`);
  // ieee-p1363 = nyers r||s (64 bájt) — pontosan ezt várja az APNs,
  // nem a DER-burkolt aláírást.
  const sig = signer.sign({ key: readFileSync(p8Path), dsaEncoding: "ieee-p1363" });
  jwt = `${header}.${payload}.${b64url(sig)}`;
} catch (e) {
  console.error(`A .p8 nem használható ES256 aláírásra: ${e.message}`);
  process.exit(1);
}

const host = envName === "sandbox" ? "api.sandbox.push.apple.com" : "api.push.apple.com";
const res = await fetch(`https://${host}/3/device/${"0".repeat(64)}`, {
  method: "POST",
  headers: {
    authorization: `bearer ${jwt}`,
    "apns-topic": `${bundleId}.push-type.liveactivity`,
    "apns-push-type": "liveactivity",
    "apns-priority": "10",
    "content-type": "application/json",
  },
  body: JSON.stringify({ aps: { timestamp: Math.floor(Date.now() / 1000), event: "update", "content-state": { keycheck: 1 } } }),
});
const body = await res.text();
console.log(`${envName} APNs → HTTP ${res.status} ${body}`);
if (res.status === 400 && body.includes("BadDeviceToken")) {
  console.log("✅ A kulcs-oldal RENDBEN: ez a Key ID + Team ID + .p8 hármas jó. Ezt kell a Cloudflare secretekbe beírni.");
} else if (res.status === 403) {
  console.log("❌ Az Apple elutasítja ezt a hármast (Key ID / Team ID / .p8 / visszavont kulcs / nincs APNs a kulcson).");
} else if (res.status === 400) {
  console.log("⚠️  A JWT-vel más gond van, lásd a reason-t (pl. TopicDisallowed = nem ehhez a bundle ID-hoz tartozó kulcs).");
}
