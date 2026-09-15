import Foundation
import Combine
import UIKit

/// Minimál, hozzájáruláshoz kötött használati statisztika.
///
/// GDPR-terv: semmit nem gyűjt és semmit nem küld, amíg a user kifejezetten
/// be nem kapcsolja (default: KI). A választás bármikor, egy koppintással
/// visszavonható a Beállítások tetején — ez az Art. 7(3) "olyan könnyű
/// visszavonni, mint megadni" követelménye.
///
/// Amit BEKAPCSOLT állapotban küld (napi max 1 heartbeat):
/// - install_id: véletlen UUID (nem eszköz-ID, törléssel újragenerálódik)
/// - school_name: az iskola KRÉTA-beli neve (a nyers intézménykód nem hagyja
///   el a telefont; névből egyén nem beazonosítható)
/// - app_version, platform (pl. "iOS 26"), nap (yyyy-MM-dd, nem pontos időbélyeg)
///
/// Amit SOHA nem küld: név, KRÉTA token/jelszó, jegyek, órarend, hely,
/// IP-cím-naplózás, eszköz-fingerprint, Cloudflare-azonosító.
///
/// Backend: közvetlen írás az EU-régiós (`eur3`) Firestore `heartbeats`
/// collectionbe (projekt: summit-14b74). A rules csak létrehozást enged,
/// szigorú sémával (lásd `Firebase/firestore.rules`); olvasni senki nem tud.
/// Minden rekord `expiresAt`-tel íródik (12 hónap), a TTL-policy a Blaze
/// bekapcsolása után élesedik.
@MainActor
final class AnalyticsStore: ObservableObject {
    @Published var hasChosen: Bool {
        didSet { UserDefaults.standard.set(hasChosen, forKey: Self.choiceKey) }
    }
    @Published var isEnabled: Bool {
        didSet { UserDefaults.standard.set(isEnabled, forKey: Self.enabledKey) }
    }

    private static let choiceKey = "analytics.choiceMade.v1"
    private static let enabledKey = "analytics.enabled.v1"
    private static let installKey = "analytics.installId.v1"
    private static let lastDayKey = "analytics.lastHeartbeatDay.v1"
    private static let lastAttemptKey = "analytics.lastAttempt.v1"
    private static let lastSchoolKey = "analytics.lastSchool.v1"
    private static let lastResultKey = "analytics.lastResult.v1"
    /// Közvetlen Firestore-írás (nincs köztes backend).
    /// A webes API-kulcs publikus azonosító — a védelmet a security rules
    /// adja (szigorú séma, csak létrehozás, olvasás sehol).
    private static let projectId = "summit-14b74"
    private static let apiKey = "AIzaSyA1TttM0aUUHsvjjAItYMbdID_no1vzg9s"

    /// Diagnosztika (Beállítások → Diagnosztika): az utolsó heartbeat-
    /// próbálkozás ember-olvasható nyoma. Release-ben is íródik, de csak
    /// státuszkódot és iskolanevet tartalmaz — személyes adatot sosem.
    @Published var lastAttempt: String {
        didSet { UserDefaults.standard.set(lastAttempt, forKey: Self.lastAttemptKey) }
    }
    @Published var lastSchool: String {
        didSet { UserDefaults.standard.set(lastSchool, forKey: Self.lastSchoolKey) }
    }
    @Published var lastResult: String {
        didSet { UserDefaults.standard.set(lastResult, forKey: Self.lastResultKey) }
    }

    let installId: String
    /// Folyamatban lévő küldés napja — párhuzamos duplázás ellen.
    private var inFlightDay: String?

    init() {
        self.hasChosen = UserDefaults.standard.bool(forKey: Self.choiceKey)
        self.isEnabled = UserDefaults.standard.bool(forKey: Self.enabledKey)
        self.lastAttempt = UserDefaults.standard.string(forKey: Self.lastAttemptKey) ?? "–"
        self.lastSchool = UserDefaults.standard.string(forKey: Self.lastSchoolKey) ?? "–"
        self.lastResult = UserDefaults.standard.string(forKey: Self.lastResultKey) ?? "–"
        if let saved = UserDefaults.standard.string(forKey: Self.installKey), !saved.isEmpty {
            self.installId = saved
        } else {
            let fresh = UUID().uuidString
            UserDefaults.standard.set(fresh, forKey: Self.installKey)
            self.installId = fresh
        }
    }

    /// Választás mentése a beleegyező képernyőről.
    func choose(enabled: Bool) {
        isEnabled = enabled
        hasChosen = true
    }

    /// Beállítások-kapcsoló (ugyanaz, mint a választás — a visszavonás egy koppintás).
    func setEnabled(_ enabled: Bool) {
        isEnabled = enabled
        hasChosen = true
        if enabled == false {
            // Kikapcsoláskor nem törlünk helyit a visszavonáson túl —
            // a szerver-oldali törlést a tájékoztatóban ígért e-mailes
            // kérelem + 12 hónapos TTL intézi.
        }
    }

