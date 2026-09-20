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
    /// Mentett naptár-link (csak ezen az eszközön — a frissítés úgyis egy
    /// helyen történik, az eredménye pedig átmegy a szinkronnal).
    static let urlKey = "schoolevents.url.v1"
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

    static func savedURL() -> String? {
        UserDefaults.standard.string(forKey: urlKey)
    }

    static func saveURL(_ raw: String?) {
        if let raw, !raw.isEmpty {
            UserDefaults.standard.set(raw, forKey: urlKey)
        } else {
            UserDefaults.standard.removeObject(forKey: urlKey)
        }
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

/// Szabad szöveges tannaptár olvasása (beillesztett szöveghez — a suli
/// honlapjáról, KRÉTA-üzenetből kimásolt lista). Mind kliensoldalt fut,
/// nincs backend: `2026.09.01.`, `09.01.`, `okt 26-28.` formák,
/// `8:00` / `9:30-11:00` időpontokkal, többnapos bontással.
enum SchoolEventsText {
    static func parse(_ text: String, now: Date = Date(), maxCount: Int = SchoolEventsStore.maxSyncedEvents) -> [SchoolEvent] {
        var out: [SchoolEvent] = []
        /// Az utolsó dátumos sor nap-csoportja (többnaposnál mindegyik nap
        /// megkapja a folytatósort, nem csak az utolsó).
        var lastGroup: Range<Int>? = nil
        for rawLine in text.components(separatedBy: "\n") {
            var line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            // Felsorolásjelek le; a hét napjai önmagukban nem események.
            while line.hasPrefix("-") || line.hasPrefix("•") || line.hasPrefix("*") {
                line = String(line.dropFirst()).trimmingCharacters(in: .whitespaces)
            }
            guard !line.isEmpty else { continue }
            let folded = line.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            if weekdays.contains(folded) { continue }
            guard let hit = matchDate(line, now: now) else {
                // Folytatósor: az előző címéhez fűzzük (fejléc nem lesz belőle,
                // mert az első dátum előtt nincs mihez fűzni).
                if let g = lastGroup, line.count > 2 {
                    let extra = cleanTitle(line)
                    if !extra.isEmpty {
                        for i in g {
                            let glued = (out[i].title + " " + extra).trimmingCharacters(in: .whitespaces)
                            out[i].title = String(glued.prefix(140))
                        }
                    }
                }
                continue
            }
            let days = expandDays(hit, maxDays: 14)
            let start = out.count
            for day in days {
                guard out.count < maxCount else { break }
                out.append(SchoolEvent(day: day, title: hit.title, location: "",
                                       allDay: hit.start.isEmpty, start: hit.start, end: hit.end))
            }
            lastGroup = start < out.count ? start..<out.count : nil
        }
        var seen = Set<String>()
        return out.filter { seen.insert($0.id).inserted }
    }

    private static let weekdays: Set<String> = ["hetfo", "kedd", "szerda", "csutortok", "pentek", "szombat", "vasarnap"]

    private static let months: [String: Int] = [
        "januar": 1, "jan": 1, "februar": 2, "febr": 2, "feb": 2,
        "marcius": 3, "marc": 3, "aprilis": 4, "apr": 4,
        "majus": 5, "maj": 5, "junius": 6, "jun": 6,
        "julius": 7, "jul": 7, "augusztus": 8, "aug": 8,
        "szeptember": 9, "szept": 9, "oktober": 10, "okt": 10,
        "november": 11, "nov": 11, "december": 12, "dec": 12,
    ]

    private struct Hit {
        var year: Int; var month: Int; var day: Int
        var endYear: Int?; var endMonth: Int?; var endDay: Int?
        var title: String; var start: String; var end: String
    }

    /// Dátum a sor elején: `éééé.hh.nn`, `hh.nn`, vagy hónapnév + nap,
    /// opcionális `- nn` / `- hh.nn` / `- hónap nn` tartományvéggel.
    private static func matchDate(_ line: String, now: Date) -> Hit? {
        // A regexek az EREDETI soron futnak (az indexek abba mutatnak);
        // csak a hónap-szót hajtjuk össze a táblázathoz.
        var rest: Substring
        var y: Int?, m: Int?, d: Int?
        var ey: Int?, em: Int?, ed: Int?
        if let r = matchYMD(line) {
            y = r.y; m = r.m; d = r.d; rest = line[r.end...]
            if let e = matchRangeEnd(String(rest), month: m!) {
                ey = e.y ?? y; em = e.m ?? m!; ed = e.d; rest = String(rest)[e.end...]
            }
        } else if let r = matchMD(line) {
            m = r.m; d = r.d; rest = line[r.end...]
            if let e = matchRangeEnd(String(rest), month: m!) {
                em = e.m ?? m!; ed = e.d; rest = String(rest)[e.end...]
            }
        } else if let r = matchNamed(line) {
            m = r.m; d = r.d; rest = line[r.end...]
            if let e = matchNamedEnd(String(rest)) {
                em = e.m ?? m!; ed = e.d; rest = String(rest)[e.end...]
            } else if let e = matchRangeEnd(String(rest), month: m!) {
                em = e.m ?? m!; ed = e.d; rest = String(rest)[e.end...]
            }
        } else {
            return nil
        }
        guard let month = m, let day = d, (1...12).contains(month), (1...31).contains(day) else { return nil }
        let year = y ?? inferYear(month: month, day: day, now: now)
        guard validDate(year: year, month: month, day: day) else { return nil }
        if let em, let ed {
            let endY = ey ?? (em < month ? year + 1 : year)
            guard validDate(year: endY, month: em, day: ed) else {
                return finish(year: year, month: month, day: day, rest: String(rest))
            }
            let a = ymdInt(year, month, day), b = ymdInt(endY, em, ed)
            guard b > a else { return finish(year: year, month: month, day: day, rest: String(rest)) }
            var hit = finish(year: year, month: month, day: day, rest: String(rest))
            hit.endYear = endY; hit.endMonth = em; hit.endDay = ed
            return hit
        }
        return finish(year: year, month: month, day: day, rest: String(rest))
    }

    private static func finish(year: Int, month: Int, day: Int, rest: String) -> Hit {
        let (title, start, end) = extractTime(from: cleanTitle(rest))
        return Hit(year: year, month: month, day: day,
                   endYear: nil, endMonth: nil, endDay: nil,
                   title: title.isEmpty ? "Iskolai esemény" : title, start: start, end: end)
    }

    /// `2026.09.01.` / `2026.09.01` a sor elején.
    private static func matchYMD(_ line: String) -> (y: Int, m: Int, d: Int, end: String.Index)? {
        let p = #"^(\d{4})\.\s?(\d{1,2})\.\s?(\d{1,2})\.?"#
        guard let r = line.range(of: p, options: .regularExpression),
              let g = groups(p, in: line),
              let y = Int(g[0]), let m = Int(g[1]), let d = Int(g[2]) else { return nil }
        return (y, m, d, r.upperBound)
    }

    /// `09.01.` / `9.1` a sor elején.
    private static func matchMD(_ line: String) -> (m: Int, d: Int, end: String.Index)? {
        let p = #"^(\d{1,2})\.\s?(\d{1,2})\.?"#
        guard let r = line.range(of: p, options: .regularExpression),
              let g = groups(p, in: line),
              let m = Int(g[0]), let d = Int(g[1]) else { return nil }
        // Négyjegyű év elejét (`2026…`) nem esszük meg részben: azt matchYMD vitte.
        return (m, d, r.upperBound)
    }

    /// `okt 26.` / `október 26`, ragokkal (`26-tól`, `26-án`).
    private static func matchNamed(_ line: String) -> (m: Int, d: Int, end: String.Index)? {
        let p = #"^([a-záéíóöőúüű]+)\.?\s+(\d{1,2})(?:-(?:tol|tól|től|ig|án|én|on|en|ön))?\.?"#
        guard let r = line.range(of: p, options: [.regularExpression, .caseInsensitive]),
              let g = groups(p, in: line),
              let m = months[foldWord(g[0])], let d = Int(g[1]) else { return nil }
        return (m, d, r.upperBound)
    }

    private static func foldWord(_ s: String) -> String {
        s.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
    }

    /// Tartományvég számokkal: `- 28.` / `- 11.02.` / `- 2026.11.02.`.
    /// Időpontot (`- 8:00`) nem eszik meg: a nap után nem állhat `:NN`/`.NN`.
    private static func matchRangeEnd(_ s: String, month: Int) -> (y: Int?, m: Int?, d: Int, end: String.Index)? {
        let p = #"^\s*[-–]\s*(?:(\d{4})\.\s?)?(?:(\d{1,2})\.\s?)?(\d{1,2})\.?(?![:.]\d)"#
        guard let r = s.range(of: p, options: .regularExpression),
              let g = groups(p, in: s) else { return nil }
        let y = g[0].isEmpty ? nil : Int(g[0])
        let m = g[1].isEmpty ? nil : Int(g[1])
        guard let d = Int(g[2]) else { return nil }
        // Csak akkor tartomány, ha tényleg kötőjellel kezdődött (a regex
        // kötő nélkül is illeszkedne egy sima napra — azt nem kérjük).
        guard s.trimmingCharacters(in: .whitespaces).hasPrefix("-") || s.contains("–") else { return nil }
        _ = month
        return (y, m, d, r.upperBound)
    }

    /// Tartományvég hónapnévvel: `- nov 2.` / `- november 2`.
    private static func matchNamedEnd(_ s: String) -> (m: Int?, d: Int, end: String.Index)? {
        let p = #"^\s*[-–]\s*([a-záéíóöőúüű]+)\.?\s+(\d{1,2})\.?"#
        guard let r = s.range(of: p, options: [.regularExpression, .caseInsensitive]),
              let g = groups(p, in: s),
              let m = months[foldWord(g[0])], let d = Int(g[1]) else { return nil }
        return (m, d, r.upperBound)
    }

    private static func groups(_ pattern: String, in s: String) -> [String]? {
        guard let re = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
              let m = re.firstMatch(in: s, range: NSRange(s.startIndex..., in: s)) else { return nil }
        return (1..<m.numberOfRanges).map { i in
            guard let r = Range(m.range(at: i), in: s) else { return "" }
            return String(s[r])
        }
    }

    /// Év, ha nincs kiírva: a dátum essen a [most-60 nap, most+330 nap] ablakba
    /// (szeptemberi import augusztusban, januári import decemberben is jó).
    private static func inferYear(month: Int, day: Int, now: Date) -> Int {
        let cal = Calendar.current
        let thisYear = cal.component(.year, from: now)
        var c = DateComponents(); c.year = thisYear; c.month = month; c.day = day
        guard let date = cal.date(from: c) else { return thisYear }
        if date < now.addingTimeInterval(-60 * 86400) { return thisYear + 1 }
        if date > now.addingTimeInterval(330 * 86400) { return thisYear - 1 }
        return thisYear
    }

    private static func validDate(year: Int, month: Int, day: Int) -> Bool {
        var c = DateComponents(); c.year = year; c.month = month; c.day = day
        guard let d = Calendar.current.date(from: c) else { return false }
        let got = Calendar.current.dateComponents([.year, .month, .day], from: d)
        return got.year == year && got.month == month && got.day == day
    }

    private static func ymdInt(_ y: Int, _ m: Int, _ d: Int) -> Int { y * 10000 + m * 100 + d }

    private static func expandDays(_ hit: Hit, maxDays: Int) -> [String] {
        let start = String(format: "%04d-%02d-%02d", hit.year, hit.month, hit.day)
        guard let em = hit.endMonth, let ed = hit.endDay else { return [start] }
        let endY = hit.endYear ?? hit.year
        var days: [String] = []
        var cur = start
        let end = String(format: "%04d-%02d-%02d", endY, em, ed)
        // Szöveges tartomány inkluzív ("okt 26-28" = 26, 27, 28) —
        // az ICS DTEND-del ellentétben itt a végnap is benne van.
        while cur <= end, days.count < maxDays {
            days.append(cur)
            cur = nextDay(cur)
        }
        return days.isEmpty ? [start] : days
    }

    private static func nextDay(_ day: String) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        guard let d = f.date(from: day),
              let n = Calendar.current.date(byAdding: .day, value: 1, to: d) else { return day + "!" }
        return f.string(from: n)
    }

    /// Vezető `: – -` takarítás + időablak kivágása a címből.
    private static func cleanTitle(_ s: String) -> String {
        var t = s.trimmingCharacters(in: .whitespacesAndNewlines)
        while let c = t.first, ":–—-•".contains(c) {
            t = String(t.dropFirst()).trimmingCharacters(in: .whitespaces)
        }
        return String(t.prefix(140))
    }

    private static func extractTime(from title: String) -> (String, String, String) {
        let rangeP = #"(\d{1,2})[:.](\d{2})\s*[-–]\s*(\d{1,2})[:.](\d{2})"#
        if let m = title.range(of: rangeP, options: .regularExpression),
           let g = groups(rangeP, in: title),
           let h1 = Int(g[0]), let m1 = Int(g[1]), let h2 = Int(g[2]), let m2 = Int(g[3]),
           (0...23).contains(h1), (0...59).contains(m1), (0...23).contains(h2), (0...59).contains(m2) {
            let t = title.replacingCharacters(in: m, with: "").trimmingCharacters(in: .whitespaces)
            return (cleanTitle(t), String(format: "%02d:%02d", h1, m1), String(format: "%02d:%02d", h2, m2))
        }
        let singleP = #"(\d{1,2})[:.](\d{2})"#
        if let m = title.range(of: singleP, options: .regularExpression),
           let g = groups(singleP, in: title),
           let h = Int(g[0]), let mm = Int(g[1]), (0...23).contains(h), (0...59).contains(mm) {
            let t = title.replacingCharacters(in: m, with: "").trimmingCharacters(in: .whitespaces)
            return (cleanTitle(t), String(format: "%02d:%02d", h, mm), "")
        }
        return (title, "", "")
    }
}
