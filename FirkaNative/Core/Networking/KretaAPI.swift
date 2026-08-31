import Foundation

enum KretaAPI {
    static let clientId = "kreta-ellenorzo-student-mobile-ios"
    static let idpBase = "https://idp.e-kreta.hu"
    static let tokenPath = "/connect/token"
    static let revokePath = "/connect/revocation"
    static let noncePath = "/nonce"

    static var login: URL { URL(string: idpBase + tokenPath)! }
    static var logout: URL { URL(string: idpBase + revokePath)! }
    static var nonce: URL { URL(string: idpBase + noncePath)! }

    static func kreta(_ iss: String) -> String { "https://\(iss).e-kreta.hu" }
    static let adminBase = "https://eugyintezes.e-kreta.hu"

    static func student(_ iss: String) -> URL { URL(string: kreta(iss) + "/ellenorzo/V3/Sajat/TanuloAdatlap")! }
    static func grades(_ iss: String) -> URL { URL(string: kreta(iss) + "/ellenorzo/V3/Sajat/Ertekelesek")! }
    static func timetable(_ iss: String, start: Date? = nil, end: Date? = nil) -> URL {
        var url = kreta(iss) + "/ellenorzo/V3/Sajat/OrarendElemek"
        if let s = start, let e = end {
            let df = ISO8601DateFormatter()
            df.formatOptions = [.withInternetDateTime]
            url += "?datumTol=\(df.string(from: s))&datumIg=\(df.string(from: e))"
        }
        return URL(string: url)!
    }
    static func exams(_ iss: String) -> URL { URL(string: kreta(iss) + "/ellenorzo/V3/Sajat/BejelentettSzamonkeresek")! }
    static func homework(_ iss: String) -> URL { URL(string: kreta(iss) + "/ellenorzo/V3/Sajat/HaziFeladatok")! }
    static func absences(_ iss: String) -> URL { URL(string: kreta(iss) + "/ellenorzo/V3/Sajat/Mulasztasok")! }
    static func notes(_ iss: String) -> URL { URL(string: kreta(iss) + "/ellenorzo/V3/Sajat/Feljegyzesek")! }
    static func events(_ iss: String) -> URL { URL(string: kreta(iss) + "/ellenorzo/V3/Sajat/FaliujsagElemek")! }
    static func messages(_ endpoint: String) -> URL { URL(string: adminBase + "/api/v1/kommunikacio/postaladaelemek/\(endpoint)")! }

    // OAuth authorize URL (same as Flutter)
    static var authorizeURL: URL {
        URL(string: "https://idp.e-kreta.hu/connect/authorize?prompt=login&nonce=wylCrqT4oN6PPgQn2yQB0euKei9nJeZ6_ffJ-VpSKZU&response_type=code&code_challenge_method=S256&scope=openid%20email%20offline_access%20kreta-ellenorzo-webapi.public%20kreta-eugyintezes-webapi.public%20kreta-fileservice-webapi.public%20kreta-mobile-global-webapi.public%20kreta-dkt-webapi.public%20kreta-ier-webapi.public&code_challenge=HByZRRnPGb-Ko_wTI7ibIba1HQ6lor0ws4bcgReuYSQ&redirect_uri=https://mobil.e-kreta.hu/ellenorzo-student/prod/oauthredirect&client_id=kreta-ellenorzo-student-mobile-ios&state=refilc_student_mobile")!
    }
    static let redirectURI = "https://mobil.e-kreta.hu/ellenorzo-student/prod/oauthredirect"
    static let codeVerifier = "DSpuqj_HhDX4wzQIbtn8lr8NLE5wEi1iVLMtMK0jY6c"
}
