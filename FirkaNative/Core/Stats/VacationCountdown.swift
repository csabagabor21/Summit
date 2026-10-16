import Foundation
import WidgetKit

// MARK: - Vakáció-visszaszámláló — Foundation-only, app + widget target
//
// Az app (TimetableView, 0. hét) számolja a KRÉTA naptári napokból
// (`NaptariNapok`, most → aug. 31., gyorstárazott egyetlen kérés),
// a widget csak olvassa az App Groupból. Személyes adat nincs benne:
// darabszám + céldátum.
//
// Tanév vége adatvezérelt, fallback-létrával:
//   1. „nyári szünet" kezdetű naptári jelölés előtti nap (KRÉTA),
//   2. június 15. (a magyar tanév rendje szerinti tipikus utolsó hét).
// Nyáron átvált: „X nap az iskolakezdésig (szept. 1.)".
enum VacationCountdown {
    static let appGroupID = "group.hu.flint.summit"
    static let infoKey = "vacation.info.v1"

    /// Naptári szünnap az app oldaláról (a widget ilyet sosem számol).
    struct DayOff: Hashable {
        /// Nap eleje.
        var day: Date
        /// KRÉTA típusnév („Tanítás nélküli munkanap", „Nyári szünet", …).
        var name: String
    }

    struct Info: Codable {
        enum State: String, Codable { case countdown, onBreak }
        var state: State
        /// Countdown: tanítási napok a szünetig; onBreak: naptári napok suliig.
        var daysLeft: Int
        /// Szünet kezdete / suli kezdete.
        var targetDate: Date
        /// „Őszi szünet", „Téli szünet", „Nyári szünet", „Tanítás nélküli nap", …
        var breakName: String
        var computedAt: Date
    }

    /// Egybefüggő szünnap-csoport (a hétvége nem szakítja meg: péntek→hétfő
    /// 3 napos ugrás még ugyanaz a szünet).
    struct Break {
        var start: Date
        var end: Date
        var name: String
        var days: [Date]
    }

    // MARK: - Perzisztencia (App Group)

    private static var defaults: UserDefaults? {
        UserDefaults(suiteName: appGroupID)
    }

    static func load() -> Info? {
        guard let d = defaults,
              let data = d.data(forKey: infoKey),
              let info = try? JSONDecoder().decode(Info.self, from: data) else { return nil }
        return info
    }

    @discardableResult
    static func save(_ info: Info) -> Bool {
        guard let d = defaults,
              let data = try? JSONEncoder().encode(info) else { return false }
        d.set(data, forKey: infoKey)
        WidgetCenter.shared.reloadAllTimelines()
        return true
    }

    // MARK: - Számítás (tiszta, UI-független)

    /// Melyik tanév júniusához számolunk: szept. előtt az idei, utána a jövő évi.
    static func endYear(for now: Date, calendar: Calendar = .current) -> Int {
        let y = calendar.component(.year, from: now)
        let m = calendar.component(.month, from: now)
        return m >= 9 ? y + 1 : y
    }

    /// Naptár-lehúzási határ: a tanév-végi aug. 31. (a nyári jelölésnek benne kell lennie).
    static func rangeEnd(for now: Date, calendar: Calendar = .current) -> Date {
        let y = endYear(for: now, calendar: calendar)
        return calendar.date(from: DateComponents(year: y, month: 8, day: 31)) ?? now.addingTimeInterval(300 * 86400)
    }

    /// Szünnapok csoportosítása szünetekké (időrendben). A hétvége nem
    /// szakít: a péntek→hétfő 3 napos ugrás még egy csoport.
    /// A csoport neve a leggyakoribb típusnév (döntetlenre a legkorábbi).
    static func breaks(from daysOff: [DayOff], calendar: Calendar = .current) -> [Break] {
        let days = daysOff.map { calendar.startOfDay(for: $0.day) }.sorted()
        guard !days.isEmpty else { return [] }
        var groups: [[Date]] = [[days[0]]]
        for d in days.dropFirst() {
            let gap = calendar.dateComponents([.day], from: groups[groups.count - 1].last!, to: d).day ?? 99
            if gap <= 3 {
                groups[groups.count - 1].append(d)
            } else {
                groups.append([d])
            }
        }
        return groups.compactMap { g -> Break? in
            guard let first = g.first, let last = g.last else { return nil }
            var votes: [String: Int] = [:]
            for d in g {
                let n = daysOff.first { calendar.isDate($0.day, inSameDayAs: d) }?.name
                    .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                if !n.isEmpty { votes[n, default: 0] += 1 }
            }
            let name = votes.max { $0.value < $1.value }?.key ?? "Szünet"
            return Break(start: first, end: last, name: name, days: g)
        }
    }

