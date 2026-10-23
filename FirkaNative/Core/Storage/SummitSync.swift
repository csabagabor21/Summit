import Foundation
import Combine
import CryptoKit
import Security
import UIKit
import FirebaseCore
import FirebaseFirestore

/// Szinkronizált mezőnevek (megegyeznek a Firestore-mezőkkel).
/// Delta-szinkron: egy helyi szerkesztés csak a saját mezőjét jelöli
/// piszkosnak, a feltöltés a többit a szerverről visszakeverve őrzi meg.
enum SummitSyncField: String, CaseIterable {
    case theme
    case accentHex
    case sizeKey
    case skin
    case photo
    case rounding
    case exempted
    case completedHw
    case completedEx
    case notifyEnabled
    case liveActivity
    case schoolEvents
    case schoolEventsShow
    case schoolEventsURL
    case customTasks
    case cheatSheets
    case metaAIKey
    case examRollover
    case travelMode
    case wrappedStars
    case hasWatch

    /// A mező verzióbélyege a docban (`ts_theme` …). Régi docokban
    /// hiányozhat — olyankor az `updatedAt` a helyettese.
    var tsKey: String { "ts_\(rawValue)" }
}

/// Eszközök közötti beállítás-szinkron Blaze nélkül, tisztán Sparkon.
///
/// Kulcsképzés az eszközön (v2, `sync2` collection, lásd SummitSyncKey):
/// `PBKDF2-SHA256(jelmondat, "summit-sync-v2" + stabilUserKulcs, 600k)` →
/// HKDF-fel külön doc-ID és külön AES-GCM mezőkulcs.
/// - A stabil kulcs a JWT `sub`/`email` (minden eszközön azonos).
/// - A jelmondat (min. 8 kar.) csak a Keychainben él, sehova nem megy ki.
/// - A szerverre csak a doc-ID, a bélyegek és TITKOSÍTOTT mezőértékek
///   kerülnek: a szerver (és aki a projekthez hozzáfér) sem látja a képet,
///   a jegyzeteket vagy a Meta AI-kulcsot. A doc-ID ismerete a hozzáférési
///   jogosultság; a rules gyűjtést (list) nem enged, minden kérés App
///   Check tokent visz, a lassú kulcsképzés pedig a próbálgatást drágítja.
/// - Átállás: a régi, nyílt `sync` (v1) docot az első v2-es kör beolvassa,
///   összefésüli, titkosítva átírja, majd törli (lásd migrateLegacyIfNeeded).
///
/// Delta-elv: a feltöltés csak a piszkos mezőket írja felül (a többit a
/// szerverről visszakeverve), a lehúzás csak az újabb bélyegű mezőket
/// alkalmazza. Így egy új eszköz "Frissítés most"-ja nem öli meg a többi
/// eszköz beállításait, és két eszköz eltérő mezői nem ütik egymást.
///
/// Szinkronizált tartalom: téma (mode), kiemelőszín, szövegméret, profilkép,
/// kerekítés, felmentések, házi/dolgozat pipák, értesítés-főkapcsoló,
/// Live Activity kapcsoló, iskolai események (+ mutatás-kapcsoló és a
/// mentett naptár-link, hogy a kézi felülírás linkje is átmenjen),
/// saját feladatok/dolgozatok, tanulójegyzet-lapok, Meta AI-kulcs,
/// dolgozat-pótlás kapcsoló, Wrapped-csillagok (melyik hónapra melyik
/// kép van rögzítve), órajelenlét (párosított óra van-e ezen az
/// eszközön — ebből tudja meg a Mac, hogy mutathatja a Watch tabot).
@MainActor
final class SummitSync: ObservableObject {
    @Published var isEnabled: Bool {
        didSet {
            UserDefaults.standard.set(isEnabled, forKey: Self.enabledKey)
            if !isEnabled { stopListener() }
        }
    }
    /// Rövid, ember-olvasható állapot a Beállítások sornak.
    @Published var status: String = "kikapcsolva"
    /// Pull alkalmazása után eddig nem küldünk vissza automatikusan —
    /// különben minden lehúzás egy felesleges feltöltést generálna.
    var suppressPushUntil = Date.distantPast

    private static let enabledKey = "sync.enabled.v1"
    private static let lastAppliedKey = "sync.lastApplied.v1"
    private static let fieldTsKey = "summitsync.fieldTs.v1"
    private static let dirtyKey = "summitsync.dirty.v1"
    private static let dirtyTsKey = "summitsync.dirtyTs.v1"
    private static let keychainService = "hu.flint.summit.sync"
    private static let keychainAccount = "passphrase"
    /// Fejlesztői másolat kulcsa: csak akkor él, ha a Keychain írása
    /// elhasal (aláíratlan/sandboxolt Mac-build, -34018).
    private static let passphraseFallbackKey = "sync.passphrase.fallback.v1"
    private static let projectId = "summit-14b74"
    private static let apiKey = "AIzaSyA1TttM0aUUHsvjjAItYMbdID_no1vzg9s"
    static let minPassphraseLength = SummitSyncKey.minPassphraseLength
    /// Kerekítés-JSON plafon (karakter): ~30 tárgy is bőven belefér.
    static let maxRoundingChars = 16_000
    /// Fotó-base64 plafon (karakter): 256 px jpeg mellé bőséges, 1 MiB
    /// doc-limittől messze van. A rules ugyanezt kényszeríti.
    static let maxPhotoChars = 100_000
    /// Iskolai esemény JSON-plafon (karakter): ~500 esemény fér bele.
    /// A rules 50 000-et enged (régi kliensek felé opcionális mező).
    static let maxSchoolEventsChars = 48_000
    /// Mentett naptár-link plafon (karakter). A rules ugyanezt kényszeríti.
    static let maxSchoolEventsURLChars = 2_000
    /// Saját feladat/dolgozat JSON-plafon (karakter): ~200 tétel fér bele.
    /// A rules 48 000-et enged (régi kliensek felé opcionális mező).
    static let maxCustomTasksChars = 48_000
    /// Tanulójegyzet-lap JSON-plafon (karakter): az AI-jegyzetek miatt
    /// nagyobb, mint a saját feladatoké. A rules 100 000-et enged
    /// (régi kliensek felé opcionális mező).
    static let maxCheatSheetsChars = 100_000
    /// Meta AI-kulcs plafon (karakter): a kulcs rövid, a vágás csak
    /// sérült adat ellen véd. A rules 500-at enged (régi kliensek
    /// felé opcionális mező).
    static let maxMetaAIKeyChars = 500
    /// Utazás-intervallum plafon (karakter): "yyyy-MM-dd/yyyy-MM-dd"
    /// 21 kar. A rules 32-t enged (régi kliensek felé opcionális mező).
    static let maxTravelModeChars = 32
    /// Wrapped-csillag JSON-plafon (karakter): ~36 havi rögzítés fér bele.
    /// A rules 4 000-et enged (régi kliensek felé opcionális mező).
    static let maxWrappedStarsChars = 4_000
    /// Utoljára felküldött órajelenlét-érték: csak a helyi `true`
    /// válthat dirty-re (az óra nélküli eszköz — pl. a Mac — sosem
    /// jelöl, így nem írhatja felül a telefon `true`-ját `false`-szal).
    private static let hasWatchSentKey = "summitsync.hasWatchSent.v1"

    /// Piszkos (feltöltésre váró) mezők — memóriában + perzisztálva, hogy
    /// egy újraindulás se nyelje el a még fel nem töltött szerkesztést.
    private var dirtyFields: Set<String> = []
    /// Piszkos mezőnként a SZERKESZTÉS pillanata (nem a feltöltésé).
    /// A feltöltés ezt a bélyeget viszi fel — egy beragadt régi jelölés
    /// így nem írhatja felül a frissebb szervert (last-writer-wins).
    private var dirtyTimes: [String: Date] = [:]
    /// Mezőnkénti utolsó ismert (küldött vagy alkalmazott) bélyeg.
    private var fieldTimestamps: [String: Date] = [:]

    init() {
        self.isEnabled = UserDefaults.standard.bool(forKey: Self.enabledKey)
        if isEnabled { status = "bekapcsolva" }
        if let arr = UserDefaults.standard.array(forKey: Self.dirtyKey) as? [String] {
            dirtyFields = Set(arr)
        }
        if let dict = UserDefaults.standard.dictionary(forKey: Self.dirtyTsKey) as? [String: Double] {
            dirtyTimes = dict.mapValues { Date(timeIntervalSince1970: $0) }
        }
        // Migráció: időbélyeg nélküli, régi jelölések a mostani
        // pillanattal indulnak (a mai viselkedéssel azonosan).
        let now = Date()
        for f in dirtyFields where dirtyTimes[f] == nil { dirtyTimes[f] = now }
        if let dict = UserDefaults.standard.dictionary(forKey: Self.fieldTsKey) as? [String: Double] {
            fieldTimestamps = dict.mapValues { Date(timeIntervalSince1970: $0) }
        }
        observeLocalEdits()
    }

