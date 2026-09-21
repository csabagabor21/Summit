import Foundation

/// Admin iskolai naptár-adatbázis (`school_calendars` Firestore-collection,
/// publikus olvasás — lásd `Firebase/firestore.rules`).
///
/// Belépéskor az app az institut-kód alapján megnézi, van-e az iskolához
/// admin által megadott naptár-link, és ha igen, automatikusan letölti.
/// Szabályok (a user kérése):
/// - az admin-link az ALAPÉRTELMEZETT forrás;
/// - ha az adminban nincs bejegyzés, marad a kézi felülírás (link / szöveg
///   / .ics), ami a SummitSync-kel átmegy a többi eszközre is;
/// - akinek már van kézi beállítása (esemény vagy mentett link), annál az
///   admin sosem ír felül — a kézi nyer.
enum SchoolCalendarDirectory {
    /// Egy admin-bejegyzés: a suli naptár-linkje + megjelenő neve.
    struct Entry: Equatable {
        var calendarURL: String
        var name: String?
    }

    /// Feloldás végeredménye (UI-üzenethez és naplózáshoz).
    enum ResolveResult: Equatable {
        case skipped          // nincs használható institut-kód (demo/unknown)
        case keptManual       // van kézi beállítás — az admin nem nyúl hozzá
        case noEntry          // az adminban nincs ilyen iskola — jöhet a kézi
        case badLink          // az admin-linkből nem lesz letöltés
        case empty            // letöltve, de nincs benne felismerhető esemény
        case applied(Int)     // ennyi esemény jött le az admin-linkről
    }

    private static let projectId = "summit-14b74"
    private static let apiKey = "AIzaSyA1TttM0aUUHsvjjAItYMbdID_no1vzg9s"

    /// Institut-kód → admin doc-ID: kisbetű, trim, host-formából prefix
    /// (`xy.e-kreta.hu` → `xy`). `nil` = nincs értelmes kód (demo, unknown,
    /// üres) — ilyenkor az adminhoz nem nyúlunk.
    static func key(forInstituteCode code: String?) -> String? {
        guard var t = code?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
              !t.isEmpty, t.count <= 64,
              t != "demo", t != "unknown" else { return nil }
        if let dot = t.firstIndex(of: ".") {
            t = String(t[..<dot])
        }
        guard !t.isEmpty else { return nil }
        let ok = t.allSatisfy { $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" }
        guard ok else { return nil }
        return t
    }

    /// Admin-bejegyzés lekérése (publikus doc, auth nélkül — a rules engedi).
    /// `nil` = nincs bejegyzés vagy hálózati hiba (a hívó ilyenkor a kézi
    /// útra esik vissza — nincs hibaüzenet, ez a normál eset).
    static func fetchEntry(instituteCode: String) async -> Entry? {
        guard let key = key(forInstituteCode: instituteCode),
              let url = URL(string: "https://firestore.googleapis.com/v1/projects/\(projectId)/databases/(default)/documents/school_calendars/\(key)?key=\(apiKey)") else {
            return nil
        }
        do {
            let (data, resp) = try await URLSession.shared.data(from: url)
            guard (resp as? HTTPURLResponse)?.statusCode == 200,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let fields = json["fields"] as? [String: Any],
                  let link = (fields["calendarUrl"] as? [String: String])?["stringValue"],
                  !link.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  link.count <= 2000 else { return nil }
            let name = (fields["name"] as? [String: String])?["stringValue"]
            return Entry(calendarURL: link, name: name)
        } catch {
            return nil
        }
    }

    /// Belépés (vagy Beállítások-megnyitás) utáni feloldás: ha az eszközön
    /// nincs kézi beállítás és az adminban van bejegyzés, letölti a naptárat,
    /// menti a linket (frissítéshez + szinkronhoz) — a store-értesítéseken
    /// át a SummitSync magától felviszi a többi eszközre.
    @MainActor
    static func resolveAfterLogin(instituteCode: String?) async -> ResolveResult {
        guard let code = instituteCode, key(forInstituteCode: code) != nil else {
            return .skipped
        }
        // Kézi beállítás nyer: eseménylista vagy mentett link már van.
        if !SchoolEventsStore.load().isEmpty || SchoolEventsStore.savedURL() != nil {
            return .keptManual
        }
        guard let entry = await fetchEntry(instituteCode: code) else {
            return .noEntry
        }
        guard let url = SchoolEventsStore.directDownloadURL(fromLink: entry.calendarURL) else {
            return .badLink
        }
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            guard let text = SchoolEventsStore.decodeData(data),
                  !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                return .empty
            }
            let parsed = SchoolEventsStore.parseAny(text)
            guard !parsed.isEmpty else { return .empty }
            SchoolEventsStore.replaceAll(parsed, sourceName: entry.name ?? url.host ?? "iskolai naptár")
            SchoolEventsStore.saveURL(entry.calendarURL.trimmingCharacters(in: .whitespacesAndNewlines))
            return .applied(parsed.count)
        } catch {
            return .empty
        }
    }
}
