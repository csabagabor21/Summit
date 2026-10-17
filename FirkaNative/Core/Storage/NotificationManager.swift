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
/// utoljára látott ID-khoz képest. Egy frissítési körre legfeljebb 1 banner
/// megy ki (digest): 1 db újdonságnál specifikus, többnél összevont sorok.
/// Háttérben a meglévő liveactivity-refresh BGTask ébresztésekor is lefut.
@MainActor
final class NotificationManager: NSObject, ObservableObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationManager()

    /// Engedély-állapot a Beállítások sornak (unknown / denied / authorized)
    @Published var permissionStatus: String = "Ismeretlen"

    /// Fullscreen ünneplő kártya célja — ha nem nil, a MainTabView felteszi.
    /// Új jegy diffjekor, értesítés-koppintáskor és demo szimuláláskor töltődik.
    @Published var celebrationGrade: GradeItem?

    // MARK: - Toggle kulcsok (SettingsView @AppStorage-gal írja)

    /// Egyetlen főkapcsoló: minden helyi értesítés (jegy, házi/dolgozat,
    /// hiányzás) együtt. A régi per-típus kulcsok (`notify.grades`,
    /// `notify.tasks`, `notify.absences`) megvannak még az eszközön —
    /// a `migratePerTypeKeys` hajtja őket össze ebbe az egybe.
    static let masterKey = "notify.enabled"

    /// Hiányzó kulcs = bekapcsolva (az első verzióban minden default ON).
    static func isEnabled(_ key: String) -> Bool {
        guard UserDefaults.standard.object(forKey: key) != nil else { return true }
        return UserDefaults.standard.bool(forKey: key)
    }

    /// Egyszeri összevonás a régi per-típus kapcsolókból a főkapcsolóba:
    /// ha BÁRMELYIK régi ki volt kapcsolva, a főkapcsoló is KI lesz
    /// (konzervatív: nem kapcsolunk vissza olyat, amit a user leoltott).
    /// Utána a régi kulcsok törlődnek. Többször hívható (idempotens).
    static func migratePerTypeKeys() {
        let d = UserDefaults.standard
        let olds = ["notify.grades", "notify.tasks", "notify.absences"]
        guard olds.contains(where: { d.object(forKey: $0) != nil }) else { return }
        let allOn = olds.allSatisfy { d.object(forKey: $0) as? Bool ?? true }
        if d.object(forKey: masterKey) == nil {
            d.set(allOn, forKey: masterKey)
        }
        for k in olds { d.removeObject(forKey: k) }
    }

    // MARK: - Setup

    /// Egyszer hívandó (SummitApp .onAppear) — különben előtérben nem jelenik meg banner.
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

    // Értesítés-koppintás: jegy-értesítésből az ünneplő kártyát nyitja.
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        let info = response.notification.request.content.userInfo
        // Dolgozat-koppintás → Feladatok/Dolgozatok tab
        if (info["kind"] as? String) == "exams" {
            NotificationCenter.default.post(
                name: Notification.Name("summit.switchToTasks"),
                object: nil, userInfo: ["segment": "exams"]
            )
            return
        }
        guard let grade = Self.gradeFromUserInfo(info) else { return }
        await MainActor.run { NotificationManager.shared.celebrationGrade = grade }
    }

    // MARK: - Kártya userInfo (koppintás kilőtt appból is működik)

    nonisolated static func gradeUserInfo(_ g: GradeItem) -> [AnyHashable: Any] {
        [
            "kind": "grade", "id": g.id, "subject": g.subject, "value": g.value,
            "valueText": g.valueText, "topic": g.topic, "type": g.type,
            "teacher": g.teacher, "weight": g.weight,
            "date": g.date.timeIntervalSince1970,
        ]
    }

    nonisolated static func gradeFromUserInfo(_ info: [AnyHashable: Any]) -> GradeItem? {
        guard (info["kind"] as? String) == "grade",
              let subject = info["subject"] as? String,
              let value = info["value"] as? Int
        else { return nil }
        return GradeItem(
            id: (info["id"] as? String) ?? UUID().uuidString,
            subject: subject, value: value,
            valueText: (info["valueText"] as? String) ?? "\(value)",
            date: Date(timeIntervalSince1970: (info["date"] as? Double) ?? Date().timeIntervalSince1970),
            teacher: (info["teacher"] as? String) ?? "",
            type: (info["type"] as? String) ?? "",
            weight: (info["weight"] as? Int) ?? 100,
            topic: (info["topic"] as? String) ?? ""
        )
    }

    // MARK: - Diff + értesítés

    private func seenKey(_ kind: String, userId: String) -> String {
        "summit.seen\(kind).v1.\(userId)"
    }

    private func loadSeen(_ kind: String, userId: String) -> Set<String> {
        Set(UserDefaults.standard.stringArray(forKey: seenKey(kind, userId: userId)) ?? [])
    }

    private func saveSeen(_ kind: String, userId: String, ids: Set<String>) {
        UserDefaults.standard.set(Array(ids), forKey: seenKey(kind, userId: userId))
    }

    /// Diff-mag: első futáskor csak magot vet (nincs spam belépéskor),
    /// utána visszaadja az új ID-kat és lépteti a seen-készletet.
    /// Ütemezést nem végez — azt a hívó dönti el (azonnali / digest).
    private func fresh(kind: String, userId: String, ids: [String]) -> [String] {
        let key = seenKey(kind, userId: userId)
        guard UserDefaults.standard.object(forKey: key) != nil else {
            // Első találkozás: baseline mag, újdonság nélkül.
            UserDefaults.standard.set(ids, forKey: key)
            return []
        }
        var seen = loadSeen(kind, userId: userId)
        let new = ids.filter { !seen.contains($0) }
        guard !new.isEmpty else { return [] }
        new.forEach { seen.insert($0) }
        saveSeen(kind, userId: userId, ids: seen)
        return new
    }

    /// Olvasatlan-számláló per felhasználó — ebből lesz az ikon-jelvény száma.
    private func unreadKey(_ userId: String) -> String { "summit.unread.v1.\(userId)" }

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
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("summit-grade-\(value).png")
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

    private func schedule(id: String, title: String, body: String, userId: String, bumpBy: Int, imageURL: URL? = nil, userInfo: [AnyHashable: Any] = [:]) {
        if bumpBy > 0 { bumpBadge(userId: userId, by: bumpBy) }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        content.userInfo = userInfo
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

    /// Új elemek oldalhatás nélkül (toggle + diff, ütemezés nélkül) —
    /// a digest (checkAll) és az azonnali (checkX) ág közös alapja.
    private func freshGradeItems(_ grades: [GradeItem], userId: String) -> [GradeItem] {
        guard Self.isEnabled(Self.masterKey) else { return [] }
        let byId = Dictionary(uniqueKeysWithValues: grades.map { ($0.id, $0) })
        return fresh(kind: "Grades", userId: userId, ids: grades.map(\.id)).compactMap { byId[$0] }
    }

    private func freshHomeworkItems(_ items: [HomeworkItem], userId: String) -> [HomeworkItem] {
        guard Self.isEnabled(Self.masterKey) else { return [] }
        let byId = Dictionary(uniqueKeysWithValues: items.map { ($0.id, $0) })
        return fresh(kind: "Homework", userId: userId, ids: items.map(\.id)).compactMap { byId[$0] }
    }

    private func freshExamItems(_ items: [ExamItem], userId: String) -> [ExamItem] {
        guard Self.isEnabled(Self.masterKey) else { return [] }
        let byId = Dictionary(uniqueKeysWithValues: items.map { ($0.id, $0) })
        return fresh(kind: "Exams", userId: userId, ids: items.map(\.id)).compactMap { byId[$0] }
    }

    private func freshAbsenceCount(_ items: [AbsenceItem], userId: String) -> Int {
        guard Self.isEnabled(Self.masterKey) else { return 0 }
        return fresh(kind: "Absences", userId: userId, ids: items.map(\.id)).count
    }

    /// Jegy-bannerek: 1 db-nál specifikus, többnél összevont.
    private func scheduleGrades(_ items: [GradeItem], userId: String) {
        if items.count == 1, let g = items.first {
            schedule(
                id: "summit.grade.\(g.id)",
                title: "Új jegy: \(g.valueText) (\(g.subject))",
                body: [friendlyGradeType(g.type), g.plainTopic, g.teacher].filter { !$0.isEmpty }.joined(separator: " • "),
                userId: userId, bumpBy: 1,
                imageURL: gradeImageURL(value: g.value),
                userInfo: Self.gradeUserInfo(g)
            )
        } else {
            let latest = items.sorted(by: { $0.date > $1.date }).first
            schedule(
                id: "summit.grades.\(Int(Date().timeIntervalSince1970))",
                title: "\(items.count) új jegy érkezett",
                body: items.prefix(3)
                    .map { "\($0.valueText) • \($0.subject)" }.joined(separator: ", "),
                userId: userId, bumpBy: items.count,
                userInfo: latest.map { Self.gradeUserInfo($0) } ?? [:]
            )
        }
    }

    private func scheduleHomeworks(_ items: [HomeworkItem], userId: String) {
        if items.count == 1, let h = items.first {
            schedule(id: "summit.hw.\(h.id)", title: "Új házi: \(h.subject)", body: h.plainTitle, userId: userId, bumpBy: 1)
        } else {
            schedule(
                id: "summit.hw.\(Int(Date().timeIntervalSince1970))",
                title: "\(items.count) új házi feladat",
                body: items.prefix(3).map(\.subject).joined(separator: ", "),
                userId: userId, bumpBy: items.count
            )
        }
    }

    private func scheduleExams(_ items: [ExamItem], userId: String) {
        let df = DateFormatter(); df.locale = Locale(identifier: "hu_HU"); df.dateFormat = "MMM d."
        if items.count == 1, let e = items.first {
            schedule(
                id: "summit.exam.\(e.id)", title: "Új dolgozat: \(e.subject)",
                body: "\(e.mode) • \(df.string(from: e.date))\(e.plainDescription.isEmpty ? "" : " • \(e.plainDescription)")",
                userId: userId, bumpBy: 1,
                userInfo: ["kind": "exams"]
            )
        } else {
            schedule(
                id: "summit.exam.\(Int(Date().timeIntervalSince1970))",
                title: "\(items.count) új dolgozat",
                body: items.prefix(3).map(\.subject).joined(separator: ", "),
                userId: userId, bumpBy: items.count,
                userInfo: ["kind": "exams"]
            )
        }
    }

    private func scheduleAbsences(count: Int, userId: String) {
        schedule(
            id: "summit.abs.\(Int(Date().timeIntervalSince1970))",
            title: count == 1 ? "Új hiányzás" : "\(count) új hiányzás",
            body: "Nézd meg a Hiányzások fülön.",
            userId: userId, bumpBy: count
        )
    }

    /// Utazás mód alatt semmi nem megy ki — a seen-készlet viszont LÉPTETVE
    /// van (a diff alapja frissül), hogy hazatéréskor ne zúduljon rá a
    /// userre az egész nyaralás alatti elmaradás.
    @discardableResult
    func checkGrades(_ grades: [GradeItem], userId: String) -> Int {
        if TravelMode.isActive() {
            _ = freshGradeItems(grades, userId: userId)
            return 0
        }
        let items = freshGradeItems(grades, userId: userId)
        guard !items.isEmpty else { return 0 }
        // A legfrissebb új jegyre fullscreen ünneplő kártya is jár.
        if let latest = items.sorted(by: { $0.date > $1.date }).first {
            self.celebrationGrade = latest
        }
        scheduleGrades(items, userId: userId)
        return items.count
    }

    @discardableResult
    func checkHomeworks(_ items: [HomeworkItem], userId: String) -> Int {
        if TravelMode.isActive() {
            _ = freshHomeworkItems(items, userId: userId)
            return 0
        }
        let freshItems = freshHomeworkItems(items, userId: userId)
        guard !freshItems.isEmpty else { return 0 }
        scheduleHomeworks(freshItems, userId: userId)
        return freshItems.count
    }

    @discardableResult
    func checkExams(_ items: [ExamItem], userId: String) -> Int {
        if TravelMode.isActive() {
            _ = freshExamItems(items, userId: userId)
            return 0
        }
        let freshItems = freshExamItems(items, userId: userId)
        guard !freshItems.isEmpty else { return 0 }
        scheduleExams(freshItems, userId: userId)
        return freshItems.count
    }

    @discardableResult
    func checkAbsences(_ items: [AbsenceItem], userId: String) -> Int {
        if TravelMode.isActive() {
            _ = freshAbsenceCount(items, userId: userId)
            return 0
        }
        let count = freshAbsenceCount(items, userId: userId)
        guard count > 0 else { return 0 }
        scheduleAbsences(count: count, userId: userId)
        return count
    }

    /// Összevont kör: akárhány kategóriában van újdonság, legfeljebb
    /// 1 rendszer-banner megy ki (megnyitáskor nem torlódik 3-4).
    /// 1 db újdonságnál a specifikus banner jön (mint eddig).
    /// A HomeViewModel.refresh és a háttér-ébresztés is ezt hívja.
    @discardableResult
    func checkAll(grades: [GradeItem], homeworks: [HomeworkItem], exams: [ExamItem], absences: [AbsenceItem], userId: String) -> Int {
        // Utazás mód: a diff-alap léptetve, banner és ünneplő kártya nélkül.
        if TravelMode.isActive() {
            _ = freshGradeItems(grades, userId: userId)
            _ = freshHomeworkItems(homeworks, userId: userId)
            _ = freshExamItems(exams, userId: userId)
            _ = freshAbsenceCount(absences, userId: userId)
            return 0
        }
        let fg = freshGradeItems(grades, userId: userId)
        let fh = freshHomeworkItems(homeworks, userId: userId)
        let fe = freshExamItems(exams, userId: userId)
        let fa = freshAbsenceCount(absences, userId: userId)
        let total = fg.count + fh.count + fe.count + fa
        guard total > 0 else { return 0 }
        // A legfrissebb új jegyre fullscreen ünneplő kártya is jár.
        let latestGrade = fg.sorted(by: { $0.date > $1.date }).first
        if let latest = latestGrade {
            self.celebrationGrade = latest
        }
        if total == 1 {
            if let g = fg.first { scheduleGrades([g], userId: userId) }
            else if let h = fh.first { scheduleHomeworks([h], userId: userId) }
            else if let e = fe.first { scheduleExams([e], userId: userId) }
            else { scheduleAbsences(count: 1, userId: userId) }
            return 1
        }
        var lines: [String] = []
        if !fg.isEmpty {
            lines.append("\(fg.count) új jegy: " + (latestGrade.map { "\($0.valueText) • \($0.subject)" } ?? "") + (fg.count > 1 ? " (+\(fg.count - 1) további)" : ""))
        }
        if !fh.isEmpty {
            lines.append("\(fh.count) új házi: " + fh.prefix(2).map(\.subject).joined(separator: ", "))
        }
        if !fe.isEmpty {
            lines.append("\(fe.count) új dolgozat: " + fe.prefix(2).map(\.subject).joined(separator: ", "))
        }
        if fa > 0 {
            lines.append(fa == 1 ? "1 új hiányzás" : "\(fa) új hiányzás")
        }
        // Koppintási cél: jegy → ünneplő kártya, különben dolgozat → Feladatok tab.
        var tap: [AnyHashable: Any] = [:]
        if let latest = latestGrade {
            tap = Self.gradeUserInfo(latest)
        } else if !fe.isEmpty {
            tap = ["kind": "exams"]
        }
        schedule(
            id: "summit.digest.\(Int(Date().timeIntervalSince1970))",
            title: "\(total) újdonság a Krétában",
            body: lines.joined(separator: "\n"),
            userId: userId, bumpBy: total,
            userInfo: tap
        )
        return total
    }

    // MARK: - Demo teszt

    /// Azonnali teszt-banner (engedélyt is kér, ha még nincs).
    /// A jelvényt is +1-gyel mutatja, hogy az is tesztelhető legyen.
    func sendTest(userId: String) async {
        _ = await requestPermission()
        schedule(id: "summit.test.\(Int(Date().timeIntervalSince1970))",
                 title: "Teszt értesítés",
                 body: "Ha ezt látod, működnek a Summit értesítések.",
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
        // Demo teszt: a kártya azonnal felpattan (az értesítés mellé).
        celebrationGrade = fake
        return fake
    }

    /// Demo újrateszteléshez: elfelejti a látott ID-kat.
    func resetDemoSeen() {
        for kind in ["Grades", "Homework", "Exams", "Absences"] {
            UserDefaults.standard.removeObject(forKey: seenKey(kind, userId: "demo-user"))
        }
    }
}
