import Foundation
import SwiftUI

@MainActor
final class AuthViewModel: ObservableObject {
    @Published var isLoading = false
    @Published var error: String?
    @Published var code: String?

    func handleCode(_ code: String, kreta: KretaClient, session: SessionStore) async {
        isLoading = true
        error = nil
        do {
            let token = try await kreta.exchangeCode(code)
            // Institut-fejtés próbálgatással (refilc-minta: az iskolalista halott,
            // a tokenben lévő rövid kód meg nem host): minden jelöltet
            // végigpróbálunk access token + id_token + userinfo forrásokból,
            // és az ELSŐ MŰKÖDŐT tartjuk meg — tippelés és beírogatás nélkül.
            var candidates = JWT.allInstituteCandidates(from: token.access_token)
            if let idt = token.id_token {
                for c in JWT.allInstituteCandidates(from: idt) where !candidates.contains(c) {
                    candidates.append(c)
                }
            }
            if candidates.isEmpty, let info = await kreta.fetchUserInfo() {
                candidates = JWT.allInstituteCandidates(fromUserInfo: info)
            }
            candidates = Array(candidates.prefix(8))
            var user: AppUser? = nil
            for cand in candidates {
                if let data = await kreta.probeInstitute(cand),
                   var u = AppUser.from(token: token, studentData: data) {
                    u.instituteCode = cand
                    kreta.instituteCode = cand
                    // Ha az adatlap nem adott nevet, a token névszerű
                    // claimjeiből pótoljuk — különben üres név ragad be.
                    if !AnalyticsStore.isRealSchoolName(u.schoolName) {
                        let toks = [token.access_token, token.id_token].compactMap { $0 }
                        if let hit = toks.flatMap({ JWT.schoolNameCandidates(fromJWT: $0) })
                            .first(where: { AnalyticsStore.isRealSchoolName($0) }) {
                            u.schoolName = hit
                        }
                    }
                    user = u
                    break
                }
            }
            if user == nil {
                // Minden próba elbukott (pl. külföldről): minimál user, az üres
                // tabok + diagnosztika megmondja, miért — nincs néma halál.
                kreta.diag("login: minden institut-próba elbukott (\(candidates.joined(separator: ",")))")
                let name = (JWT.payload(token.access_token)?["name"] as? String) ?? "Diák"
                let fb = candidates.first ?? "unknown"
                user = AppUser(id: UUID().uuidString, name: name, username: name, instituteCode: fb, role: "student", accessToken: token.access_token, refreshToken: token.refresh_token ?? "", accessTokenExpire: Date().addingTimeInterval(Double((token.expires_in ?? 3600)-30)), studentName: name, schoolName: fb, schoolCity: "")
            }
            session.add(user!)
        } catch {
            self.error = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
        isLoading = false
    }

    /// Demo belépés ugyanazon a kapun, mint az éles: rendes AppUser kerül
    /// a SessionStore-ba (instituteCode "demo"). Innentől minden nézet a
    /// normál fetchX-hívásokkal dolgozik — a KretaClient helyből szolgál ki.
    func loginDemo(session: SessionStore) {
        session.add(.demo)
    }

    /// App Review tesztfiók (KRÉTA-fiók nélkül). A megadott páros a
    /// Review Notes-ban szerepel; sikeres egyezéskor valósághű user
    /// lép be ugyanarra a helyi adatpipeline-ra (instituteCode "demo").
    static let reviewerUsername = "summitreview"
    static let reviewerPassword = "Summit-Review-2026"

    /// Tesztfiókos belépés. Igazat ad vissza helyes páros esetén.
    func loginReviewer(username: String, password: String, session: SessionStore) -> Bool {
        let u = username.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !u.isEmpty, !password.isEmpty,
              u.lowercased() == Self.reviewerUsername,
              password == Self.reviewerPassword else {
            error = "Hibás felhasználónév vagy jelszó."
            return false
        }
        error = nil
        session.add(.reviewer)
        return true
    }
}
