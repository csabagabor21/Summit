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

    @Published private var cache: [String: UIImage] = [:]

    func image(for userId: String?) -> UIImage? {
        guard let id = userId, !id.isEmpty else { return nil }
        if let c = cache[id] { return c }
        let url = fileURL(for: id)
        guard let data = try? Data(contentsOf: url), let img = UIImage(data: data) else { return nil }
        cache[id] = img
        return img
    }

    func save(image: UIImage, for userId: String) {
        guard !userId.isEmpty else { return }
        let url = fileURL(for: userId)
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        guard let data = image.jpegData(compressionQuality: 0.85) else { return }
        try? data.write(to: url, options: [.atomic])
        cache[userId] = image
        objectWillChange.send()
        NotificationCenter.default.post(name: Self.changedNotification, object: nil)
    }

    func remove(for userId: String) {
        let url = fileURL(for: userId)
        try? FileManager.default.removeItem(at: url)
        cache.removeValue(forKey: userId)
        objectWillChange.send()
        NotificationCenter.default.post(name: Self.changedNotification, object: nil)
    }

    func hasImage(for userId: String?) -> Bool {
        guard let id = userId else { return false }
        return image(for: id) != nil
    }

    private func fileURL(for userId: String) -> URL {
        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("profile_images", isDirectory: true)
        return dir.appendingPathComponent("\(userId).jpg")
    }
}
