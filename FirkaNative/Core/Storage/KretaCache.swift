import CryptoKit
import Foundation
import Observation

// MARK: - KRÉTA-gyorstár: lemez + egyetlen közös adatforrás (stale-while-revalidate)
//
// Cél: hidegindításkor a Főoldal és az Órarend az ELSŐ képkockán a legutóbbi
// valós adatot mutassa, hálózatra várás nélkül; a frissítés a háttérben,
// adattípusonként fut, és látszik, hogy fut.
//
// Rétegek:
// - `KretaDiskCache`: fiókonkénti könyvtár (`Application Support/KretaCache/
//   <fiók-hash>/`), típusonként egy fájl + ISO-hetenként egy órarend-fájl.
//   Codable boríték {schema, savedAt, payload}, atomi írás, a kódolás és a
//   dekódolás a főszálon kívül (soros háttérsor). Fájlvédelem:
//   completeUntilFirstUserAuthentication (a háttér-ébresztés zárolt
//   képernyőn is olvashat), iCloud-mentésből kizárva.
// - `KretaStore`: a tabok EGYETLEN adatforrása (@Observable — a nézetek csak
//   akkor rajzolnak újra, ha az általuk olvasott típus változik). A
//   KretaClient minden sikeres hálózati válasza ide íródik (ingest), így a
//   háttér-ébresztés, a Watch-push és a widget-előtöltés is ugyanazt a
//   gyorstárat tartja frissen.
// - Fiókváltás / kijelentkezés: a memória azonnal ürül, a lemezen minden
//   fióknak saját könyvtára van — A fiók adata B-nek soha nem látszik.
//   Kijelentkezéskor a fiók könyvtára törlődik.

/// Gyorstárazott adattípus. Az órarend és a naptári napok ISO-hetenként
/// (hétfő 00:00 a kulcs) — minden fogyasztó ugyanazt a hetet kéri, így a
/// Főoldal, az Órarend, a Feladatok, a Watch és a widget kulcsai közösek.
enum KretaDataKind: Hashable, Sendable {
    case grades, homework, exams, absences, messages, subjects
    case timetable(Date)
    case calendar(Date)
}

// MARK: - ISO-hét segédek

enum KretaWeek {
    /// Az adott nap hetének hétfője (nap eleje), a rendszer-naptárban.
    static func monday(for date: Date, calendar: Calendar = .current) -> Date {
        let day = calendar.startOfDay(for: date)
        let weekday = calendar.component(.weekday, from: day)
        let offset = weekday == 1 ? -6 : 2 - weekday
        return calendar.date(byAdding: .day, value: offset, to: day) ?? day
    }

    static func adding(weeks: Int, to monday: Date, calendar: Calendar = .current) -> Date {
        calendar.date(byAdding: .day, value: weeks * 7, to: monday) ?? monday
    }

    /// A hét vége (következő hétfő 00:00) — a hét tartománya [hétfő, ez).
    static func end(of monday: Date, calendar: Calendar = .current) -> Date {
        adding(weeks: 1, to: monday, calendar: calendar)
    }

    /// Minden hétfő, amelynek hete metszi a [from, to) tartományt.
    static func mondays(covering from: Date, to: Date, calendar: Calendar = .current) -> [Date] {
        guard to > from else { return [monday(for: from, calendar: calendar)] }
        var out: [Date] = []
        var m = monday(for: from, calendar: calendar)
        while m < to && out.count < 60 {
            out.append(m)
            m = adding(weeks: 1, to: m, calendar: calendar)
        }
        return out
    }

    /// Hány héttel van a mostani hét után (negatív: múlt).
    static func offset(of monday: Date, now: Date = Date(), calendar: Calendar = .current) -> Int {
        let current = self.monday(for: now, calendar: calendar)
        let days = calendar.dateComponents([.day], from: current, to: monday).day ?? 0
        return Int((Double(days) / 7.0).rounded())
    }

    /// Fájlnév-kulcs (yyyy-MM-dd, helyi naptár szerint).
    static func key(for monday: Date, calendar: Calendar = .current) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: monday)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    static func monday(fromKey key: String, calendar: Calendar = .current) -> Date? {
        let parts = key.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        return calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2]))
            .map { calendar.startOfDay(for: $0) }
    }
}

// MARK: - Frissítési szabályok