    /// Napi egy heartbeat, csak ha: be van kapcsolva + van értelmes sulinév.
    /// Kód-szerű, üres és demo neveket nem küldünk (azokból úgysem lenne térkép).
    /// - Parameter schoolName: az iskola KRÉTA-beli neve (`AppUser.schoolName`).
    func recordHeartbeat(schoolName: String?) {
        let now = Date()
        guard isEnabled else {
            note(result: "kihagyva: kikapcsolva", school: schoolName, at: now)
            return
        }
        guard let raw = schoolName?.trimmingCharacters(in: .whitespacesAndNewlines),
              !raw.isEmpty else {
            note(result: "kihagyva: nincs iskolanév", school: nil, at: now)
            return
        }
        guard Self.isRealSchoolName(raw) else {
            note(result: "kihagyva: szűrt név", school: raw, at: now)
            return
        }
        let today = Self.dayBucket(Date())
        if UserDefaults.standard.string(forKey: Self.lastDayKey) == today {
            note(result: "kihagyva: ma már elküldve", school: raw, at: now)
            return
        }
        // A "mai nap elküldve" jelölés csak sikeres küldéskor áll be
        // (lásd applyDelivery) — sikertelen próba után a következő
        // előtérbe hozás újrapróbálja, nem hallgat el egész napra.
        if inFlightDay == today { return }
        inFlightDay = today
        note(result: "küldés…", school: raw, at: now)
        deliver(schoolName: raw, day: today)
    }

    /// Valódi sulinév-e, vagy kód/demo/üres placeholder.
    /// A KRÉTA-nevek tulajdonnevek (nagybetűsek) és/vagy ékezetesek; a kódok
    /// (pl. "klik035454001", "siszc-mathiasz") csupa kisbetűsek, szóköz
    /// nélkül — az ilyen sosem oldható fel térkép-pinné, kiküldeni is felesleges.
    static func isRealSchoolName(_ s: String) -> Bool {
        let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
        guard t.count >= 2, t.count <= 120 else { return false }
        let low = t.lowercased()
        if low == "demo" || low == "unknown" || low == "demo iskola" || low == "diák" { return false }
        if !t.contains(" ") && t == low
            && t.rangeOfCharacter(from: CharacterSet(charactersIn: "áéíóöőúüű")) == nil {
            return false
        }
        return true
    }

    // MARK: - Private

    /// Közvetlen dokumentum-létrehozás a `heartbeats` collectionben.
    /// Doc-ID: "{install_id}_{day}" — ugyanaz az app ugyanazon a napon
    /// csak egyszer számít, és a rules ezt ellenőrzi is.
    private func deliver(schoolName: String, day: String) {
        let now = Date()
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime]
        iso.timeZone = TimeZone(secondsFromGMT: 0)
        let created = iso.string(from: now)
        let expires = iso.string(from: now.addingTimeInterval(365 * 86400))

        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
        let build = Bundle.main.object(forInfoDictionaryKey: kCFBundleVersionKey as String) as? String ?? "?"
        let str = { (v: String) -> [String: String] in ["stringValue": v] }
        let doc: [String: Any] = ["fields": [
            "school_name": str(String(schoolName.prefix(120))),
            "install_id": str(installId),
            "day": str(day),
            "app_version": str("\(version) (\(build))"),
            "platform": str("iOS \(UIDevice.current.systemVersion)"),
            "createdAt": ["timestampValue": created],
            "expiresAt": ["timestampValue": expires]
        ]]
        var comps = URLComponents(string: "https://firestore.googleapis.com/v1/projects/\(Self.projectId)/databases/(default)/documents/heartbeats")!
        comps.queryItems = [
            URLQueryItem(name: "documentId", value: "\(installId)_\(day)"),
            URLQueryItem(name: "key", value: Self.apiKey)
        ]
        var req = URLRequest(url: comps.url!)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try? JSONSerialization.data(withJSONObject: doc)
        URLSession.shared.dataTask(with: req) { [weak self] _, resp, err in
            let code = (resp as? HTTPURLResponse)?.statusCode
            let result: String
            let ok: Bool
            if code == 200 {
                result = "OK 200"; ok = true
            } else if let code {
                result = "HTTP \(code)"; ok = false
            } else {
                result = "hálózati hiba"; ok = false
            }
            #if DEBUG
            if !ok { print("[analytics] heartbeat \(result): \(err?.localizedDescription ?? "–")") }
            #endif
            Task { await self?.applyDelivery(day: day, result: result, ok: ok) }
        }.resume()
    }

    /// Diagnosztikai nyom rögzítése (sikeres és kihagyott próbálkozásnál is).
    private func note(result: String, school: String?, at: Date) {
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime]
        iso.timeZone = TimeZone(secondsFromGMT: 0)
        lastResult = result
        if let s = school?.trimmingCharacters(in: .whitespacesAndNewlines), !s.isEmpty {
            lastSchool = String(s.prefix(120))
        }
        lastAttempt = iso.string(from: at)
    }

    /// Küldés lezárása: a napi jelölés csak HTTP 200-ra áll be, különben
    /// a következő trigger újrapróbálkozik.
    private func applyDelivery(day: String, result: String, ok: Bool) {
        if inFlightDay == day { inFlightDay = nil }
        lastResult = result
        if ok { UserDefaults.standard.set(day, forKey: Self.lastDayKey) }
    }

    private static func dayBucket(_ d: Date) -> String {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .iso8601)
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: d)
    }
}
