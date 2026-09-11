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

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                island(header: "Fejlesztői mód") {
                    row {
                        Toggle(isOn: $devEnabled) {
                            Label("Fejlesztői mód", systemImage: "hammer.fill")
                                .font(.subheadline.weight(.medium))
                        }
                        .tint(colors.accent)
                    }
                } footer: {
                    "Kikapcsolva a Fejlesztő menü és minden tesztelőeszköz eltűnik."
                }

                island(header: "Idő-eltolás") {
                    row {
                        Toggle(isOn: $isPreviewActive) {
                            Label("Idő előnézet", systemImage: "slider.horizontal.3")
                                .font(.subheadline.weight(.medium))
                        }
                        .tint(colors.accent)
                    }
                    if isPreviewActive {
                        settingsDivider
                        row {
                            VStack(spacing: 8) {
                                Slider(value: $previewMinutes, in: 420...960, step: 5)
                                    .tint(colors.accent)
                                HStack {
                                    Text("07:00").font(.caption2).foregroundStyle(.tertiary)
                                    Spacer()
                                    Text(previewTimeText).font(.caption.weight(.semibold).monospacedDigit()).foregroundStyle(colors.accent)
                                    Spacer()
                                    Text("16:00").font(.caption2).foregroundStyle(.tertiary)
                                }
                                Button("Vissza élő időre") { withAnimation { isPreviewActive = false } }
                                    .font(.caption.weight(.semibold)).tint(colors.accent)
                                Label("A csúszka a Főoldalt, az Órarendet és a Live Activity-t is mozgatja", systemImage: "livephoto")
                                    .font(.caption2).foregroundStyle(.tertiary)
                            }
                            .padding(.vertical, 4)
                        }
                    }
                    settingsDivider
                    row {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Label("Ugrás az óra végére", systemImage: "forward.fill")
                                    .font(.subheadline.weight(.medium))
                                Spacer()
                                Stepper("\(jumpMinutes) perc", value: $jumpMinutes, in: 1...15)
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            Button("Előrepörgetés most") { Task { await jumpToLessonEnd() } }
                                .font(.caption.weight(.semibold)).tint(colors.accent)
                            if let jumpInfo {
                                Text(jumpInfo).font(.caption2).foregroundStyle(.tertiary)
                            }
                            Text("A csúszkát az aktuális óra vége elé állítja — az óraátmenetet az app nyitva tartva várd meg (percenkénti sync kapcsolja át).")
                                .font(.caption2).foregroundStyle(.tertiary)
                        }
                        .padding(.vertical, 4)
                    }
                } footer: {
                    "A Főoldal és az Órarend az eltolt idő szerint rajzol — valós és demo fiókkal is."
                }

                island(header: "Értesítések") {
                    row {
                        HStack {
                            Text("Rendszerengedély").font(.subheadline)
                            Spacer()
                            Text(notifStatus).font(.caption.weight(.medium)).foregroundStyle(.secondary)
                            Button("Kérés") { Task {
                                await NotificationManager.shared.requestPermission()
                                notifStatus = NotificationManager.shared.permissionStatus
                            } }
                            .font(.caption.weight(.semibold)).tint(colors.accent)
                        }
                    }
                    settingsDivider
                    row {
                        Button("Teszt értesítés küldése") { Task {
                            await NotificationManager.shared.sendTest(userId: session.selectedUser?.id ?? "dev")
                            notifStatus = NotificationManager.shared.permissionStatus
                        } }
                        .tint(colors.accent)
                    }
                    settingsDivider
                    row {
                        Button("Új jegy szimulálása (5-ös Matek + kártya)") { Task {
                            _ = await NotificationManager.shared.simulateDemoGrade()
                            // A fullscreen ünneplő kártya magától felpattan — ez a tesztje.
                        } }
                        .tint(colors.accent)
                    }
                    settingsDivider
                    row {
                        Button("Értesítési előzmény törlése (újrateszteléshez)") {
                            NotificationManager.shared.resetDemoSeen()
                            simMessage = "Előzmény törölve — a következő frissítés csendben magot vet."
                            showSimAlert = true
                        }
                        .tint(.red)
                    }
                }

                island(header: "Live Activity") {
                    row {
                        HStack(spacing: 6) {
                            Circle().fill(liveManager.isSystemEnabled ? Color.green : Color.red).frame(width: 7, height: 7)
                            Text(liveManager.isSystemEnabled ? "Rendszer OK" : "Rendszer tiltva")
                                .font(.caption2.weight(.medium))
                                .foregroundStyle(liveManager.isSystemEnabled ? Color.secondary : Color.red)
                            Spacer()
                            Text("\(liveManager.activeCount) aktív • \(liveManager.lastAction)")
                                .font(.caption2).foregroundStyle(.tertiary).lineLimit(1)
                        }
                    }
                    if let err = liveManager.lastError {
                        settingsDivider
                        row { Text(err).font(.caption2).foregroundStyle(.orange).lineLimit(2) }
                    }
                    settingsDivider
                    row {
                        HStack(spacing: 12) {
                            Button("Teszt indítása most") {
                                Task { await liveManager.startDemoTestNow(userId: session.selectedUser?.id ?? "", accentHex: theme.accentHex) }
                            }
                            .font(.caption.weight(.semibold)).tint(colors.accent)
                            Button("Leállítás") {
                                Task { await liveManager.endAll(dismissalPolicy: .immediate) }
                            }
                            .font(.caption.weight(.semibold)).tint(.red)
                        }
                    }
                    settingsDivider
                    row {
                        VStack(alignment: .leading, spacing: 6) {
                            Button("Push-terv feltöltése most (Cloudflare)") {
                                Task { await uploadPushPlanNow() }
                            }
                            .font(.caption.weight(.semibold)).tint(colors.accent)
                            if let pushUploadInfo {
                                Text(pushUploadInfo).font(.caption2).foregroundStyle(.secondary)
                            } else {
                                Text("A mentett mai terv (vagy friss órarend) ad hoc feltöltése a workerbe — az eredmény a Diagnosztikában is látszik.")
                                    .font(.caption2).foregroundStyle(.tertiary)
                            }
                        }
                        .padding(.vertical, 2)
                    }
                    settingsDivider
                    row {
                        // Widget extension telepítve? Enélkül a pill felmegy, de az expanded fekete.
                        if isWidgetExtensionInstalled {
                            Label("Widget extension telepítve", systemImage: "checkmark.circle.fill")
                                .font(.caption2).foregroundStyle(.secondary)
                        } else {
                            Label("Widget extension HIÁNYZIK — töröld az appot és telepítsd újra Xcode-ból, ez okozza a fekete Islandet", systemImage: "exclamationmark.triangle.fill")
                                .font(.caption2).foregroundStyle(.red)
                        }
                    }
                    settingsDivider
                    row {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Eseménynapló")
                                .font(.caption2.weight(.bold)).foregroundStyle(.secondary)
                            if liveManager.recentEvents.isEmpty {
                                Text("Még nincs esemény — nyisd meg a Főoldalt tanítási időben.")
                                    .font(.caption2).foregroundStyle(.tertiary)
                            } else {
                                ForEach(Array(liveManager.recentEvents.suffix(8).enumerated()), id: \.offset) { _, line in
                                    Text(line)
                                        .font(.caption2.monospacedDigit()).foregroundStyle(.secondary)
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
            .frame(maxWidth: isPad ? MacSupport.contentWidth(ipad: 800, mac: 920) : .infinity)
            .frame(maxWidth: .infinity)
        }
        .background { SummitBackdrop(imageName: "DevPeak") }
        .scrollContentBackground(.hidden)
        .navigationTitle("Fejlesztő")
        .navigationBarTitleDisplayMode(.inline)
        .alert("Fejlesztői eszközök", isPresented: $showSimAlert) {
            Button("OK", role: .cancel) {}
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
                Text(header).font(.caption.weight(.semibold)).foregroundStyle(.secondary).textCase(.uppercase)
                    .padding(.horizontal, 4)
            }
            VStack(alignment: .leading, spacing: 0) {
                content()
            }
            .summitGlassRow(cornerRadius: 20)
            if let footer = footer() {
                Text(footer).font(.caption2).foregroundStyle(.secondary)
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

    private var settingsDivider: some View {
        Divider().padding(.leading, 16)
    }
}
