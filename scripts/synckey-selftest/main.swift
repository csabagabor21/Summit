// SummitSyncKey önteszt — futtatás: sh scripts/synckey_selftest.sh
import Foundation
import CryptoKit
func check(_ c: Bool, _ m: String) { if !c { print("FAIL:", m); exit(1) } else { print("ok:", m) } }
let t0 = Date()
let k = SummitSyncKey.deriveV2(stableKey: "123456", passphrase: "correct horse")!
print("pbkdf2 600k:", Date().timeIntervalSince(t0), "s")
let k2 = SummitSyncKey.deriveV2(stableKey: "123456", passphrase: "correct horse")!
check(k.docId == k2.docId && k.docId.count == 64, "deterministic 64-hex docId")
check(SummitSyncKey.deriveV2(stableKey: "123457", passphrase: "correct horse")!.docId != k.docId, "stable key changes id")
check(SummitSyncKey.deriveV2(stableKey: "123456", passphrase: "short") == nil, "short passphrase rejected")
check(k.docId != SummitSyncKey.syncId(stableKey: "123456", passphrase: "correct horse"), "v2 id != v1 id")
let s = SummitSyncKey.seal(["stringValue": "árvíztűrő / \"x\""], field: "cheatSheets", keys: k)!
check((SummitSyncKey.open(s, field: "cheatSheets", keys: k)?["stringValue"] as? String) == "árvíztűrő / \"x\"", "string roundtrip")
check(SummitSyncKey.open(s, field: "customTasks", keys: k) == nil, "field swap rejected (AAD)")
let other = SummitSyncKey.deriveV2(stableKey: "999", passphrase: "correct horse")!
check(SummitSyncKey.open(s, field: "cheatSheets", keys: other) == nil, "wrong key rejected")
check((SummitSyncKey.open(SummitSyncKey.seal(["booleanValue": false], field: "hasWatch", keys: k)!, field: "hasWatch", keys: k)?["booleanValue"] as? Bool) == false, "bool roundtrip")
check((SummitSyncKey.open(SummitSyncKey.seal(["integerValue": "16777215"], field: "accentHex", keys: k)!, field: "accentHex", keys: k)?["integerValue"] as? String) == "16777215", "int roundtrip")
check(SummitSyncKey.seal(["timestampValue": "x"], field: "theme", keys: k) == nil, "unsupported type not sealed")
var tampered = Data(base64Encoded: s)!; tampered[tampered.count-1] ^= 1
check(SummitSyncKey.open(tampered.base64EncodedString(), field: "cheatSheets", keys: k) == nil, "tamper rejected")
let names = ["theme","photo","metaAIKey"]
let plain: [String: Any] = ["updatedAt": ["timestampValue": "2026-10-23T10:00:00Z"], "theme": ["stringValue": "dark"],
  "ts_theme": ["timestampValue": "2026-10-23T09:00:00Z"], "photo": ["stringValue": String(repeating: "A", count: 130_000)],
  "metaAIKey": ["stringValue": "sk-secret"]]
let (sealed, skipped) = SummitSyncKey.sealFields(plain, fieldNames: names, keys: k)
check(skipped == ["photo"] && sealed["photo"] == nil && sealed["ts_photo"] == nil, "oversized field skipped")
check(!(String(describing: sealed).contains("sk-secret")) && !(String(describing: sealed).contains("dark")), "no plaintext in sealed map")
check(((sealed["v"] as? [String: String])?["integerValue"]) == "2", "v=2")
let opened = SummitSyncKey.openFields(sealed, fieldNames: names, keys: k)
check(((opened["metaAIKey"] as? [String: Any])?["stringValue"] as? String) == "sk-secret", "openFields roundtrip")
check(((opened["ts_theme"] as? [String: String])?["timestampValue"]) == "2026-10-23T09:00:00Z", "ts kept")
let v1: [String: Any] = ["updatedAt": ["timestampValue": "2026-10-23T11:00:00Z"], "theme": ["stringValue": "light"], "metaAIKey": ["stringValue": "old"], "ts_metaAIKey": ["timestampValue": "2026-10-01T00:00:00Z"]]
let (merged, won) = SummitSyncKey.mergeFields(opened, v1, fieldNames: names)
check(won && ((merged["theme"] as? [String: Any])?["stringValue"] as? String) == "light", "newer v1 field wins")
check(((merged["metaAIKey"] as? [String: Any])?["stringValue"] as? String) == "sk-secret", "older v1 field loses")
print("ALL OK")
