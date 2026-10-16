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
        enum State: String, Codable { case countdown, summer }
        var state: State
        /// Countdown: hátralévő tanítási napok; summer: napok szept. 1-ig.
        var daysLeft: Int
        /// Utolsó tanítási nap / szept. 1.
        var targetDate: Date
        var computedAt: Date
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

    static func compute(now: Date = Date(), daysOff: [DayOff], calendar: Calendar = .current) -> Info {
        let today = calendar.startOfDay(for: now)
        let ey = endYear(for: now, calendar: calendar)
        let offSet = Set(daysOff.map { calendar.startOfDay(for: $0.day) })

        // Nyári szünet kezdete: június 1. utáni „nyár"-jelölés (ékezet-toleráns).
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

        // Utolsó tanítási nap: jelölés előtti nap, különben jún. 15.
        let lastTeachingDay: Date
        if let s = summerStart,
           let prev = calendar.date(byAdding: .day, value: -1, to: s) {
            lastTeachingDay = prev
        } else {
            lastTeachingDay = calendar.date(from: DateComponents(year: ey, month: 6, day: 15)) ?? today
        }

        // Nyár: a céldátum szept. 1.
        if today > lastTeachingDay {
            let schoolStart = calendar.date(from: DateComponents(year: ey, month: 9, day: 1)) ?? today
            let days = max(0, calendar.dateComponents([.day], from: today, to: schoolStart).day ?? 0)
            return Info(state: .summer, daysLeft: days, targetDate: schoolStart, computedAt: now)
        }

        // Hátralévő tanítási napok: holnaptól az utolsó napig, hétköznapok
        // mínusz a KRÉTA-jelölt szünnapok.
        var count = 0
        var day = calendar.date(byAdding: .day, value: 1, to: today) ?? today
        while day <= lastTeachingDay {
            let wd = calendar.component(.weekday, from: day)
            if (2...6).contains(wd), !offSet.contains(day) { count += 1 }
            guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
            day = next
        }
        return Info(state: .countdown, daysLeft: count, targetDate: lastTeachingDay, computedAt: now)
    }
}
