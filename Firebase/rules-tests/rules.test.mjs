// Firestore rules-tesztek (emulátor). Futtatás: lásd README.md.
import { readFileSync } from "node:fs";
import { after, before, beforeEach, describe, test } from "node:test";
import {
  assertFails,
  assertSucceeds,
  initializeTestEnvironment,
} from "@firebase/rules-unit-testing";
import {
  Timestamp,
  collection,
  deleteDoc,
  doc,
  getDoc,
  getDocs,
  setDoc,
} from "firebase/firestore";

const RULES = readFileSync(new URL("../firestore.rules", import.meta.url), "utf8");
const UUID = "550E8400-E29B-41D4-A716-446655440000";
const SYNC_ID = "a".repeat(64);
const DAY = new Date().toISOString().slice(0, 10);

let env;
let db;

before(async () => {
  env = await initializeTestEnvironment({
    projectId: "demo-summit",
    firestore: { rules: RULES },
  });
  db = env.unauthenticatedContext().firestore();
});

after(async () => {
  await env?.cleanup();
});

beforeEach(async () => {
  await env.clearFirestore();
  await env.withSecurityRulesDisabled(async (ctx) => {
    const admin = ctx.firestore();
    await setDoc(doc(admin, "public/map"), { demo: false, schools: [] });
    await setDoc(doc(admin, "public/ai_fallback"), { geminiKey: "x", geminiModel: "y" });
    await setDoc(doc(admin, "school_pins/p1"), { name: "x", lon: 19, lat: 47 });
  });
});

function heartbeat(installId = UUID) {
  const createdAt = Timestamp.fromMillis(Date.now() - 1000);
  return {
    school_name: "Teszt Gimnázium",
    institute_code: "teszt-gimi",
    install_id: installId,
    day: DAY,
    app_version: "1.0",
    platform: "iOS",
    createdAt,
    expiresAt: Timestamp.fromMillis(createdAt.toMillis() + 365 * 86400 * 1000),
  };
}

/// A jelenlegi (v1) app által küldött doc alakja (SummitSync.pushNow).
function legacySyncDoc() {
  const now = Timestamp.now();
  const d = {
    v: 1,
    updatedAt: now,
    theme: "system",
    accentHex: 0x3366ff,
    sizeKey: "system",
    skin: "summit",
    photo: "",
    rounding: "",
    exempted: "[]",
    completedHw: "[]",
    completedEx: "[]",
    notifyEnabled: true,
    liveActivity: true,
    schoolEvents: "[]",
    schoolEventsShow: true,
    schoolEventsURL: "",
    customTasks: "[]",
    cheatSheets: "[]",
    metaAIKey: "",
    examRollover: true,
    travelMode: "",
    wrappedStars: "{}",
    hasWatch: false,
  };
  for (const k of Object.keys(d)) {
    if (k !== "v" && k !== "updatedAt") d[`ts_${k}`] = now;
  }
  return d;
}

const SYNC2_FIELDS = [
  "theme", "accentHex", "sizeKey", "skin", "photo", "rounding", "exempted",
  "completedHw", "completedEx", "notifyEnabled", "liveActivity", "schoolEvents",
  "schoolEventsShow", "schoolEventsURL", "customTasks", "cheatSheets",
  "metaAIKey", "examRollover", "travelMode", "wrappedStars", "hasWatch",
];

/// A rules `isValidSync2Doc` plafonjai — a kettőnek egyeznie kell.
const SYNC2_MAX = {
  theme: 200, accentHex: 200, sizeKey: 200, skin: 200, photo: 160100,
  rounding: 42800, exempted: 21400, completedHw: 32100, completedEx: 32100,
  notifyEnabled: 200, liveActivity: 200, schoolEvents: 133400,
  schoolEventsShow: 200, schoolEventsURL: 5400, customTasks: 128100,
  cheatSheets: 266800, metaAIKey: 1400, examRollover: 200, travelMode: 200,
  wrappedStars: 10800, hasWatch: 200,
};

function sync2Doc() {
  const now = Timestamp.now();
  const d = { v: 2, updatedAt: now };
  for (const k of SYNC2_FIELDS) {
    d[k] = "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA";
    d[`ts_${k}`] = now;
  }
  return d;
}

describe("public", () => {
  test("map olvasható", async () => {
    await assertSucceeds(getDoc(doc(db, "public/map")));
  });
  test("ai_fallback NEM olvasható", async () => {
    await assertFails(getDoc(doc(db, "public/ai_fallback")));
  });
  test("írás tiltott", async () => {
    await assertFails(setDoc(doc(db, "public/map"), { demo: true }));
  });
});

