import Foundation
import Combine

@MainActor
final class SessionStore: ObservableObject {
    @Published var users: [AppUser] = []
    @Published var selectedId: String? {
        didSet { persist() }
    }
    var selectedUser: AppUser? { users.first(where: { $0.id == selectedId }) }

    private let key = "firka.users.v1"

    init() { load() }

    func load() {
        if let data = UserDefaults.standard.data(forKey: key),
           let decoded = try? JSONDecoder().decode(StoredUsers.self, from: data) {
            users = decoded.users
            selectedId = decoded.selectedId
        }
    }
    func persist() {
        let stored = StoredUsers(users: users, selectedId: selectedId)
        if let data = try? JSONEncoder().encode(stored) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }
    func add(_ user: AppUser) {
        if let idx = users.firstIndex(where: { $0.id == user.id }) { users[idx] = user }
        else { users.append(user) }
        selectedId = user.id
        persist()
    }
    func logout() {
        if let id = selectedId { users.removeAll { $0.id == id } }
        selectedId = users.first?.id
        persist()
    }
    var isLoggedIn: Bool { selectedUser != nil }
}
