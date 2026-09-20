import Foundation

/// Iskolai események (tannaptár) — egyszeri ICS-import, utána a SummitSync
/// viszi minden eszközre. A nyers ICS nem utazik: csak a tisztított,
/// kompakt JSON (`syncString`), max 500 esemény / 48 000 kar.
/// A mutatás-kapcsoló (`showKey`, alapból BE) külön bool mezőként
/// szinkronizálódik, hogy egy kapcsolgatás ne küldje újra a blobot.
enum SchoolEventsStore {
    static let listKey = "schoolevents.list.v1"
    static let showKey = "schoolevents.show.v1"
    static let sourceKey = "schoolevents.source.v1"
    static let changedNotification = Notification.Name("summit.schoolEventsChanged")

    /// Ennyi esemény / karakter utazik a sync docban (a Firestore 1 MiB-es
    /// doc-limittől és a rules 50 000-es plafonjától messze van).
    static let maxSyncedEvents = 500
    static let maxSyncChars = 48_000

    static func load() -> [SchoolEvent] {
        guard let data = UserDefaults.standard.data(forKey: listKey),
              let arr = try? JSONDecoder().decode([SchoolEvent].self, from: data) else { return [] }
        return arr
    }

    static func isVisible() -> Bool {
        UserDefaults.standard.object(forKey: showKey) as? Bool ?? true
    }

    static func sourceName() -> String? {
        UserDefaults.standard.string(forKey: sourceKey)
    }

    /// Teljes csere (import vagy távoli pull). Mindig postol — a SummitSync
    /// visszhang-védelme (suppress + dirty-takarítás) mellé ez ébreszti az UI-t.
    static func replaceAll(_ events: [SchoolEvent], sourceName: String?) {
        let capped = Array(events.prefix(maxSyncedEvents))
        if let data = try? JSONEncoder().encode(capped) {
            UserDefaults.standard.set(data, forKey: listKey)
        }
        if let sourceName {
            UserDefaults.standard.set(sourceName, forKey: sourceKey)
        } else {
            UserDefaults.standard.removeObject(forKey: sourceKey)
        }
        NotificationCenter.default.post(name: changedNotification, object: nil)
    }

    /// Kapcsoló — NEM postol (a hívó jelöli dirty-nek a `schoolEventsShow`
    /// mezőt; az órarend `@AppStorage`-dzsel követi).
    static func setVisible(_ on: Bool) {
        UserDefaults.standard.set(on, forKey: showKey)
    }

    static func removeAll() {
        UserDefaults.standard.removeObject(forKey: listKey)
        UserDefaults.standard.removeObject(forKey: sourceKey)
        NotificationCenter.default.post(name: changedNotification, object: nil)
    }

    /// Adott naptári nap eseményei, idő szerint (egész napos elöl).
    static func events(on day: Date, from all: [SchoolEvent]) -> [SchoolEvent] {
        let key = Self.dayKey(day)
        return all.filter { $0.day == key }.sorted {
            if $0.allDay != $1.allDay { return $0.allDay && !$1.allDay }
            if $0.start != $1.start { return $0.start < $1.start }
            return $0.title < $1.title
        }
    }

    static func dayKey(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: date)
    }

    // MARK: - Szinkron-hub (SummitSync) számára

    /// Kompakt JSON a sync docba. `nil` sosem lehet (üres lista = `"[]"` —
    /// a törlés is terjed; a még sosem írt mező a docban hiányzik = nil).
    static func syncString(_ events: [SchoolEvent]) -> String {
        let capped = Array(events.prefix(maxSyncedEvents))
        guard !capped.isEmpty,
              let data = try? JSONEncoder().encode(capped),
              let s = String(data: data, encoding: .utf8),
              s.count <= maxSyncChars else { return "[]" }
        return s
    }

    /// Üres string = tudatos törlés (`[]`); érvénytelen JSON = nil (a helyi marad).
    static func decodeSync(_ s: String) -> [SchoolEvent]? {
        if s.isEmpty { return [] }
        guard s.count <= maxSyncChars,
              let data = s.data(using: .utf8),
              var arr = try? JSONDecoder().decode([SchoolEvent].self, from: data) else { return nil }
        arr = arr.filter { !$0.day.isEmpty && !$0.title.isEmpty }
        return Array(arr.prefix(maxSyncedEvents))
    }
}

