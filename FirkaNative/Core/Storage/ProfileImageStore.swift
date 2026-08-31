import SwiftUI
import Combine

@MainActor
final class ProfileImageStore: ObservableObject {
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
    }

    func remove(for userId: String) {
        let url = fileURL(for: userId)
        try? FileManager.default.removeItem(at: url)
        cache.removeValue(forKey: userId)
        objectWillChange.send()
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
