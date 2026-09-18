import ActivityKit
import Foundation
import UIKit

// MARK: - Szerver-oldali push szinkron (Cloudflare Worker)
// Az app a mai határokhoz tartozó KÉSZ állapotokat tölti fel a workerbe
// (ő az egyetlen igazságforrás — a worker csak időzítve kézbesíti APNs-en).
// Részletek: LiveActivityPush/README.md
//
// Biztonság (v1, tudatos egyszerűsítés): a végponton nincs auth — a userId
// nem titok, a kár legfeljebb egy hamis órarend-push valaki zárképernyőjére.
// Ha az app kinövi, ide HMAC-aláírás vagy Firebase Auth kerül.

@MainActor
final class SummitPushSync {
    static let shared = SummitPushSync()

    /// A worker címe. Amíg a FILL-IN benne van, a feltöltés csendben kimarad
    /// és az app tisztán helyi módban dolgozik (lásd LiveActivityPush/README).
    static var baseURL: String = "https://calm-leaf-ff15.gaborcsabusz.workers.dev"
    static var isConfigured: Bool { !baseURL.contains("FILL-IN") && baseURL.hasPrefix("https://") }

    private static let lastUploadKey = "liveActivity.pushUpload.v1"
    /// Utolsó sikeres feltöltés összefoglalója (újraindítás után is látszik).
    static let lastUploadSummaryKey = "liveActivity.pushLastUpload.v1"
    /// Utolsó kimaradt feltöltés oka — a Diagnosztika mutatja. Csak változáskor
    /// írjuk (a percenkénti sync spammelne a push-naplóba).
    static let lastSkipReasonKey = "liveActivity.pushLastSkip.v1"
    private init() {}

    /// A content-state-et a rendszer MINDIG a default JSON-stratégiával
    /// dekódolja (Apple, ActivityKit push doksi: „don't use any custom JSON
    /// encoding strategies … Custom encoding strategies will result in
    /// update failures.”). Default = másodperc 2001-01-01 óta
    /// (.deferredToDate). TILOS ide .secondsSince1970-et vagy .iso8601-et
    /// tenni — a korábbi .secondsSince1970 minden pusholt dátumot +31 évre
    /// (2057) tolt, a pusholt kártya timerei/progressze széthullott.
    /// Az aps-szintű unix mp mezőket (fireAt, staleDate) külön Int/Double
    /// mezőben visszük, nem a content-state-ben.
    private static func makeEncoder() -> JSONEncoder {
        JSONEncoder()
    }

    /// Kimaradás rögzítése: csak az első (változáskor), hogy a percenkénti
    /// sync ne árassza el a push-naplót — de a Diagnosztika mindig mutassa.
    private static func noteSkipped(_ reason: String) {
        let prev = UserDefaults.standard.string(forKey: Self.lastSkipReasonKey)
        UserDefaults.standard.set("\(SummitLiveActivityManager.eventTimeString()) • \(reason)", forKey: Self.lastSkipReasonKey)
        // Az időbélyeg mindig frissül, de a naplóba csak az ok váltásakor írunk.
        guard prev?.hasSuffix(reason) != true else { return }
        SummitLiveActivityManager.shared.pushLogEvent("feltöltés kimaradt: \(reason)")
    }

    /// Sikeres feltöltéskor a kimaradás-okát töröljük (újra aktuális az állapot).
    private static func clearSkipped() {
        UserDefaults.standard.removeObject(forKey: Self.lastSkipReasonKey)
    }

    /// Feltöltés-hash érvénytelenítése egy napra: a következő `kick` akkor is
    /// POST-ol, ha a body látszólag változatlan. Új activity-indítás után
    /// hívjuk (SummitLiveActivityManager) — az új activity ÚJ push-tokent kap,
    /// a workeren lévő régi tokenes vagy üres/lezárt terv különben bennragadna,
    /// és a token-érkezéskori feltöltés a hash-egyezés miatt némán kimaradna.
    func invalidateUploadHash(dayKey: String) {
        UserDefaults.standard.removeObject(forKey: Self.lastUploadKey + "." + dayKey)
    }

