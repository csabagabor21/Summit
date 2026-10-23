import SwiftUI
import UIKit

// Külön tab a Beállításokon belül: ha "semmi nem jön be a KRÉTÁ-ból",
// ez mutatja meg, hol hal meg — institut, token-állapot, endpoint+státusz napló.
struct DiagnosticsView: View {
    @EnvironmentObject var session: SessionStore
    @EnvironmentObject var kreta: KretaClient
    @EnvironmentObject var analytics: AnalyticsStore
    @EnvironmentObject var completed: CompletedStore
    @EnvironmentObject var theme: ThemeStore
    @Environment(\.colorScheme) var scheme
    var colors: AppColors { theme.colors(for: scheme) }
    @ObservedObject private var liveManager = SummitLiveActivityManager.shared
    /// A hálózati napló élő figyelése CSAK itt (a KretaClient már nem publikálja).
    @ObservedObject private var networkLog = KretaDiagLog.shared
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
                Text("Statisztika (térkép)").mcFont(.caption)
            } footer: {
                Text("Előtérben naponta max 1, belépéskor és bekapcsoláskor azonnal — külön dokumentumban. A térkép install_id alapján számol, a dupla nem dupláz. Sikertelenségkor a következő trigger újrapróbálja.").mcFont(.caption)
            }
            .mcListRowComfy(fill: colors.surface)
            Section("Állapot") {
                diagRow("Iskola", session.selectedUser?.instituteCode ?? "–")
                diagRow("Token", tokenDiag)
                diagRow("Munkamenet", kreta.sessionExpired ? "HALOTT (újra belépés kell)" : "él")
            }
            .mcListRowComfy(fill: colors.surface)
            Section {
                diagRow("Worker", SummitPushSync.isConfigured ? (URL(string: SummitPushSync.baseURL)?.host ?? SummitPushSync.baseURL) : "nincs beállítva")
                diagRow("Push token", pushTokenDiag)
                diagRow("Utolsó feltöltés", lastUploadDiag)
                diagRow("Kimaradás oka", skipDiag)
                diagRow("Terv-kulcs", planKeyDiag)
            } header: {
                Text("Push (Cloudflare)").mcFont(.caption)
            } footer: {
                Text("A napi terv és a határ-entryk feltöltése a workerbe — ha a token vagy a feltöltés hiányzik, a szerver nem tud átkapcsolni.").mcFont(.caption)
            }
            .mcListRowComfy(fill: colors.surface)
            Section {
                Text(workerStatus).skinFont(.caption2, design: .monospaced).foregroundStyle(.secondary)
                Button("Worker állapot frissítése") { Task { await loadWorkerStatus() } }
                .mcInlineButton()
            } header: {
                Text("Worker (mai terv)").mcFont(.caption)
            } footer: {
                Text("A worker /status válasza: melyik határra ment ki push, hány próbával, mit felelt az APNs. „Nincs terv” = a feltöltés maradt ki; APNs 400/410 = rossz token vagy sandbox–prod keveredés; 403 = kulcs/Team ID.").mcFont(.caption)
            }
            .mcListRowComfy(fill: colors.surface)
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
                .mcInlineButton()
            } header: {
                Text("Apple Watch szinkron").mcFont(.caption)
            } footer: {
                Text(watchReport.hintText.isEmpty ? "Tab-lehúzáskor (Főoldal, Órarend, Jegyek, Feladatok) az app automatikusan tol az órára." : watchReport.hintText).mcFont(.caption)
            }
            .onReceive(NotificationCenter.default.publisher(for: WatchSyncSender.reportChanged)) { _ in
                watchReport = WatchSyncSender.report()
            }
            .mcListRowComfy(fill: colors.surface)
            Section {
                diagRow("Rendszer", liveManager.isSystemEnabled ? "engedélyezett" : "TILTVA (Beállítások → Summit)")
                diagRow("App-kapcsoló", liveManager.isAppEnabled ? "be" : "KI")
                diagRow("Aktív activity", "\(liveManager.activeCount)")
                diagRow("Utolsó művelet", liveManager.lastAction)
                if let err = liveManager.lastError { diagRow("Hiba", err) }
                if liveManager.recentEvents.isEmpty {
                    Text("Még nincs esemény.").skinFont(.caption).foregroundStyle(.tertiary)
                } else {
                    ForEach(Array(liveManager.recentEvents.enumerated()), id: \.offset) { _, line in
                        Text(line).skinFont(.caption2, design: .monospaced).foregroundStyle(.secondary)
                    }
                }
            } header: {
                Text("Live Activity események").mcFont(.caption)
            }
            .mcListRowComfy(fill: colors.surface)
            Section {
                if liveManager.pushLog.isEmpty {
                    Text("Még nincs push-forgalom — tanítási időben nyisd meg a Főoldalt.")
                        .skinFont(.caption).foregroundStyle(.tertiary)
                } else {
                    ForEach(Array(liveManager.pushLog.enumerated()), id: \.offset) { _, line in
                        Text(line).skinFont(.caption2, design: .monospaced).foregroundStyle(.secondary)
                    }
                }
            }
            .mcListRowComfy(fill: colors.surface)
            Section {
                Button("Napló másolása") {
                    UIPasteboard.general.string = diagExport
                }
                .mcInlineButton()
            } header: {
                Text("Napló").mcFont(.caption)
            } footer: {
                Text("Ha üres minden: a Főoldal lehúzása után ez mutatja, 401/404/üres-200/DNS-hiba áll-e mögötte.").mcFont(.caption)
            }
            .mcListRowComfy(fill: colors.surface)
            Section {
                Button("Finom tick (selection)") { SummitHaptics.selection() }
                .mcInlineButton()
                Button("Sikeres (success)") { SummitHaptics.success() }
                .mcInlineButton()
                Button("Hibás (error)") { SummitHaptics.error() }
                .mcInlineButton()
            } header: {
                Text("Haptika-teszt").mcFont(.caption)
            } footer: {
                Text("Ha itt sem érzel semmit: iPhone Beállítások → Hangok és haptika → Rendszerhaptika legyen BE. Ha az BE van és ez rezeg, de máshol néma az app, szólj — akkor kódbug.").mcFont(.caption)
            }
            .mcListRowComfy(fill: colors.surface)
            Section {
                if networkLog.lines.isEmpty {
                    Text("Még nincs napló — húzd le a Főoldalt a frissítéshez.")
                        .skinFont(.caption).foregroundStyle(.tertiary)
                } else {
                    ForEach(Array(networkLog.lines.enumerated()), id: \.offset) { _, line in
                        Text(line).skinFont(.caption2, design: .monospaced).foregroundStyle(.secondary)
                    }
                }
            }
            .mcListRowComfy(fill: colors.surface)
        }
        .mcListChrome()
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
            Text(k).skinFont(.caption, weight: .semibold).foregroundStyle(.secondary)
            Spacer(minLength: 8)
            Text(v).skinFont(.caption, design: .monospaced).foregroundStyle(.primary).multilineTextAlignment(.trailing)
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
            + networkLog.lines.joined(separator: "\n")
            + "\n--- live activity események ---\n"
            + liveManager.recentEvents.joined(separator: "\n")
            + "\n--- push ---\n"
            + liveManager.pushLog.joined(separator: "\n")
            + "\n--- worker ---\n"
            + workerStatus
    }
}