/// Mikor számít egy gyorstárazott adat frissnek (ilyenkor a nem kényszerített
/// lekérés hálózat nélkül tér vissza). A lehúzás (force) mindig frissít.
enum KretaRefreshPolicy {
    /// Jegyek, házik, dolgozatok, hiányzások, üzenetek, aktuális + jövő hét:
    /// előtérbe hozáskor / tabra lépéskor legfeljebb ennyi időnként.
    static let foregroundInterval: TimeInterval = 120
    /// Távolabbi jövőbeli hetek (+2…): kor szerint.
    static let farWeekInterval: TimeInterval = 6 * 3600
    /// Naptári napok (tanév rendje): naponta.
    static let calendarInterval: TimeInterval = 24 * 3600
    /// Tantárgylista: hetente.
    static let subjectsInterval: TimeInterval = 7 * 24 * 3600

    static func isFresh(_ kind: KretaDataKind, savedAt: Date, now: Date = Date()) -> Bool {
        let age = now.timeIntervalSince(savedAt)
        guard age >= 0 else { return false }
        switch kind {
        case .grades, .homework, .exams, .absences, .messages:
            return age < foregroundInterval
        case .subjects:
            return age < subjectsInterval
        case .calendar:
            return age < calendarInterval
        case .timetable(let monday):
            let off = KretaWeek.offset(of: monday, now: now)
            // Múlt hét: magától soha (csak lehúzásra) — a lezárt hét nem változik.
            if off < 0 { return true }
            if off <= 1 { return age < foregroundInterval }
            return age < farWeekInterval
        }
    }
}

// MARK: - Lemez

/// Mentett érték + mentési idő (memóriában és a lemezen is).
struct KretaCached<Value: Sendable>: Sendable {
    var value: Value
    var savedAt: Date
}

/// Naptári napok hosszú tartománya (vakáció-számláló: most → aug. 31.).
struct KretaCalendarSpan: Codable, Sendable {
    var from: Date
    var to: Date
    var days: [SchoolDayInfo]
}

/// Indításkori pillanatkép a lemezről (háttérben épül).
struct KretaCacheSnapshot: Sendable {
    var grades: KretaCached<[GradeItem]>?
    var homework: KretaCached<[HomeworkItem]>?
    var exams: KretaCached<[ExamItem]>?
    var absences: KretaCached<[AbsenceItem]>?
    var messages: KretaCached<[MessageItem]>?
    var subjects: KretaCached<[String]>?
    var weeks: [Date: KretaCached<[LessonItem]>] = [:]
    var calendarWeeks: [Date: KretaCached<[SchoolDayInfo]>] = [:]
    var calendarSpan: KretaCached<KretaCalendarSpan>?
    var homeworkDetails: KretaCached<[String: KretaHomeworkDetailEntry]>?
}

/// Házi-részlet csatolmány-eredménye (az üres is: negatív gyorstár — a
/// csatolmány nélküli házihoz nem kérdezünk minden tabra lépéskor újra).
struct KretaHomeworkDetailEntry: Codable, Sendable {
    var attachments: [AttachmentItem]
    var checkedAt: Date
}

final class KretaDiskCache: @unchecked Sendable {
    /// A tárolt tételek szerkezetének verziója. Mezőváltozáskor léptetni
    /// kell — az eltérő verziójú fájlok olvasáskor törlődnek.
    static let schema = 1
    /// Órarend-megőrzés: ennyi hét vissza / előre (a Feladatok tab −35 napos
    /// csatolmány-ablaka és a 60 napos dolgozat-pótló horizont is belefér).
    static let keepPastWeeks = 6
    static let keepFutureWeeks = 10

    let accountHash: String
    let directory: URL
    /// Minden lemezművelet ezen a soros soron fut (sorrendtartó írás, a
    /// kódolás/dekódolás nem a főszálon).
    private let queue: DispatchQueue

    private struct Envelope<Payload: Codable>: Codable {
        let schema: Int
        let savedAt: Date
        let payload: Payload
    }

    /// A gyorstár gyökere: Application Support/KretaCache (iCloud-mentésből kizárva).
    static func rootDirectory() -> URL? {
        guard let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else { return nil }
        return base.appendingPathComponent("KretaCache", isDirectory: true)
    }

    init?(accountHash: String) {
        guard let root = Self.rootDirectory() else { return nil }
        self.accountHash = accountHash
        self.directory = root.appendingPathComponent(accountHash, isDirectory: true)
        self.queue = DispatchQueue(label: "hu.flint.summit.kretacache.\(accountHash.prefix(8))", qos: .utility)
    }

