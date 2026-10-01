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
        // Olvasáskor is normalizálunk (csak nézet): a régi, egybetömbös
        // AI-szövegek így mentés nélkül is tagoltan jelennek meg a
        // telefonon és az órán; a perzisztálást a cap() végzi.
        let sorted = arr.sorted { $0.updatedAt > $1.updatedAt }
        let norm = sorted.map { normalizeTopics($0) }
        // Egyszeri migráció indításonként: ha a tárolt anyag még a régi,
        // tagolatlan alak, visszamentjük — a mentés changed-jelzése
        // tolja az órát (CheatWatchPush) és a syncet is, így a watchra
        // magától átmegy a tagolt szöveg, kézi újramentés nélkül.
        if !migratedThisLaunch {
            migratedThisLaunch = true
            if norm != sorted { save(norm) }
        }
        return norm
    }

    private static var migratedThisLaunch = false

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
            t.body = String(CheatTopic.normalizedBody(String(t.body.prefix(maxBodyChars))).prefix(maxBodyChars))
            return t
        }
        return s
    }

    /// Téma-törzsek normalizálása mentés nélkül (load-nézet + migráció).
    /// Idempotens: az újrafuttatás ugyanazt adja.
    static func normalizeTopics(_ sheet: CheatSheet) -> CheatSheet {
        var s = sheet
        s.topics = s.topics.map {
            var t = $0
            t.body = CheatTopic.normalizedBody(t.body)
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

    // MARK: - Lemez-tár a TELJES anyagokhoz (generáláshoz)
    // A UserDefaults/sync továbbra is vágott szöveget visz (15k —
    // a Firestore-doc és a sync-séma védelme), de a generálás innen
    // olvassa a TELJES szöveget + a pdf/kép binárist. Anyagonként:
    // <id>.txt (full szöveg), <id>.pdf (eredeti pdf), <id>.jpg (kép).
    // Csak ezen az eszközön él (nem szinkronizálódik).
    static func materialDir() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = base.appendingPathComponent("CheatMaterials", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    static func saveFullPayload(id: String, text: String?, pdf: Data?, image: Data?) {
        let dir = materialDir()
        if let t = text, !t.isEmpty { try? t.write(to: dir.appendingPathComponent("\(id).txt"), atomically: true, encoding: .utf8) }
        if let p = pdf { try? p.write(to: dir.appendingPathComponent("\(id).pdf")) }
        if let im = image { try? im.write(to: dir.appendingPathComponent("\(id).jpg")) }
    }

    static func fullText(id: String) -> String? {
        try? String(contentsOf: materialDir().appendingPathComponent("\(id).txt"), encoding: .utf8)
    }

    static func pdfData(id: String) -> Data? {
        try? Data(contentsOf: materialDir().appendingPathComponent("\(id).pdf"))
    }

    static func imageData(id: String) -> Data? {
        try? Data(contentsOf: materialDir().appendingPathComponent("\(id).jpg"))
    }

    static func removePayload(id: String) {
        let dir = materialDir()
        for ext in ["txt", "pdf", "jpg"] {
            try? FileManager.default.removeItem(at: dir.appendingPathComponent("\(id).\(ext)"))
        }
    }
}
