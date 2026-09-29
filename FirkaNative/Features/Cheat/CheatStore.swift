import Foundation

// MARK: - CheatStore — tanulójegyzet-lapok tára
// Perzisztencia: UserDefaults (JSON), a SummitSync viszi eszközök között
// (CustomTasksStore-minta). Minden írás postol — a SummitSync erre
// jelöli piszkosnak a `cheatSheets` mezőt, a Watch-push pedig az órára
// tolja a pillanatképet. Az API-kulcs NEM itt él (lásd MetaAIKeyStore) —
// belépési adathoz hasonlóan sosem szinkronizálunk ilyet.
enum CheatStore {
    static let listKey = "summit.cheatSheets.v1"
    static let changedNotification = Notification.Name("summit.cheatSheetsChanged")
    /// Ennyi lap / anyag / karakter utazik a sync docban (a Firestore
    /// 1 MiB-es doc-limittől és a rules 100 000-es plafonjától messze van).
    static let maxSheets = 100
    static let maxMaterialsPerSheet = 20
    static let maxMaterialChars = 15_000
    static let maxTitleChars = 200
    static let maxBodyChars = 20_000
    static let maxSyncChars = 100_000

    static func load() -> [CheatSheet] {
        guard let data = UserDefaults.standard.data(forKey: listKey),
              let arr = try? JSONDecoder().decode([CheatSheet].self, from: data) else { return [] }
        return arr.sorted { $0.updatedAt > $1.updatedAt }
    }

    static func save(_ sheets: [CheatSheet]) {
        let capped = Array(sheets.prefix(maxSheets)).map { cap($0) }
        if let data = try? JSONEncoder().encode(capped) {
            UserDefaults.standard.set(data, forKey: listKey)
        }
        NotificationCenter.default.post(name: changedNotification, object: nil)
    }

    static func upsert(_ sheet: CheatSheet) {
        var all = load()
        var s = cap(sheet)
        s.updatedAt = Date()
        if let i = all.firstIndex(where: { $0.id == s.id }) { all[i] = s }
        else { all.append(s) }
        save(all)
    }

    static func remove(id: String) {
        save(load().filter { $0.id != id })
    }

    /// Teljes csere (távoli pull). Mindig postol — a SummitSync
    /// visszhang-védelme (suppress + dirty-takarítás) mellé ez ébreszti az UI-t.
    static func replaceAll(_ sheets: [CheatSheet]) {
        save(Array(sheets.prefix(maxSheets)))
    }

    /// Méretkorlátok egy lapon: anyag-szöveg és jegyzet-törzs vágása.
    /// A vágás a tároláskor történik, hogy a sync doc sose nőjön túl.
    static func cap(_ sheet: CheatSheet) -> CheatSheet {
        var s = sheet
        s.title = String(s.title.prefix(maxTitleChars))
        s.subject = String(s.subject.prefix(120))
        s.materials = Array(s.materials.prefix(maxMaterialsPerSheet)).map {
            var m = $0
            m.name = String(m.name.prefix(120))
            m.text = String(m.text.prefix(maxMaterialChars))
            return m
        }
        s.topics = s.topics.map {
            var t = $0
            t.title = String(t.title.prefix(maxTitleChars))
            t.body = String(t.body.prefix(maxBodyChars))
            return t
        }
        return s
    }

    // MARK: - Szinkron-hub (SummitSync) számára

    /// Kompakt JSON a sync docba. Üres lista = `"[]"` (a törlés is terjed;
    /// a még sosem írt mező a docban hiányzik = nil).
    static func syncString(_ sheets: [CheatSheet]) -> String {
        let capped = Array(sheets.prefix(maxSheets)).map { cap($0) }
        guard !capped.isEmpty,
              let data = try? JSONEncoder().encode(capped),
              let s = String(data: data, encoding: .utf8),
              s.count <= maxSyncChars else { return "[]" }
        return s
    }

    /// Üres string = tudatos törlés (`[]`); érvénytelen JSON = nil (a helyi marad).
    static func decodeSync(_ s: String) -> [CheatSheet]? {
        if s.isEmpty { return [] }
        guard s.count <= maxSyncChars,
              let data = s.data(using: .utf8),
              let arr = try? JSONDecoder().decode([CheatSheet].self, from: data) else { return nil }
        return arr.map { cap($0) }
    }
}