    var hasPassphrase: Bool { Self.loadPassphrase() != nil }

    // MARK: - Kulcsképzés

    /// Eszközfüggetlen stabil kulcs a tokenből. A JWT-sub mellé a
    /// review-fiók helyi kulcsa is beszáll (`SummitSyncKey`), így a
    /// summitreview is tud szinkronizálni — a demo továbbra sem.
    private static func stableKey(accessToken: String) -> String? {
        JWT.stableUserKey(from: accessToken) ?? SummitSyncKey.localStableKey(from: accessToken)
    }

    /// Gyors (PBKDF2 nélküli) előellenőrzés a Beállításoknak: képezhető-e
    /// szinkronkulcs ebből a tokenből és jelmondatból.
    static func canSync(accessToken: String, passphrase: String) -> Bool {
        stableKey(accessToken: accessToken) != nil
            && passphrase.count >= SummitSyncKey.minPassphraseLength
    }

    /// v2 kulcsanyag a tokenhez + a mentett jelmondathoz. A PBKDF2 a
    /// főszálon kívül fut, és fiók+jelmondat páronként egyszer: az
    /// eredmény memóriában marad (a jelmondat ujjlenyomatával kulcsolva).
    private func v2Keys(accessToken: String) async -> SummitSyncKey.V2Keys? {
        guard let pass = Self.loadPassphrase(),
              let stable = Self.stableKey(accessToken: accessToken) else { return nil }
        let fingerprint = SHA256.hash(data: Data("\(stable)\n\(pass)".utf8))
            .map { String(format: "%02x", $0) }.joined()
        if let c = keyCache, c.fingerprint == fingerprint { return c.keys }
        let keys = await Task.detached(priority: .userInitiated) {
            SummitSyncKey.deriveV2(stableKey: stable, passphrase: pass)
        }.value
        if let keys { keyCache = (fingerprint, keys) }
        return keys
    }

    /// A régi (v1) doc-ID — csak az átálláshoz és a törléshez.
    private static func legacySyncId(accessToken: String) -> String? {
        guard let pass = loadPassphrase() else { return nil }
        return SummitSyncKey.syncId(stableKey: stableKey(accessToken: accessToken), passphrase: pass)
    }

    static func savePassphrase(_ s: String) {
        let stored = KeychainHelper.save(Data(s.utf8), service: keychainService, account: keychainAccount) == errSecSuccess
            && loadKeychainPassphrase() != nil
        if stored {
            // Kulcstároló él — esetleges régi fejlesztői másolat törlése,
            // hogy ne maradjon két helyen a jelmondat.
            UserDefaults.standard.removeObject(forKey: passphraseFallbackKey)
        } else {
            // Sandboxolt, keychain-entitlement nélküli (aláíratlan) Mac-build:
            // a SecItemAdd -34018-cal elhasal. Ilyenkor UserDefaults-másolatba
            // mentünk, hogy a szinkron ott is bekapcsolható legyen. Aláírt
            // builden ez az ág sosem él (ott a Keychain az elsődleges).
            UserDefaults.standard.set(s, forKey: passphraseFallbackKey)
        }
    }

    static func loadPassphrase() -> String? {
        if let kc = loadKeychainPassphrase() { return kc }
        guard let f = UserDefaults.standard.string(forKey: passphraseFallbackKey),
              !f.isEmpty else { return nil }
        return f
    }

    /// A fejlesztői másolat él-e (Keychain üres, de van mentett jelmondat) —
    /// a Beállítások ilyenkor egy tájékoztató sort mutat.
    static var isPassphraseFallbackActive: Bool {
        loadKeychainPassphrase() == nil
            && (UserDefaults.standard.string(forKey: passphraseFallbackKey)?.isEmpty == false)
    }

    private static func loadKeychainPassphrase() -> String? {
        guard let d = KeychainHelper.load(service: keychainService, account: keychainAccount),
              let s = String(data: d, encoding: .utf8), !s.isEmpty else { return nil }
        return s
    }

    static func deletePassphrase() {
        KeychainHelper.delete(service: keychainService, account: keychainAccount)
        UserDefaults.standard.removeObject(forKey: passphraseFallbackKey)
    }

    private var lastApplied: String {
        get { UserDefaults.standard.string(forKey: Self.lastAppliedKey) ?? "" }
        set { UserDefaults.standard.set(newValue, forKey: Self.lastAppliedKey) }
    }

    private func persistDirty() {
        UserDefaults.standard.set(Array(dirtyFields), forKey: Self.dirtyKey)
        UserDefaults.standard.set(dirtyTimes.mapValues { $0.timeIntervalSince1970 }, forKey: Self.dirtyTsKey)
    }

    private func persistFieldTs() {
        UserDefaults.standard.set(fieldTimestamps.mapValues { $0.timeIntervalSince1970 }, forKey: Self.fieldTsKey)
    }

    // MARK: - REST

    private static let collectionV2 = "sync2"
    private static let collectionLegacy = "sync"

    private static func docURL(collection: String, id: String) -> URL? {
        URL(string: "https://firestore.googleapis.com/v1/projects/\(projectId)/databases/(default)/documents/\(collection)/\(id)?key=\(apiKey)")
    }

    /// REST-hívás App Check tokennel. - Returns: (törzs, HTTP-kód) vagy
    /// (nil, nil) hálózati hibánál.
    private static func send(_ url: URL, method: String, body: Data? = nil) async -> (Data?, Int?) {
        var req = URLRequest(url: url)
        req.httpMethod = method
        if let body {
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = body
        }
        await SummitAppCheck.attach(to: &req)
        do {
            let (data, resp) = try await URLSession.shared.data(for: req)
            return (data, (resp as? HTTPURLResponse)?.statusCode)
        } catch {
            return (nil, nil)
        }
    }

    /// Egy doc nyers REST-mezői. - Returns: (mezők, HTTP-kód); a kód nil
    /// hálózati hibánál, 404 ha nincs doc.
    private static func fetchRawFields(collection: String, id: String) async -> ([String: Any]?, Int?) {
        let (fields, _, code) = await fetchRawDoc(collection: collection, id: id)
        return (fields, code)
    }

    /// Mint a fetchRawFields, plusz a doc `updateTime`-ja (feltételes íráshoz).
    private static func fetchRawDoc(collection: String, id: String) async -> ([String: Any]?, String?, Int?) {
        guard let url = docURL(collection: collection, id: id) else { return (nil, nil, nil) }
        let (data, code) = await send(url, method: "GET")
        guard code == 200, let data,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let fields = json["fields"] as? [String: Any] else { return (nil, nil, code) }
        return (fields, json["updateTime"] as? String, code)
    }

    private static var fieldNames: [String] { SummitSyncField.allCases.map(\.rawValue) }

    /// Plaintext mezők titkosítása és teljes doc-írás a `sync2`-be.
    /// - Returns: HTTP-kód (nil = hálózati hiba) + a méret miatt kihagyott mezők.
    /// Feltétel a doc-íráshoz: csak akkor írjon, ha a doc azóta nem változott
    /// (`updateTime`), illetve ha még nem létezik.
    enum WritePrecondition {
        case updateTime(String)
        case notExists
    }

    private static func writeV2(_ plain: [String: Any], keys: SummitSyncKey.V2Keys, precondition: WritePrecondition? = nil) async -> (Int?, [String]) {
        let (sealed, skipped) = SummitSyncKey.sealFields(plain, fieldNames: fieldNames, keys: keys)
        var url = docURL(collection: collectionV2, id: keys.docId)
        if let base = url, let precondition, var comps = URLComponents(url: base, resolvingAgainstBaseURL: false) {
            switch precondition {
            case .updateTime(let t): comps.queryItems?.append(URLQueryItem(name: "currentDocument.updateTime", value: t))
            case .notExists: comps.queryItems?.append(URLQueryItem(name: "currentDocument.exists", value: "false"))
            }
            url = comps.url
        }
        guard let url,
              let body = try? JSONSerialization.data(withJSONObject: ["fields": sealed]) else { return (nil, skipped) }
        let (_, code) = await send(url, method: "PATCH", body: body)
        return (code, skipped)
    }

    private static func isoNow() -> String {
        isoString(from: Date())
    }

    private static func isoString(from date: Date) -> String {
        isoPlain.string(from: date)
    }

    /// UserDefaults-bool a deklarált alapértelmezéssel (a sima
    /// `bool(forKey:)` a még sosem írt kulcsra false-t adna).
    static func flag(_ key: String, default d: Bool) -> Bool {
        UserDefaults.standard.object(forKey: key) as? Bool ?? d
    }

