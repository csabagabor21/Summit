import SwiftUI
import Combine

@MainActor
final class ProfileImageStore: ObservableObject {
    /// Profilkép változott (mentés/törlés) — a SummitSync erre jelöli
    /// piszkosnak a `photo` mezőt (delta-feltöltés).
    static let changedNotification = Notification.Name("summit.profileImageChanged")

    /// Eszköz- és belépésfüggetlen képkulcs: az AppUser.id belépésenként
    /// új UUID, ezért a JWT stabil kulcsa (sub/e-mail) az elsődleges —
    /// csak így találja meg a másik eszköz / új belépés ugyanazt a képet.
    /// A kulcs csak fájlnév, sehova nem kerül fel.
    static func key(userId: String?, accessToken: String?) -> String {
        if let at = accessToken, !at.isEmpty,
           let s = JWT.stableUserKey(from: at), !s.isEmpty {
            return "stable-\(s)"
        }
        if let u = userId, !u.isEmpty { return u }
        return "default"
    }

    /// Dekódolt képek. NEM @Published: a régi kód a nézet body-jából olvasta
    /// a lemezt, dekódolta a JPEG-et a főszálon, és közben (frissítés alatt)
    /// publikált. Most a body csak a memóriából olvas; hiánynál a betöltés
    /// háttérben fut, és a kész kép után egyetlen objectWillChange jön.
    private var cache: [String: UIImage] = [:]
    /// Nincs kép ehhez a kulcshoz (ne nézzük meg minden body-ban újra).
    private var missing: Set<String> = []
    private var loading: Set<String> = []

    init() {
        // Indításkor a meglévő profilkép(ek) háttérben dekódolódnak, hogy a
        // Főoldal fejléce lehetőleg már az első képkockán a képet mutassa.
        let dir = Self.directory
        Task.detached(priority: .userInitiated) { [weak self] in
            let names = (try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? []
            var decoded: [String: UIImage] = [:]
            for name in names where name.hasSuffix(".jpg") {
                let url = dir.appendingPathComponent(name)
                if let data = try? Data(contentsOf: url), let img = UIImage(data: data)?.preparingForDisplay() {
                    decoded[String(name.dropLast(4))] = img
                }
            }
            guard !decoded.isEmpty else { return }
            let ready = decoded
            await self?.adopt(ready)
        }
    }

    /// Háttérben dekódolt képek átvétele (főszálon, nézet-frissítésen kívül).
    private func adopt(_ images: [String: UIImage]) {
        for (k, v) in images where cache[k] == nil { cache[k] = v }
        objectWillChange.send()
    }

    private func finishLoad(_ id: String, image: UIImage?) {
        loading.remove(id)
        if let image {
            cache[id] = image
            objectWillChange.send()
        } else {
            missing.insert(id)
        }
    }

    /// Body-biztos olvasás: csak memória; hiánynál háttér-betöltés indul.
    func image(for userId: String?) -> UIImage? {
        guard let id = userId, !id.isEmpty else { return nil }
        if let c = cache[id] { return c }
        guard !missing.contains(id) else { return nil }
        load(id)
        return nil
    }

    /// Szinkron olvasás nézeten kívüli hívóknak (pl. a SummitSync feltöltése).
    func loadedImage(for userId: String?) -> UIImage? {
        guard let id = userId, !id.isEmpty else { return nil }
        if let c = cache[id] { return c }
        guard let data = try? Data(contentsOf: fileURL(for: id)), let img = UIImage(data: data) else { return nil }
        cache[id] = img
        return img
    }

    private func load(_ id: String) {
        guard loading.insert(id).inserted else { return }
        let url = fileURL(for: id)
        Task.detached(priority: .userInitiated) { [weak self] in
            let img = (try? Data(contentsOf: url)).flatMap { UIImage(data: $0)?.preparingForDisplay() }
            await self?.finishLoad(id, image: img)
        }
    }

    func save(image: UIImage, for userId: String) {
        guard !userId.isEmpty else { return }
        let url = fileURL(for: userId)
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        guard let data = image.jpegData(compressionQuality: 0.85) else { return }
        try? data.write(to: url, options: [.atomic])
        cache[userId] = image
        missing.remove(userId)
        objectWillChange.send()
        NotificationCenter.default.post(name: Self.changedNotification, object: nil)
    }

    func remove(for userId: String) {
        let url = fileURL(for: userId)
        try? FileManager.default.removeItem(at: url)
        cache.removeValue(forKey: userId)
        missing.insert(userId)
        objectWillChange.send()
        NotificationCenter.default.post(name: Self.changedNotification, object: nil)
    }

    /// Van-e kép (dekódolás nélkül: memória vagy fájl-létezés).
    func hasImage(for userId: String?) -> Bool {
        guard let id = userId, !id.isEmpty else { return false }
        if cache[id] != nil { return true }
        if missing.contains(id) { return false }
        return FileManager.default.fileExists(atPath: fileURL(for: id).path)
    }

    private nonisolated static var directory: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("profile_images", isDirectory: true)
    }

    private func fileURL(for userId: String) -> URL {
        Self.directory.appendingPathComponent("\(userId).jpg")
    }
}