/// Egy napi bontású iskolai esemény. Többnapos egész napos ICS-esemény
/// napokra bontva érkezik (egy `SchoolEvent` = egy nap).
struct SchoolEvent: Codable, Equatable, Identifiable {
    var day: String      // yyyy-MM-dd
    var title: String
    var location: String // "" ha nincs
    var allDay: Bool
    var start: String    // "HH:mm" vagy ""
    var end: String

    enum CodingKeys: String, CodingKey {
        case day = "d", title = "t", location = "loc", allDay = "all", start = "s", end = "e"
    }

    var id: String { "\(day)|\(start)|\(end)|\(title)|\(location)" }

    /// Kártya-alcím: "8:00 – 9:00 • Aula" / "Egész nap • Kirándulás" / "".
    var subtitle: String {
        var parts: [String] = []
        if !allDay, !start.isEmpty {
            parts.append(end.isEmpty ? start : "\(start) – \(end)")
        } else if location.isEmpty {
            parts.append("Egész nap")
        }
        if !location.isEmpty { parts.append(location) }
        return parts.joined(separator: " • ")
    }
}

/// Minimál ICS-olvasó (RFC 5545 részhalmaz): VEVENT / DTSTART / DTEND /
/// SUMMARY / LOCATION. RRULE-t nem fejt (az első előfordulás látszik),
/// időzónát TZID nélkül lebegőként, `Z`-vel UTC-ként értelmez.
enum SchoolEventsICS {
    static func parse(_ text: String, maxCount: Int = SchoolEventsStore.maxSyncedEvents) -> [SchoolEvent] {
        // Sor-összehajtás: szóközzel/tabulátorral kezdődő sor az előző folytatása.
        var lines: [String] = []
        for raw in text.components(separatedBy: "\n") {
            let line = raw.hasSuffix("\r") ? String(raw.dropLast()) : raw
            if line.hasPrefix(" ") || line.hasPrefix("\t"), !lines.isEmpty {
                lines[lines.count - 1] += String(line.dropFirst())
            } else {
                lines.append(line)
            }
        }
        var out: [SchoolEvent] = []
        var inEvent = false
        var props: [(name: String, params: String, value: String)] = []
        func flush() {
            if inEvent { out.append(contentsOf: buildEvent(props)) }
            inEvent = false
            props = []
        }
        for line in lines {
            if line == "BEGIN:VEVENT" { flush(); inEvent = true; continue }
            if line == "END:VEVENT" { flush(); continue }
            guard inEvent, let colon = line.firstIndex(of: ":") else { continue }
            let head = String(line[..<colon])
            let value = String(line[line.index(after: colon)...])
            let parts = head.split(separator: ";", maxSplits: 1)
            let name = String(parts[0])
            let params = parts.count > 1 ? String(parts[1]).uppercased() : ""
            if name == "DTSTART" || name == "DTEND" || name == "SUMMARY" || name == "LOCATION" {
                props.append((name, params, value))
            }
        }
        flush()
        // Rendezés + duplátlanítás + sapka.
        var seen = Set<String>()
        let clean = out.filter { seen.insert($0.id).inserted }
        return Array(clean.sorted {
            if $0.day != $1.day { return $0.day < $1.day }
            if $0.start != $1.start { return $0.start < $1.start }
            return $0.title < $1.title
        }.prefix(maxCount))
    }