    /// String-tömb JSON-né (felmentések, pipák). Rendezett, sapkázott.
    static func stringArrayJSON(_ arr: [String], maxChars: Int, maxCount: Int) -> String {
        let clean = arr.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && $0.count <= 120 }
            .sorted()
        let capped = Array(clean.prefix(maxCount))
        guard !capped.isEmpty,
              let data = try? JSONSerialization.data(withJSONObject: capped, options: [.sortedKeys]),
              let s = String(data: data, encoding: .utf8),
              s.count <= maxChars else { return "[]" }
        return s
    }

    static func decodeStringArray(_ s: String, maxChars: Int, maxCount: Int) -> [String]? {
        guard s.count <= maxChars, let data = s.data(using: .utf8),
              let raw = try? JSONSerialization.jsonObject(with: data) as? [String] else { return nil }
        return Array(raw.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && $0.count <= 120 }
            .prefix(maxCount))
    }

    /// Helyi pillanatkép feltöltéshez. A fotó `nil` = túl nagy/kódolhatatlan —
    /// ilyenkor a távoli kép marad (nem töröljük a szervert egy `""`-rel).
    private struct LocalValues {
        var theme: String
        var accentHex: Int
        var sizeKey: String
        var skin: String
        var photo: String?
        var rounding: String
        var exempted: String
        var completedHw: String
        var completedEx: String
        var notifyEnabled: Bool
        var liveActivity: Bool
        var schoolEvents: String
        var schoolEventsShow: Bool
        var schoolEventsURL: String
        var customTasks: String
        var cheatSheets: String
        var metaAIKey: String
        var examRollover: Bool
        var travelMode: String
        var wrappedStars: String
        var hasWatch: Bool
    }

    private func localValues() -> LocalValues? {
        guard let theme = liveTheme else { return nil }
        let img = liveProfile?.loadedImage(for: profileKey())
        return LocalValues(
            theme: theme.mode.rawValue,
            accentHex: theme.accentHex,
            sizeKey: theme.sizeCategoryKey,
            skin: theme.skin.rawValue,
            photo: Self.photoBase64(img),
            rounding: Self.roundingJSON(GradingLogic.loadThresholds()),
            exempted: Self.stringArrayJSON(Array(ExemptedStore.load()), maxChars: 8_000, maxCount: 128),
            completedHw: Self.stringArrayJSON(CompletedStore.loadHomeworkIDs(), maxChars: 12_000, maxCount: 256),
            completedEx: Self.stringArrayJSON(CompletedStore.loadExamIDs(), maxChars: 12_000, maxCount: 256),
            notifyEnabled: Self.flag("notify.enabled", default: true),
            liveActivity: Self.flag("liveActivity.enabled", default: true),
            schoolEvents: SchoolEventsStore.syncString(SchoolEventsStore.load()),
            schoolEventsShow: SchoolEventsStore.isVisible(),
            schoolEventsURL: SchoolEventsStore.savedURL() ?? "",
            customTasks: CustomTasksStore.syncString(CustomTasksStore.load()),
            cheatSheets: CheatStore.syncString(CheatStore.load()),
            metaAIKey: String(MetaAIKeyStore.apiKey.prefix(Self.maxMetaAIKeyChars)),
            examRollover: Self.flag("exams.rolloverOnAbsence", default: true),
            travelMode: TravelMode.syncString(),
            wrappedStars: WrappedStarStore.syncString(WrappedStarStore.loadStars()),
            hasWatch: WatchAvailability.shared.hasWatch
        )
    }

    /// Eszközfüggetlen profilkép-kulcs: a JWT stabil kulcsa az elsődleges,
    /// mert az AppUser.id belépésenként új UUID (azzal a másik eszköz vagy
    /// egy új belépés sosem találná meg ugyanazt a képet).
    private func profileKey() -> String {
        ProfileImageStore.key(userId: liveUserId, accessToken: lastToken)
    }

    /// Csak a piszkos mezők feltöltése: a többit a szerverről visszakeverjük,
    /// így egy friss eszköz alapértelmezései nem ölik meg a többi eszköz
    /// beállításait. Üres dirty-halmaz = nincs teendő (nem nyúlunk a doc-hoz).
    func pushNow() async -> Bool {
        guard let at = lastToken, liveTheme != nil, localValues() != nil,
              let keys = await v2Keys(accessToken: at) else {
            status = "nincs kulcs"
            return false
        }
        let pending = dirtyFields
        guard !pending.isEmpty else { return true }
        await migrateLegacyIfNeeded(accessToken: at, keys: keys)
        // A helyi pillanatkép a (lassú) kulcsképzés és az átállás UTÁN
        // készül, hogy a közben történt szerkesztések is benne legyenek.
        guard let local = localValues() else {
            status = "nincs kulcs"
            return false
        }
        let now = Date()
        let nowISO = Self.isoString(from: now)
        let (remote, remoteCode) = await fetchPayload(keys: keys)
        // Csak ismert távoli állapotra írunk: 200 (van doc) vagy 404 (nincs).
        // Hálózati hiba, 403 (pl. még nincs App Check token), 429 (betelt
        // olvasási keret) vagy 5xx esetén a vak írás a másik eszköz újabb
        // mezőit taposná el — a jelölések maradnak, később újra.
        guard remoteCode == 200 || remoteCode == 404 else {
            status = remoteCode == nil ? "hálózati hiba" : "olvasási hiba (HTTP \(remoteCode ?? 0))"
            return false
        }
        /// A távoli docban tényleg ott van-e a mező (titkosítva kimaradt vagy
        /// visszafejthetetlen mező = nincs, ilyenkor a helyi érték megy).
        func remoteHas(_ field: SummitSyncField) -> Bool {
            remote?.fieldDates[field.rawValue] != nil
        }

        // Segéd: piszkos mezőnél a helyi érték csak akkor nyer, ha a
        // szerkesztése újabb a távolinál — egy beragadt régi jelölés
        // nem írhatja felül a frissebb szervert. Tisztánál a távoli
        // (ha van), különben a helyi a régi bélyegével.
        func pick<T>(_ field: SummitSyncField, local: T, remote remoteValue: T?) -> (T, Date) {
            let remote = remoteHas(field) ? remoteValue : nil
            if pending.contains(field.rawValue) {
                let editAt = dirtyTimes[field.rawValue] ?? now
                if let r = remote,
                   SummitSyncKey.remoteWins(remoteTs: remoteDate(for: field), dirtyAt: editAt, localTs: fieldTimestamps[field.rawValue] ?? .distantPast) {
                    return (r, remoteDate(for: field))
                }
                return (local, editAt)
            }
            if let r = remote { return (r, remoteDate(for: field)) }
            return (local, fieldTimestamps[field.rawValue] ?? now)
        }
        func remoteDate(for field: SummitSyncField) -> Date {
            remote?.fieldDates[field.rawValue] ?? remote?.updatedAtDate ?? now
        }

        let str = { (v: String) -> [String: String] in ["stringValue": v] }
        let bool = { (v: Bool) -> [String: Bool] in ["booleanValue": v] }
        let ts = { (d: Date) -> [String: String] in ["timestampValue": Self.isoString(from: d)] }

        let (themeV, themeTs) = pick(.theme, local: local.theme, remote: remote?.theme)
        let (accentV, accentTs) = pick(.accentHex, local: local.accentHex, remote: remote?.accentHex)
        let (sizeV, sizeTs) = pick(.sizeKey, local: local.sizeKey, remote: remote?.sizeKey)
        let (skinV, skinTs) = pick(.skin, local: local.skin, remote: remote?.skinRaw)
        let (roundingV, roundingTs) = pick(.rounding, local: local.rounding, remote: remote?.roundingRaw)
        let (exemptedV, exemptedTs) = pick(.exempted, local: local.exempted, remote: remote?.exemptedRaw)
        let (hwV, hwTs) = pick(.completedHw, local: local.completedHw, remote: remote?.completedHwRaw)
        let (exV, exTs) = pick(.completedEx, local: local.completedEx, remote: remote?.completedExRaw)
        let (neV, neTs) = pick(.notifyEnabled, local: local.notifyEnabled, remote: remote?.notifyEnabled)
        let (laV, laTs) = pick(.liveActivity, local: local.liveActivity, remote: remote?.liveActivity)
        let (erV, erTs) = pick(.examRollover, local: local.examRollover, remote: remote?.examRollover)
        // Iskolai események: a régi docban még hiányozhat (nil) — olyankor a
        // helyi érték a régi bélyegével megy (nem töröljük a frisset üresre).
        let (seV, seTs): (String, Date) = {
            if pending.contains(SummitSyncField.schoolEvents.rawValue) { return (local.schoolEvents, now) }
            if let r = remote?.schoolEventsRaw { return (r, remoteDate(for: .schoolEvents)) }
            return (local.schoolEvents, fieldTimestamps[SummitSyncField.schoolEvents.rawValue] ?? now)
        }()
        let (seShowV, seShowTs): (Bool, Date) = {
            if pending.contains(SummitSyncField.schoolEventsShow.rawValue) { return (local.schoolEventsShow, now) }
            if let r = remote?.schoolEventsShow { return (r, remoteDate(for: .schoolEventsShow)) }
            return (local.schoolEventsShow, fieldTimestamps[SummitSyncField.schoolEventsShow.rawValue] ?? now)
        }()
        // Mentett link: a régi docban még hiányozhat (nil) — olyankor a
        // helyi link a régi bélyegével megy (nem töröljük a frisset üresre).
        let (seURLV, seURLTs): (String, Date) = {
            if pending.contains(SummitSyncField.schoolEventsURL.rawValue) { return (local.schoolEventsURL, now) }
            if let r = remote?.schoolEventsURLRaw { return (r, remoteDate(for: .schoolEventsURL)) }
            return (local.schoolEventsURL, fieldTimestamps[SummitSyncField.schoolEventsURL.rawValue] ?? now)
        }()
        // Saját feladatok: a régi docban még hiányozhat (nil) — olyankor a
        // helyi lista a régi bélyegével megy (nem töröljük a frisset üresre).
        let (ctV, ctTs): (String, Date) = {
            if pending.contains(SummitSyncField.customTasks.rawValue) { return (local.customTasks, now) }
            if let r = remote?.customTasksRaw { return (r, remoteDate(for: .customTasks)) }
            return (local.customTasks, fieldTimestamps[SummitSyncField.customTasks.rawValue] ?? now)
        }()
        // Tanulójegyzet-lapok: a régi docban még hiányozhat (nil) —
        // olyankor a helyi lista a régi bélyegével megy.
        let (chV, chTs): (String, Date) = {
            if pending.contains(SummitSyncField.cheatSheets.rawValue) { return (local.cheatSheets, now) }
            if let r = remote?.cheatSheetsRaw { return (r, remoteDate(for: .cheatSheets)) }
            return (local.cheatSheets, fieldTimestamps[SummitSyncField.cheatSheets.rawValue] ?? now)
        }()
        // Meta AI-kulcs: a régi docban még hiányozhat (nil) — olyankor
        // a helyi kulcs a régi bélyegével megy. Üres helyi kulccsal
        // nem írunk felül távoli kulcsot (a még kulcs-nélküli eszköz
        // első push-a nem törölheti a másik eszköz kulcsát).
        let (mkV, mkTs): (String, Date) = {
            if pending.contains(SummitSyncField.metaAIKey.rawValue) { return (local.metaAIKey, now) }
            if let r = remote?.metaAIKeyRaw { return (r, remoteDate(for: .metaAIKey)) }
            return (local.metaAIKey, fieldTimestamps[SummitSyncField.metaAIKey.rawValue] ?? now)
        }()
        // Utazás-intervallum: a régi docban még hiányozhat (nil) —
        // olyankor a helyi érték a régi bélyegével megy. Üres string =
        // kikapcsolt utazás mód (tudatos törlés).
        let (tmV, tmTs): (String, Date) = {
            if pending.contains(SummitSyncField.travelMode.rawValue) { return (local.travelMode, now) }
            if let r = remote?.travelModeRaw { return (r, remoteDate(for: .travelMode)) }
            return (local.travelMode, fieldTimestamps[SummitSyncField.travelMode.rawValue] ?? now)
        }()
        // Wrapped-csillagok: a régi docban még hiányozhat (nil) — olyankor
        // a helyi rögzítés a régi bélyegével megy. Üres `"{}"` = nincs
        // csillag (a levétel is terjed).
        let (wsV, wsTs): (String, Date) = {
            if pending.contains(SummitSyncField.wrappedStars.rawValue) { return (local.wrappedStars, now) }
            if let r = remote?.wrappedStarsRaw { return (r, remoteDate(for: .wrappedStars)) }
            return (local.wrappedStars, fieldTimestamps[SummitSyncField.wrappedStars.rawValue] ?? now)
        }()
        // Órajelenlét: ragadós `true` — ha BÁRMELYIK oldalon van óra,
        // az marad (a Mac `false`-a sosem törölheti a telefon `true`-ját;
        // a párosítás végleges törlése így nem terjed — tudatos határ).
        let (watchV, watchTs): (Bool, Date) = {
            if local.hasWatch {
                if pending.contains(SummitSyncField.hasWatch.rawValue) {
                    let editAt = dirtyTimes[SummitSyncField.hasWatch.rawValue] ?? now
                    if let r = remote?.hasWatch,
                       SummitSyncKey.remoteWins(remoteTs: remoteDate(for: .hasWatch), dirtyAt: editAt, localTs: fieldTimestamps[SummitSyncField.hasWatch.rawValue] ?? .distantPast) {
                        return (r, remoteDate(for: .hasWatch))
                    }
                    return (true, editAt)
                }
                // Ragadós `true` bélyegemelés nélkül: egyszer felment,
                // onnantól nem írjuk újra minden feltöltéskor.
                if let r = remote?.hasWatch, r { return (true, remoteDate(for: .hasWatch)) }
                return (true, fieldTimestamps[SummitSyncField.hasWatch.rawValue] ?? now)
            }
            if let r = remote?.hasWatch { return (r, remoteDate(for: .hasWatch)) }
            return (false, fieldTimestamps[SummitSyncField.hasWatch.rawValue] ?? now)
        }()
        // Fotó: túl nagy helyi képnél (nil) a távoli marad — sosem küldünk
        // rá üreset, mert az a szerver-oldali kép törlését jelentené.
        let photoPair: (String, Date)
        if pending.contains(SummitSyncField.photo.rawValue), let s = local.photo {
            photoPair = (s, now)
        } else if remoteHas(.photo), let r = remote?.photoRaw {
            photoPair = (r, remoteDate(for: .photo))
        } else if let s = local.photo {
            photoPair = (s, fieldTimestamps[SummitSyncField.photo.rawValue] ?? now)
        } else {
            photoPair = (remote?.photoRaw ?? "", remoteDate(for: .photo))
        }

        var fields: [String: Any] = [
            "v": ["integerValue": "1"],
            "updatedAt": ["timestampValue": nowISO],
            "theme": str(themeV),
            "accentHex": ["integerValue": String(accentV)],
            "sizeKey": str(sizeV),
            "skin": str(skinV),
            "photo": str(photoPair.0),
            "rounding": str(roundingV),
            "exempted": str(exemptedV),
            "completedHw": str(hwV),
            "completedEx": str(exV),
            "notifyEnabled": bool(neV),
            "liveActivity": bool(laV),
            "schoolEvents": str(seV),
            "schoolEventsShow": bool(seShowV),
            "schoolEventsURL": str(seURLV),
            "customTasks": str(ctV),
            "cheatSheets": str(chV),
            "metaAIKey": str(mkV),
            "examRollover": bool(erV),
            "travelMode": str(tmV),
            "wrappedStars": str(wsV),
            "hasWatch": bool(watchV),
        ]
        let tsPairs: [(SummitSyncField, Date)] = [
            (.theme, themeTs), (.accentHex, accentTs), (.sizeKey, sizeTs), (.skin, skinTs),
            (.photo, photoPair.1), (.rounding, roundingTs), (.exempted, exemptedTs),
            (.completedHw, hwTs), (.completedEx, exTs), (.notifyEnabled, neTs),
            (.liveActivity, laTs),
            (.schoolEvents, seTs), (.schoolEventsShow, seShowTs),
            (.schoolEventsURL, seURLTs), (.customTasks, ctTs),
            (.cheatSheets, chTs), (.metaAIKey, mkTs), (.examRollover, erTs),
            (.travelMode, tmTs), (.wrappedStars, wsTs), (.hasWatch, watchTs),
        ]
        for (f, d) in tsPairs { fields[f.tsKey] = ts(d) }

        let (code, skipped) = await Self.writeV2(fields, keys: keys)
        guard code == 200 else {
            status = code == nil ? "hálózati hiba" : "feltöltés hiba (HTTP \(code ?? 0))"
            return false
        }
        for (f, d) in tsPairs { fieldTimestamps[f.rawValue] = d }
        persistFieldTs()
        // A ténylegesen felküldött órajelenlét jegyzése a refresh-triggerhez.
        UserDefaults.standard.set(watchV, forKey: Self.hasWatchSentKey)
        // Feltöltés közben újra piszkolódott mező marad (az újabb
        // szerkesztés bélyege nagyobb a most felvittnél) — a többi
        // jelölés mehet, az a szerverrel szinkronban van.
        let usedTs = Dictionary(uniqueKeysWithValues: tsPairs.map { ($0.0.rawValue, $0.1) })
        for f in pending {
            if (dirtyTimes[f] ?? .distantPast) <= (usedTs[f] ?? .distantFuture) {
                dirtyFields.remove(f)
                dirtyTimes.removeValue(forKey: f)
            }
        }
        persistDirty()
        lastApplied = nowISO
        // Titkosítva a korlát fölé nőtt mező nem ment fel (a többi eszközön
        // a helyi érték marad) — ezt látni kell, nem lehet néma.
        status = skipped.isEmpty ? "szinkronizálva" : "szinkronizálva, túl nagy, kimaradt: \(skipped.joined(separator: ", "))"
        return true
    }

    /// Tanári kerekítés JSON-stringgé (tárgy → küszöb). Csak ép
    /// bejegyzések mennek fel (név 1-120 kar., max 128 tárgy, 0...1 érték).
    static func roundingJSON(_ dict: [String: Double]) -> String {
        var clean: [String: Double] = [:]
        for (k, v) in dict {
            let t = k.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !t.isEmpty, t.count <= 120, v >= 0, v <= 1 else { continue }
            clean[t] = v
            if clean.count >= 128 { break }
        }
        guard !clean.isEmpty,
              let data = try? JSONSerialization.data(withJSONObject: clean, options: [.sortedKeys]),
              let s = String(data: data, encoding: .utf8),
              s.count <= maxRoundingChars else { return "" }
        return s
    }

    /// Visszafejtés + szigorú szűrés; érvénytelen bejegyzések eldobva.
    static func decodeRounding(_ s: String) -> [String: Double]? {
        if s.isEmpty { return [:] }
        guard s.count <= maxRoundingChars,
              let data = s.data(using: .utf8),
              let raw = try? JSONSerialization.jsonObject(with: data) as? [String: Double] else { return nil }
        var out: [String: Double] = [:]
        for (k, v) in raw {
            let t = k.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !t.isEmpty, t.count <= 120, v >= 0, v <= 1 else { continue }
            out[t] = v
            if out.count >= 128 { break }
        }
        return out
    }

    /// 256 px-es jpeg base64-ben.
    /// - `nil` képnél `""` (nincs kép — a törlés is terjed).
    /// - Túl nagy/kódolhatatlan képnél `nil` (a távoli kép marad — a feltöltés
    ///   sosem törölheti a szervert egy méret-túllépés miatt).
    static func photoBase64(_ photo: UIImage?) -> String? {
        guard let photo else { return "" }
        let s = max(photo.size.width, photo.size.height)
        let img: UIImage
        if s > 256 {
            let k = 256 / s
            let ns = CGSize(width: photo.size.width * k, height: photo.size.height * k)
            let r = UIGraphicsImageRenderer(size: ns)
            img = r.image { _ in photo.draw(in: CGRect(origin: .zero, size: ns)) }
        } else {
            img = photo
        }
        guard let data = img.jpegData(compressionQuality: 0.75) else { return nil }
        let b64 = data.base64EncodedString()
        return b64.count <= maxPhotoChars ? b64 : nil
    }

    struct Payload {
        let updatedAt: String
        let updatedAtDate: Date
        let theme: String
        let accentHex: Int
        let sizeKey: String
        /// Felület-skin (`nil` = régi doc, ilyenkor a helyi marad).
        let skinRaw: String?
        /// A nyers base64 (feltöltéskori visszakeveréshez).
        let photoRaw: String
        let photo: UIImage?
        /// Nem üres, de dekódolhatatlan fotó — ilyenkor a helyi kép marad.
        let photoDecodeFailed: Bool
        let rounding: [String: Double]
        let roundingRaw: String
        let exempted: [String]
        let exemptedRaw: String
        let completedHw: [String]
        let completedHwRaw: String
        let completedEx: [String]
        let completedExRaw: String
        let notifyEnabled: Bool
        let liveActivity: Bool
        /// Dolgozat-pótlás kapcsoló (`nil` = a régi docban még nincs mező —
        /// ilyenkor a helyi állapot marad, nem írunk felül).
        let examRollover: Bool?
        /// Órajelenlét (`nil` = a régi docban még nincs mező —
        /// ilyenkor a helyi peer-jelzés marad, nem törlünk).
        let hasWatch: Bool?
        /// Iskolai esemény JSON (`nil` = a régi docban még nincs mező —
        /// ilyenkor a helyi állapot marad, nem törlünk).
        let schoolEventsRaw: String?
        /// Mutatás-kapcsoló (`nil` = régi doc, marad a helyi).
        let schoolEventsShow: Bool?
        /// Mentett naptár-link (`nil` = a régi docban még nincs mező —
        /// ilyenkor a helyi link marad, nem törlünk).
        let schoolEventsURLRaw: String?
        /// Saját feladatok JSON (`nil` = a régi docban még nincs mező —
        /// ilyenkor a helyi lista marad, nem törlünk).
        let customTasksRaw: String?
        /// Tanulójegyzet-lapok JSON (`nil` = a régi docban még nincs mező —
        /// ilyenkor a helyi lista marad, nem törlünk).
        let cheatSheetsRaw: String?
        /// Meta AI-kulcs (`nil` = a régi docban még nincs mező —
        /// ilyenkor a helyi kulcs marad, nem törlünk).
        let metaAIKeyRaw: String?
        /// Utazás-intervallum (`nil` = a régi docban még nincs mező —
        /// ilyenkor a helyi beállítás marad, nem törlünk).
        let travelModeRaw: String?
        /// Wrapped-csillag JSON (`nil` = a régi docban még nincs mező —
        /// ilyenkor a helyi rögzítés marad, nem törlünk).
        let wrappedStarsRaw: String?
        /// Mezőnkénti bélyeg (`ts_*`, régi docban az `updatedAt`).
        let fieldDates: [String: Date]
    }

    private static let isoPlain: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        f.timeZone = TimeZone(secondsFromGMT: 0)
        return f
    }()

    private static let isoFrac: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        f.timeZone = TimeZone(secondsFromGMT: 0)
        return f
    }()

    /// ISO-idő dátummá (tört másodperccel vagy anélkül). Ismeretlen
    /// forma: távoli jövő — inkább alkalmazza egyszer, mint sose.
    private static func isoDate(_ s: String) -> Date {
        if let d = isoPlain.date(from: s) { return d }
        if let d = isoFrac.date(from: s) { return d }
        return .distantFuture
    }

    /// Letöltés + alkalmazás (csak az újabb bélyegű mezők).
    /// - Returns: "applied", "fresh" (nincs újabb), "nodoc", "error".
    func pullNow() async -> String {
        guard let at = lastToken, liveTheme != nil, liveProfile != nil,
              let keys = await v2Keys(accessToken: at) else {
            return "error"
        }
        await migrateLegacyIfNeeded(accessToken: at, keys: keys)
        let (payload, code) = await fetchPayload(keys: keys)
        guard code == 200, let p = payload else {
            // Csak a tényleges 404 jelent „nincs doc"-ot — a Beállítások erre
            // mindent piszkosnak jelöl és feltölt, egy 403/429/5xx-re ez a
            // másik eszköz teljes állapotát taposná el.
            return code == 404 ? "nodoc" : "error"
        }
        guard let theme = liveTheme, let profile = liveProfile else { return "error" }
        guard applyRemote(p, theme: theme, profile: profile, completed: liveCompleted) else { return "fresh" }
        return "applied"
    }

    /// Közös GET a push-merge és a pull számára.
    /// - Returns: a payload (nil, ha nincs doc vagy hibás) + HTTP-kód
    ///   (nil = hálózati hiba).
    private func fetchPayload(keys: SummitSyncKey.V2Keys) async -> (Payload?, Int?) {
        let (raw, code) = await Self.fetchRawFields(collection: Self.collectionV2, id: keys.docId)
        guard let raw else { return (nil, code) }
        let plain = SummitSyncKey.openFields(raw, fieldNames: Self.fieldNames, keys: keys)
        return (Self.parse(fields: plain), code)
    }

    /// Egyszeri (és naponta egyszer újraellenőrzött) átállás a régi, nyílt
    /// `sync` docról a titkosított `sync2`-re: a v1 tartalmát mezőnként
    /// összefésüli a v2-vel (az újabb bélyeg nyer), titkosítva visszaírja,
    /// majd törli a v1 docot. A napi újraellenőrzés azért kell, mert egy
    /// még régi appot futtató másik eszköz újra létrehozhatja a v1 docot —
    /// az ő szerkesztései így sem vesznek el, és a nyílt másolat sem marad
    /// fent. Hálózati hibánál nem jelöl: a következő kör újrapróbálja.
    private func migrateLegacyIfNeeded(accessToken: String, keys: SummitSyncKey.V2Keys) async {
        // Egyszerre csak egy átállás fut (push, pull és listener is hívja) —
        // a második megvárja az elsőt, nem olvas-ír párhuzamosan.
        if let running = migrationTask {
            await running.value
            return
        }
        let task = Task { await self.runLegacyMigration(accessToken: accessToken, keys: keys) }
        migrationTask = task
        await task.value
        migrationTask = nil
    }

    private func runLegacyMigration(accessToken: String, keys: SummitSyncKey.V2Keys) async {
        var checks = UserDefaults.standard.dictionary(forKey: Self.legacyCheckKey) as? [String: Double] ?? [:]
        let now = Date().timeIntervalSince1970
        if let last = checks[keys.docId], now - last < 24 * 3600 { return }
        guard let legacyId = Self.legacySyncId(accessToken: accessToken) else { return }
        let (legacy, legacyCode) = await Self.fetchRawFields(collection: Self.collectionLegacy, id: legacyId)
        guard let legacyCode else { return }
        if let legacy, legacyCode == 200 {
            let (current, updateTime, currentCode) = await Self.fetchRawDoc(collection: Self.collectionV2, id: keys.docId)
            guard currentCode == 200 || currentCode == 404 else { return }
            let opened = current.map { SummitSyncKey.openFields($0, fieldNames: Self.fieldNames, keys: keys) } ?? [:]
            // Egy régi app bekapcsoláskori „mindent feltöltök" docja a már
            // élő v2 mellett csak a hiányzó mezőket pótolhatja — különben a
            // régi eszköz alapállapota (üres listák, kép nélkül) mindent
            // felülírna a frissített eszközökön.
            let bulk = current != nil && SummitSyncKey.isBulkUpload(
                legacy, fieldNames: Self.fieldNames, newerThan: SummitSyncKey.updatedAt(opened))
            let (merged, legacyWon) = SummitSyncKey.mergeFields(opened, legacy, fieldNames: Self.fieldNames, onlyMissing: bulk)
            if current == nil || legacyWon {
                // Feltételes írás: ha közben valaki a v2-be írt, nem tapossuk
                // el — a következő kör friss állapotból újra összefésül.
                let precondition: WritePrecondition? = current == nil ? .notExists : updateTime.map { .updateTime($0) }
                let (code, _) = await Self.writeV2(merged, keys: keys, precondition: precondition)
                guard code == 200 else { return }
            }
            guard let url = Self.docURL(collection: Self.collectionLegacy, id: legacyId) else { return }
            let (_, delCode) = await Self.send(url, method: "DELETE")
            // 403: a 2. fázis rules-a már a régi collectiont is tiltja.
            guard delCode == 200 || delCode == 404 || delCode == 403 else { return }
        } else if legacyCode != 404 && legacyCode != 403 {
            return
        }
        checks[keys.docId] = now
        UserDefaults.standard.set(checks, forKey: Self.legacyCheckKey)
    }

    private static func parse(fields: [String: Any]) -> Payload? {
        func s(_ k: String) -> String? { (fields[k] as? [String: String])?["stringValue"] }
        func i(_ k: String) -> Int? { Int((fields[k] as? [String: String])?["integerValue"] ?? "") }
        func tsDate(_ k: String, fallback: Date) -> Date {
            guard let raw = (fields[k] as? [String: String])?["timestampValue"] else { return fallback }
            return isoDate(raw)
        }
        guard let updatedAt = (fields["updatedAt"] as? [String: String])?["timestampValue"],
              let theme = s("theme"), let sizeKey = s("sizeKey"), let accent = i("accentHex") else { return nil }
        let updatedAtDate = isoDate(updatedAt)
        var fieldDates: [String: Date] = [:]
        // Bélyeg csak a docban ténylegesen meglévő mezőhöz jár: a hiányzó
        // (régi kliens, méret miatt kimaradt vagy visszafejthetetlen) mező
        // így sosem „újabb", a helyi érték marad (applyRemote / pushNow).
        for f in SummitSyncField.allCases where fields[f.rawValue] != nil {
            fieldDates[f.rawValue] = tsDate(f.tsKey, fallback: updatedAtDate)
        }
        let photoRaw = s("photo") ?? ""
        var photo: UIImage? = nil
        var photoDecodeFailed = false
        if !photoRaw.isEmpty {
            if let data = Data(base64Encoded: photoRaw), let img = UIImage(data: data) {
                photo = img
            } else {
                photoDecodeFailed = true
            }
        }
        func b(_ k: String) -> Bool? { (fields[k] as? [String: Any])?["booleanValue"] as? Bool }
        let roundingRaw = s("rounding") ?? ""
        let exemptedRaw = s("exempted") ?? ""
        let completedHwRaw = s("completedHw") ?? ""
        let completedExRaw = s("completedEx") ?? ""
        guard let rounding = decodeRounding(roundingRaw),
              let exempted = decodeStringArray(exemptedRaw, maxChars: 8_000, maxCount: 128),
              let completedHw = decodeStringArray(completedHwRaw, maxChars: 12_000, maxCount: 256),
              let completedEx = decodeStringArray(completedExRaw, maxChars: 12_000, maxCount: 256),
              let notifyEnabled = b("notifyEnabled"),
              let liveActivity = b("liveActivity") else { return nil }
        // REST-út: ugyanaz az opcionális szemantika, mint a snapshotnál.
        let schoolEventsRaw: String? = {
            guard let raw = s("schoolEvents"), raw.count <= maxSchoolEventsChars else { return nil }
            return raw
        }()
        let schoolEventsURLRaw: String? = {
            guard let raw = s("schoolEventsURL"), raw.count <= maxSchoolEventsURLChars else { return nil }
            return raw
        }()
        // REST-út: ugyanaz az opcionális szemantika, mint a snapshotnál.
        let customTasksRaw: String? = {
            guard let raw = s("customTasks"), raw.count <= maxCustomTasksChars else { return nil }
            return raw
        }()
        let cheatSheetsRaw: String? = {
            guard let raw = s("cheatSheets"), raw.count <= maxCheatSheetsChars else { return nil }
            return raw
        }()
        let metaAIKeyRaw: String? = {
            guard let raw = s("metaAIKey"), raw.count <= maxMetaAIKeyChars else { return nil }
            return raw
        }()
        let travelModeRaw: String? = {
            guard let raw = s("travelMode"), raw.count <= maxTravelModeChars else { return nil }
            return raw
        }()
        let wrappedStarsRaw: String? = {
            guard let raw = s("wrappedStars"), raw.count <= maxWrappedStarsChars else { return nil }
            return raw
        }()
        // Felület-skin (REST-út): régi docban hiányozhat (nil = helyi marad).
        let skinRaw = s("skin")
        return Payload(updatedAt: updatedAt, updatedAtDate: updatedAtDate,
                       theme: theme, accentHex: accent, sizeKey: sizeKey, skinRaw: skinRaw,
                       photoRaw: photoRaw, photo: photo, photoDecodeFailed: photoDecodeFailed,
                       rounding: rounding, roundingRaw: roundingRaw,
                       exempted: exempted, exemptedRaw: exemptedRaw,
                       completedHw: completedHw, completedHwRaw: completedHwRaw,
                       completedEx: completedEx, completedExRaw: completedExRaw,
                       notifyEnabled: notifyEnabled, liveActivity: liveActivity,
                       examRollover: b("examRollover"),
                       hasWatch: b("hasWatch"),
                       schoolEventsRaw: schoolEventsRaw, schoolEventsShow: b("schoolEventsShow"),
                       schoolEventsURLRaw: schoolEventsURLRaw,
                       customTasksRaw: customTasksRaw,
                       cheatSheetsRaw: cheatSheetsRaw,
                       metaAIKeyRaw: metaAIKeyRaw,
                       travelModeRaw: travelModeRaw,
                       wrappedStarsRaw: wrappedStarsRaw,
                       fieldDates: fieldDates)
    }

    /// Közös alkalmazás pull- és listener-útra: mezőnként csak az újabb
    /// bélyeg ír felül, a helyben piszkos (még fel nem töltött) mezőt a
    /// távoli sosem tapossa el. Sérült fotó-adatnál a helyi kép marad.
    /// - Returns: true, ha legalább egy mező alkalmazva lett.
    @discardableResult
    private func applyRemote(_ p: Payload, theme: ThemeStore, profile: ProfileImageStore, completed: CompletedStore?) -> Bool {
        /// Frissebb-e a távoli mező, mint a helyi: egy fel nem töltött
        /// RÉGI szerkesztés nem blokkolhatja az újabb szervert — csak a
        /// távozónál frissebb helyi szerkesztés tartja meg a mezőt.
        func newer(_ field: SummitSyncField) -> Bool {
            guard let rts = p.fieldDates[field.rawValue] else { return false }
            return SummitSyncKey.remoteWins(
                remoteTs: rts,
                dirtyAt: dirtyTimes[field.rawValue],
                localTs: fieldTimestamps[field.rawValue] ?? .distantPast)
        }
        var applied: [SummitSyncField] = []
        if newer(.theme), let m = AppThemeMode(rawValue: p.theme) {
            theme.mode = m
            applied.append(.theme)
        }
        if newer(.accentHex) {
            theme.accentHex = p.accentHex
            applied.append(.accentHex)
        }
        if newer(.sizeKey) {
            theme.sizeCategoryKey = p.sizeKey
            applied.append(.sizeKey)
        }
        // Felület-skin: `nil` = régi doc, a helyi marad. Ismeretlen
        // érték (jövőbeli skin) szintén nem ír felül.
        if newer(.skin), let raw = p.skinRaw, let s = VisualSkin(rawValue: raw) {
            theme.skin = s
            applied.append(.skin)
        }
        if newer(.photo), !p.photoDecodeFailed {
            let key = profileKey()
            if let img = p.photo { profile.save(image: img, for: key) }
            else { profile.remove(for: key) }
            applied.append(.photo)
        }
        if newer(.rounding) {
            GradingLogic.save(p.rounding)
            applied.append(.rounding)
        }
        if newer(.exempted) {
            ExemptedStore.save(Set(p.exempted))
            applied.append(.exempted)
        }
        if newer(.completedHw) || newer(.completedEx) {
            // A két pipa-lista egy hub-értesítésen osztozik, de csak az
            // újabbik cserélődik — a helyben frissebb lista értéke
            // nem veszhet el egy részleges lehúzásban.
            let hwNew = newer(.completedHw), exNew = newer(.completedEx)
            completed?.replaceAll(
                homework: hwNew ? p.completedHw : Array(completed?.homeworkDone ?? []),
                exams: exNew ? p.completedEx : Array(completed?.examDone ?? []))
            if hwNew { applied.append(.completedHw) }
            if exNew { applied.append(.completedEx) }
        }
        let d = UserDefaults.standard
        if newer(.notifyEnabled) {
            d.set(p.notifyEnabled, forKey: "notify.enabled")
            applied.append(.notifyEnabled)
        }
        if newer(.liveActivity) {
            d.set(p.liveActivity, forKey: "liveActivity.enabled")
            SummitLiveActivityManager.shared.setAppEnabled(p.liveActivity)
            applied.append(.liveActivity)
        }
        // Dolgozat-pótlás kapcsoló: `nil` = régi doc, a helyi marad.
        if newer(.examRollover), let v = p.examRollover {
            d.set(v, forKey: ExamRollover.enabledKey)
            NotificationCenter.default.post(name: ExamRollover.changedNotification, object: nil)
            applied.append(.examRollover)
        }
        // Utazás-intervallum: `nil` = régi doc, a helyi marad. Az
        // alkalmazás maga postolja a változás-értesítést (Beállítások
        // kapcsolója és a widget-tükör így követi).
        if newer(.travelMode), let raw = p.travelModeRaw {
            TravelMode.applySyncString(raw)
            applied.append(.travelMode)
        }
        // Wrapped-csillagok: `nil` nyers mező = régi doc, a helyi marad.
        // Üres `"{}"` = nincs csillag (a másik eszközön levették).
        // Sérült JSON-nál a helyi marad. A saját mentés értesítését itt
        // is eldobjuk (lásd a ciklust lejjebb), mint a többi mezőnél.
        if newer(.wrappedStars), let raw = p.wrappedStarsRaw,
           let stars = WrappedStarStore.decodeSync(raw) {
            WrappedStarStore.replaceAll(stars)
            applied.append(.wrappedStars)
        }
        // Órajelenlét: `nil` = régi doc, a helyi peer-jel marad. `true`
        // érkezésekor a Mac is megmutatja a Watch tabot (jegyzetkészítés
        // Macről is). A mentés @Published-ön át azonnal újrarajzol.
        if newer(.hasWatch), let v = p.hasWatch {
            WatchAvailability.shared.setPeerHasWatch(v)
            applied.append(.hasWatch)
        }
        // Iskolai események: `nil` nyers mező = régi doc, a helyi marad.
        // Üres string = tudatos törlés. Sérült JSON-nál a helyi marad.
        if newer(.schoolEvents), let raw = p.schoolEventsRaw,
           let events = SchoolEventsStore.decodeSync(raw) {
            SchoolEventsStore.replaceAll(events, sourceName: nil)
            applied.append(.schoolEvents)
        }
        if newer(.schoolEventsShow), let show = p.schoolEventsShow {
            SchoolEventsStore.setVisible(show)
            applied.append(.schoolEventsShow)
        }
        // Mentett link: `nil` nyers mező = régi doc, a helyi marad.
        // Üres string = nincs mentett link. A saját mentés értesítése itt
        // is eldobjuk (lásd a ciklust lejjebb), mint a többi mezőnél.
        if newer(.schoolEventsURL), let raw = p.schoolEventsURLRaw {
            SchoolEventsStore.saveURL(raw.isEmpty ? nil : raw)
            applied.append(.schoolEventsURL)
        }
        // Saját feladatok: `nil` nyers mező = régi doc, a helyi marad.
        // Üres string = tudatos törlés. Sérült JSON-nál a helyi marad.
        if newer(.customTasks), let raw = p.customTasksRaw,
           let tasks = CustomTasksStore.decodeSync(raw) {
            CustomTasksStore.replaceAll(tasks)
            applied.append(.customTasks)
        }
        // Tanulójegyzet-lapok: `nil` nyers mező = régi doc, a helyi marad.
        // Üres string = tudatos törlés. Sérült JSON-nál a helyi marad.
        if newer(.cheatSheets), let raw = p.cheatSheetsRaw,
           let sheets = CheatStore.decodeSync(raw) {
            CheatStore.replaceAll(sheets)
            applied.append(.cheatSheets)
        }
        // Meta AI-kulcs: `nil` nyers mező = régi doc, a helyi marad.
        // Üres string = tudatos törlés (a másik eszközön törölték).
        // Üres helyi kulccsal nem írunk felül távoli kulcsot — a még
        // kulcs-nélküli eszköz lehúzása nem törölhet (a push-merge
        // ugyanígy a távoli értéket tartja meg).
        if newer(.metaAIKey), let raw = p.metaAIKeyRaw {
            let clean = String(raw.prefix(Self.maxMetaAIKeyChars))
            if !clean.isEmpty || !MetaAIKeyStore.hasKey {
                if clean != MetaAIKeyStore.apiKey { MetaAIKeyStore.save(clean) }
            }
            applied.append(.metaAIKey)
        }
        guard !applied.isEmpty else { return false }
        for f in applied {
            // A fenti mentések (fotó, kerekítés, felmentés) dirty-értesítést
            // postolnak — azokat itt eldobjuk, hiszen épp a szerverről jöttek.
            // A szerver nyert, így az esetleges elavult helyi jelölés is
            // mehet (a frissebb helyi szerkesztést a `newer` megőrizte volna).
            dirtyFields.remove(f.rawValue)
            dirtyTimes.removeValue(forKey: f.rawValue)
            if let rts = p.fieldDates[f.rawValue] { fieldTimestamps[f.rawValue] = rts }
        }
        persistDirty()
        persistFieldTs()
        if p.updatedAtDate > Self.isoDate(lastApplied) || lastApplied.isEmpty {
            // Üres előzménynél is jegyezzük (kivéve a távoli-jövő védőértéket).
            if p.updatedAtDate < .distantFuture { lastApplied = p.updatedAt }
        }
        suppressPushUntil = Date().addingTimeInterval(10)
        status = "szinkronizálva"
        return true
    }

    // MARK: - Realtime listener + dirty-követés

    private var listener: ListenerRegistration?
    private var liveId: String?
    private var lastToken: String?
    private var liveTheme: ThemeStore?
    private var liveProfile: ProfileImageStore?
    private var liveCompleted: CompletedStore?
    private var liveUserId: String?
    /// A legutóbb képzett v2 kulcsanyag (a jelmondat+fiók ujjlenyomatával).
    private var keyCache: (fingerprint: String, keys: SummitSyncKey.V2Keys)?
    /// Utolsó v1→v2 egyeztetés ideje doc-onként (lásd migrateLegacyIfNeeded).
    private static let legacyCheckKey = "summitsync.legacyCheck.v1"
    /// A futó v1→v2 átállás (legfeljebb egy egyszerre).
    private var migrationTask: Task<Void, Never>?
    private var dirtyTask: Task<Void, Never>?
    private var pushing = false

    /// Store-hivatkozások gyorsítótárazása (push/pull/listener mind innen dolgozik).
    func configure(accessToken: String, theme: ThemeStore, profile: ProfileImageStore, completed: CompletedStore, userId: String?) {
        lastToken = accessToken
        liveTheme = theme
        liveProfile = profile
        liveCompleted = completed
        liveUserId = userId
    }

    private func observeLocalEdits() {
        let map: [(Notification.Name, [SummitSyncField])] = [
            (GradingLogic.changedNotification, [.rounding]),
            (ExemptedStore.changedNotification, [.exempted]),
            (CompletedStore.changedNotification, [.completedHw, .completedEx]),
            (ProfileImageStore.changedNotification, [.photo]),
            // A kapcsolgatást (`schoolEventsShow`) a Beállítások jelöli
            // expliciten — különben minden kapcsolás újra feltöltené a blobot.
            (SchoolEventsStore.changedNotification, [.schoolEvents]),
            // A mentett naptár-linket (kézi felülírás vagy admin-alap) a
            // store postolja minden mentéskor/törléskor.
            (SchoolEventsStore.urlChangedNotification, [.schoolEventsURL]),
            // Saját feladat/dolgozat felvétele, törlése, távoli pull.
            (CustomTasksStore.changedNotification, [.customTasks]),
            // Tanulójegyzet-lap felvétele, szerkesztése, törlése, távoli pull.
            (CheatStore.changedNotification, [.cheatSheets]),
            // Meta AI-kulcs megadása, cseréje, törlése, távoli pull.
            (MetaAIKeyStore.changedNotification, [.metaAIKey]),
            // Utazás-intervallum beállítása, törlése, távoli pull.
            (TravelMode.changedNotification, [.travelMode]),
            // Wrapped-csillag felvétele, levétele, távoli pull.
            (WrappedStarStore.changedNotification, [.wrappedStars]),
        ]
        for (name, fields) in map {
            NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                self?.markDirty(fields)
            }
        }
    }

    /// Helyi szerkesztés után 2 mp-cel feltölt (összevonja a sorozatos
    /// csúszka-pötyögéseket) — a Beállításokban átállított érték így
    /// magától felmegy, nem kell hozzá lehúzás. Csak a megjelölt mezők
    /// mennek fel, a szerkesztés pillanatának bélyegével: a frissebb
    /// szerver így sosem íródik felül egy régebbi helyi szerkesztéssel.
    /// A többi mező a szerverről keveredik vissza. A suppress-ablak a
    /// saját pull-alkalmazás visszhangját szűri.
    func markDirty(_ fields: SummitSyncField...) {
        markDirty(fields)
    }

    func markDirty(_ fields: [SummitSyncField]) {
        guard !fields.isEmpty else { return }
        // A mező értéke a legutóbbi írás, ezért a bélyeg is az:
        // minden jelölés felülírja az előzőt.
        let now = Date()
        for f in fields {
            dirtyFields.insert(f.rawValue)
            dirtyTimes[f.rawValue] = now
        }
        persistDirty()
        dirtyTask?.cancel()
        dirtyTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            guard let self, !Task.isCancelled, self.isEnabled,
                  Date() > self.suppressPushUntil, !self.pushing else { return }
            self.pushing = true
            defer { self.pushing = false }
            _ = await self.pushNow()
        }
    }

    /// Minden mező megjelölése (első feltöltéshez, amikor még nincs doc).
    func markAllDirty() {
        markDirty(SummitSyncField.allCases)
    }

    /// Függő szerkesztések eldobása (bekapcsoláskor, amikor a szerver nyer —
    /// különben egy kikapcsolt állapotban ejtett régi jelölés blokkolná a
    /// lehúzást a saját mezőjén).
    func discardPendingEdits() {
        dirtyFields = []
        dirtyTimes = [:]
        persistDirty()
    }

    /// Firebase-init, ha a GoogleService-Info.plist bekerült a bundle-be.
    /// Nélküle a listener néma marad, a REST push/pull tovább működik.
    /// Az App Check provider-gyár a configure ELŐTT kerül be (különben az
    /// SDK nem használja).
    static func configureIfNeeded() {
        guard FirebaseApp.app() == nil,
              Bundle.main.path(forResource: "GoogleService-Info", ofType: "plist") != nil else { return }
        SummitAppCheck.installProviderFactory()
        FirebaseApp.configure()
    }

    @Published private(set) var realtimeActive = false
    /// Listener él, ha a plist bekerült (különben a REST-út marad).
    var realtimeAvailable: Bool { FirebaseApp.app() != nil }

    /// Csendes frissítés előtérbe hozáskor / Beállítások-megnyitáskor:
    /// előbb a függő helyi szerkesztések mennek fel, aztán jön a lehúzás
    /// (listener ha lehet, különben egyszeri REST-pull).
    func refresh(accessToken: String, theme: ThemeStore, profile: ProfileImageStore, completed: CompletedStore, userId: String?) {
        configure(accessToken: accessToken, theme: theme, profile: profile, completed: completed, userId: userId)
        guard isEnabled else { return }
        // Óra-jelenlét terjesztése: CSAK a helyi `true` jelöl dirty-re
        // (és csak amíg fel nem ment — utána a sent-jelzés blokkol).
        // Az óra nélküli eszköz (pl. a Mac) sosem jelöl, így a telefon
        // `true`-ját sosem írhatja felül `false`-szal.
        if WatchAvailability.shared.hasWatch,
           !(UserDefaults.standard.object(forKey: Self.hasWatchSentKey) as? Bool ?? false) {
            markDirty(.hasWatch)
        }
        Task { [weak self] in await self?.flushThenPull() }
    }

    /// Oda-vissza szinkron egy hívásban: ELŐBB a távoliak lehúzása
    /// (a frissebb szerver akkor is beolvasódik, ha helyben beragadt
    /// egy régi, fel nem töltött jelölés), UTÁNA a megmaradt — tényleg
    /// a szervernél újabb — helyi szerkesztések feltöltése (vagy a
    /// listener életben tartása). Gyógyítja a „lehúztam, de a másik
    /// eszközön semmi" esetet: a 2 mp-es debounce közben megölt app
    /// piszkos mezői a következő előtér/lehúzáskor kipucolódnak.
    /// Mac (Catalyst) REST-úton ugyanezt futtatja, ezért ott is javul.
    func flushThenPull() async {
        guard isEnabled, lastToken != nil, liveTheme != nil else { return }
        if realtimeAvailable {
            startListener()
        } else {
            _ = await pullNow()
        }
        if !dirtyFields.isEmpty {
            status = "feltöltés…"
            _ = await pushNow()
        }
    }

    /// Élő követés indítása/életben tartása. A listener csak az újabb
    /// bélyegű mezőket alkalmazza, így nincs visszhang-hurok.
    /// A kulcsképzés (PBKDF2) aszinkron, ezért a feliratkozás egy Taskban
    /// történik; a hívó szinkron marad.
    func startListener() {
        guard isEnabled, FirebaseApp.app() != nil, liveTheme != nil,
              let at = lastToken, Self.loadPassphrase() != nil else {
            stopListener()
            return
        }
        Task { [weak self] in
            guard let self, let keys = await self.v2Keys(accessToken: at) else {
                self?.stopListener()
                return
            }
            // Közben kikapcsolhatták / kijelentkezhettek / fiókot válthattak.
            guard self.isEnabled, self.lastToken == at else { return }
            guard self.liveId != keys.docId || self.listener == nil else { return }
            await self.migrateLegacyIfNeeded(accessToken: at, keys: keys)
            guard self.isEnabled, self.lastToken == at,
                  self.liveId != keys.docId || self.listener == nil else { return }
            self.stopListener()
            self.liveId = keys.docId
            self.realtimeActive = true
            self.listener = Firestore.firestore().collection(Self.collectionV2).document(keys.docId)
                .addSnapshotListener { [weak self] snap, _ in
                    guard let data = snap?.data() else { return }
                    let raw = Self.restFields(fromSnapshot: data)
                    Task { @MainActor [weak self] in
                        guard let self,
                              let theme = self.liveTheme, let profile = self.liveProfile,
                              self.liveId == keys.docId,
                              let p = Self.parse(fields: SummitSyncKey.openFields(raw, fieldNames: Self.fieldNames, keys: keys))
                        else { return }
                        self.applyRemote(p, theme: theme, profile: profile, completed: self.liveCompleted)
                    }
                }
        }
    }

    /// SDK-snapshot (natív típusok) → REST-alakú mezőtérkép, hogy a
    /// listener és a REST-út ugyanazt a visszafejtést és parse-t használja.
    nonisolated private static func restFields(fromSnapshot data: [String: Any]) -> [String: Any] {
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        iso.timeZone = TimeZone(secondsFromGMT: 0)
        var out: [String: Any] = [:]
        for (k, v) in data {
            if let s = v as? String { out[k] = ["stringValue": s] }
            else if let t = v as? Timestamp { out[k] = ["timestampValue": iso.string(from: t.dateValue())] }
            else if let b = v as? Bool { out[k] = ["booleanValue": b] }
            else if let i = v as? Int64 { out[k] = ["integerValue": String(i)] }
            else if let i = v as? Int { out[k] = ["integerValue": String(i)] }
        }
        return out
    }

    /// Csak a listenert állítja le; a gyorsítótárazott refek maradnak
    /// (a következő start/refresh úgyis felülírja őket).
    func stopListener() {
        listener?.remove()
        listener = nil
        realtimeActive = false
        liveId = nil
    }

    /// Szerver-doc törlése + helyi szinkronállapot nullázása (a jelmondat
    /// a Keychainben marad — újbóli bekapcsolás ugyanoda szinkronizál).
    /// A titkosított (v2) és — ha még fent van — a régi nyílt (v1) doc is törlődik.
    func deleteRemote(accessToken: String) async -> Bool {
        guard let keys = await v2Keys(accessToken: accessToken),
              let url = Self.docURL(collection: Self.collectionV2, id: keys.docId) else { return false }
        do {
            let (_, code) = await Self.send(url, method: "DELETE")
            guard let code else { throw URLError(.notConnectedToInternet) }
            guard code == 200 || code == 404 else {
                status = "törlés hiba"
                return false
            }
            if let legacyId = Self.legacySyncId(accessToken: accessToken),
               let legacyURL = Self.docURL(collection: Self.collectionLegacy, id: legacyId) {
                let (_, legacyCode) = await Self.send(legacyURL, method: "DELETE")
                // 403: a 2. fázis rules-a már a régi collectiont is tiltja.
                guard legacyCode == 200 || legacyCode == 404 || legacyCode == 403 else {
                    status = "törlés hiba"
                    return false
                }
            }
            lastApplied = ""
            fieldTimestamps = [:]
            persistFieldTs()
            dirtyFields = []
            persistDirty()
            isEnabled = false
            status = "törölve"
            return true
        } catch {
            status = "hálózati hiba"
            return false
        }
    }
}
