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
    static var userinfo: URL { URL(string: idpBase + "/connect/userinfo")! }

    // Minden institut-függő builder opcionális: koszos institut-kód
    // (szóköz, URL) esetén a URL(string:) nil-t adna, és a régi `!`
    // force-unwrap egy async Task-ban az APP-ot ölte meg (crash-loop
    // bejelentkezés után). Nil → a hívó kegyesen üres adattal tér vissza.
    static func student(_ iss: String) -> URL? { URL(string: kreta(iss) + "/ellenorzo/V3/Sajat/TanuloAdatlap") }
    static func grades(_ iss: String) -> URL? { URL(string: kreta(iss) + "/ellenorzo/V3/Sajat/Ertekelesek") }
    static func timetable(_ iss: String, start: Date? = nil, end: Date? = nil) -> URL? {
        let base = kreta(iss) + "/ellenorzo/V3/Sajat/OrarendElemek"
        guard let s = start, let e = end else { return URL(string: base) }
        // Refilc / firka self mintára: UTC ISO8601 — ld. refilc_kreta_api/lib/client/api.dart:
        // "?datumTol=${start.toUtc().toIso8601String()}&datumIg=${end.toUtc().toIso8601String()}"
        // URLComponents végzi a korrekt percent-encodinget (+, : stb.)
        guard var comps = URLComponents(string: base) else { return nil }
        let df = ISO8601DateFormatter()
        df.formatOptions = [.withInternetDateTime]
        df.timeZone = TimeZone(secondsFromGMT: 0)
        comps.queryItems = [
            URLQueryItem(name: "datumTol", value: df.string(from: s)),
            URLQueryItem(name: "datumIg", value: df.string(from: e))
        ]
        return comps.url ?? URL(string: base)
    }
    static func exams(_ iss: String) -> URL? { URL(string: kreta(iss) + "/ellenorzo/V3/Sajat/BejelentettSzamonkeresek") }
    // refilc mintára: a lista ?datumTol=yyyy-MM-dd dátumszűrővel jön le
    // (csupasz endpointra a KRÉTA nem ad vissza használható listát),
    // majd minden házi részlete külön: HaziFeladatok/{uid}
    static func homework(_ iss: String, from: Date? = nil) -> URL? {
        let base = kreta(iss) + "/ellenorzo/V3/Sajat/HaziFeladatok"
        guard let f = from else { return URL(string: base) }
        guard var comps = URLComponents(string: base) else { return nil }
        let df = DateFormatter()
        df.locale = Locale(identifier: "en_US_POSIX")
        df.dateFormat = "yyyy-MM-dd"
        comps.queryItems = [URLQueryItem(name: "datumTol", value: df.string(from: f))]
        return comps.url ?? URL(string: base)
    }
    static func homeworkDetail(_ iss: String, id: String) -> URL? {
        URL(string: kreta(iss) + "/ellenorzo/V3/Sajat/HaziFeladatok/\(id)")
    }
    static func absences(_ iss: String) -> URL? { URL(string: kreta(iss) + "/ellenorzo/V3/Sajat/Mulasztasok") }
    static func notes(_ iss: String) -> URL? { URL(string: kreta(iss) + "/ellenorzo/V3/Sajat/Feljegyzesek") }
    static func events(_ iss: String) -> URL? { URL(string: kreta(iss) + "/ellenorzo/V3/Sajat/FaliujsagElemek") }
    /// Postaláda-lista (e-Ügyintézés): a KRÉTA csak ezt a három dobozt
    /// ismeri — ekreta-docs-v3 ("Get all messages": az endpoint
    /// `beerkezett`, `elkuldott` vagy `torolt` lehet).
    /// A régi `bejovo`/`kimenő`/`piszkozat` nevekre az API nem válaszol,
    /// ezért nem töltődött be semmi az Üzenetek képernyőn.
    enum Mailbox: String, CaseIterable {
        case incoming = "beerkezett"
        case sent = "elkuldott"
        case trash = "torolt"
    }
    static func messages(_ box: Mailbox) -> URL? { URL(string: adminBase + "/api/v1/kommunikacio/postaladaelemek/\(box.rawValue)") }
    /// Egy üzenet részlete (törzs + csatolmánylista) a numerikus
    /// azonosító alapján: `postaladaelemek/{id}` (ekreta-docs-v3:
    /// "Get information about a specific message").
    static func messageDetail(id: String) -> URL? {
        URL(string: adminBase + "/api/v1/kommunikacio/postaladaelemek/\(id)")
    }
    /// Házi/dolgozat csatolmány-letöltés Refilc-mintára
    /// (refilc_kreta_api `KretaApiEndpoints.downloadHomeworkAttachments`):
    /// EGYES számú `Csatolmany/{uid}` az intézeti Ellenőrző hoston.
    /// A Refilc a `type`-ot átveszi, de az URL-be nem építi be — egyetlen
    /// uid-útvonal van, házi-azonosító NÉLKÜL. A régi beágyazott
    /// `HaziFeladatok/{hw}/Csatolmanyok/{att}` és a többes számú
    /// `Csatolmanyok/{att}` útvonal nem létezik (404 → nem nyílt meg a PDF).
    static func homeworkAttachment(_ iss: String, attachmentId: String) -> URL? {
        URL(string: kreta(iss) + "/ellenorzo/V3/Sajat/Csatolmany/\(attachmentId)")
    }
    /// Üzenet-csatolmány (e-Ügyintézés fileservice, ekreta-docs-v3 +
    /// Refilc `KretaAdminEndpoints.downloadAttachment`): a részlet
    /// `uzenet.csatolmanyok` listájának `azonosito`-ja ide megy,
    /// NEM az intézeti (`{iss}.e-kreta.hu`) hostra.
    static func messageAttachment(_ attachmentId: String) -> URL? {
        URL(string: adminBase + "/api/v1/dokumentumok/uzenetek/\(attachmentId)")
    }
    // Tantárgyi átlagok — minden felvett tárgyat visszaad, akkor is ha még nincs benne jegy (KRÉTA tudja)
    static func subjectAverages(_ iss: String) -> URL? { URL(string: kreta(iss) + "/ellenorzo/V3/Sajat/Ertekelesek/Atlagok/TantargyiAtlagok") }
    static func subjectAveragesAlt(_ iss: String) -> URL? { URL(string: kreta(iss) + "/ellenorzo/V3/Sajat/TantargyiAtlagok") }

    // OAuth authorize URL (same as Flutter)
    static var authorizeURL: URL {
        URL(string: "https://idp.e-kreta.hu/connect/authorize?prompt=login&nonce=wylCrqT4oN6PPgQn2yQB0euKei9nJeZ6_ffJ-VpSKZU&response_type=code&code_challenge_method=S256&scope=openid%20email%20offline_access%20kreta-ellenorzo-webapi.public%20kreta-eugyintezes-webapi.public%20kreta-fileservice-webapi.public%20kreta-mobile-global-webapi.public%20kreta-dkt-webapi.public%20kreta-ier-webapi.public&code_challenge=HByZRRnPGb-Ko_wTI7ibIba1HQ6lor0ws4bcgReuYSQ&redirect_uri=https://mobil.e-kreta.hu/ellenorzo-student/prod/oauthredirect&client_id=kreta-ellenorzo-student-mobile-ios&state=refilc_student_mobile")!
    }
    static let redirectURI = "https://mobil.e-kreta.hu/ellenorzo-student/prod/oauthredirect"
    static let codeVerifier = "DSpuqj_HhDX4wzQIbtn8lr8NLE5wEi1iVLMtMK0jY6c"
}
