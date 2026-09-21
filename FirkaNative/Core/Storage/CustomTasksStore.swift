import Foundation

/// Saját feladat / dolgozat: a user veszi fel kézzel a Feladatok tabon,
/// nem a KRÉTA adja. Csak a meglévő (Jegyeknél is látható) tantárgyak
/// közül választhat — szabad szöveges, "random" tárgy nincs.
/// Perzisztencia: UserDefaults (JSON), a SummitSync viszi eszközök között.
enum CustomTaskKind: String, Codable, CaseIterable {
    case homework
    case exam
}

struct CustomTask: Codable, Identifiable, Hashable {
    /// Mindig `custom-` előtaggal — így dönti el a UI, hogy törölhető-e,
    /// és a CompletedStore-pipák sem ütköznek KRÉTA-azonosítókkal.
    var id: String
    var kind: CustomTaskKind
    /// Pontosan egy meglévő tantárgynév (a felvevő sheet csak ilyet enged).
    var subject: String
    /// Házi szövege / dolgozat megnevezése (pl. "Témazáró – Egyenletek").
    var title: String
    /// Határidő (házi) / időpont (dolgozat) — nap + óra egyben.
    var date: Date
    var createdAt: Date

    init(id: String = "custom-" + UUID().uuidString,
         kind: CustomTaskKind, subject: String, title: String,
         date: Date, createdAt: Date = Date()) {
        self.id = id
        self.kind = kind
        self.subject = subject
        self.title = title
        self.date = date
        self.createdAt = createdAt
    }
}

enum CustomTasksStore {
    static let listKey = "summit.customTasks.v1"
    static let changedNotification = Notification.Name("summit.customTasksChanged")
    /// Ennyi saját tétel / karakter utazik a sync docban (a Firestore
    /// 1 MiB-es doc-limittől és a rules 48 000-es plafonjától messze van).
    static let maxSyncedTasks = 200
    static let maxSyncChars = 48_000
    static let maxTitleChars = 500

    static func isCustomId(_ id: String) -> Bool { id.hasPrefix("custom-") }

    static func load() -> [CustomTask] {
        guard let data = UserDefaults.standard.data(forKey: listKey),
              let arr = try? JSONDecoder().decode([CustomTask].self, from: data) else { return [] }
        return arr.sorted { $0.date < $1.date }
    }

    static func add(kind: CustomTaskKind, subject: String, title: String, date: Date) {
        let subject = subject.trimmingCharacters(in: .whitespacesAndNewlines)
        let title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !subject.isEmpty, !title.isEmpty else { return }
        var all = load()
        all.append(CustomTask(kind: kind, subject: String(subject.prefix(120)),
                              title: String(title.prefix(maxTitleChars)), date: date))
        save(all)
    }

    static func remove(id: String) {
        save(load().filter { $0.id != id })
    }

    /// Teljes csere (távoli pull). Mindig postol — a SummitSync
    /// visszhang-védelme (suppress + dirty-takarítás) mellé ez ébreszti az UI-t.
    static func replaceAll(_ tasks: [CustomTask]) {
        save(Array(tasks.prefix(maxSyncedTasks)))
    }

    private static func save(_ tasks: [CustomTask]) {
        if let data = try? JSONEncoder().encode(Array(tasks.prefix(maxSyncedTasks))) {
            UserDefaults.standard.set(data, forKey: listKey)
        }
        NotificationCenter.default.post(name: changedNotification, object: nil)
    }

    // MARK: - Megjelenítés (KRÉTA-itemekké alakítva)

    static func homeworkItems(from tasks: [CustomTask]? = nil) -> [HomeworkItem] {
        (tasks ?? load()).filter { $0.kind == .homework }.map {
            HomeworkItem(id: $0.id, subject: $0.subject, title: $0.title,
                         deadline: $0.date, teacher: "", isDone: false)
        }
    }

    static func examItems(from tasks: [CustomTask]? = nil) -> [ExamItem] {
        (tasks ?? load()).filter { $0.kind == .exam }.map {
            ExamItem(id: $0.id, subject: $0.subject, date: $0.date,
                     mode: $0.title, description: "")
        }
    }

    // MARK: - Szinkron-hub (SummitSync) számára

    /// Kompakt JSON a sync docba. Üres lista = `"[]"` (a törlés is terjed;
    /// a még sosem írt mező a docban hiányzik = nil).
    static func syncString(_ tasks: [CustomTask]) -> String {
        let capped = Array(tasks.prefix(maxSyncedTasks))
        guard !capped.isEmpty,
              let data = try? JSONEncoder().encode(capped),
              let s = String(data: data, encoding: .utf8),
              s.count <= maxSyncChars else { return "[]" }
        return s
    }

    /// Üres string = tudatos törlés (`[]`); érvénytelen JSON = nil (a helyi marad).
    static func decodeSync(_ s: String) -> [CustomTask]? {
        if s.isEmpty { return [] }
        guard s.count <= maxSyncChars,
              let data = s.data(using: .utf8),
              var arr = try? JSONDecoder().decode([CustomTask].self, from: data) else { return nil }
        arr = arr.filter {
            $0.id.hasPrefix("custom-") && !$0.subject.isEmpty && $0.subject.count <= 120
            && !$0.title.isEmpty && $0.title.count <= maxTitleChars
        }
        return Array(arr.prefix(maxSyncedTasks))
    }
}