    /// Könyvtár létrehozása (+ backup-kizárás a gyökeren). Csak a soron hívjuk.
    private func ensureDirectory() throws {
        let fm = FileManager.default
        guard let root = Self.rootDirectory() else { throw CocoaError(.fileNoSuchFile) }
        if !fm.fileExists(atPath: root.path) {
            try fm.createDirectory(at: root, withIntermediateDirectories: true,
                                   attributes: [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication])
            var rootURL = root
            var values = URLResourceValues()
            values.isExcludedFromBackup = true
            try rootURL.setResourceValues(values)
        }
        if !fm.fileExists(atPath: directory.path) {
            try fm.createDirectory(at: directory, withIntermediateDirectories: true,
                                   attributes: [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication])
        }
    }

    // MARK: Fájlnevek

    static func fileName(for kind: KretaDataKind) -> String {
        switch kind {
        case .grades: return "grades.json"
        case .homework: return "homework.json"
        case .exams: return "exams.json"
        case .absences: return "absences.json"
        case .messages: return "messages.json"
        case .subjects: return "subjects.json"
        case .timetable(let m): return "tt-\(KretaWeek.key(for: m)).json"
        case .calendar(let m): return "cal-\(KretaWeek.key(for: m)).json"
        }
    }
    static let calendarSpanFile = "calendar-span.json"
    static let homeworkDetailsFile = "homework-details.json"

    // MARK: Írás

