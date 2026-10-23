import CryptoKit
import Foundation
import Security

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
    /// Naptári napok (tanév rendje): nap típusa (tanítási nap, tanítás
    /// nélküli munkanap, szünet …), órarendi-nap jelölés, hét napja.
    /// A hivatalos app ebből írja ki pl. „Tanítás nélküli munkanap
    /// (Nem órarendi nap) (Hétfő)"-t az órarend üres napjaira.
    static func calendarDays(_ iss: String, from: Date? = nil, to: Date? = nil) -> URL? {
        let base = kreta(iss) + "/ellenorzo/V3/Sajat/NaptariNapok"
        guard let f = from, let t = to else { return URL(string: base) }
        guard var comps = URLComponents(string: base) else { return nil }
        let df = ISO8601DateFormatter()
        df.formatOptions = [.withInternetDateTime]
        df.timeZone = TimeZone(secondsFromGMT: 0)
        comps.queryItems = [
            URLQueryItem(name: "datumTol", value: df.string(from: f)),
            URLQueryItem(name: "datumIg", value: df.string(from: t))
        ]
        return comps.url ?? URL(string: base)
    }
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

    static let redirectURI = "https://mobil.e-kreta.hu/ellenorzo-student/prod/oauthredirect"
    static let scope = "openid email offline_access kreta-ellenorzo-webapi.public kreta-eugyintezes-webapi.public kreta-fileservice-webapi.public kreta-mobile-global-webapi.public kreta-dkt-webapi.public kreta-ier-webapi.public"

    /// Egy belépési kísérlet OAuth-anyaga. Minden belépéshez FRISS, véletlen
    /// PKCE code_verifier, nonce és state készül: egy fix verifierrel a PKCE
    /// semmit nem véd (aki elkapja a redirect `code`-ját, be is váltaná),
    /// a state pedig a hamis/régi redirectet szűri ki.
    struct AuthorizationRequest {
        let url: URL
        let codeVerifier: String
        let state: String
    }

    static func makeAuthorizationRequest() -> AuthorizationRequest {
        let verifier = randomURLSafe(bytes: 32)
        let challenge = base64URL(Data(SHA256.hash(data: Data(verifier.utf8))))
        let state = randomURLSafe(bytes: 16)
        var comps = URLComponents(string: idpBase + "/connect/authorize")!
        comps.queryItems = [
            URLQueryItem(name: "prompt", value: "login"),
            URLQueryItem(name: "nonce", value: randomURLSafe(bytes: 32)),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "scope", value: scope),
            URLQueryItem(name: "code_challenge", value: challenge),
            URLQueryItem(name: "redirect_uri", value: redirectURI),
            URLQueryItem(name: "client_id", value: clientId),
            URLQueryItem(name: "state", value: state),
        ]
        return AuthorizationRequest(url: comps.url!, codeVerifier: verifier, state: state)
    }

    /// Kriptográfiai véletlen, base64url (padding nélkül, RFC 7636).
    private static func randomURLSafe(bytes count: Int) -> String {
        var bytes = [UInt8](repeating: 0, count: count)
        guard SecRandomCopyBytes(kSecRandomDefault, count, &bytes) == errSecSuccess else {
            // A rendszer-RNG hibája nem fordulhat elő; ha mégis, a CryptoKit
            // kulcsgenerátora is kriptográfiai forrás.
            return base64URL(SymmetricKey(size: .bits256).withUnsafeBytes { Data($0) }.prefix(count))
        }
        return base64URL(Data(bytes))
    }

    private static func base64URL(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
