import SwiftUI

// MARK: - Fejlesztői mód képernyő
// Feloldás: Beállítások alján a "Summit • Gábor Csaba" sor 10x tap.
// Minden tesztelőeszköz itt él (nem demo-felhasználóhoz kötve):
// idő-eltolás csúszka, értesítés-tesztek, Live Activity teszt.
// Háttér: DevPeak fotó, Beállítások-stílusú liquid glass szigetekkel.
struct DeveloperView: View {
    @EnvironmentObject var session: SessionStore
    @EnvironmentObject var theme: ThemeStore
    @Environment(\.colorScheme) var scheme
    @Environment(\.horizontalSizeClass) private var hSize
    private var isPad: Bool { hSize == .regular }
    var colors: AppColors { theme.colors(for: scheme) }

    @AppStorage("developer.enabled") private var devEnabled = true
    @AppStorage("home.demoPreviewActive") private var isPreviewActive = false
    @AppStorage("home.demoPreviewMinutes") private var previewMinutes: Double = 540
    @ObservedObject private var liveManager = SummitLiveActivityManager.shared
    @State private var notifStatus = NotificationManager.shared.permissionStatus
    @State private var simMessage: String?
    @State private var showSimAlert = false
    @State private var jumpMinutes = 2
    @State private var jumpInfo: String?
    @State private var pushUploadInfo: String?
    @State private var pushRestartInfo: String?

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                island(header: "Fejlesztői mód") {
                    row {
                        Toggle(isOn: $devEnabled) {
                            SkinLabel("Fejlesztői mód", systemImage: "hammer.fill")
                                .skinFont(.subheadline, weight: .medium)
                        }
                        .tint(colors.accent)
                        .skinToggleStyle()
                    }
                } footer: {
                    "Kikapcsolva a Fejlesztő menü és minden tesztelőeszköz eltűnik."
                }

