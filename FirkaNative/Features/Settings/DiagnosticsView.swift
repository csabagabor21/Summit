import SwiftUI
import UIKit

// Külön tab a Beállításokon belül: ha "semmi nem jön be a KRÉTÁ-ból",
// ez mutatja meg, hol hal meg — institut, token-állapot, endpoint+státusz napló.
struct DiagnosticsView: View {
    @EnvironmentObject var session: SessionStore
    @EnvironmentObject var kreta: KretaClient
    @ObservedObject private var liveManager = SummitLiveActivityManager.shared

    var body: some View {
        List {
            Section("Állapot") {
                diagRow("Iskola", session.selectedUser?.instituteCode ?? "–")
                diagRow("Token", tokenDiag)
                diagRow("Munkamenet", kreta.sessionExpired ? "HALOTT (újra belépés kell)" : "él")
            }
            Section {
                diagRow("Worker", SummitPushSync.isConfigured ? (URL(string: SummitPushSync.baseURL)?.host ?? SummitPushSync.baseURL) : "nincs beállítva")
                diagRow("Push token", liveManager.pushTokens.isEmpty
                    ? (liveManager.startedWithoutPush ? "nincs (push nélküli build)" : "nincs")
                    : "van (\(liveManager.pushTokens.count))")
                diagRow("Utolsó feltöltés", UserDefaults.standard.string(forKey: SummitPushSync.lastUploadSummaryKey) ?? "–")
                diagRow("Kimaradás oka", UserDefaults.standard.string(forKey: SummitPushSync.lastSkipReasonKey) ?? "–")
            } header: {
                Text("Push (Cloudflare)")
            } footer: {
                Text("A napi terv és a határ-entryk feltöltése a workerbe — ha a token vagy a feltöltés hiányzik, a szerver nem tud átkapcsolni.")
            }
            Section {
                if liveManager.pushLog.isEmpty {
                    Text("Még nincs push-forgalom — tanítási időben nyisd meg a Főoldalt.")
                        .font(.caption).foregroundStyle(.tertiary)
                } else {
                    ForEach(Array(liveManager.pushLog.enumerated()), id: \.offset) { _, line in
                        Text(line).font(.caption2.monospaced()).foregroundStyle(.secondary)
                    }
                }
            }
            Section {
                Button("Napló másolása") {
                    UIPasteboard.general.string = diagExport
                }
            } header: {
                Text("Napló")
            } footer: {
                Text("Ha üres minden: a Főoldal lehúzása után ez mutatja, 401/404/üres-200/DNS-hiba áll-e mögötte.")
            }
            Section {
                if kreta.diagLog.isEmpty {
                    Text("Még nincs napló — húzd le a Főoldalt a frissítéshez.")
                        .font(.caption).foregroundStyle(.tertiary)
                } else {
                    ForEach(Array(kreta.diagLog.enumerated()), id: \.offset) { _, line in
                        Text(line).font(.caption2.monospaced()).foregroundStyle(.secondary)
                    }
                }
            }
        }
        .navigationTitle("Diagnosztika")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func diagRow(_ k: String, _ v: String) -> some View {
        HStack(alignment: .top) {
            Text(k).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            Spacer(minLength: 8)
            Text(v).font(.caption.monospaced()).foregroundStyle(.primary).multilineTextAlignment(.trailing)
        }
    }
    private var tokenDiag: String {
        guard session.selectedUser != nil else { return "nincs user" }
        guard kreta.accessToken != nil else { return "nincs access token" }
        if let exp = kreta.accessTokenExpire {
            let s = Int(exp.timeIntervalSinceNow)
            return s > 0 ? "él (\(s / 60)p \(s % 60)mp)" : "LEJÁRT"
        }
        return "van (lejárat ismeretlen)"
    }
    private var diagExport: String {
        "iskola=\(session.selectedUser?.instituteCode ?? "-") token=\(tokenDiag) sessionExpired=\(kreta.sessionExpired)\n"
            + kreta.diagLog.joined(separator: "\n")
            + "\n--- push ---\n"
            + liveManager.pushLog.joined(separator: "\n")
    }
}
