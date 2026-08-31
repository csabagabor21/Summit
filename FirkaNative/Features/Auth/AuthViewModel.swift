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
            // Fetch student to get name/school
            let iss = JWT.payload(token.access_token)?["kreta:institute_code"] as? String
                ?? JWT.instituteCode(from: token.access_token)
                ?? "unknown"
            // Try to fetch student, fallback to demo-like user if fails (outside HU)
            var user: AppUser
            do {
                let data: Data = try await kreta.getRaw(KretaAPI.student(iss))
                if let u = AppUser.from(token: token, studentData: data) {
                    user = u
                } else {
                    throw KretaError.network
                }
            } catch {
                // Fallback - create minimal user from JWT
                let name = (JWT.payload(token.access_token)?["name"] as? String) ?? "Diák"
                user = AppUser(id: UUID().uuidString, name: name, username: name, instituteCode: iss, role: "student", accessToken: token.access_token, refreshToken: token.refresh_token ?? "", accessTokenExpire: Date().addingTimeInterval(Double((token.expires_in ?? 3600)-30)), studentName: name, schoolName: iss, schoolCity: "")
            }
            session.add(user)
        } catch {
            self.error = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
        isLoading = false
    }

    func loginDemo(session: SessionStore) {
        session.add(.demo)
    }
}