    /// Következő tanítási hétköznap az adott nap után (hétvége +
    /// KRÉTA-szünnapok átugrásával). Okt. 23. környéki lyukakra is jó.
    static func nextSchoolDay(after day: Date, offSet: Set<Date>, calendar: Calendar = .current) -> Date {
        var d = day
        for _ in 0..<400 {
            guard let next = calendar.date(byAdding: .day, value: 1, to: d) else { break }
            d = next
            let wd = calendar.component(.weekday, from: d)
            if (2...6).contains(wd), !offSet.contains(d) { return d }
        }
        return d
    }

    static func compute(now: Date = Date(), daysOff: [DayOff], calendar: Calendar = .current) -> Info {
        let today = calendar.startOfDay(for: now)
        let ey = endYear(for: now, calendar: calendar)
        let offSet = Set(daysOff.map { calendar.startOfDay(for: $0.day) })
        let groups = breaks(from: daysOff, calendar: calendar)

        // Épp szünet van (ma KRÉTA-szünnap, vagy egy már elkezdődött
        // csoporton belül vagyunk — pl. hétvége az őszi szünet közepén):
        // a céldátum a suli kezdete.
        if offSet.contains(today)
            || groups.contains(where: { $0.start <= today && today <= $0.end }) {
            let name = daysOff.first { calendar.isDate($0.day, inSameDayAs: today) }?.name
                .trimmingCharacters(in: .whitespacesAndNewlines)
                ?? groups.first { $0.start <= today && today <= $0.end }?.name
                ?? "Szünet"
            let resume = nextSchoolDay(after: today, offSet: offSet, calendar: calendar)
            let days = max(0, calendar.dateComponents([.day], from: today, to: resume).day ?? 0)
            return Info(state: .onBreak, daysLeft: days, targetDate: resume, breakName: name, computedAt: now)
        }

        // Következő szünet: az első olyan csoport, ami még nem múlt el.
        if let next = groups.first(where: { $0.end >= today }) {
            var count = 0
            var day = calendar.date(byAdding: .day, value: 1, to: today) ?? today
            while day < next.start {
                let wd = calendar.component(.weekday, from: day)
                if (2...6).contains(wd), !offSet.contains(day) { count += 1 }
                guard let nxt = calendar.date(byAdding: .day, value: 1, to: day) else { break }
                day = nxt
            }
            return Info(state: .countdown, daysLeft: count, targetDate: next.start, breakName: next.name, computedAt: now)
        }

        // Nincs több jelölt szünet az adatokban (pl. nyárjel nélküli
        // nyár): fallback a tanév végére, mint eddig.
        let june1 = calendar.date(from: DateComponents(year: ey, month: 6, day: 1)) ?? today
        let summerStart = daysOff
            .map { calendar.startOfDay(for: $0.day) }
            .filter { $0 >= calendar.startOfDay(for: june1) }
            .sorted()
            .first(where: { day in
                daysOff.contains {
                    calendar.isDate($0.day, inSameDayAs: day)
                    && $0.name.folding(options: .diacriticInsensitive, locale: .current).lowercased().contains("nyar")
                }
            })
        let lastTeachingDay: Date
        if let s = summerStart,
           let prev = calendar.date(byAdding: .day, value: -1, to: s) {
            lastTeachingDay = prev
        } else {
            lastTeachingDay = calendar.date(from: DateComponents(year: ey, month: 6, day: 15)) ?? today
        }
        if today > lastTeachingDay {
            let schoolStart = calendar.date(from: DateComponents(year: ey, month: 9, day: 1)) ?? today
            let days = max(0, calendar.dateComponents([.day], from: today, to: schoolStart).day ?? 0)
            return Info(state: .onBreak, daysLeft: days, targetDate: schoolStart, breakName: "Nyári szünet", computedAt: now)
        }
        var count = 0
        var day = calendar.date(byAdding: .day, value: 1, to: today) ?? today
        while day <= lastTeachingDay {
            let wd = calendar.component(.weekday, from: day)
            if (2...6).contains(wd), !offSet.contains(day) { count += 1 }
            guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
            day = next
        }
        return Info(state: .countdown, daysLeft: count, targetDate: lastTeachingDay, breakName: "Nyári szünet", computedAt: now)
    }
}