    private static func buildEvent(_ props: [(name: String, params: String, value: String)]) -> [SchoolEvent] {
        func first(_ n: String) -> (params: String, value: String)? {
            props.first(where: { $0.name == n }).map { ($0.params, $0.value) }
        }
        guard let ds = first("DTSTART"), let start = parseDate(ds.value) else { return [] }
        let title: String = {
            let raw = first("SUMMARY")?.value ?? ""
            let t = unescape(raw).trimmingCharacters(in: .whitespacesAndNewlines)
            return String(t.prefix(140)).isEmpty ? "Iskolai esemény" : String(t.prefix(140))
        }()
        let location: String = {
            let raw = first("LOCATION")?.value ?? ""
            return String(unescape(raw).trimmingCharacters(in: .whitespacesAndNewlines).prefix(120))
        }()
        if start.allDay {
            // Többnapos: DTEND (exkluzív) napokra bontva, naponta max 14 nap.
            if let de = first("DTEND"), let end = parseDate(de.value), end.day > start.day {
                var days: [String] = []
                var cur = start.day
                while cur < end.day, days.count < 14 {
                    days.append(cur)
                    cur = nextDay(cur)
                }
                return days.map { SchoolEvent(day: $0, title: title, location: location, allDay: true, start: "", end: "") }
            }
            return [SchoolEvent(day: start.day, title: title, location: location, allDay: true, start: "", end: "")]
        }
        let end: String = {
            guard let de = first("DTEND"), let e = parseDate(de.value), !e.allDay, e.day == start.day else { return "" }
            return e.time
        }()
        return [SchoolEvent(day: start.day, title: title, location: location, allDay: false, start: start.time, end: end)]
    }

    private struct ParsedDate { var day: String; var time: String; var allDay: Bool }

    private static func parseDate(_ v: String) -> ParsedDate? {
        let s = v.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.range(of: #"^\d{8}$"#, options: .regularExpression) != nil {
            guard let d = ymd(s) else { return nil }
            return ParsedDate(day: d, time: "", allDay: true)
        }
        // YYYYMMDDTHHMMSS[Z] — másodperc nélkül is elfogadva.
        guard s.count >= 13, s.contains("T"),
              let t = s.firstIndex(of: "T") else { return nil }
        let datePart = String(s[..<t])
        var timePart = String(s[s.index(after: t)...])
        let isUTC = timePart.hasSuffix("Z")
        if isUTC { timePart.removeLast() }
        guard let day8 = ymd(datePart),
              timePart.count >= 4,
              let hh = Int(timePart.prefix(2)), let mm = Int(timePart.dropFirst(2).prefix(2)),
              (0...23).contains(hh), (0...59).contains(mm) else { return nil }
        if isUTC {
            // UTC → helyi idő (a nyári/téli átállást is a rendszer oldja).
            let f = DateFormatter()
            f.locale = Locale(identifier: "en_US_POSIX")
            f.timeZone = TimeZone(secondsFromGMT: 0)
            f.dateFormat = "yyyyMMddHHmm"
            guard let d = f.date(from: datePart + String(format: "%02d%02d", hh, mm)) else { return nil }
            f.timeZone = .current
            f.dateFormat = "yyyy-MM-dd"
            let day = f.string(from: d)
            f.dateFormat = "HH:mm"
            return ParsedDate(day: day, time: f.string(from: d), allDay: false)
        }
        return ParsedDate(day: day8, time: String(format: "%02d:%02d", hh, mm), allDay: false)
    }

    /// yyyyMMdd → yyyy-MM-dd (csak valós naptári dátum).
    private static func ymd(_ s: String) -> String? {
        guard s.count == 8 else { return nil }
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyyMMdd"
        f.isLenient = false
        guard let d = f.date(from: s) else { return nil }
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: d)
    }

    private static func nextDay(_ day: String) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        guard let d = f.date(from: day),
              let n = Calendar.current.date(byAdding: .day, value: 1, to: d) else { return day + "!" }
        return f.string(from: n)
    }

    private static func unescape(_ s: String) -> String {
        var r = s
        r = r.replacingOccurrences(of: "\\N", with: " ")
        r = r.replacingOccurrences(of: "\\n", with: " ")
        r = r.replacingOccurrences(of: "\\,", with: ",")
        r = r.replacingOccurrences(of: "\\;", with: ";")
        r = r.replacingOccurrences(of: "\\\\", with: "\\")
        return r
    }
}