    /// Érvényes-e a push-token? A Live Activity tokenje NEM a klasszikus
    /// 32 bájtos (64 hex karakteres) device token: az Apple szerint opak
    /// érték, amelynek a hosszára NEM szabad építeni — a gyakorlatban
    /// jóval hosszabb. A korábbi `count == 64` feltétel ezért minden
    /// valódi Live Activity tokenre „nincs push-token"-t mondott: a
    /// feltöltés némán kimaradt, a workerre nem került terv, és a
    /// szerver-oldali óraváltás soha nem tudott elindulni — miközben a
    /// Diagnosztika „van (1)" tokent jelzett. Csak azt kötjük ki, ami
    /// tényleg kell: nem üres, páros hosszú, csupa hex (a token az APNs
    /// URL path-jába kerül).
    static func isValidToken(_ t: String?) -> Bool {
        guard let t, t.count >= 32, t.count % 2 == 0 else { return false }
        return t.allSatisfy(\.isHexDigit)
    }

    /// Eszköz-szintű kulcs: ugyanaz a user iPhone-on és iPaden KÜLÖN tervet
    /// kap (különben felülírnák egymást, és a push csak az egyikre menne).
    /// Különböző userek eleve külön kulcson vannak (`plan:nap:userId`).
    static func scopedUserId(_ raw: String) -> String {
        let dev = UIDevice.current.identifierForVendor?.uuidString.prefix(8) ?? "nodev"
        return "\(raw).\(dev)"
    }

    struct PushEntry: Encodable {
        var fireAt: Int
        var contentState: SummitLiveActivityAttributes.ContentState
        var staleDate: Double?
        /// true → a worker `event: "end"`-et küld (utolsó óra vége), a
        /// rendszer 1 perc múlva leveszi a kártyát — nem ül 0:00-n.
        var end: Bool?
    }

    struct PlanUpload: Encodable {
        var userId: String
        var dayKey: String
        var pushToken: String
        var sandbox: Bool
        var entries: [PushEntry]
        /// "preview" → a worker külön kulcsra teszi (valós tervet nem bánt).
        var tag: String?
    }

    /// Határ-entryk a mai tervből: minden jövőbeli határra (órakezdet/vég)
    /// a határ+10 mp-nek megfelelő kész állapot. Max ~30 db.
    static func buildEntries(today: [LessonItem], now: Date) -> [PushEntry] {
        let bounds = Set(today.flatMap { [$0.start, $0.end] }.filter { $0 > now }).sorted()
        var out: [PushEntry] = []
        for b in bounds.prefix(30) {
            let at = b.addingTimeInterval(10)
            let cur = today.first { $0.start <= at && $0.end >= at }
            let nxt = today.first { $0.start > at }
            guard cur != nil || nxt != nil else { continue }
            let state = SummitLiveActivityManager.makeState(today: today, current: cur, next: nxt, now: at)
            out.append(PushEntry(fireAt: Int(at.timeIntervalSince1970), contentState: state,
                                 staleDate: state.staleDate?.timeIntervalSince1970, end: nil))
        }
        // Utolsó óra vége: záró push. A fenti ciklus erre a határra nem ad
        // entryt (cur és nxt is nil), így enélkül a kártya a nap végén
        // lejárt 0:00-s timerrel ülne, amíg a stale-date le nem hervasztja.
        if let last = today.max(by: { $0.end < $1.end }), last.end > now {
            let at = last.end.addingTimeInterval(10)
            let final = SummitLiveActivityManager.makeState(today: today, current: last, next: nil, now: at)
            out.append(PushEntry(fireAt: Int(at.timeIntervalSince1970), contentState: final,
                                 staleDate: nil, end: true))
        }
        return out
    }

    /// Feltöltés, de csak ha változott valami (hash-összehasonlítás) —
    /// a percenkénti előtéri sync ne írja a KV-t folyamatosan.
    /// Csak valós (cacheable) syncből hívható — preview/demo sosem.
    /// Preview-feltöltés nyoma: a valós sync elsőként törli a preview-kulcsot,
    /// hogy kikapcsolt csúszkánál ne jöhessen szellem-push az eltolt tervből.
    static let previewUsedKey = "liveActivity.pushPreviewUsed.v1"

