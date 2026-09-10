import ActivityKit
import Foundation

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
    private init() {}

    struct PushEntry: Encodable {
        var fireAt: Int
        var contentState: SummitLiveActivityAttributes.ContentState
        var staleDate: Double?
    }

    struct PlanUpload: Encodable {
        var userId: String
        var dayKey: String
        var pushToken: String
        var sandbox: Bool
        var entries: [PushEntry]
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
            out.append(PushEntry(fireAt: Int(at.timeIntervalSince1970), contentState: state, staleDate: state.staleDate?.timeIntervalSince1970))
        }
        return out
    }

    /// Feltöltés, de csak ha változott valami (hash-összehasonlítás) —
    /// a percenkénti előtéri sync ne írja a KV-t folyamatosan.
    /// Csak valós (cacheable) syncből hívható — preview/demo sosem.
    func kick(today: [LessonItem], now: Date, dayKey: String, userId: String, pushToken: String?) async {
        guard Self.isConfigured else { return }
        guard !userId.isEmpty else { return }
        guard let pushToken, pushToken.count == 64 else { return }
        let entries = Self.buildEntries(today: today, now: now)
        #if DEBUG
        let sandbox = true
        #else
        let sandbox = false
        #endif
        let upload = PlanUpload(userId: userId, dayKey: dayKey, pushToken: pushToken, sandbox: sandbox, entries: entries)
        guard let body = try? JSONEncoder().encode(upload),
              let bodyString = String(data: body, encoding: .utf8) else { return }
        let hashKey = Self.lastUploadKey + "." + dayKey
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
            }
        } catch {
            // Hálózat-hiba: a következő sync úgyis újrapróbálja.
            debugPrint("[LiveActivity] push upload failed: \(error.localizedDescription)")
        }
    }

    /// Terv törlése a workerből (toggle KI, nap vége, kijelentkezés):
    /// üres entries-sel felülírjuk, így nem jön szellem-push.
    func clear(userId: String, dayKey: String) async {
        guard Self.isConfigured else { return }
        #if DEBUG
        let sandbox = true
        #else
        let sandbox = false
        #endif
        let upload = PlanUpload(userId: userId, dayKey: dayKey, pushToken: "", sandbox: sandbox, entries: [])
        guard let body = try? JSONEncoder().encode(upload),
              let url = URL(string: Self.baseURL + "/plan") else { return }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "content-type")
        req.httpBody = body
        try? await URLSession.shared.data(for: req)
        UserDefaults.standard.removeObject(forKey: Self.lastUploadKey + "." + dayKey)
    }
}
