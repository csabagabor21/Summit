import Foundation

/// Wrapped-csillag: melyik hónapra melyik hegykép van rögzítve.
/// Hónap-azonosító (`"2026-10"`) → katalógusnév (`"Matterhorn"`).
/// A csillagozott hónap képe nem forog tovább, ameddig a csillagot
/// le nem veszik. SummitSync-kel átmegy a többi eszközre (lásd
/// `SummitSyncField.wrappedStars`); a megnyitás-számláló viszont
/// eszköz-helyi (nem szinkronizálódik).
enum WrappedStarStore {
    static let starsKey = "wrapped.stars.v1"
    /// Megnyitás-számláló (hónap → hanyadszor nyitották): ebből forog a
    /// kép minden megnyitásra — szerverre sosem megy, csak ezen az eszközön él.
    static let opensKey = "wrapped.opens.v1"
    static let changedNotification = Notification.Name("summit.wrappedStarsChanged")
    /// Ennyi rögzítés utazik a sync docban (havi 1-gyel számolva 3 év).
    static let maxEntries = 36
    static let maxSyncChars = 4_000

    static func loadStars() -> [String: String] {
        guard let data = UserDefaults.standard.data(forKey: starsKey),
              let raw = try? JSONDecoder().decode([String: String].self, from: data) else { return [:] }
        return sanitize(raw)
    }

    static func starredArt(monthId: String) -> String? {
        loadStars()[monthId]
    }

    /// Csillag fel/le. Mindig postol — a SummitSync visszhang-védelme
    /// (suppress + dirty-takarítás) mellé ez ébreszti az UI-t.
    static func setStar(monthId: String, artName: String?) {
        var stars = loadStars()
        if let artName, !artName.isEmpty {
            stars[monthId] = artName
        } else {
            stars.removeValue(forKey: monthId)
        }
        save(stars)
        NotificationCenter.default.post(name: changedNotification, object: nil)
    }

    /// Teljes csere távoli pullból. Mindig postol (a hívó `newer`-rel
    /// szűrt — lásd `SummitSync.applyRemote`).
    static func replaceAll(_ stars: [String: String]) {
        save(stars)
        NotificationCenter.default.post(name: changedNotification, object: nil)
    }

    private static func save(_ stars: [String: String]) {
        let capped = Dictionary(uniqueKeysWithValues: Array(sanitize(stars).prefix(maxEntries)))
        if let data = try? JSONEncoder().encode(capped) {
            UserDefaults.standard.set(data, forKey: starsKey)
        }
    }

    /// Alak-szűrés: rövid kulcs/érték, különben dobva (sérült adat ellen).
    static func sanitize(_ raw: [String: String]) -> [String: String] {
        var out: [String: String] = [:]
        for (k, v) in raw {
            let key = k.trimmingCharacters(in: .whitespacesAndNewlines)
            let val = v.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !key.isEmpty, key.count <= 16, !val.isEmpty, val.count <= 40 else { continue }
            out[key] = val
            if out.count >= maxEntries { break }
        }
        return out
    }

    /// Kompakt JSON a sync docba. Üres rögzítés = `"{}"` (a csillag-levétel is terjed).
    static func syncString(_ stars: [String: String]) -> String {
        let capped = Dictionary(uniqueKeysWithValues: Array(sanitize(stars).prefix(maxEntries)))
        guard let data = try? JSONEncoder().encode(capped),
              let s = String(data: data, encoding: .utf8),
              s.count <= maxSyncChars else { return "{}" }
        return s
    }

    /// Üres string = üres rögzítés; érvénytelen JSON = nil (a helyi marad).
    static func decodeSync(_ s: String) -> [String: String]? {
        if s.isEmpty { return [:] }
        guard s.count <= maxSyncChars,
              let data = s.data(using: .utf8),
              let raw = try? JSONDecoder().decode([String: String].self, from: data) else { return nil }
        return sanitize(raw)
    }

    // MARK: - Megnyitás-számláló (csak ezen az eszközön)

    static func openCount(monthId: String) -> Int {
        guard let data = UserDefaults.standard.data(forKey: opensKey),
              let raw = try? JSONDecoder().decode([String: Int].self, from: data) else { return 0 }
        return max(0, raw[monthId] ?? 0)
    }

    /// Következő megnyitásra lép — NEM postol (ez nem szinkron-adat,
    /// az UI-t sem kell ébresztenie).
    static func bumpOpen(monthId: String) {
        var raw: [String: Int] = [:]
        if let data = UserDefaults.standard.data(forKey: opensKey),
           let loaded = try? JSONDecoder().decode([String: Int].self, from: data) {
            raw = loaded
        }
        raw[monthId] = ((raw[monthId] ?? 0) + 1) % 1_000_000
        if raw.count > 48 {
            raw = Dictionary(uniqueKeysWithValues: raw.sorted { $0.value > $1.value }.prefix(48).map { ($0.key, $0.value) })
        }
        if let data = try? JSONEncoder().encode(raw) {
            UserDefaults.standard.set(data, forKey: opensKey)
        }
    }
}