    func kick(today: [LessonItem], now: Date, dayKey: String, userId: String, pushToken: String?, preview: Bool = false) async {
        guard Self.isConfigured else { Self.noteSkipped("worker nincs beállítva"); return }
        guard !userId.isEmpty else { Self.noteSkipped("nincs belépett user"); return }
        let userId = Self.scopedUserId(userId)
        guard let pushToken, Self.isValidToken(pushToken) else {
            // A hosszt is kiírjuk: ha VAN token, csak nem felel meg, az eddig
            // ugyanazt a „nincs push-token" szöveget adta, mint a tényleges
            // hiány — pont ez rejtette el a 64-karakteres feltételt.
            if let t = pushToken, !t.isEmpty {
                Self.noteSkipped("a push-token nem érvényes (\(t.count) karakter)")
            } else if UserDefaults.standard.bool(forKey: SummitLiveActivityManager.pushTypeNilKey) {
                Self.noteSkipped("nincs push-token (ez a build push nélkül fut — újratelepítés kell)")
            } else {
                Self.noteSkipped("nincs push-token (a token még nem jött meg)")
            }
            return
        }
        // Valós sync preview-nyom után: a preview-kulcs törlése először.
        if !preview, UserDefaults.standard.bool(forKey: Self.previewUsedKey) {
            await clear(userId: userId, dayKey: dayKey, preview: true)
            UserDefaults.standard.set(false, forKey: Self.previewUsedKey)
        }
        let entries = Self.buildEntries(today: today, now: now)
        #if DEBUG
        let sandbox = true
        #else
        let sandbox = false
        #endif
        let upload = PlanUpload(userId: userId, dayKey: dayKey, pushToken: pushToken, sandbox: sandbox, entries: entries, tag: preview ? "preview" : nil)
        guard let body = try? Self.makeEncoder().encode(upload),
              let bodyString = String(data: body, encoding: .utf8) else { return }
        let hashKey = Self.lastUploadKey + "." + dayKey + (preview ? ".preview" : "")
        if UserDefaults.standard.string(forKey: hashKey) == bodyString { return }
        guard let url = URL(string: Self.baseURL + "/plan") else { return }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "content-type")
        req.httpBody = body
        do {
            let (_, resp) = try await URLSession.shared.data(for: req)
            if let http = resp as? HTTPURLResponse, 200..<300 ~= http.statusCode {
                UserDefaults.standard.set(bodyString, forKey: hashKey)
                Self.clearSkipped()
                if preview { UserDefaults.standard.set(true, forKey: Self.previewUsedKey) }
                let scope = preview ? "preview" : "napi terv"
                // Az összefoglaló csak a valós tervé (a preview ne írja felül).
                if !preview {
                    UserDefaults.standard.set("\(SummitLiveActivityManager.eventTimeString()) • \(entries.count) határ • \(dayKey)", forKey: Self.lastUploadSummaryKey)
                }
                // Az APNs Live Activity payload-limit 4 KB: a legnagyobb
                // content-state méretét is naplózzuk, hogy az eldobott
                // (túl nagy) push ne legyen láthatatlan ok — sok órás napon
                // a hátralévő terv (plan) szoros lehet.
                let maxBytes = entries.compactMap { try? Self.makeEncoder().encode($0.contentState).count }.max() ?? 0
                SummitLiveActivityManager.shared.pushLogEvent(
                    "feltöltve (\(scope)): \(entries.count) határ, max \(maxBytes) B"
                        + (maxBytes > 3800 ? " — FIGYELEM: 4 KB közelében, az APNs eldobhatja" : ""))
            } else if let http = resp as? HTTPURLResponse {
                SummitLiveActivityManager.shared.pushLogEvent("feltöltés HTTP \(http.statusCode)")
            }
        } catch {
            // Hálózat-hiba: a következő sync úgyis újrapróbálja.
            SummitLiveActivityManager.shared.pushLogEvent("feltöltés hiba: \(error.localizedDescription)")
            debugPrint("[LiveActivity] push upload failed: \(error.localizedDescription)")
        }
    }

    /// GET /status a mai (vagy adott napi) tervre — a Diagnosztika mutatja,
    /// mi van a workerben, mi ment ki, és mit válaszolt az APNs. Ez a döntő
    /// adat, ha „nem vált a kártya”: nincs terv fent (feltöltés kimaradt),
    /// APNs 400/410 (rossz token, sandbox–prod keveredés), 403 (kulcs/Team
    /// ID), vagy minden 200 és mégsem vált (payload / widget oldal).
    func fetchStatus(userId rawUserId: String, dayKey: String, preview: Bool = false) async -> String {
        guard Self.isConfigured else { return "worker nincs beállítva" }
        guard !rawUserId.isEmpty else { return "nincs belépett user" }
        guard var comps = URLComponents(string: Self.baseURL + "/status") else { return "rossz URL" }
        comps.queryItems = [
            URLQueryItem(name: "userId", value: Self.scopedUserId(rawUserId)),
            URLQueryItem(name: "dayKey", value: dayKey),
        ]
        if preview { comps.queryItems?.append(URLQueryItem(name: "tag", value: "preview")) }
        guard let url = comps.url else { return "rossz URL" }
        do {
            let (data, resp) = try await URLSession.shared.data(from: url)
            guard let http = resp as? HTTPURLResponse else { return "nincs HTTP válasz" }
            guard 200..<300 ~= http.statusCode else { return "HTTP \(http.statusCode)" }
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { return "nem JSON válasz" }
            guard json["found"] as? Bool == true else { return "nincs terv a workerben (\(dayKey)) — a feltöltés kimaradt" }
            let tf = DateFormatter()
            tf.locale = Locale(identifier: "hu_HU")
            tf.dateFormat = "HH:mm:ss"
            func time(_ v: Any?) -> String? {
                guard let d = v as? Double else { return nil }
                return tf.string(from: Date(timeIntervalSince1970: d))
            }
            let sandbox = json["sandbox"] as? Bool == true
            let suffix = json["tokenSuffix"] as? String ?? "?"
            let updated = time(json["updatedAt"]) ?? "?"
            let next = time(json["indexNext"]) ?? (json["indexNext"] as? String ?? "nincs több")
            var lines = ["terv fent: \(sandbox ? "sandbox" : "prod") APNs, token …\(suffix), feltöltve \(updated), köv. push \(next)"]
            for e in json["entries"] as? [[String: Any]] ?? [] {
                let at = time(e["fireAt"]) ?? "?"
                let end = e["end"] as? Bool == true ? " END" : ""
                let sent = e["sent"] as? Bool == true ? "kiment" : "vár"
                let attempts = e["attempts"] as? Int ?? 0
                var last = ""
                if let l = e["last"] as? [String: Any] {
                    let body = String((l["body"] as? String ?? "").prefix(80))
                    last = " → APNs \(l["status"] as? Int ?? 0)\(body.isEmpty ? "" : " \(body)")"
                }
                lines.append("  \(at)\(end) \(sent)\(attempts > 0 ? " (\(attempts) próba)" : "")\(last)")
            }
            return lines.joined(separator: "\n")
        } catch {
            return "hiba: \(error.localizedDescription)"
        }
    }

    /// Terv törlése a workerből (toggle KI, nap vége, kijelentkezés,
    /// illetve preview-nyom eltakarítása): üres entries-sel felülírjuk,
    /// így nem jön szellem-push.
    func clear(userId: String, dayKey: String, preview: Bool = false) async {
        guard Self.isConfigured else { return }
        let userId = Self.scopedUserId(userId)
        #if DEBUG
        let sandbox = true
        #else
        let sandbox = false
        #endif
        let upload = PlanUpload(userId: userId, dayKey: dayKey, pushToken: "", sandbox: sandbox, entries: [], tag: preview ? "preview" : nil)
        guard let body = try? JSONEncoder().encode(upload),
              let url = URL(string: Self.baseURL + "/plan") else { return }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "content-type")
        req.httpBody = body
        if let (_, resp) = try? await URLSession.shared.data(for: req),
           let http = resp as? HTTPURLResponse, 200..<300 ~= http.statusCode {
            SummitLiveActivityManager.shared.pushLogEvent(preview ? "preview-terv törölve" : "napi terv törölve a workerből")
        }
        UserDefaults.standard.removeObject(forKey: Self.lastUploadKey + "." + dayKey)
        if !preview { UserDefaults.standard.removeObject(forKey: Self.lastUploadSummaryKey) }
    }
}
