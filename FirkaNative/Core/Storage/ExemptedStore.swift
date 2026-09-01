import Foundation

enum ExemptedStore {
    static let key = "firka.exemptedSubjects.v1"
    static let changedNotification = Notification.Name("firka.exemptedChanged")

    static func load() -> Set<String> {
        Set(UserDefaults.standard.stringArray(forKey: key) ?? [])
    }
    static func save(_ set: Set<String>) {
        UserDefaults.standard.set(Array(set), forKey: key)
        NotificationCenter.default.post(name: changedNotification, object: nil)
    }
    static func isExempted(_ subject: String) -> Bool {
        // Támogatja a kanonikus egyeztetést is (Matek <-> Matematika)
        if load().contains(subject) { return true }
        // kanonikus formával is ellenőriz
        let canon = SubjectMatcher.canonical(subject)
        return load().contains(where: { SubjectMatcher.canonical($0) == canon })
    }
    static func setExempted(_ subject: String, _ on: Bool) {
        var s = load()
        if on { s.insert(subject) } else {
            // kanonikus törlés: minden variánst kiszedünk ami ugyanazt a kanonikust adja
            let canon = SubjectMatcher.canonical(subject)
            s = s.filter { SubjectMatcher.canonical($0) != canon }
            if !on { /* már szűrt */ }
        }
        if on { s.insert(subject) }
        save(s)
    }
    // Kanonikus ellenőrzéshez helper — szubjekt normalizálás nélkül is működik
    static func isExemptedCanonical(_ canonical: String) -> Bool {
        load().contains(where: { SubjectMatcher.canonical($0) == canonical })
    }
}