    /// Aszinkron, sorrendtartó írás: a kódolás a háttérsoron fut.
    /// Hiba esetén a fájl törlődik (félkész/régi tartalom ne maradjon),
    /// és a hiba a diagnosztikai naplóba kerül.
    func write<Payload: Codable & Sendable>(_ payload: Payload, savedAt: Date, file: String) {
        queue.async { [self] in
            do {
                try ensureDirectory()
                let data = try JSONEncoder().encode(Envelope(schema: Self.schema, savedAt: savedAt, payload: payload))
                try data.write(to: directory.appendingPathComponent(file),
                               options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
            } catch {
                try? FileManager.default.removeItem(at: directory.appendingPathComponent(file))
                let msg = "gyorstár-írás hiba (\(file)): \(error.localizedDescription)"
                Task { @MainActor in KretaDiagLog.shared.append(msg) }
            }
        }
    }

    func remove(file: String) {
        queue.async { [self] in
            try? FileManager.default.removeItem(at: directory.appendingPathComponent(file))
        }
    }

    // MARK: Olvasás

    /// Egy boríték olvasása; eltérő séma / sérült fájl → törlés, nil.
    private func read<Payload: Codable>(_ type: Payload.Type, file: String) -> KretaCached<Payload>? where Payload: Sendable {
        let url = directory.appendingPathComponent(file)
        guard let data = try? Data(contentsOf: url) else { return nil }
        guard let env = try? JSONDecoder().decode(Envelope<Payload>.self, from: data), env.schema == Self.schema else {
            try? FileManager.default.removeItem(at: url)
            return nil
        }
        return KretaCached(value: env.payload, savedAt: env.savedAt)
    }

    /// Teljes pillanatkép a lemezről — szinkron, a hívó gondoskodik róla,
    /// hogy NE a főszálon fusson (a soron fut, a függő írások után).
    /// A megőrzési ablakon kívüli órarend-/naptár-heteket közben törli.
    func loadSnapshotSync(now: Date = Date()) -> KretaCacheSnapshot {
        queue.sync { loadSnapshotOnQueue(now: now) }
    }

    func loadSnapshot(now: Date = Date()) async -> KretaCacheSnapshot {
        await withCheckedContinuation { cont in
            queue.async { [self] in cont.resume(returning: loadSnapshotOnQueue(now: now)) }
        }
    }

    private func loadSnapshotOnQueue(now: Date) -> KretaCacheSnapshot {
        var snap = KretaCacheSnapshot()
        snap.grades = read([GradeItem].self, file: Self.fileName(for: .grades))
        snap.homework = read([HomeworkItem].self, file: Self.fileName(for: .homework))
        snap.exams = read([ExamItem].self, file: Self.fileName(for: .exams))
        snap.absences = read([AbsenceItem].self, file: Self.fileName(for: .absences))
        snap.messages = read([MessageItem].self, file: Self.fileName(for: .messages))
        snap.subjects = read([String].self, file: Self.fileName(for: .subjects))
        snap.calendarSpan = read(KretaCalendarSpan.self, file: Self.calendarSpanFile)
        snap.homeworkDetails = read([String: KretaHomeworkDetailEntry].self, file: Self.homeworkDetailsFile)
        let current = KretaWeek.monday(for: now)
        let oldest = KretaWeek.adding(weeks: -Self.keepPastWeeks, to: current)
        let newest = KretaWeek.adding(weeks: Self.keepFutureWeeks, to: current)
        let files = (try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []
        for name in files where name.hasSuffix(".json") {
            let isTT = name.hasPrefix("tt-"), isCal = name.hasPrefix("cal-")
            guard isTT || isCal else { continue }
            let key = String(name.dropFirst(isTT ? 3 : 4).dropLast(5))
            guard let monday = KretaWeek.monday(fromKey: key) else {
                try? FileManager.default.removeItem(at: directory.appendingPathComponent(name))
                continue
            }
            guard monday >= oldest, monday <= newest else {
                try? FileManager.default.removeItem(at: directory.appendingPathComponent(name))
                continue
            }
            if isTT {
                if let w = read([LessonItem].self, file: name) { snap.weeks[monday] = w }
            } else if let c = read([SchoolDayInfo].self, file: name) {
                snap.calendarWeeks[monday] = c
            }
        }
        return snap
    }

    // MARK: Törlés

    /// Egy fiók teljes gyorstára (kijelentkezés).
    static func wipe(accountHash: String) {
        guard let root = rootDirectory() else { return }
        let dir = root.appendingPathComponent(accountHash, isDirectory: true)
        DispatchQueue.global(qos: .utility).async {
            try? FileManager.default.removeItem(at: dir)
        }
    }

    /// Az élő fiókokon kívüli könyvtárak törlése (pl. régi, már nem létező fiók).
    static func prune(keeping hashes: Set<String>) {
        guard let root = rootDirectory() else { return }
        DispatchQueue.global(qos: .utility).async {
            let fm = FileManager.default
            guard let names = try? fm.contentsOfDirectory(atPath: root.path) else { return }
            for name in names where !hashes.contains(name) {
                try? fm.removeItem(at: root.appendingPathComponent(name, isDirectory: true))
            }
        }
    }
}

// MARK: - Közös adatforrás

@MainActor
@Observable
final class KretaStore {
    static let shared = KretaStore()

    /// Az aktív fiók gyorstár-kulcsa (SHA-256 a fiókkulcsból — a fájlútban
    /// nincs felhasználónév / intézmény).
    private(set) var accountHash: String?
    /// Helyi (demo / tesztfiók) backend: nincs lemez, a DemoData tölt.
    private(set) var isLocalBackend = false
    /// Amíg a fiók lemezes pillanatképe töltődik: a nézetek ilyenkor nem
    /// mutatnak üres állapotot („Nincs jegy"), mert az adat nem ismert.
    private(set) var isBootstrapping = false

    private(set) var grades: KretaCached<[GradeItem]>?
    private(set) var homework: KretaCached<[HomeworkItem]>?
    private(set) var exams: KretaCached<[ExamItem]>?
    private(set) var absences: KretaCached<[AbsenceItem]>?
    private(set) var messages: KretaCached<[MessageItem]>?
    private(set) var subjects: KretaCached<[String]>?
    private(set) var weeks: [Date: KretaCached<[LessonItem]>] = [:]
    private(set) var calendarWeeks: [Date: KretaCached<[SchoolDayInfo]>] = [:]

    /// Éppen frissülő típusok („Frissítés…").
    private(set) var refreshing: Set<KretaDataKind> = []
    /// Legutóbbi frissítési kísérlete sikertelen volt („Mentve: …").
    private(set) var failed: Set<KretaDataKind> = []

    @ObservationIgnored private var calendarSpan: KretaCached<KretaCalendarSpan>?
    @ObservationIgnored private var homeworkDetails: [String: KretaHomeworkDetailEntry] = [:]
    @ObservationIgnored private var disk: KretaDiskCache?
    /// Egyszerre futó frissítések számlálója típusonként (két hívó is
    /// frissítheti ugyanazt — a jelző csak az utolsó végén alszik ki).
    @ObservationIgnored private var refreshDepth: [KretaDataKind: Int] = [:]
    /// Indításkori háttér-betöltés (App.init kezdi, a végén veszi át).
    @ObservationIgnored private var launchLoad: (hash: String, group: DispatchGroup, box: SnapshotBox)?

    /// Utolsó aktív fiók mutatója (indításkori előtöltéshez, a SessionStore
    /// Keychain-olvasása nélkül). Csak hash — személyes adat nincs benne.
    private static let lastAccountKey = "kretaCache.lastAccount.v1"
    private static let lastLocalKey = "kretaCache.lastAccountLocal.v1"

    private init() {}

    /// Fiók → gyorstár-kulcs. A demo/tesztfiók külön kulcsot kap.
    static func accountHash(for user: AppUser) -> String {
        let digest = SHA256.hash(data: Data(("summit.kretacache|" + user.accountKey).utf8))
        return digest.prefix(16).map { String(format: "%02x", $0) }.joined()
    }

    // MARK: Indítás

    /// Thread-safe doboz a háttérben épülő pillanatképnek.
    final class SnapshotBox: @unchecked Sendable {
        var snapshot: KretaCacheSnapshot?
    }

    /// App.init ELEJÉN: a legutóbbi fiók lemezes gyorstárának betöltése
    /// háttérszálon indul (a dekódolás nem a főszálon fut), miközben az
    /// init a többi indítási munkát végzi.
    func beginLaunchBootstrap() {
        let d = UserDefaults.standard
        guard let hash = d.string(forKey: Self.lastAccountKey), !hash.isEmpty else { return }
        if d.bool(forKey: Self.lastLocalKey) {
            // Helyi backend: a DemoData olcsó, szinkron tölthető.
            accountHash = hash
            isLocalBackend = true
            fillLocalBackend()
            return
        }
        guard let cache = KretaDiskCache(accountHash: hash) else { return }
        let group = DispatchGroup()
        let box = SnapshotBox()
        group.enter()
        DispatchQueue.global(qos: .userInteractive).async {
            box.snapshot = cache.loadSnapshotSync()
            group.leave()
        }
        accountHash = hash
        disk = cache
        isBootstrapping = true
        launchLoad = (hash, group, box)
    }

    /// App.init VÉGÉN: a háttérben elkészült pillanatkép átvétele, még
    /// mielőtt bármelyik nézet megszületne — így az első képkocka már a
    /// mentett adatot rajzolja. Ha a lemez lassú, legfeljebb `timeout`-ig
    /// várunk; utána a betöltés aszinkron fejeződik be (a nézetek addig
    /// semleges állapotot mutatnak, nem hamis üres állapotot).
    func completeLaunchBootstrap(timeout: TimeInterval = 0.8) {
        guard let load = launchLoad else { return }
        if load.group.wait(timeout: .now() + timeout) == .success, let snap = load.box.snapshot {
            launchLoad = nil
            apply(snap)
            isBootstrapping = false
            return
        }
        load.group.notify(queue: .main) { [weak self] in
            MainActor.assumeIsolated {
                guard let self, self.accountHash == load.hash, let snap = load.box.snapshot else { return }
                self.launchLoad = nil
                self.apply(snap)
                self.isBootstrapping = false
            }
        }
    }

    // MARK: Fiók-aktiválás

    /// A kiválasztott fiók gyorstárának élesítése (indításkor, fiókváltáskor,
    /// háttér-ébresztéskor). Más fióknál a memória AZONNAL ürül, mielőtt az
    /// új fiók adata betöltődne. Nil user: kijelentkezett állapot.
    /// - Parameter knownAccounts: az eszközön élő fiókok (a többiek könyvtára törlődik).
    func activate(_ user: AppUser?, knownAccounts: [AppUser] = []) {
        guard let user else {
            clearMemory()
            accountHash = nil
            disk = nil
            launchLoad = nil
            isLocalBackend = false
            isBootstrapping = false
            UserDefaults.standard.removeObject(forKey: Self.lastAccountKey)
            UserDefaults.standard.removeObject(forKey: Self.lastLocalKey)
            if !knownAccounts.isEmpty { KretaDiskCache.prune(keeping: Set(knownAccounts.map(Self.accountHash(for:)))) }
            return
        }
        let hash = Self.accountHash(for: user)
        let local = user.isLocalBackend
        if !knownAccounts.isEmpty {
            KretaDiskCache.prune(keeping: Set((knownAccounts + [user]).filter { !$0.isLocalBackend }.map(Self.accountHash(for:))))
        }
        UserDefaults.standard.set(hash, forKey: Self.lastAccountKey)
        UserDefaults.standard.set(local, forKey: Self.lastLocalKey)
        guard hash != accountHash else { return }
        clearMemory()
        launchLoad = nil
        accountHash = hash
        isLocalBackend = local
        if local {
            disk = nil
            isBootstrapping = false
            fillLocalBackend()
            return
        }
        guard let cache = KretaDiskCache(accountHash: hash) else {
            disk = nil
            isBootstrapping = false
            return
        }
        disk = cache
        isBootstrapping = true
        Task { [weak self] in
            let snap = await cache.loadSnapshot()
            guard let self, self.accountHash == hash else { return }
            self.apply(snap)
            self.isBootstrapping = false
        }
    }

    /// Háttér-útvonalakhoz (BG-ébresztés, óra-ébresztés): aktiválás és a
    /// lemezes pillanatkép megvárása, mielőtt a hálózati eredmény beíródik.
    func activateAndWait(_ user: AppUser) async {
        activate(user)
        while isBootstrapping, accountHash == Self.accountHash(for: user) {
            try? await Task.sleep(nanoseconds: 20_000_000)
        }
    }

    /// Kijelentkezés: a fiók lemezes gyorstára törlődik, aktív fióknál a memória is.
    func forget(_ user: AppUser) {
        let hash = Self.accountHash(for: user)
        KretaDiskCache.wipe(accountHash: hash)
        if hash == accountHash {
            clearMemory()
            accountHash = nil
            disk = nil
            launchLoad = nil
            isBootstrapping = false
        }
        if UserDefaults.standard.string(forKey: Self.lastAccountKey) == hash {
            UserDefaults.standard.removeObject(forKey: Self.lastAccountKey)
            UserDefaults.standard.removeObject(forKey: Self.lastLocalKey)
        }
    }

    private func clearMemory() {
        grades = nil; homework = nil; exams = nil; absences = nil; messages = nil; subjects = nil
        weeks = [:]; calendarWeeks = [:]
        calendarSpan = nil; homeworkDetails = [:]
        refreshing = []; failed = []; refreshDepth = [:]
    }

    private func apply(_ snap: KretaCacheSnapshot) {
        // Ami közben a hálózatról már frissebben megjött, az nyer.
        func newer<T>(_ current: KretaCached<T>?, _ disk: KretaCached<T>?) -> KretaCached<T>? {
            guard let disk else { return current }
            guard let current else { return disk }
            return current.savedAt >= disk.savedAt ? current : disk
        }
        grades = newer(grades, snap.grades)
        homework = newer(homework, snap.homework)
        exams = newer(exams, snap.exams)
        absences = newer(absences, snap.absences)
        messages = newer(messages, snap.messages)
        subjects = newer(subjects, snap.subjects)
        var w = weeks
        for (m, v) in snap.weeks { w[m] = newer(w[m], v) }
        weeks = w
        var c = calendarWeeks
        for (m, v) in snap.calendarWeeks { c[m] = newer(c[m], v) }
        calendarWeeks = c
        calendarSpan = newer(calendarSpan, snap.calendarSpan)
        if let hd = snap.homeworkDetails?.value {
            homeworkDetails.merge(hd) { current, _ in current }
        }
    }

    /// Helyi backend: a DemoData szinkron töltése (a mostani ± 1 hét).
    private func fillLocalBackend() {
        let now = Date()
        grades = KretaCached(value: DemoData.gradesExpanded().sorted { $0.date > $1.date }, savedAt: now)
        homework = KretaCached(value: DemoData.homeworks(), savedAt: now)
        exams = KretaCached(value: DemoData.exams().sorted { $0.date < $1.date }, savedAt: now)
        absences = KretaCached(value: DemoData.absences(), savedAt: now)
        messages = KretaCached(value: DemoData.messages(), savedAt: now)
        let current = KretaWeek.monday(for: now)
        var w: [Date: KretaCached<[LessonItem]>] = [:]
        for off in -1...2 {
            let m = KretaWeek.adding(weeks: off, to: current)
            w[m] = KretaCached(value: DemoData.lessons(from: m, to: KretaWeek.end(of: m)), savedAt: now)
        }
        weeks = w
    }

    // MARK: Olvasás (KretaClient + nézetek)

    /// Ehhez a fiókhoz tartozik-e az aktív gyorstár.
    func isActive(account: String?) -> Bool {
        guard let account else { return false }
        return account == accountHash
    }

    func savedAt(_ kind: KretaDataKind) -> Date? {
        switch kind {
        case .grades: return grades?.savedAt
        case .homework: return homework?.savedAt
        case .exams: return exams?.savedAt
        case .absences: return absences?.savedAt
        case .messages: return messages?.savedAt
        case .subjects: return subjects?.savedAt
        case .timetable(let m): return weeks[m]?.savedAt
        case .calendar(let m): return calendarWeeks[m]?.savedAt
        }
    }

    /// Típusos érték (bármilyen korú) — a hívó típusa dönt (`[GradeItem]` stb.).
    func value<T>(_ kind: KretaDataKind) -> T? {
        switch kind {
        case .grades: return grades?.value as? T
        case .homework: return homework?.value as? T
        case .exams: return exams?.value as? T
        case .absences: return absences?.value as? T
        case .messages: return messages?.value as? T
        case .subjects: return subjects?.value as? T
        case .timetable(let m): return weeks[m]?.value as? T
        case .calendar(let m): return calendarWeeks[m]?.value as? T
        }
    }

    /// Csak frissnek számító érték (KretaRefreshPolicy).
    func freshValue<T>(_ kind: KretaDataKind, account: String?) -> T? {
        guard isActive(account: account), let at = savedAt(kind),
              KretaRefreshPolicy.isFresh(kind, savedAt: at) else { return nil }
        return value(kind)
    }

    /// Egy hét órái (nil: még nincs róla adat).
    func lessons(week monday: Date) -> [LessonItem]? { weeks[monday]?.value }

    /// Órák egy tetszőleges tartományban, a gyorstárazott hetekből.
    /// Nil, ha bármelyik érintett hét hiányzik (a hívó nem tudhatja, üres-e).
    func lessons(from: Date, to: Date) -> [LessonItem]? {
        var out: [LessonItem] = []
        for m in KretaWeek.mondays(covering: from, to: to) {
            guard let w = weeks[m]?.value else { return nil }
            out.append(contentsOf: w)
        }
        return out.filter { $0.start >= from && $0.start < to }.sorted { $0.start < $1.start }
    }

    /// Ami a tartományból megvan (hiányzó hetek nélkül) — a Feladatok
    /// csatolmány-összefésüléséhez, ahol a részleges anyag is hasznos.
    func availableLessons(from: Date, to: Date) -> [LessonItem] {
        KretaWeek.mondays(covering: from, to: to)
            .flatMap { weeks[$0]?.value ?? [] }
            .filter { $0.start >= from && $0.start < to }
            .sorted { $0.start < $1.start }
    }

    func calendarDays(week monday: Date) -> [SchoolDayInfo]? { calendarWeeks[monday]?.value }

    func calendarSpanDays(from: Date, to: Date, freshOnly: Bool, account: String?) -> [SchoolDayInfo]? {
        guard isActive(account: account), let span = calendarSpan else { return nil }
        let cal = Calendar.current
        guard span.value.from <= cal.startOfDay(for: from), span.value.to >= to else { return nil }
        if freshOnly, Date().timeIntervalSince(span.savedAt) >= KretaRefreshPolicy.calendarInterval { return nil }
        return span.value.days.filter { $0.date >= cal.startOfDay(for: from) && $0.date <= to }
    }

    /// Házi-részlet gyorstár: nem üres eredmény a lista-ablakon belül
    /// végleges, az üres (nincs fájl) egy napig.
    func homeworkDetail(_ id: String, account: String?) -> [AttachmentItem]? {
        guard isActive(account: account), let e = homeworkDetails[id] else { return nil }
        if e.attachments.isEmpty, Date().timeIntervalSince(e.checkedAt) >= KretaRefreshPolicy.calendarInterval { return nil }
        return e.attachments
    }

    // MARK: Írás (a KretaClient sikeres hálózati válaszaiból)

    /// Sikeres lehúzás beírása + mentés. Más fiók válasza (fiókváltás közben
    /// beérkező kérés) eldobódik.
    func ingest<T>(_ value: T, kind: KretaDataKind, account: String?, at date: Date = Date()) {
        guard isActive(account: account) else { return }
        switch kind {
        case .grades:
            guard let v = value as? [GradeItem] else { return assertionFailure("típushiba: \(kind)") }
            grades = KretaCached(value: v, savedAt: date); persist(v, kind: kind, at: date)
        case .homework:
            guard let v = value as? [HomeworkItem] else { return assertionFailure("típushiba: \(kind)") }
            homework = KretaCached(value: v, savedAt: date); persist(v, kind: kind, at: date)
        case .exams:
            guard let v = value as? [ExamItem] else { return assertionFailure("típushiba: \(kind)") }
            exams = KretaCached(value: v, savedAt: date); persist(v, kind: kind, at: date)
        case .absences:
            guard let v = value as? [AbsenceItem] else { return assertionFailure("típushiba: \(kind)") }
            absences = KretaCached(value: v, savedAt: date); persist(v, kind: kind, at: date)
        case .messages:
            guard let v = value as? [MessageItem] else { return assertionFailure("típushiba: \(kind)") }
            messages = KretaCached(value: v, savedAt: date); persist(v, kind: kind, at: date)
        case .subjects:
            guard let v = value as? [String] else { return assertionFailure("típushiba: \(kind)") }
            subjects = KretaCached(value: v, savedAt: date); persist(v, kind: kind, at: date)
        case .timetable(let m):
            guard let v = value as? [LessonItem] else { return assertionFailure("típushiba: \(kind)") }
            weeks[m] = KretaCached(value: v, savedAt: date); persist(v, kind: kind, at: date)
        case .calendar(let m):
            guard let v = value as? [SchoolDayInfo] else { return assertionFailure("típushiba: \(kind)") }
            calendarWeeks[m] = KretaCached(value: v, savedAt: date); persist(v, kind: kind, at: date)
        }
        failed.remove(kind)
    }

    private func persist<Payload: Codable & Sendable>(_ payload: Payload, kind: KretaDataKind, at date: Date) {
        disk?.write(payload, savedAt: date, file: KretaDiskCache.fileName(for: kind))
    }

    func ingestCalendarSpan(from: Date, to: Date, days: [SchoolDayInfo], account: String?) {
        guard isActive(account: account) else { return }
        let span = KretaCalendarSpan(from: Calendar.current.startOfDay(for: from), to: to, days: days)
        let now = Date()
        calendarSpan = KretaCached(value: span, savedAt: now)
        disk?.write(span, savedAt: now, file: KretaDiskCache.calendarSpanFile)
    }

    func ingestHomeworkDetails(_ found: [String: [AttachmentItem]], account: String?) {
        guard isActive(account: account), !found.isEmpty else { return }
        let now = Date()
        for (id, atts) in found { homeworkDetails[id] = KretaHomeworkDetailEntry(attachments: atts, checkedAt: now) }
        // A lista-ablakon (30 nap) kívül eső régi bejegyzések nem nőhetnek a végtelenségig.
        if homeworkDetails.count > 400 {
            let keep = homeworkDetails.sorted { $0.value.checkedAt > $1.value.checkedAt }.prefix(300)
            homeworkDetails = Dictionary(uniqueKeysWithValues: keep.map { ($0.key, $0.value) })
        }
        disk?.write(homeworkDetails, savedAt: now, file: KretaDiskCache.homeworkDetailsFile)
    }

    // MARK: Frissítés-állapot

    func beginRefresh(_ kind: KretaDataKind, account: String?) {
        guard isActive(account: account) else { return }
        refreshDepth[kind, default: 0] += 1
        refreshing.insert(kind)
    }

    func endRefresh(_ kind: KretaDataKind, success: Bool, account: String?) {
        guard isActive(account: account) else { return }
        let depth = max(0, (refreshDepth[kind] ?? 1) - 1)
        refreshDepth[kind] = depth == 0 ? nil : depth
        if depth == 0 { refreshing.remove(kind) }
        if !success { failed.insert(kind) }
    }

    /// Képernyő-szintű állapot a „Frissítés…" / „Mentve: …" sorhoz.
    enum ScreenStatus: Equatable {
        case idle
        case refreshing
        /// Sikertelen frissítés után a mentett adat ideje (a legrégebbi érintetté).
        case saved(Date)
    }

    func status(for kinds: [KretaDataKind]) -> ScreenStatus {
        if kinds.contains(where: { refreshing.contains($0) }) { return .refreshing }
        let stale = kinds.filter { failed.contains($0) }.compactMap { savedAt($0) }
        if let oldest = stale.min() { return .saved(oldest) }
        return .idle
    }
}
