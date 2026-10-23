import CommonCrypto
import CryptoKit
import Foundation

/// SummitSync kulcsképzés és mezőtitkosítás JWT-független része (csak
/// Foundation + CryptoKit + CommonCrypto). Külön fájlban, hogy a logika az
/// app-célpont Firebase-függései nélkül, önállóan is tesztelhető legyen.
enum SummitSyncKey {
    static let versionTag = "summit-sync-v1"
    static let minPassphraseLength = 8

    /// Helyi (nem JWT) tokenek stabil kulcsa. A tesztfiók fix tokenje
    /// minden eszközön azonos, így a jelmondattal együtt ugyanúgy
    /// kitalálhatatlan doc-ID-t ad, mint a JWT-sub.
    /// Kifejezetten csak a review-fiók kap kulcsot — a demo szinkron
    /// szándékosan nem létezik (a Beállítások UI-kapu mögött marad,
    /// és itt sem kap kulcsot).
    static func localStableKey(from accessToken: String) -> String? {
        let t = accessToken.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard t == AppUser.reviewerToken else { return nil }
        return "local:summitreview"
    }

    /// v1 (régi, `sync` collection) doc-ID a stabil kulcsból + jelmondatból.
    /// Nil, ha nincs stabil kulcs, vagy a jelmondat túl rövid. Csak az
    /// egyszeri v1→v2 átálláshoz (régi doc beolvasása és törlése) kell.
    static func syncId(stableKey: String?, passphrase: String) -> String? {
        guard let stable = stableKey, !stable.isEmpty,
              passphrase.count >= minPassphraseLength else { return nil }
        let input = "\(versionTag)\n\(stable)\n\(passphrase)"
        let digest = SHA256.hash(data: Data(input.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    // MARK: - v2: lassú kulcsképzés + végponttól végpontig titkosítás

    /// v2-es kulcsanyag: a doc-ID és a mezőtitkosító kulcs ugyanabból a
    /// PBKDF2-mesterkulcsból, HKDF-fel szétválasztva — a doc-ID-ből a
    /// kulcs nem számolható vissza, és a jelmondat nélkül egyik sem.
    struct V2Keys {
        let docId: String
        let fieldKey: SymmetricKey
    }

    static let versionTagV2 = "summit-sync-v2"
    /// PBKDF2-HMAC-SHA256 körszám (OWASP 2023+ ajánlás). Egy iPhone-on
    /// ~0,3 mp, egyszer fut fiók+jelmondat páronként (a hívó gyorsítótáraz),
    /// egy offline próbálgatónak viszont ennyivel drágább minden tipp.
    static let pbkdf2Rounds: UInt32 = 600_000

    /// Lassú (PBKDF2) — SOHA ne a főszálon hívd.
    static func deriveV2(stableKey: String?, passphrase: String, rounds: UInt32 = pbkdf2Rounds) -> V2Keys? {
        guard let stable = stableKey, !stable.isEmpty,
              passphrase.count >= minPassphraseLength else { return nil }
        let password = Array(passphrase.utf8)
        let salt = Array("\(versionTagV2)\n\(stable)".utf8)
        var master = [UInt8](repeating: 0, count: 32)
        let rc = password.withUnsafeBufferPointer { pw in
            pw.baseAddress!.withMemoryRebound(to: Int8.self, capacity: password.count) { pwPtr in
                CCKeyDerivationPBKDF(CCPBKDFAlgorithm(kCCPBKDF2), pwPtr, password.count,
                                     salt, salt.count, CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256),
                                     rounds, &master, master.count)
            }
        }
        guard rc == kCCSuccess else { return nil }
        let ikm = SymmetricKey(data: master)
        let idKey = HKDF<SHA256>.deriveKey(inputKeyMaterial: ikm, info: Data("\(versionTagV2)/doc-id".utf8), outputByteCount: 32)
        let fieldKey = HKDF<SHA256>.deriveKey(inputKeyMaterial: ikm, info: Data("\(versionTagV2)/field-key".utf8), outputByteCount: 32)
        let docId = idKey.withUnsafeBytes { $0.map { String(format: "%02x", $0) }.joined() }
        return V2Keys(docId: docId, fieldKey: fieldKey)
    }

    /// Egy Firestore REST-értékobjektum (`{"stringValue": …}`,
    /// `{"booleanValue": …}`, `{"integerValue": "…"}`) titkosítása
    /// AES-GCM-mel. A mezőnév és a doc-ID az AAD-ben van, így egy
    /// titkos szöveg nem tehető át másik mezőbe vagy másik docba.
    /// Kimenet: base64(nonce ‖ titkos szöveg ‖ tag).
    static func seal(_ value: Any, field: String, keys: V2Keys) -> String? {
        let plain: String
        if let d = value as? [String: Any] {
            if let s = d["stringValue"] as? String { plain = "s:" + s }
            else if let b = d["booleanValue"] as? Bool { plain = b ? "b:1" : "b:0" }
            else if let i = d["integerValue"] as? String, Int64(i) != nil { plain = "i:" + i }
            else { return nil }
        } else {
            return nil
        }
        guard let box = try? AES.GCM.seal(Data(plain.utf8), using: keys.fieldKey,
                                          authenticating: aad(field: field, docId: keys.docId)),
              let combined = box.combined else { return nil }
        return combined.base64EncodedString()
    }

    /// A `seal` párja: visszaadja az eredeti REST-értékobjektumot, vagy nil
    /// (rossz kulcs, sérült/áthelyezett adat, ismeretlen típus).
    static func open(_ cipher: String, field: String, keys: V2Keys) -> [String: Any]? {
        guard let data = Data(base64Encoded: cipher),
              let box = try? AES.GCM.SealedBox(combined: data),
              let plainData = try? AES.GCM.open(box, using: keys.fieldKey,
                                                authenticating: aad(field: field, docId: keys.docId)),
              let plain = String(data: plainData, encoding: .utf8),
              plain.count >= 2 else { return nil }
        let tag = plain.prefix(2)
        let body = String(plain.dropFirst(2))
        switch tag {
        case "s:": return ["stringValue": body]
        case "b:": return body == "1" ? ["booleanValue": true] : body == "0" ? ["booleanValue": false] : nil
        case "i:": return Int64(body) != nil ? ["integerValue": body] : nil
        default: return nil
        }
    }

    private static func aad(field: String, docId: String) -> Data {
        Data("\(versionTagV2)|\(docId)|\(field)".utf8)
    }

    /// Titkosított mezők felső mérete (a `sync2` rules ugyanezt kényszeríti).
    /// A fölötte lévő mező nem megy fel (a többi eszközön a helyi marad).
    static let maxCipherChars: [String: Int] = [
        "photo": 160_100, "rounding": 42_800, "exempted": 21_400,
        "completedHw": 32_100, "completedEx": 32_100, "schoolEvents": 133_400,
        "schoolEventsURL": 5_400, "customTasks": 128_100, "cheatSheets": 266_800,
        "metaAIKey": 1_400, "travelMode": 200, "wrappedStars": 10_800,
    ]
    static let defaultMaxCipherChars = 200

    /// Plaintext REST-mezőtérkép → v2 (titkosított) mezőtérkép.
    /// `updatedAt` és a `ts_*` bélyegek nyíltak maradnak (a rules ezeket
    /// ellenőrzi, és nem hordoznak tartalmat); `v` = 2.
    /// - Returns: a v2 mezők + a méretkorlát miatt kihagyott mezők nevei.
    static func sealFields(_ fields: [String: Any], fieldNames: [String], keys: V2Keys) -> (fields: [String: Any], skipped: [String]) {
        var out: [String: Any] = ["v": ["integerValue": "2"]]
        if let u = fields["updatedAt"] { out["updatedAt"] = u }
        var skipped: [String] = []
        for name in fieldNames {
            if let ts = fields["ts_\(name)"] { out["ts_\(name)"] = ts }
            guard let value = fields[name] else { continue }
            guard let c = seal(value, field: name, keys: keys),
                  c.count <= (maxCipherChars[name] ?? defaultMaxCipherChars) else {
                skipped.append(name)
                out.removeValue(forKey: "ts_\(name)")
                continue
            }
            out[name] = ["stringValue": c]
        }
        return (out, skipped)
    }

    /// v2 (titkosított) REST-mezőtérkép → plaintext REST-mezőtérkép,
    /// ugyanabban az alakban, amit a v1 doc adna. Nyithatatlan mező
    /// kimarad (a hívó a hiányzó mezőnél a helyi értéket tartja meg).
    static func openFields(_ fields: [String: Any], fieldNames: [String], keys: V2Keys) -> [String: Any] {
        var out: [String: Any] = [:]
        if let u = fields["updatedAt"] { out["updatedAt"] = u }
        for name in fieldNames {
            if let ts = fields["ts_\(name)"] { out["ts_\(name)"] = ts }
            guard let c = (fields[name] as? [String: Any])?["stringValue"] as? String,
                  let v = open(c, field: name, keys: keys) else { continue }
            out[name] = v
        }
        return out
    }

    /// Két plaintext REST-mezőtérkép mezőnkénti összefésülése (az újabb
    /// `ts_*` — hiányában `updatedAt` — nyer). A v1→v2 átálláskor kell:
    /// egy még régi appot futtató eszköz a v1 docba írhatott a v2
    /// létrejötte után is, és ezek a szerkesztések nem veszhetnek el.
    /// - Returns: az összefésült térkép + volt-e mező, ahol `b` nyert.
    static func mergeFields(_ a: [String: Any], _ b: [String: Any], fieldNames: [String]) -> (fields: [String: Any], bWon: Bool) {
        func date(_ m: [String: Any], _ k: String) -> Date? {
            guard let raw = (m[k] as? [String: Any])?["timestampValue"] as? String else { return nil }
            return parseISO(raw)
        }
        let aUpdated = date(a, "updatedAt") ?? .distantPast
        let bUpdated = date(b, "updatedAt") ?? .distantPast
        var out = a
        var bWon = false
        for name in fieldNames {
            guard let bv = b[name] else { continue }
            let aTs = date(a, "ts_\(name)") ?? aUpdated
            let bTs = date(b, "ts_\(name)") ?? bUpdated
            if a[name] == nil || bTs > aTs {
                out[name] = bv
                out["ts_\(name)"] = ["timestampValue": isoString(bTs)]
                bWon = true
            }
        }
        if bUpdated > aUpdated { out["updatedAt"] = ["timestampValue": isoString(bUpdated)] }
        return (out, bWon)
    }

    private static func parseISO(_ s: String) -> Date? {
        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        if let d = plain.date(from: s) { return d }
        let frac = ISO8601DateFormatter()
        frac.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return frac.date(from: s)
    }

    private static func isoString(_ d: Date) -> String {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        f.timeZone = TimeZone(secondsFromGMT: 0)
        return f.string(from: d)
    }

    /// Mezőszintű last-writer-wins: a távoli nyer, ha bélyege újabb,
    /// mint a helyi szerkesztés (piszkos-mező idő, különben az utolsó
    /// ismert bélyeg). Egyenlőnél a helyi marad — a saját push
    /// visszhangja nem minősül újdonságnak.
    static func remoteWins(remoteTs: Date?, dirtyAt: Date?, localTs: Date) -> Bool {
        guard let r = remoteTs else { return false }
        if let d = dirtyAt { return r > d }
        return r > localTs
    }
}
