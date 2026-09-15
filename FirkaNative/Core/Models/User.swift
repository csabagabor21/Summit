import Foundation

struct AppUser: Codable, Identifiable, Equatable {
    var id: String
    var name: String
    var username: String
    var instituteCode: String
    var role: String // student / parent
    var accessToken: String
    var refreshToken: String
    var accessTokenExpire: Date
    var studentName: String
    var schoolName: String
    /// Kézzel beírt iskolanév a térkép-statisztikához (Beállítások → Fiók).
    /// Ha az adatlapból nem jön név, ez menti meg a heartbeatet. Régi
    /// mentésekből hiányozhat — ezért opcionális (nil = nincs felülírás).
    var schoolNameOverride: String? = nil
    var schoolCity: String

    var displayName: String { name }

    static var demo: AppUser {
        AppUser(id: "demo-user", name: "Demo Diák", username: "demo", instituteCode: "demo", role: "student", accessToken: "demo", refreshToken: "demo", accessTokenExpire: Date().addingTimeInterval(3600*24*365), studentName: "Demo Diák", schoolName: "Demo Iskola", schoolCity: "Budapest")
    }
    var isDemo: Bool { id == "demo-user" }
}

struct StoredUsers: Codable {
    var users: [AppUser] = []
    var selectedId: String?
}
