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
    static func from(token: TokenResponse, studentData: Data) -> AppUser? {
        // decode JWT for institute/username (keményített parser — lásd JWT.instituteCode)
        let payload = JWT.payload(token.access_token)
        let iss = JWT.instituteCode(from: token.access_token) ?? "unknown"
        let uname = (payload?["sub"] as? String) ?? (payload?["email"] as? String) ?? "user"
        let name = (try? JSONDecoder().decode(StudentResponse.self, from: studentData))?.Nev ?? uname
        let school = (try? JSONDecoder().decode(StudentResponse.self, from: studentData))?.IntezmenyNeve ?? ""
        return AppUser(
            id: UUID().uuidString,
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
