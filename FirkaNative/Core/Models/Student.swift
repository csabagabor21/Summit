import Foundation

// Minimal decodable for TanuloAdatlap
struct StudentResponse: Decodable {
    let Nev: String?
    let SzulletesiDatum: String?
    let IntezmenyNeve: String?
    let OsztalyNev: String?
    struct OsztalyCsoport: Decodable { let Nev: String? }
    let OsztalyCsoport: OsztalyCsoport?
}

extension AppUser {
    /// Stabil fiók-azonosító a belépésenkénti UUID helyett: ugyanaz a
    /// KRÉTA-fiók (felhasználónév + intézmény) minden belépéskor ugyanazt
    /// az id-t kapja. Enélkül minden újrabelépés (lejárt munkamenet után
    /// tipikus) új selectedId-t adott, ami a SummitApp-ban kikapcsolta a
    /// beállítás-szinkront — főleg asztali gépen volt feltűnő. Nil, ha
    /// nincs megbízható felhasználónév/intézmény (olyankor marad az UUID).
    static func stableId(username: String, instituteCode: String) -> String? {
        let u = username.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let c = instituteCode.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard u.count >= 2, u.count <= 128,
              !["user", "demo", "unknown"].contains(u),
              !c.isEmpty, c != "unknown" else { return nil }
        return "kreta:\(c)|\(u)"
    }

    static func from(token: TokenResponse, studentData: Data) -> AppUser? {
        // decode JWT for institute/username (keményített parser — lásd JWT.instituteCode)
        let payload = JWT.payload(token.access_token)
        let iss = JWT.instituteCode(from: token.access_token) ?? "unknown"
        let uname = (payload?["sub"] as? String) ?? (payload?["email"] as? String) ?? "user"
        let name = (try? JSONDecoder().decode(StudentResponse.self, from: studentData))?.Nev ?? uname
        let school = (try? JSONDecoder().decode(StudentResponse.self, from: studentData))?.IntezmenyNeve ?? ""
        return AppUser(
            id: stableId(username: uname, instituteCode: iss) ?? UUID().uuidString,
            name: name,
            username: uname,
            instituteCode: iss,
            role: "student",
            accessToken: token.access_token,
            refreshToken: token.refresh_token ?? "",
            accessTokenExpire: Date().addingTimeInterval(Double((token.expires_in ?? 3600) - 30)),
            studentName: name,
            schoolName: school,
            schoolCity: ""
        )
    }
}
