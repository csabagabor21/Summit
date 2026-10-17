import Foundation
import WidgetKit

// MARK: - Utazás mód ("ne zavarj az iskolával, nyaralok")
//
// Előre beállított [mettől, meddig] intervallum (nap-alapú, mindkét vég
// beleértve). Amíg aktív:
//   - se helyi értesítés (jegy / házi / dolgozat / hiányzás),
//   - se Live Activity (a futót is lezárjuk),
//   - a widget üreset mutat ("Utazás mód — pihenj!").
// Lejárat után magától kikapcsol (nincs beragadt némítás).
//
// Perzisztencia: standard UserDefaults + App Group tükör (a widget
// extension a fő app defaults-át nem látja, ezért mindkét helyre írunk).
// Szinkron: `SummitSync` `travelMode` mezője ("yyyy-MM-dd/yyyy-MM-dd",
// üres = kikapcsolva) — lásd `SummitSyncKey`/`firestore.rules`.
enum TravelMode {
    static let fromKey = "travel.from.v1"
    static let toKey = "travel.to.v1"
    static let appGroupID = "group.hu.flint.summit"
    static let changedNotification = Notification.Name("summit.travelModeChanged")

    /// Beállított intervallum (nap elejére normalizálva), vagy nil.
    static func range(calendar: Calendar = .current) -> (from: Date, to: Date)? {
        let d = UserDefaults.standard
        guard d.object(forKey: fromKey) != nil, d.object(forKey: toKey) != nil else { return nil }
        let from = d.double(forKey: fromKey)
        let to = d.double(forKey: toKey)
        guard from > 0, to > 0, to >= from else { return nil }
        let fromDay = calendar.startOfDay(for: Date(timeIntervalSince1970: from))
        // A "meddig" nap vége is beletartozik (23:59:59-ig aktív).
        guard let toEnd = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: Date(timeIntervalSince1970: to))) else { return nil }
        return (fromDay, toEnd)
    }

    /// Aktív-e most az utazás mód.
    static func isActive(at now: Date = Date()) -> Bool {
        guard let r = range() else { return false }
        return now >= r.from && now < r.to
    }

    /// Rövid címke a Beállítások sornak ("okt. 20–25." vagy "kikapcsolva").
    static func label(calendar: Calendar = .current) -> String {
        guard range() != nil else { return "kikapcsolva" }
        let d = UserDefaults.standard
        let from = Date(timeIntervalSince1970: d.double(forKey: fromKey))
        let to = Date(timeIntervalSince1970: d.double(forKey: toKey))
        let f = DateFormatter()
        f.locale = Locale(identifier: "hu_HU")
        if calendar.isDate(from, inSameDayAs: to) {
            f.dateFormat = "MMM d."
            return f.string(from: from)
        }
        f.dateFormat = "MMM d."
        return "\(f.string(from: from))–\(f.string(from: to))"
    }

    /// Szinkron-sztring ("yyyy-MM-dd/yyyy-MM-dd", üres = kikapcsolva).
    static func syncString() -> String {
        let d = UserDefaults.standard
        guard d.object(forKey: fromKey) != nil, d.object(forKey: toKey) != nil else { return "" }
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        let from = Date(timeIntervalSince1970: d.double(forKey: fromKey))
        let to = Date(timeIntervalSince1970: d.double(forKey: toKey))
        return "\(f.string(from: from))/\(f.string(from: to))"
    }

    /// Távoli sztring alkalmazása (szinkron-pull). Üres = kikapcsolás.
    /// - Returns: igaz, ha a helyi állapot változott.
    @discardableResult
    static func applySyncString(_ s: String) -> Bool {
        let before = syncString()
        if s.isEmpty {
            clear(silent: true)
        } else {
            let parts = s.split(separator: "/").map(String.init)
            guard parts.count == 2 else { return false }
            let f = DateFormatter()
            f.locale = Locale(identifier: "en_US_POSIX")
            f.dateFormat = "yyyy-MM-dd"
            guard let from = f.date(from: parts[0]), let to = f.date(from: parts[1]) else { return false }
            set(from: from, to: to, silent: true)
        }
        let changed = before != syncString()
        if changed { NotificationCenter.default.post(name: changedNotification, object: nil) }
        return changed
    }

    static func set(from: Date, to: Date, silent: Bool = false) {
        let cal = Calendar.current
        let fromDay = cal.startOfDay(for: from)
        let toDay = cal.startOfDay(for: to)
        let lo = min(fromDay, toDay), hi = max(fromDay, toDay)
        write(start: lo, endOfTo: hi)
        if !silent { NotificationCenter.default.post(name: changedNotification, object: nil) }
    }

    static func clear(silent: Bool = false) {
        UserDefaults.standard.removeObject(forKey: fromKey)
        UserDefaults.standard.removeObject(forKey: toKey)
        sharedDefaults()?.removeObject(forKey: fromKey)
        sharedDefaults()?.removeObject(forKey: toKey)
        WidgetCenter.shared.reloadAllTimelines()
        if !silent { NotificationCenter.default.post(name: changedNotification, object: nil) }
    }

    private static func write(start: Date, endOfTo: Date) {
        let d = UserDefaults.standard
        d.set(start.timeIntervalSince1970, forKey: fromKey)
        d.set(endOfTo.timeIntervalSince1970, forKey: toKey)
        // App Group tükör a widgetnek.
        sharedDefaults()?.set(start.timeIntervalSince1970, forKey: fromKey)
        sharedDefaults()?.set(endOfTo.timeIntervalSince1970, forKey: toKey)
        // A widgetek azonnal üresre váltanak (nem a következő timeline-ra várnak).
        WidgetCenter.shared.reloadAllTimelines()
    }

    static func sharedDefaults() -> UserDefaults? {
        UserDefaults(suiteName: appGroupID)
    }

    /// Widget-oldali olvasás (shared suite-ből, Foundation-only).
    static func isActiveInShared(at now: Date = Date()) -> Bool {
        guard let d = sharedDefaults(),
              let from = d.object(forKey: fromKey) as? Double,
              let to = d.object(forKey: toKey) as? Double,
              from > 0, to > 0, to >= from else { return false }
        let cal = Calendar.current
        let fromDay = cal.startOfDay(for: Date(timeIntervalSince1970: from))
        guard let toEnd = cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: Date(timeIntervalSince1970: to))) else { return false }
        return now >= fromDay && now < toEnd
    }
}
