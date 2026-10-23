import Foundation

// MARK: - Óra-változás felismerés (helyettesítés, elmaradás, áthelyezés, teremcsere, új óra)
//
// Az órarend évente egyszer áll össze — ami közben változik, az a lényeg:
// helyettesítés, elmaradó óra, teremcsere. A háttér-frissítés minden heti
// lehúzáskor a mentett példányhoz hasonlítja az új hetet (ma → +14 nap), és
// a változott óra kis jelölést kap, amíg a user meg nem látta; a következő
// ~2 nap változásairól helyi értesítés is megy (NotificationManager, a
// látott-készlettel duplázás nélkül).

/// Egy felismert változás egy órán.
struct LessonChange: Codable, Hashable, Sendable, Identifiable {
    enum Kind: String, Codable, Sendable {
        /// Az óra elmarad (eddig megtartott volt).
        case cancelled
        /// Helyettesítés lett / másik helyettes.
        case substituted
        /// Más időpontra került (azonos óra).
        case moved
        /// Teremváltozás.
        case room
        /// Új óra (eddig nem volt ezen a helyen).
        case added
        /// Egyéb módosulás (más tárgy ugyanazon a helyen, visszaállított óra).
        case changed
    }

    var lessonId: String
    var kind: Kind
    var subject: String
    var index: String
    var start: Date
    /// Rövid „régi → új" leírás a részletezőhöz (pl. „12 → 14").
    var detail: String
    var detectedAt: Date

    var id: String { lessonId }

    /// Duplázás-kulcs az értesítéshez: ugyanaz a változás ugyanarra az órára
    /// (időpont, terem, tanár szerint) csak egyszer jelez.
    var notificationKey: String {
        "\(lessonId)|\(kind.rawValue)|\(Int(start.timeIntervalSince1970))|\(detail)"
    }

    /// A sor-jelölés felirata. Az elmaradást / helyettesítést a sor saját
    /// jelvénye már kiírja — ott a jelölés csak annyit mond: „új".
    var markerTitle: String {
        switch kind {
        case .cancelled, .substituted: return "Új"
        case .moved: return "Áthelyezve"
        case .room: return "Teremcsere"
        case .added: return "Új óra"
        case .changed: return "Módosult"
        }
    }

    /// Értesítés-sor (rövid): „Fizika elmarad", „Matek: teremcsere (12 → 14)".
    var summary: String {
        switch kind {
        case .cancelled: return "\(subject) elmarad"
        case .substituted: return "\(subject): helyettesítés (\(detail))"
        case .moved: return "\(subject): áthelyezve (\(detail))"
        case .room: return "\(subject): teremcsere (\(detail))"
        case .added: return "\(subject): új óra"
        case .changed: return "\(subject): módosult (\(detail))"
        }
    }
}

enum LessonChangeDetector {
    /// Ennyi napra előre figyelünk változást (ma → +14 nap).
    static let horizonDays = 15
    /// Értesítés csak a közeli (ma + 2 nap) változásokról.
    static let notifyDays = 3

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "hu_HU")
        f.dateFormat = "H:mm"
        return f
    }()
    private static let dayTimeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "hu_HU")
        f.dateFormat = "EEE H:mm"
        return f
    }()

    /// Régi (mentett) és új (friss) heti órák összevetése. Csak a ma → +14
    /// napos ablak órái számítanak; az első lehúzás (nincs régi példány)
    /// sosem ad változást.
    static func diff(old: [LessonItem], new: [LessonItem], now: Date = Date(), calendar: Calendar = .current) -> [LessonChange] {
        let today = calendar.startOfDay(for: now)
        guard let horizon = calendar.date(byAdding: .day, value: horizonDays, to: today) else { return [] }
        func inWindow(_ l: LessonItem) -> Bool { l.start >= today && l.start < horizon }
        let oldById = Dictionary(old.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        let newIds = Set(new.map(\.id))
        // Azonosító nélküli párosításhoz: régi óra nap + óraszám szerint
        // (a KRÉTA átrendezéskor új Uid-t adhat ugyanannak a helynek).
        var oldBySlot: [String: LessonItem] = [:]
        for l in old where !newIds.contains(l.id) {
            oldBySlot[slotKey(l, calendar: calendar)] = l
        }
        var out: [LessonChange] = []
        for n in new where inWindow(n) {
            let o = oldById[n.id] ?? oldBySlot[slotKey(n, calendar: calendar)]
            guard let o else {
                // Teljesen új óra (nem volt ezen a helyen semmi).
                out.append(change(.added, n, detail: timeFormatter.string(from: n.start), now: now))
                continue
            }
            if let c = compare(old: o, new: n, now: now, calendar: calendar) { out.append(c) }
        }
        return out
    }

    private static func slotKey(_ l: LessonItem, calendar: Calendar) -> String {
        let d = calendar.startOfDay(for: l.start).timeIntervalSince1970
        // Számozatlan órán ("-") az időpont a hely.
        let idx = Int(l.index) != nil ? l.index : "t\(Int(l.start.timeIntervalSince1970))"
        return "\(Int(d))|\(idx)"
    }

    private static func compare(old o: LessonItem, new n: LessonItem, now: Date, calendar: Calendar) -> LessonChange? {
        if !SubjectMatcher.same(o.subject, n.subject) {
            return change(.changed, n, detail: "\(o.subject) → \(n.subject)", now: now)
        }
        if !o.isCancelled && n.isCancelled {
            return change(.cancelled, n, detail: "Elmarad", now: now)
        }
        if o.isCancelled && !n.isCancelled {
            return change(.changed, n, detail: "Elmarad → megtartva", now: now)
        }
        if !n.isCancelled && n.isSubstituted && (!o.isSubstituted || o.teacher != n.teacher) {
            return change(.substituted, n, detail: n.teacher.isEmpty ? "Helyettesítés" : n.teacher, now: now)
        }
        if o.start != n.start {
            let sameDay = calendar.isDate(o.start, inSameDayAs: n.start)
            let f = sameDay ? timeFormatter : dayTimeFormatter
            return change(.moved, n, detail: "\(f.string(from: o.start)) → \(f.string(from: n.start))", now: now)
        }
        if o.room != n.room, !n.isCancelled {
            return change(.room, n, detail: "\(o.room) → \(n.room)", now: now)
        }
        return nil
    }

    private static func change(_ kind: LessonChange.Kind, _ l: LessonItem, detail: String, now: Date) -> LessonChange {
        LessonChange(lessonId: l.id, kind: kind, subject: l.subject, index: l.index,
                     start: l.start, detail: detail, detectedAt: now)
    }

    /// Értesítésre érdemes-e (a közeli napokra esik, és még nem kezdődött el).
    static func isNotifiable(_ c: LessonChange, now: Date = Date(), calendar: Calendar = .current) -> Bool {
        let today = calendar.startOfDay(for: now)
        guard let limit = calendar.date(byAdding: .day, value: notifyDays, to: today) else { return false }
        return c.start >= now && c.start < limit
    }
}