                island(header: "Idő-eltolás") {
                    row {
                        Toggle(isOn: $isPreviewActive) {
                            SkinLabel("Idő előnézet", systemImage: "slider.horizontal.3")
                                .skinFont(.subheadline, weight: .medium)
                        }
                        .tint(colors.accent)
                        .skinToggleStyle()
                    }
                    if isPreviewActive {
                        settingsDivider
                        row {
                            VStack(spacing: 8) {
                                SkinSlider(value: $previewMinutes, range: 420...960, step: 5)
                                    .tint(colors.accent)
                                HStack {
                                    Text("07:00").skinFont(.caption2).foregroundStyle(.tertiary)
                                    Spacer()
                                    Text(previewTimeText).skinFont(.caption, weight: .semibold).monospacedDigit().foregroundStyle(colors.accent)
                                    Spacer()
                                    Text("16:00").skinFont(.caption2).foregroundStyle(.tertiary)
                                }
                                Button("Vissza élő időre") { withAnimation { isPreviewActive = false } }
                                    .skinFont(.caption, weight: .semibold).tint(colors.accent)
                                    .voxelInlineButton()
                                SkinLabel("A csúszka a Főoldalt, az Órarendet és a Live Activity-t is mozgatja", systemImage: "livephoto")
                                    .skinFont(.caption2).foregroundStyle(.tertiary)
                            }
                            .padding(.vertical, 4)
                        }
                    }
                    settingsDivider
                    row {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                SkinLabel("Ugrás az óra végére", systemImage: "forward.fill")
                                    .skinFont(.subheadline, weight: .medium)
                                Spacer()
                                SkinStepper(title: "\(jumpMinutes) perc", value: $jumpMinutes, range: 1...15)
                                    .skinFont(.caption).foregroundStyle(.secondary)
                            }
                            Button("Előrepörgetés most") { Task { await jumpToLessonEnd() } }
                                .skinFont(.caption, weight: .semibold).tint(colors.accent)
                                .voxelInlineButton()
                            if let jumpInfo {
                                Text(jumpInfo).skinFont(.caption2).foregroundStyle(.tertiary)
                            }
                            Text("A csúszkát az aktuális óra vége elé állítja — az óraátmenetet az app nyitva tartva várd meg (percenkénti sync kapcsolja át).")
                                .skinFont(.caption2).foregroundStyle(.tertiary)
                        }
                        .padding(.vertical, 4)
                    }
                } footer: {
                    "A Főoldal és az Órarend az eltolt idő szerint rajzol — valós és demo fiókkal is."
                }

                island(header: "Értesítések") {
                    row {
                        HStack {
                            Text("Rendszerengedély").skinFont(.subheadline)
                            Spacer()
                            Text(notifStatus).skinFont(.caption, weight: .medium).foregroundStyle(.secondary)
                            Button("Kérés") { Task {
                                await NotificationManager.shared.requestPermission()
                                notifStatus = NotificationManager.shared.permissionStatus
                            } }
                            .skinFont(.caption, weight: .semibold).tint(colors.accent)
                            .voxelInlineButton()
                        }
                    }
                    settingsDivider
                    row {
                        Button("Teszt értesítés küldése") { Task {
                            await NotificationManager.shared.sendTest(userId: session.selectedUser?.id ?? "dev")
                            notifStatus = NotificationManager.shared.permissionStatus
                        } }
                        .tint(colors.accent)
                        .voxelInlineButton()
                    }
                    settingsDivider
                    row {
                        Button("Új jegy szimulálása (5-ös Matek + kártya)") { Task {
                            _ = await NotificationManager.shared.simulateDemoGrade()
                            // A fullscreen ünneplő kártya magától felpattan — ez a tesztje.
                        } }
                        .tint(colors.accent)
                        .voxelInlineButton()
                    }
                    settingsDivider
                    row {
                        Button("Értesítési előzmény törlése (újrateszteléshez)") {
                            NotificationManager.shared.resetDemoSeen()
                            simMessage = "Előzmény törölve — a következő frissítés csendben magot vet."
                            showSimAlert = true
                        }
                        .tint(.red)
                        .voxelInlineButton()
                    }
                }

                island(header: "Live Activity") {
                    row {
                        HStack(spacing: 6) {
                            SkinDot(color: liveManager.isSystemEnabled ? Color.green : Color.red, size: 7)
                            Text(liveManager.isSystemEnabled ? "Rendszer OK" : "Rendszer tiltva")
                                .skinFont(.caption2, weight: .medium)
                                .foregroundStyle(liveManager.isSystemEnabled ? Color.secondary : Color.red)
                            Spacer()
                            Text("\(liveManager.activeCount) aktív • \(liveManager.lastAction)")
                                .skinFont(.caption2).foregroundStyle(.tertiary).lineLimit(1)
                        }
                    }
                    if let err = liveManager.lastError {
                        settingsDivider
                        row { Text(err).skinFont(.caption2).foregroundStyle(.orange).lineLimit(2) }
                    }
                    settingsDivider
                    row {
                        HStack(spacing: 12) {
                            Button("Teszt indítása most") {
                                Task { await liveManager.startDemoTestNow(userId: session.selectedUser?.id ?? "", accentHex: theme.accentHex) }
                            }
                            .skinFont(.caption, weight: .semibold).tint(colors.accent)
                            .voxelInlineButton()
                            #if !targetEnvironment(macCatalyst)
                            Button("Leállítás") {
                                Task { await liveManager.endAll(dismissalPolicy: .immediate) }
                            }
                            .skinFont(.caption, weight: .semibold).tint(.red)
                            .voxelInlineButton()
                            #endif
                        }
                    }
                    settingsDivider
                    row {
                        VStack(alignment: .leading, spacing: 6) {
                            Button("Push-újraindítás (beragadt activity cseréje)") {
                                Task { await restartPushNow() }
                            }
                            .skinFont(.caption, weight: .semibold).tint(colors.accent)
                            .voxelInlineButton()
                            if let pushRestartInfo {
                                Text(pushRestartInfo).skinFont(.caption2).foregroundStyle(.secondary)
                            } else {
                                Text("Régi buildtől örökölt, push nélküli activityt cserél újra — tokenre vár, majd feltölt. Ha nincs mentett mai terv (este), előbb a Demo teszt kell.")
                                    .skinFont(.caption2).foregroundStyle(.tertiary)
                            }
                        }
                        .padding(.vertical, 2)
                    }
                    settingsDivider
                    row {
                        VStack(alignment: .leading, spacing: 6) {
                            Button("Push-terv feltöltése most (Cloudflare)") {
                                Task { await uploadPushPlanNow() }
                            }
                            .skinFont(.caption, weight: .semibold).tint(colors.accent)
                            .voxelInlineButton()
                            if let pushUploadInfo {
                                Text(pushUploadInfo).skinFont(.caption2).foregroundStyle(.secondary)
                            } else {
                                Text("A mentett mai terv (vagy friss órarend) ad hoc feltöltése a workerbe — az eredmény a Diagnosztikában is látszik.")
                                    .skinFont(.caption2).foregroundStyle(.tertiary)
                            }
                        }
                        .padding(.vertical, 2)
                    }
                    settingsDivider
                    row {
                        // Widget extension telepítve? Enélkül a pill felmegy, de az expanded fekete.
                        if isWidgetExtensionInstalled {
                            SkinLabel("Widget extension telepítve", systemImage: "checkmark.circle.fill")
                                .skinFont(.caption2).foregroundStyle(.secondary)
                        } else {
                            SkinLabel("Widget extension HIÁNYZIK — töröld az appot és telepítsd újra Xcode-ból, ez okozza a fekete Islandet", systemImage: "exclamationmark.triangle.fill")
                                .skinFont(.caption2).foregroundStyle(.red)
                        }
                    }
                    settingsDivider
                    row {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Eseménynapló")
                                .skinFont(.caption2, weight: .bold).foregroundStyle(.secondary)
                            if liveManager.recentEvents.isEmpty {
                                Text("Még nincs esemény — nyisd meg a Főoldalt tanítási időben.")
                                    .skinFont(.caption2).foregroundStyle(.tertiary)
                            } else {
                                ForEach(Array(liveManager.recentEvents.suffix(8).enumerated()), id: \.offset) { _, line in
                                    Text(line)
                                        .skinFont(.caption2).monospacedDigit().foregroundStyle(.secondary)
                                        .lineLimit(2)
                                }
                            }
                        }
                    }
                } footer: {
                    "Órarend-független gyorsteszt — este is működik. A határok a workerbe is felmennek: zárd le a telefont, az átkapcsolás push-ban jön (2. percnél szünet, 4.-nél következő óra)."
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 24)
            .frame(maxWidth: isPad ? MacSupport.contentWidth(ipad: 1000, mac: 920) : .infinity)
            .padding(.horizontal, MacSupport.sidePadding)
            .frame(maxWidth: .infinity)
        }
        .background {
            if theme.isNeon {
                NeonBackdrop()
            } else if theme.isVoxel {
                VoxelBackdrop(mountain: true)
            } else {
                SummitBackdrop(imageName: "DevPeak")
            }
        }
        .scrollContentBackground(.hidden)
        .navigationTitle("Fejlesztő")
        .navigationBarTitleDisplayMode(.inline)
        .alert("Fejlesztői eszközök", isPresented: $showSimAlert) {
            Button("OK", role: .cancel) {}
            .voxelInlineButton()
        } message: {
            Text(simMessage ?? "")
        }
        .task {
            // Első indításkor a csúszka a mostani időre álljon (ne fix 09:00-ra).
            if UserDefaults.standard.object(forKey: "home.demoPreviewMinutes") == nil {
                let c = Calendar.current
                let h = c.component(.hour, from: Date())
                let m = c.component(.minute, from: Date())
                previewMinutes = Double(max(420, min(960, h * 60 + m)))
            }
        }
    }

    private var previewTimeText: String { previewDate.formatted(date: .omitted, time: .shortened) }
    private var previewDate: Date {
        let base = Calendar.current.startOfDay(for: Date())
        return base.addingTimeInterval(previewMinutes * 60)
    }

    /// Előrepörgetés az aktuális óra végére: a csúszkát az óra vége elé
    /// (választhatóan X perccel) állítja és bekapcsolja az idő-előnézetet —
    /// így a Live Activity óraátmenet pár perc alatt, élőben tesztelhető.
    /// Valós és demo fiókkal is megy (a demo helyből szolgál ki).
    @MainActor
    private func jumpToLessonEnd() async {
        jumpInfo = nil
        let now = Date()
        guard let user = session.selectedUser else {
            jumpInfo = "Nincs belépett felhasználó."
            return
        }
        let kreta = KretaClient()
        kreta.accessToken = user.accessToken
        kreta.refreshToken = user.refreshToken
        kreta.instituteCode = user.instituteCode
        let iss = user.instituteCode.isEmpty
            ? (JWT.instituteCode(from: user.accessToken) ?? "")
            : user.instituteCode
        guard !iss.isEmpty, iss != "unknown" else {
            jumpInfo = "Ismeretlen iskola-kód."
            return
        }
        let cal = Calendar.current
        let start = cal.startOfDay(for: now)
        guard let end = cal.date(byAdding: .day, value: 1, to: start) else { return }
        let today = await kreta.fetchTimetable(iss: iss, from: start, to: end)
            .filter { cal.isDate($0.start, inSameDayAs: now) }
            .sorted { $0.start < $1.start }
        guard let cur = today.first(where: { $0.start <= now && $0.end >= now }) else {
            jumpInfo = "Most nincs tanóra — szünetben vagy tanításmentes napon nincs mire ugrani."
            return
        }
        // Cél: az óra vége előtt X perccel. Ha ennél közelebb a vége,
        // a végére ugrunk (min. ~20 mp maradjon a visszaszámlálóból).
        var target = cur.end.addingTimeInterval(-Double(jumpMinutes * 60))
        var jumpedToEnd = false
        if target <= now.addingTimeInterval(20) {
            target = cur.end.addingTimeInterval(-20)
            if target <= now { target = now.addingTimeInterval(15) }
            jumpedToEnd = true
        }
        previewMinutes = target.timeIntervalSince(start) / 60
        isPreviewActive = true
        let t = target.formatted(date: .omitted, time: .shortened)
        let label = "„\(cur.subject) \(cur.index). óra”"
        jumpInfo = jumpedToEnd
            ? "\(label) már a végén jár — a végére ugrottam (\(t))."
            : "\(label) vége elé ugrottam \(jumpMinutes) perccel (\(t))."
    }

    /// Push-újraindítás: beragadt (örökölt, push nélküli) activity cseréje
    /// újra, tokenre várás, majd azonnali feltöltés. Este, mentett terv
    /// nélkül nem megy (akkor előbb a Demo teszt gomb kell).
    @MainActor
    private func restartPushNow() async {
        pushRestartInfo = nil
        guard await liveManager.restartForPush() else {
            pushRestartInfo = "Nincs mentett mai terv — este a Demo teszt gombbal indul activity."
            return
        }
        for _ in 0..<15 {
            if liveManager.pushTokens.values.first != nil { break }
            try? await Task.sleep(nanoseconds: 1_000_000_000)
        }
        guard liveManager.pushTokens.values.first != nil else {
            pushRestartInfo = liveManager.startedWithoutPush
                ? "Újraindult, de ez a build továbbra is push nélkül kér — profilhiba, reinstall kell."
                : "Újraindult, token még nem jött meg — várj fél percet, majd nyomd meg a feltöltést."
            return
        }
        await uploadPushPlanNow()
        pushRestartInfo = pushUploadInfo
    }

    /// Ad hoc push-terv feltöltés a Cloudflare workerbe (valós kulcsra,
    /// nem preview-ra). Forrás: előbb a mentett mai terv-cache (offline is
    /// megy), ha az nincs, friss órarend-lekérés a KRÉTÁ-ból. Az eredményt
    /// a kick a Diagnosztikában is naplózza (Utolsó feltöltés / Kimaradás).
    @MainActor
    private func uploadPushPlanNow() async {
        pushUploadInfo = nil
        let now = Date()
        guard let user = session.selectedUser else {
            pushUploadInfo = "Nincs belépett felhasználó."
            return
        }
        var lessons = liveManager.cachedLessons(now: now)?.lessons
        if lessons == nil {
            let kreta = KretaClient()
            kreta.accessToken = user.accessToken
            kreta.refreshToken = user.refreshToken
            kreta.instituteCode = user.instituteCode
            let iss = user.instituteCode.isEmpty
                ? (JWT.instituteCode(from: user.accessToken) ?? "")
                : user.instituteCode
            guard !iss.isEmpty, iss != "unknown" else {
                pushUploadInfo = "Ismeretlen iskola-kód."
                return
            }
            let cal = Calendar.current
            let start = cal.startOfDay(for: now)
            guard let end = cal.date(byAdding: .day, value: 1, to: start) else { return }
            lessons = await kreta.fetchTimetable(iss: iss, from: start, to: end)
                .filter { cal.isDate($0.start, inSameDayAs: now) }
                .sorted { $0.start < $1.start }
        }
        guard let lessons, !lessons.isEmpty else {
            pushUploadInfo = "Nincs mai órarend (cache üres, hálózat üres)."
            return
        }
        // Token csak élő activityhez jár: ha üres, megmondjuk, activity
        // sincs (Főoldal kell előbb), vagy az activity él, de a token még
        // nem érkezett meg / ez a build pushType nélkül fut (régi profil).
        guard let token = liveManager.pushTokens.values.first else {
            if liveManager.activeCount == 0 {
                pushUploadInfo = "Nincs élő Live Activity — token csak élő activityhez jár. Előbb nyisd meg a Főoldalt tanítási időben."
            } else if liveManager.startedWithoutPush {
                pushUploadInfo = "Ez a build push nélkül fut (a profilban nincs Push) — ebből a buildből a feltöltés nem fog menni. Megoldás: app törlése + újratelepítés a javított TestFlight builddel."
            } else {
                pushUploadInfo = "Nincs token, pedig \(liveManager.activeCount) activity él — várj pár mp-et, majd nyomd újra."
            }
            return
        }
        let before = UserDefaults.standard.string(forKey: SummitPushSync.lastUploadSummaryKey)
        await SummitPushSync.shared.kick(
            today: lessons, now: now,
            dayKey: SummitLiveActivityManager.dayKey(for: now),
            userId: user.id,
            pushToken: token)
        let after = UserDefaults.standard.string(forKey: SummitPushSync.lastUploadSummaryKey)
        if after != before, let after {
            pushUploadInfo = "Feltöltve: \(after)"
        } else if let skip = UserDefaults.standard.string(forKey: SummitPushSync.lastSkipReasonKey) {
            pushUploadInfo = "Kimaradt: \(skip)"
        } else {
            pushUploadInfo = "Változatlan — ez a terv már fent van a workerben."
        }
    }

    /// A widget appex tényleg az app része? Régi telepítésnél hiányozhat → fekete expanded Island.
    private var isWidgetExtensionInstalled: Bool {
        let url = Bundle.main.bundleURL.appendingPathComponent("PlugIns/SummitWidgets.appex", isDirectory: true)
        return FileManager.default.fileExists(atPath: url.path)
    }

    // MARK: - Beállítások-stílusú glass szigetek (helyi másolat, DevPeak-háttérhez)
    private func island<Content: View>(header: String? = nil, @ViewBuilder content: () -> Content, footer: () -> String? = { nil }) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            if let header {
                Text(header).voxelSectionHeader()
                    .padding(.horizontal, 4)
            }
            VStack(alignment: .leading, spacing: 0) {
                content()
            }
            .summitGlassRow(cornerRadius: 20)
            if let footer = footer() {
                Text(footer).skinFont(.caption2).foregroundStyle(.secondary)
                    .padding(.horizontal, 4)
            }
        }
    }

    private func row<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 0) { content() }
            .padding(.horizontal, 16)
            .padding(.vertical, 11)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var settingsDivider: some View {
        if theme.isNeon {
            Rectangle().fill(NeonTheme.line).frame(height: 1).padding(.leading, 16)
        } else if theme.isVoxel {
            Rectangle().fill(Color.black.opacity(0.22)).frame(height: VoxelTheme.px)
        } else {
            Divider().padding(.leading, 16)
        }
    }
}
