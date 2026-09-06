import Foundation
import UserNotifications
import UIKit

/// Helyi értesítések új jegyekről, házikról, dolgozatokról és hiányzásokról.
///
/// Őszinte korlát: a KRÉTA API-nak NINCS push végpontja — csak lekérdezhető
/// GET endpointok vannak (Ertekelesek, HaziFeladatok, ...). Valódi azonnali
/// push-hoz saját backend szerver + APNs kellene (a Firka is így oldja meg a
/// Live Activity / push részt, kliens-oldali jegy-push nekik sincs).
/// Ezért ez polling-alapú: minden sikeres adatfrissítés után diffelünk az
/// utoljára látott ID-khoz képest, és ami új, arra helyi értesítést ütemezünk.
/// Háttérben a meglévő liveactivity-refresh BGTask ébresztésekor is lefut.
@MainActor
final class NotificationManager: NSObject, ObservableObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationManager()

    /// Engedély-állapot a Beállítások sornak (unknown / denied / authorized)
    @Published var permissionStatus: String = "Ismeretlen"

    // MARK: - Toggle kulcsok (SettingsView @AppStorage-gal írja)

    static let gradesKey = "notify.grades"
    static let tasksKey = "notify.tasks" // házi + dolgozat együtt
    static let absencesKey = "notify.absences"

    /// Hiányzó kulcs = bekapcsolva (az első verzióban minden default ON).
    static func isEnabled(_ key: String) -> Bool {
        guard UserDefaults.standard.object(forKey: key) != nil else { return true }
        return UserDefaults.standard.bool(forKey: key)
    }

    // MARK: - Setup

    /// Egyszer hívandó (FlintApp .onAppear) — különben előtérben nem jelenik meg banner.
    func configure() {
        UNUserNotificationCenter.current().delegate = self
        Task { await refreshPermission() }
    }

    func requestPermission() async -> Bool {
        do {
            let granted = try await UNUserNotificationCenter.current()
                .requestAuthorization(options: [.alert, .sound, .badge])
            await refreshPermission()
            return granted
        } catch {
            await refreshPermission()
            return false
        }
    }

    func refreshPermission() async {
        let s = await UNUserNotificationCenter.current().notificationSettings()
        switch s.authorizationStatus {
        case .authorized, .provisional, .ephemeral: permissionStatus = "Engedélyezve"
        case .denied: permissionStatus = "Tiltva"
        case .notDetermined: permissionStatus = "Még nem kérve"
        @unknown default: permissionStatus = "Ismeretlen"
        }
    }

    func openSystemSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        Task { @MainActor in await UIApplication.shared.open(url) }
    }

    // Előtérben is mutassa a bannert (demo tesztgombhoz ez kell).
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }

    // MARK: - Diff + értesítés

    private func seenKey(_ kind: String, userId: String) -> String {
        "flint.seen\(kind).v1.\(userId)"
    }

    private func loadSeen(_ kind: String, userId: String) -> Set<String> {
        Set(UserDefaults.standard.stringArray(forKey: seenKey(kind, userId: userId)) ?? [])
    }

    private func saveSeen(_ kind: String, userId: String, ids: Set<String>) {
        UserDefaults.standard.set(Array(ids), forKey: seenKey(kind, userId: userId))
    }

    /// Általános diff: első futáskor csak magot vet (nincs spam-spam belépéskor),
    /// utána az újakra ütemez. Visszatér az újak számával.
    @discardableResult
    private func diffAndNotify(
        kind: String, userId: String, ids: [String],
        notify: ([String]) -> Void
    ) -> Int {
        let key = seenKey(kind, userId: userId)
        guard UserDefaults.standard.object(forKey: key) != nil else {
            // Első találkozás: baseline mag, értesítés nélkül.
            UserDefaults.standard.set(ids, forKey: key)
            return 0
        }
        var seen = loadSeen(kind, userId: userId)
        let fresh = ids.filter { !seen.contains($0) }
        guard !fresh.isEmpty else { return 0 }
        fresh.forEach { seen.insert($0) }
        saveSeen(kind, userId: userId, ids: seen)
        notify(fresh)
        return fresh.count
    }

    /// Olvasatlan-számláló per felhasználó — ebből lesz az ikon-jelvény száma.
    private func unreadKey(_ userId: String) -> String { "flint.unread.v1.\(userId)" }

    var currentBadgeUserId: String?

    private func bumpBadge(userId: String, by count: Int) {
        let key = unreadKey(userId)
        let next = (UserDefaults.standard.object(forKey: key) as? Int ?? 0) + count
        UserDefaults.standard.set(next, forKey: key)
        currentBadgeUserId = userId
        UNUserNotificationCenter.current().setBadgeCount(next) { _ in }
    }

    /// App megnyitásakor hívandó — nullázza a jelvényt és a számlálót.
    func clearBadge(userId: String) {
        UserDefaults.standard.set(0, forKey: unreadKey(userId))
        if currentBadgeUserId == nil || currentBadgeUserId == userId {
            UNUserNotificationCenter.current().setBadgeCount(0) { _ in }
        }
    }

    /// Jegy-szám kép a bannerhez: 5-ösre 5-öst rajzol, 2-esre 2-est.
    /// Az app ikonját nem lehet cserélgetni, de a banner melléklet-képe igen.
    private func gradeImageURL(value: Int) -> URL? {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("flint-grade-\(value).png")
        if FileManager.default.fileExists(atPath: url.path) { return url }
        let hexes = [1: 0xFF4D6E, 2: 0xFF7A45, 3: 0xFFD23C, 4: 0x92EA3B, 5: 0x22CCAD]
        let hex = hexes[value] ?? 0x888888
        let ui = UIColor(
            red: CGFloat((hex >> 16) & 0xFF) / 255.0,
            green: CGFloat((hex >> 8) & 0xFF) / 255.0,
            blue: CGFloat(hex & 0xFF) / 255.0, alpha: 1.0
        )
        let size = CGSize(width: 120, height: 120)
        let img = UIGraphicsImageRenderer(size: size).image { ctx in
            // Sötét alap + teli jegy-szín kör + fehér szám (kicsiben is olvasható)
            UIColor(white: 0.11, alpha: 1.0).setFill()
            UIBezierPath(roundedRect: CGRect(origin: .zero, size: size), cornerRadius: 28).fill()
            ui.setFill()
            UIBezierPath(ovalIn: CGRect(x: 14, y: 14, width: 92, height: 92)).fill()
            let text = "\(value)" as NSString
            let font = UIFont.systemFont(ofSize: 56, weight: .bold)
            let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: UIColor.white]
            let tw = text.size(withAttributes: attrs)
            text.draw(at: CGPoint(x: (120 - tw.width) / 2, y: (120 - tw.height) / 2 - 2), withAttributes: attrs)
            _ = ctx
        }
        guard let data = img.pngData() else { return nil }
        try? data.write(to: url, options: .atomic)
        return url
    }

    private func schedule(id: String, title: String, body: String, userId: String, bumpBy: Int, imageURL: URL? = nil) {
        if bumpBy > 0 { bumpBadge(userId: userId, by: bumpBy) }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        // Rendszer rajzolja a jelvényt — nem formázható (Liquid Glass sem megy rá).
        content.badge = (UserDefaults.standard.object(forKey: unreadKey(userId)) as? Int ?? 0) as NSNumber
        if let imageURL, let att = try? UNNotificationAttachment(identifier: "grade", url: imageURL, options: nil) {
            content.attachments = [att]
        }
        let req = UNNotificationRequest(
            identifier: id, content: content,
            trigger: UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
        )
        UNUserNotificationCenter.current().add(req)
    }

    @discardableResult
    func checkGrades(_ grades: [GradeItem], userId: String) -> Int {
        guard Self.isEnabled(Self.gradesKey) else { return 0 }
        let byId = Dictionary(uniqueKeysWithValues: grades.map { ($0.id, $0) })
        return diffAndNotify(kind: "Grades", userId: userId, ids: grades.map(\.id)) { fresh in
            if fresh.count == 1, let g = byId[fresh[0]] {
                self.schedule(
                    id: "flint.grade.\(g.id)",
                    title: "Új jegy: \(g.valueText) (\(g.subject))",
                    body: [g.type, g.topic, g.teacher].filter { !$0.isEmpty }.joined(separator: " • "),
                    userId: userId, bumpBy: 1,
                    imageURL: self.gradeImageURL(value: g.value)
                )
            } else {
                self.schedule(
                    id: "flint.grades.\(Int(Date().timeIntervalSince1970))",
                    title: "\(fresh.count) új jegy érkezett",
                    body: fresh.compactMap { byId[$0] }.prefix(3)
                        .map { "\($0.valueText) • \($0.subject)" }.joined(separator: ", "),
                    userId: userId, bumpBy: fresh.count
                )
            }
        }
    }

    @discardableResult
    func checkHomeworks(_ items: [HomeworkItem], userId: String) -> Int {
        guard Self.isEnabled(Self.tasksKey) else { return 0 }
        let byId = Dictionary(uniqueKeysWithValues: items.map { ($0.id, $0) })
        return diffAndNotify(kind: "Homework", userId: userId, ids: items.map(\.id)) { fresh in
            if fresh.count == 1, let h = byId[fresh[0]] {
                self.schedule(id: "flint.hw.\(h.id)", title: "Új házi: \(h.subject)", body: h.plainTitle, userId: userId, bumpBy: 1)
            } else {
                self.schedule(
                    id: "flint.hw.\(Int(Date().timeIntervalSince1970))",
                    title: "\(fresh.count) új házi feladat",
                    body: fresh.compactMap { byId[$0] }.prefix(3).map(\.subject).joined(separator: ", "),
                    userId: userId, bumpBy: fresh.count
                )
            }
        }
    }

    @discardableResult
    func checkExams(_ items: [ExamItem], userId: String) -> Int {
        guard Self.isEnabled(Self.tasksKey) else { return 0 }
        let byId = Dictionary(uniqueKeysWithValues: items.map { ($0.id, $0) })
        return diffAndNotify(kind: "Exams", userId: userId, ids: items.map(\.id)) { fresh in
            if fresh.count == 1, let e = byId[fresh[0]] {
                let df = DateFormatter(); df.dateStyle = .medium; df.timeStyle = .none; df.locale = .current
                self.schedule(
                    id: "flint.exam.\(e.id)", title: "Új dolgozat: \(e.subject)",
                    body: "\(e.mode) • \(df.string(from: e.date))\(e.description.isEmpty ? "" : " • \(e.description)")",
                    userId: userId, bumpBy: 1
                )
            } else {
                self.schedule(
                    id: "flint.exam.\(Int(Date().timeIntervalSince1970))",
                    title: "\(fresh.count) új dolgozat",
                    body: fresh.compactMap { byId[$0] }.prefix(3).map(\.subject).joined(separator: ", "),
                    userId: userId, bumpBy: fresh.count
                )
            }
        }
    }

    @discardableResult
    func checkAbsences(_ items: [AbsenceItem], userId: String) -> Int {
        guard Self.isEnabled(Self.absencesKey) else { return 0 }
        return diffAndNotify(kind: "Absences", userId: userId, ids: items.map(\.id)) { fresh in
            self.schedule(
                id: "flint.abs.\(Int(Date().timeIntervalSince1970))",
                title: fresh.count == 1 ? "Új hiányzás" : "\(fresh.count) új hiányzás",
                body: "Nézd meg a Hiányzások fülön.",
                userId: userId, bumpBy: fresh.count
            )
        }
    }

    /// Minden kategória egyben — a HomeViewModel.refresh hívja.
    func checkAll(grades: [GradeItem], homeworks: [HomeworkItem], exams: [ExamItem], absences: [AbsenceItem], userId: String) {
        checkGrades(grades, userId: userId)
        checkHomeworks(homeworks, userId: userId)
        checkExams(exams, userId: userId)
        checkAbsences(absences, userId: userId)
    }

    // MARK: - Demo teszt

    /// Azonnali teszt-banner (engedélyt is kér, ha még nincs).
    /// A jelvényt is +1-gyel mutatja, hogy az is tesztelhető legyen.
    func sendTest(userId: String) async {
        _ = await requestPermission()
        schedule(id: "flint.test.\(Int(Date().timeIntervalSince1970))",
                 title: "Teszt értesítés",
                 body: "Ha ezt látod, működnek a Flint értesítések.",
                 userId: userId, bumpBy: 1)
    }

    /// Szimulált új demo jegy: baseline-mag (ha kell), majd 1 friss 5-ös Matek.
    /// Visszaadja a szimulált jegyet, hogy a UI megmutathassa.
    @discardableResult
    func simulateDemoGrade() async -> GradeItem {
        _ = await requestPermission()
        let userId = "demo-user"
        let base = DemoData.gradesExpanded()
        if UserDefaults.standard.object(forKey: seenKey("Grades", userId: userId)) == nil {
            UserDefaults.standard.set(base.map(\.id), forKey: seenKey("Grades", userId: userId))
        }
        let fake = GradeItem(
            id: "demo-sim-\(Int(Date().timeIntervalSince1970))",
            subject: "Matematika", value: 5, valueText: "5",
            date: Date(), teacher: "Kovács J.", type: "Témazáró", weight: 200,
            topic: "Függvények (szimulált)"
        )
        checkGrades(base + [fake], userId: userId)
        return fake
    }

    /// Demo újrateszteléshez: elfelejti a látott ID-kat.
    func resetDemoSeen() {
        for kind in ["Grades", "Homework", "Exams", "Absences"] {
            UserDefaults.standard.removeObject(forKey: seenKey(kind, userId: "demo-user"))
        }
    }
}
