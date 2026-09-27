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
    /// Helyi backendes fiók (demo + tesztfiók): nincs KRÉTA-munkamenet,
    /// az adat a helyi DemoData-pipeline-ból jön (instituteCode "demo",
    /// lásd KretaClient.demoInstitute). Az ilyen fiókra a lejárt-munkamenet
    /// UI (piros sáv, popup, hibaüzenet) sosem vonatkozhat — a tokenek
    /// helyiek, nincs mit a KRÉTA-nak elutasítania.
    var isLocalBackend: Bool {
        instituteCode.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "demo"
    }
    /// App Review tesztfiók: ugyanaz a helyi adatpipeline, mint a demó
    /// (instituteCode "demo"), de valósághű névvel és iskolaadattal —
    /// sehol nem jelenik meg "demo" felirat, és az isDemo-kapuk
    /// (letiltott szinkron stb.) nem vonatkoznak rá.
    static var reviewer: AppUser {
        AppUser(id: "reviewer-user", name: "Kovács Anna", username: "summitreview", instituteCode: "demo", role: "student", accessToken: "reviewer", refreshToken: "reviewer", accessTokenExpire: Date().addingTimeInterval(3600*24*365), studentName: "Kovács Anna", schoolName: "Petőfi Sándor Gimnázium", schoolCity: "Budapest")
    }
}

struct StoredUsers: Codable {
    var users: [AppUser] = []
    var selectedId: String?
}