describe("heartbeats", () => {
  test("napi doc mehet", async () => {
    await assertSucceeds(setDoc(doc(db, `heartbeats/${UUID}_${DAY}`), heartbeat()));
  });
  test("esemény-doc mehet", async () => {
    await assertSucceeds(setDoc(doc(db, `heartbeats/${UUID}_${DAY}_login_1757960000`), heartbeat()));
  });
  test("nem UUID install_id elutasítva", async () => {
    const id = "nem-uuid-de-hosszu";
    await assertFails(setDoc(doc(db, `heartbeats/${id}_${DAY}`), heartbeat(id)));
  });
  test("regex-metakarakteres install_id nem tágíthatja a mintát", async () => {
    const id = ".*.*.*.*";
    await assertFails(setDoc(doc(db, `heartbeats/barmi_${DAY}_x_1`), heartbeat(id)));
    await assertFails(setDoc(doc(db, `heartbeats/${UUID}_${DAY}_x_1`), heartbeat(id)));
  });
  test("túl hosszú esemény-név / epoch elutasítva", async () => {
    await assertFails(setDoc(doc(db, `heartbeats/${UUID}_${DAY}_${"a".repeat(33)}_1757960000`), heartbeat()));
    await assertFails(setDoc(doc(db, `heartbeats/${UUID}_${DAY}_login_1`), heartbeat()));
  });
  test("olvasás tiltott", async () => {
    await assertFails(getDoc(doc(db, `heartbeats/${UUID}_${DAY}`)));
  });
});

describe("sync (legacy v1)", () => {
  test("a mostani app doc-alakja továbbra is írható és olvasható", async () => {
    await assertSucceeds(setDoc(doc(db, `sync/${SYNC_ID}`), legacySyncDoc()));
    await assertSucceeds(getDoc(doc(db, `sync/${SYNC_ID}`)));
  });
  test("listázás tiltott", async () => {
    await assertFails(getDocs(collection(db, "sync")));
  });
});

describe("sync2", () => {
  test("érvényes doc létrehozható, olvasható, törölhető", async () => {
    await assertSucceeds(setDoc(doc(db, `sync2/${SYNC_ID}`), sync2Doc()));
    await assertSucceeds(getDoc(doc(db, `sync2/${SYNC_ID}`)));
    await assertSucceeds(deleteDoc(doc(db, `sync2/${SYNC_ID}`)));
  });
  test("csak v+updatedAt is érvényes (minden mező opcionális)", async () => {
    await assertSucceeds(setDoc(doc(db, `sync2/${SYNC_ID}`), { v: 2, updatedAt: Timestamp.now() }));
  });
  test("listázás tiltott", async () => {
    await assertFails(getDocs(collection(db, "sync2")));
  });
  test("rossz ID elutasítva", async () => {
    await assertFails(setDoc(doc(db, "sync2/rovid"), sync2Doc()));
  });
  test("túl nagy mező elutasítva", async () => {
    const big = sync2Doc();
    big.metaAIKey = "A".repeat(1401);
    await assertFails(setDoc(doc(db, `sync2/${SYNC_ID}`), big));
    const smallField = sync2Doc();
    smallField.theme = "A".repeat(201);
    await assertFails(setDoc(doc(db, `sync2/${SYNC_ID}`), smallField));
  });
  test("cheatSheets: 266800 mehet, 266801 nem", async () => {
    const ok = sync2Doc();
    ok.cheatSheets = "A".repeat(266800);
    await assertSucceeds(setDoc(doc(db, `sync2/${SYNC_ID}`), ok));
    const over = sync2Doc();
    over.cheatSheets = "A".repeat(266801);
    await assertFails(setDoc(doc(db, `sync2/${SYNC_ID}`), over));
  });
  test("minden mező a plafonján: a doc még belefér (1 MiB)", async () => {
    const d = sync2Doc();
    for (const [k, max] of Object.entries(SYNC2_MAX)) d[k] = "A".repeat(max);
    await assertSucceeds(setDoc(doc(db, `sync2/${SYNC_ID}`), d));
    await assertSucceeds(getDoc(doc(db, `sync2/${SYNC_ID}`)));
  });
  test("minden mező plafon+1: mind elutasítva", async () => {
    for (const [k, max] of Object.entries(SYNC2_MAX)) {
      const d = sync2Doc();
      d[k] = "A".repeat(max + 1);
      await assertFails(setDoc(doc(db, `sync2/${SYNC_ID}`), d));
    }
  });
  test("nem string adatmező elutasítva", async () => {
    const d = sync2Doc();
    d.notifyEnabled = true;
    await assertFails(setDoc(doc(db, `sync2/${SYNC_ID}`), d));
  });
  test("ismeretlen mező elutasítva", async () => {
    const d = sync2Doc();
    d.om = "72345678901";
    await assertFails(setDoc(doc(db, `sync2/${SYNC_ID}`), d));
  });
  test("v != 2 elutasítva", async () => {
    const d = sync2Doc();
    d.v = 1;
    await assertFails(setDoc(doc(db, `sync2/${SYNC_ID}`), d));
  });
  test("jövőbeli updatedAt elutasítva", async () => {
    const d = sync2Doc();
    d.updatedAt = Timestamp.fromMillis(Date.now() + 3600 * 1000);
    await assertFails(setDoc(doc(db, `sync2/${SYNC_ID}`), d));
  });
});

describe("egyéb", () => {
  test("school_pins tiltott", async () => {
    await assertFails(getDoc(doc(db, "school_pins/p1")));
  });
  test("ismeretlen collection tiltott", async () => {
    await assertFails(getDoc(doc(db, "akarmi/x")));
  });
});
