import Foundation

// MARK: - TaskRelay — Feladatok-megnyitás egyszeri, hurokmentes reléje
// A "summit.switchToTasks" értesítés több nézethez jut el (MainTab,
// CheatView-cover, NotesView-szegmens), és a lusta nézetek miatt egy
// késleltetett utánküldés is kell. A korábbi "mindig küldd újra"
// megoldás végtelen 0,4 mp-es láncot adott: bezárás után is jött újabb
// értesítés, így a cover visszanyílt és bezárhatatlanná vált.
//
// Szabályok:
// - Eredeti kérés (pille, értesítés, részletező): friss relayID + hop:0,
//   a `post` adja.
// - Utánküldés: CSAK hop:0-ra, EGYSZER, UGYANAZZAL a relayID-vel
//   (`scheduleRelay` — az újabb kérés felülírja a függőben lévőt).
// - Ugyanaz a relayID egy nézeten csak egyszer hathat (`claim`) —
//   a késve befutó duplikátum bezárás után sem nyithat újra.
// - Bezáráskor (`onDisappear`) a függő utánküldést törölni kell
//   (`cancelRelay`) — különben a 0,4 mp-es versenyablak visszanyit.
enum TaskRelay {
    static let name = Notification.Name("summit.switchToTasks")

    private static var pending: DispatchWorkItem?
    private static var claimed: [String] = []

    /// Eredeti kérés — pillek, push-értesítés, részletező-gombok innen küldjenek.
    static func post(segment: String? = nil, flash: String? = nil) {
        var ui: [String: Any] = ["relayID": UUID().uuidString, "hop": 0]
        if let segment { ui["segment"] = segment }
        if let flash { ui["flash"] = flash }
        NotificationCenter.default.post(name: name, object: nil, userInfo: ui)
    }

    /// Késleltetett, egyszeri utánküldés a lusta nézeteknek (ugyanaz a
    /// relayID, hop:1). Hop:1-re már senki nem ütemez tovább — nincs lánc.
    static func scheduleRelay(_ info: [String: Any]) {
        pending?.cancel()
        var ui = info
        if ui["relayID"] == nil { ui["relayID"] = UUID().uuidString }
        ui["hop"] = 1
        let item = DispatchWorkItem {
            NotificationCenter.default.post(name: name, object: nil, userInfo: ui)
        }
        pending = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4, execute: item)
    }

    /// Függő utánküldés törlése (cover-bezáráskor KÖTELEZŐ hívni).
    static func cancelRelay() {
        pending?.cancel()
        pending = nil
    }

    /// relayID-consumálás: egy ID egy nézeten csak egyszer hathat.
    /// Visszatérés: true = most először (hathat), false = duplikátum.
    static func claim(_ id: String) -> Bool {
        if claimed.contains(id) { return false }
        claimed.append(id)
        if claimed.count > 64 { claimed.removeFirst(claimed.count - 64) }
        return true
    }

    static func hop(of userInfo: [AnyHashable: Any]?) -> Int {
        (userInfo as? [String: Any])?["hop"] as? Int ?? 0
    }

    static func relayID(of userInfo: [AnyHashable: Any]?) -> String? {
        (userInfo as? [String: Any])?["relayID"] as? String
    }
}
