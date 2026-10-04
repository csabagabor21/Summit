import SwiftUI
import UIKit

// Külön tab a Beállításokon belül: ha "semmi nem jön be a KRÉTÁ-ból",
// ez mutatja meg, hol hal meg — institut, token-állapot, endpoint+státusz napló.
struct DiagnosticsView: View {
    @EnvironmentObject var session: SessionStore
    @EnvironmentObject var kreta: KretaClient
    @EnvironmentObject var analytics: AnalyticsStore
    @EnvironmentObject var completed: CompletedStore
    @ObservedObject private var liveManager = SummitLiveActivityManager.shared
    /// A worker /status válasza a mai tervre (megnyitáskor és gombra frissül).
    @State private var workerStatus: String = "–"
    /// Apple Watch szinkron-jelentés (pushonként frissül).
    @State private var watchReport = WatchSyncSender.report()

    var body: some View {
        List {
            Section {
                diagRow("Állapot", analytics.isEnabled ? "bekapcsolva" : "kikapcsolva")
                diagRow("Iskolanév", (session.heartbeatSchoolName ?? "–") + (session.selectedUser?.schoolNameOverride != nil ? " (kézi)" : ""))
                diagRow("Utolsó próba", analytics.lastAttempt)
                diagRow("Iskola (küldött)", analytics.lastSchool)
                diagRow("Eredmény", analytics.lastResult)
            } header: {
                Text("Statisztika (térkép)")
            } footer: {
                Text("Előtérben naponta max 1, belépéskor és bekapcsoláskor azonnal — külön dokumentumban. A térkép install_id alapján számol, a dupla nem dupláz. Sikertelenségkor a következő trigger újrapróbálja.")
            }
            Section("Állapot") {
                diagRow("Iskola", session.selectedUser?.instituteCode ?? "–")
                diagRow("Token", tokenDiag)
                diagRow("Munkamenet", kreta.sessionExpired ? "HALOTT (újra belépés kell)" : "él")
            }
            Section {
                diagRow("Worker", SummitPushSync.isConfigured ? (URL(string: SummitPushSync.baseURL)?.host ?? SummitPushSync.baseURL) : "nincs beállítva")
                diagRow("Push token", pushTokenDiag)
                diagRow("Utolsó feltöltés", lastUploadDiag)
                diagRow("Kimaradás oka", skipDiag)
                diagRow("Terv-kulcs", planKeyDiag)
            } header: {
                Text("Push (Cloudflare)")
            } footer: {
                Text("A napi terv és a határ-entryk feltöltése a workerbe — ha a token vagy a feltöltés hiányzik, a szerver nem tud átkapcsolni.")
            }
            Section {
                Text(workerStatus).font(.caption2.monospaced()).foregroundStyle(.secondary)
                Button("Worker állapot frissítése") { Task { await loadWorkerStatus() } }
            } header: {
                Text("Worker (mai terv)")
            } footer: {
                Text("A worker /status válasza: melyik határra ment ki push, hány próbával, mit felelt az APNs. „Nincs terv” = a feltöltés maradt ki; APNs 400/410 = rossz token vagy sandbox–prod keveredés; 403 = kulcs/Team ID.")
            }
            Section {
                diagRow("Támogatott", watchReport.supportedText)
                diagRow("Session", watchReport.activationText)
                diagRow("Párosítva", watchReport.pairedText)
                diagRow("Óra-app telepítve", watchReport.installedText)
                diagRow("Elérhető most", watchReport.reachableText)
                diagRow("Órarend push", watchReport.timetableText)
                diagRow("Jegy push", watchReport.gradesText)
                diagRow("Feladat push", watchReport.tasksText)
                diagRow("Jegyzet push", watchReport.cheatText)
                if let err = watchReport.errorText { diagRow("Hiba", err) }
                diagRow("Ítélet", watchReport.verdictText)
                Button("Óra szinkronizálása most") {
                    Task {
                        await WatchAutoPush.refreshNow(session: session, kreta: kreta, completed: completed)
                        watchReport = WatchSyncSender.report()
                    }
                }
            } header: {
                Text("Apple Watch szinkron")
            } footer: {
                Text(watchReport.hintText.isEmpty ? "Tab-lehúzáskor (Főoldal, Órarend, Jegyek, Feladatok) az app automatikusan tol az órára." : watchReport.hintText)
            }
            .onReceive(NotificationCenter.default.publisher(for: WatchSyncSender.reportChanged)) { _ in
                watchReport = WatchSyncSender.report()
            }
            Section {
                diagRow("Rendszer", liveManager.isSystemEnabled ? "engedélyezett" : "TILTVA (Beállítások → Summit)")
                diagRow("App-kapcsoló", liveManager.isAppEnabled ? "be" : "KI")
                diagRow("Aktív activity", "\(liveManager.activeCount)")
                diagRow("Utolsó művelet", liveManager.lastAction)
                if let err = liveManager.lastError { diagRow("Hiba", err) }
                if liveManager.recentEvents.isEmpty {
                    Text("Még nincs esemény.").font(.caption).foregroundStyle(.tertiary)
                } else {
                    ForEach(Array(liveManager.recentEvents.enumerated()), id: \.offset) { _, line in
                        Text(line).font(.caption2.monospaced()).foregroundStyle(.secondary)
                    }
                }
            } header: {
                Text("Live Activity események")
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
                Button("Finom tick (selection)") { SummitHaptics.selection() }
                Button("Sikeres (success)") { SummitHaptics.success() }
                Button("Hibás (error)") { SummitHaptics.error() }
            } header: {
                Text("Haptika-teszt")
            } footer: {
                Text("Ha itt sem érzel semmit: iPhone Beállítások → Hangok és haptika → Rendszerhaptika legyen BE. Ha az BE van és ez rezeg, de máshol néma az app, szólj — akkor kódbug.")
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
        .task { await loadWorkerStatus() }
    }

    private func loadWorkerStatus() async {
        guard let uid = session.selectedUser?.id else { workerStatus = "nincs belépett user"; return }
        workerStatus = "lekérés…"
        workerStatus = await SummitPushSync.shared.fetchStatus(userId: uid, dayKey: SummitLiveActivityManager.dayKey(for: Date()))
    }

    /// A HOSSZ is kell ide: a „van (1)" korábban elrejtette, hogy a token
    /// megvan, csak a feltöltés 64-karakteres feltétele dobta el. A végződés
    /// a worker /status `tokenSuffix`-ével vethető össze.
    private var pushTokenDiag: String {
        guard let t = liveManager.primaryPushToken, !t.isEmpty else {
            return liveManager.startedWithoutPush ? "nincs (push nélküli build)" : "nincs"
        }
        let ok = SummitPushSync.isValidToken(t) ? "" : " ÉRVÉNYTELEN"
        return "van (\(liveManager.pushTokens.count)), \(t.count) karakter, …\(t.suffix(6))\(ok)"
    }
    private var lastUploadDiag: String {
        UserDefaults.standard.string(forKey: SummitPushSync.lastUploadSummaryKey) ?? "–"
    }
    /// A worker KV-kulcsa (scoped userId @ nap) — curl-lel is ellenőrizhető.
    private var planKeyDiag: String {
        guard let uid = session.selectedUser?.id else { return "–" }
        return "\(SummitPushSync.scopedUserId(uid)) @ \(SummitLiveActivityManager.dayKey(for: Date()))"
    }

    private func diagRow(_ k: String, _ v: String) -> some View {
        HStack(alignment: .top) {
            Text(k).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            Spacer(minLength: 8)
            Text(v).font(.caption.monospaced()).foregroundStyle(.primary).multilineTextAlignment(.trailing)
        }
    }
    /// A kimaradás-oka csak sikeres feltöltéskor törlődik — közben viszont
    /// megérkezhet a token, és a sor beragadt, ellentmondó állapotot mutatna
    /// („van token" + „nincs push-token"). Ilyenkor jelezzük, hogy az ok
    /// már elavult, és a következő sync feltölt.
    private var skipDiag: String {
        let s = UserDefaults.standard.string(forKey: SummitPushSync.lastSkipReasonKey) ?? "–"
        if s == "–" || liveManager.pushTokens.isEmpty { return s }
        return "\(s) → már van token, a következő sync feltölt"
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
            + "analytics: enabled=\(analytics.isEnabled) attempt=\(analytics.lastAttempt) school=\(analytics.lastSchool) result=\(analytics.lastResult)\n"
            + "push: token=\(pushTokenDiag) feltöltés=\(lastUploadDiag) kimaradás=\(skipDiag)\n"
            + "terv-kulcs: \(planKeyDiag)\n"
            + "watch: támogatott=\(watchReport.supportedText) session=\(watchReport.activationText) párosítva=\(watchReport.pairedText) óra-app=\(watchReport.installedText) elérhető=\(watchReport.reachableText) órarend=\(watchReport.timetableText) jegy=\(watchReport.gradesText) feladat=\(watchReport.tasksText) jegyzet=\(watchReport.cheatText) hiba=\(watchReport.errorText ?? "–") ítélet=\(watchReport.verdictText)\n"
            + "live activity: rendszer=\(liveManager.isSystemEnabled ? "engedélyezett" : "TILTVA") app=\(liveManager.isAppEnabled ? "be" : "KI") aktív=\(liveManager.activeCount) utolsó=\(liveManager.lastAction) hiba=\(liveManager.lastError ?? "–")\n"
            + kreta.diagLog.joined(separator: "\n")
            + "\n--- live activity események ---\n"
            + liveManager.recentEvents.joined(separator: "\n")
            + "\n--- push ---\n"
            + liveManager.pushLog.joined(separator: "\n")
            + "\n--- worker ---\n"
            + workerStatus
    }
}
