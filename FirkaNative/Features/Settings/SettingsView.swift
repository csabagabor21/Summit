import SwiftUI
import PhotosUI

struct SettingsView: View {
    @EnvironmentObject var session: SessionStore
    @EnvironmentObject var theme: ThemeStore
    @EnvironmentObject var kreta: KretaClient
    @EnvironmentObject var profileStore: ProfileImageStore
    @EnvironmentObject var analytics: AnalyticsStore
    @EnvironmentObject var summitSync: SummitSync
    @EnvironmentObject var completed: CompletedStore
    @Environment(\.colorScheme) var scheme
    @Environment(\.horizontalSizeClass) private var hSize
    private var isPad: Bool { hSize == .regular }
    @State private var thresholds: [String: Double] = GradingLogic.loadThresholds()
    @State private var subjects: [String] = []
    @State private var isLoadingSubjects = true
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var cropImage: UIImage?
    @State private var showPhotoOptions = false
    @State private var showPhotoPicker = false
    @State private var instituteMsg = ""
    @State private var schoolNameMsg = ""
    /// Az utolsó bekapcsolási kísérlet elbukott: a státuszsor ilyenkor a
    /// hibát mutatja, nem a „jelszó mentve — kapcsolhatod" szöveget.
    @State private var syncEnableFailed = false
    @State private var confirmSyncDelete = false
    @AppStorage("exams.rolloverOnAbsence") private var examRollover = true
    @AppStorage("developer.enabled") private var devEnabled = false
    @AppStorage("home.demoPreviewActive") private var isPreviewOn = false
    @State private var devTaps = 0
    @State private var devTapReset: Task<Void, Never>?
    @State private var showDevAlert = false
    @State private var draftIss = ""
    @State private var draftNickname = ""
    @State private var nicknameTick = 0
    @State private var draftSchoolName = ""
    @State private var draftMetaAIKey = ""
    @State private var metaAIKeyEdited = false
    @State private var metaAIKeyMsg = ""
    @State private var repairMsg = ""
    @State private var repairRunning = false
    @State private var summitSyncPassphrase = ""
    @State private var summitSyncBusy = false
    @State private var scrollOffset: CGFloat = 0 // parallax háttérhez (onScrollGeometryChange)
    @AppStorage("tour.settings.seen.v1") private var tourSeen = false
    @State private var accountExpanded = false // Fiók: egysoros, koppintásra nyílik
    @AppStorage("notify.enabled") private var notifyEnabled = true // Értesítések főkapcsolója
    @State private var travelOn = false // Utazás mód kapcsoló
    @State private var travelFrom = Calendar.current.startOfDay(for: Date())
    @State private var travelTo = Calendar.current.startOfDay(for: Date().addingTimeInterval(7 * 86400))
    @State private var calendarExpanded = false // Iskolai események lenyíló
    @State private var tourStep: Int?
    var colors: AppColors { theme.colors(for: scheme) }

    /// Az épp magyarázott sziget-e a túra fókusza.
    private func tourIs(_ anchor: SettingsTour.Anchor) -> Bool {
        guard let i = tourStep, SettingsTour.steps.indices.contains(i) else { return false }
        return SettingsTour.steps[i].anchor == anchor
    }

    /// Kiemelőszín-választó (külön nézet, hogy az x86_64 fordító is
    /// időben végezzen a típusellenőrzéssel).
    private var accentColorContent: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Kiemelés színe").skinFont(.subheadline, weight: .medium)
            HStack(spacing: 10) {
                ForEach(ThemeStore.presets, id: \.self) { hex in
                    let c = Color(hex: UInt(hex))
                    Circle().fill(c).frame(width: 30, height: 30)
                        .overlay(Circle().strokeBorder(Color.primary.opacity(theme.accentHex == hex ? 0.9 : 0.18), lineWidth: theme.accentHex == hex ? 2 : 1))
                        .scaleEffect(theme.accentHex == hex ? 1.12 : 1)
                        .onTapGesture { withAnimation(SummitMotion.snappy) { theme.accentHex = hex } }
                        .accessibilityLabel(Text(String(format: "#%06X", hex)))
                }
                Spacer()
                ColorPicker("", selection: Binding(get: { theme.accent }, set: { new in
                    let ui = UIColor(new)
                    var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
                    if ui.getRed(&r, green: &g, blue: &b, alpha: &a) {
                        let hex = (Int(round(r*255)) << 16) | (Int(round(g*255)) << 8) | Int(round(b*255))
                        theme.accentHex = hex
                    }
                }), supportsOpacity: false)
                .labelsHidden().scaleEffect(1.2)
            }
        }
    }

    /// Szövegméret-választó (külön nézet, ld. fent).
    private var textSizeContent: some View {
        SkinMenuPicker(
            title: "Szövegméret",
            selection: Binding(get: { theme.sizeCategoryKey }, set: { theme.sizeCategoryKey = $0 }),
            options: ThemeStore.sizeSteps.map { SkinOption(value: $0.key, title: $0.title) },
            navigationStyle: true
        )
        .padding(.vertical, 4)
    }

    /// Beállítások 1. blokk: profil + archívum + megjelenés + kerekítés.
    /// (Az óriás body kifejezést az x86_64 fordító nem tudja időben
    /// típusellenőrizni — a blokkok külön-külön már mennek.)
    private var settingsTopSection: some View {
        Group {
            // Profil-sziget (fejléc nélkül, mint eddig)
            HStack(spacing: 12) {
                // Koppintásra: kép nélkül egyből a fotóválasztó, képpel a
                // csere/törlés lap (korábban kép nélkül egy csak „Mégse”
                // gombos, zsákutca-dialógus nyílt).
                Button { avatarTapped() } label: {
                ZStack(alignment: .bottomTrailing) {
                    ProfileImageView(name: session.displayName, userId: summitProfileKey, size: 56).frame(width: 56, height: 56)
                    if theme.isVoxel {
                        // Pixel-slot a kerek jelvény helyett (játékos-fej keret).
                        SkinIcon("camera.fill", size: 18)
                            .frame(width: 30, height: 30)
                            .background { VoxelInventorySlot() }
                            .offset(x: 3, y: 3)
                    } else if theme.isNeon {
                        // Levágott sarkú sárga HUD-jelvény a kerek helyett.
                        Image(systemName: "camera")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(Color.black)
                            .frame(width: 22, height: 22)
                            .background(NeonChamferShape(cut: 5, corners: [.topLeft, .bottomRight]).fill(NeonTheme.yellow))
                            .offset(x: 2, y: 2)
                    } else {
                        Circle().fill(colors.accent).frame(width: 22, height: 22)
                            .overlay(SkinIcon("camera.fill").font(.system(size: 10, weight: .bold)).foregroundStyle(.white))
                            .overlay(Circle().stroke(.white, lineWidth: 1.5))
                            .offset(x: 2, y: 2)
                    }
                }
                .contentShape(Rectangle())
                }
                .buttonStyle(.skinPlain)
                .accessibilityLabel("Profilkép módosítása")
                VStack(alignment: .leading, spacing: 2) {
                    Text(session.displayName).skinFont(.headline)
                    if let real = session.selectedUser?.name, real != session.displayName {
                        Text("KRÉTA: \(real)").skinFont(.caption).foregroundStyle(.secondary)
                    }
                    Text(session.selectedUser?.schoolName ?? "").skinFont(.caption).foregroundStyle(.secondary)
                    Text("e-KRÉTA • \(session.selectedUser?.instituteCode ?? "-")").skinFont(.caption2).foregroundStyle(.tertiary)
                }
                Spacer()
                PhotosPicker(selection: $selectedPhoto, matching: .images, photoLibrary: .shared()) {
                    Text("Módosítás").skinFont(.caption, weight: .semibold)
                }
                .tint(colors.accent)
                .onChange(of: selectedPhoto) { _, new in
                    Task { await handlePhotoChange(new) }
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .summitGlassRow(cornerRadius: 20)
            .id(AnyHashable(SettingsTour.Anchor.profile))
            .tourHighlight(active: tourIs(.profile), accent: colors.accent)
            .photosPicker(isPresented: $showPhotoPicker, selection: $selectedPhoto, matching: .images, photoLibrary: .shared())
            .confirmationDialog("Profilkép", isPresented: $showPhotoOptions, titleVisibility: .visible) {
                Button("Új kép választása") { showPhotoPicker = true }
                // A törlés SummitSync-értesítést postol → a `photo` mező
                // delta-feltöltése automatikus, kézi push nem kell.
                if profileStore.hasImage(for: summitProfileKey) {
                    Button("Kép törlése", role: .destructive) {
                        profileStore.remove(for: summitProfileKey)
                    }
                }
                Button("Mégse", role: .cancel) {}
                } message: { Text("Válassz új képet, vagy töröld a jelenlegit.") }

            // Becenév: eszköz-helyi megjelenítési név (üdvözlés, profil).
            // Nem szinkronizálódik, a KRÉTA-név és a statisztika változatlan.
            summitIsland(header: "Becenév", footer: "Csak ezen az eszközön látszik — a KRÉTA-név és a statisztika változatlan marad.") {
                summitRow {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            TextField("pl. Marci", text: $draftNickname, prompt: skinPrompt("pl. Marci"))
                                .skinFont(.subheadline)
                                .textInputAutocapitalization(.words)
                                .autocorrectionDisabled()
                                .summitInput()
                            Button("Mentés") { saveNickname() }
                                .skinFont(.subheadline, weight: .bold)
                                .disabled(draftNickname.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                                .voxelInlineButton()
                        }
                        if let nick = currentNickname {
                            HStack {
                                Text("Most: \(nick)")
                                    .skinFont(.caption2).foregroundStyle(.secondary)
                                Spacer()
                                Button("Törlés", role: .destructive) { clearNickname() }
                                    .skinFont(.caption, weight: .bold)
                                    .voxelInlineButton()
                            }
                        }
                    }
                }
            }

            // Havi Wrapped-archívum: a banner csak elsejéig él, itt minden
            // jegyes hónap visszanézhető (a jegyek gyorstárból jönnek).
            summitIsland(header: "Havi összefoglalók") {
                NavigationLink {
                    MonthlyArchiveView().voxelBackButton()
                } label: {
                    HStack {
                        SkinLabel("Havi összefoglalók", systemImage: "sparkles").skinFont(.subheadline, weight: .medium)
                        Spacer()
                        SkinIcon("chevron.right")
                            .skinFont(.caption, weight: .semibold).foregroundStyle(.tertiary)
                    }
                    .summitTapRow()
                }
                .tint(colors.accent)
            }

            summitIsland(header: "Megjelenés", tour: .appearance, tourActive: tourIs(.appearance)) {
                summitRow {
                    SkinSegmented(
                        title: "Téma",
                        selection: Binding(get: { theme.mode }, set: { theme.mode = $0 }),
                        options: AppThemeMode.allCases.map { SkinOption(value: $0, title: $0.title, icon: $0.icon) }
                    )
                    // Neonban a séma kényszerítetten sötét — a választó
                    // megmarad (a többi skinre visszaváltva él), de itt inaktív.
                    .disabled(theme.isNeon)
                    .opacity(theme.isNeon ? 0.4 : 1)
                    if theme.isNeon {
                        NeonLabel("NEON = MINDIG SÖTÉT", color: NeonTheme.dim, bracketed: false, size: 9)
                            .padding(.top, 6)
                    }
                }
                summitDivider
                // Felület-skin: Summit (gyári) vagy Voxel (modern
                // 1.20+ blokk-stílus + shader-hangulat). Minden eszközre
                // szinkronizálódik (sync `skin` mező).
                // Három előnézeti csempe (mindegyik a saját skinje stílusában),
                // így a választó bármelyik aktív skinben egyformán olvasható.
                summitRow {
                    SkinChoiceTiles(selection: Binding(get: { theme.skin }, set: { theme.skin = $0 }),
                                    accent: colors.accent)
                }
                summitDivider
                // Accent —简单 színválasztó. Voxelben a skin fűzöldje él,
                // a kiemelőszín nem hat — ott a választó el van rejtve.
                if !theme.isVoxel && !theme.isNeon {
                    summitRow {
                        accentColorContent
                            .padding(.vertical, 4)
                    }
                    summitDivider
                }
                // Szövegméret — Macen (iPad-app Macen) alapból nagyobb
                summitRow {
                    textSizeContent
                }
            }

            summitIsland(header: "Tanári kerekítés", footer: "Tantárgyanként külön állítható.", tour: .rounding, tourActive: tourIs(.rounding)) {
                NavigationLink { TeacherRoundingView().voxelBackButton() } label: {
                    HStack {
                        SkinLabel("Tanári kerekítés", systemImage: "slider.horizontal.below.rounded")
                            .skinFont(.subheadline, weight: .medium)
                        Spacer()
                        if isLoadingSubjects {
                            SkinProgress().scaleEffect(0.85)
                        } else if subjects.isEmpty {
                            Text("—").foregroundStyle(.tertiary).skinFont(.caption)
                        } else {
                            Text("\(subjects.count) tárgy").skinFont(.caption, weight: .medium).foregroundStyle(.secondary)
                        }
                        SkinIcon("chevron.right")
                            .skinFont(.caption, weight: .semibold).foregroundStyle(.tertiary)
                    }
                    .summitTapRow()
                }
                .tint(colors.accent)
            }
        }
    }

    /// Beállítások 2. blokk: értesítések + események + utazás + pótlás.
    private var settingsMidSection: some View {
        Group {
            summitIsland(header: "Értesítések", footer: "Helyi értesítés adatfrissítéskor — a KRÉTA nem küld push-t. A Live Activity a Lock Screen + Dynamic Island.", tour: .notifications, tourActive: tourIs(.notifications) || tourIs(.live)) {
                summitRow {
                    Toggle(isOn: $notifyEnabled) {
                        SkinLabel("Értesítések", systemImage: "bell.fill").skinFont(.subheadline, weight: .medium)
                    }
                    .tint(colors.accent)
                    .skinToggleStyle()
                    .onChange(of: notifyEnabled) { _, new in
                        if new { Task { await NotificationManager.shared.requestPermission() } }
                        summitSync.markDirty(.notifyEnabled)
                    }
                }
                summitDivider
                summitRow {
                    LiveActivitySettingsRow()
                }
                .id(AnyHashable(SettingsTour.Anchor.live))
                // A tesztelőeszközök (értesítés-tesztek, szimulált jegy) a
                // Fejlesztői módban élnek — Beállítások alján feloldható.
            }

            summitIsland(header: "Iskolai események", footer: "0. óraként az órarend tetején. A kézi beállításod sosem íródik felül.", tour: .events, tourActive: tourIs(.events)) {
                Button { SummitHaptics.selection(); withAnimation(SummitMotion.snappy) { calendarExpanded.toggle() } } label: {
                    HStack {
                        SkinLabel("Tannaptár", systemImage: "calendar").skinFont(.subheadline, weight: .medium)
                        Spacer()
                        SkinIcon("chevron.down")
                            .skinFont(.caption, weight: .semibold).foregroundStyle(.secondary)
                            .rotationEffect(.degrees(calendarExpanded ? 180 : 0))
                    }
                    .summitTapRow()
                }
                .buttonStyle(.skinPlain)
                .accessibilityValue(calendarExpanded ? "kinyitva" : "zárva")
                if calendarExpanded {
                    summitDivider
                    summitRow { SchoolEventsSection() }
                }
            }

            summitIsland(header: "Utazás mód", footer: "Amíg tart: se értesítés, se Live Activity, a widget üreset mutat. Lejárat után magától kikapcsol.") {
                summitRow {
                    Toggle(isOn: $travelOn) {
                        SkinLabel("Utazás mód", systemImage: "airplane").skinFont(.subheadline, weight: .medium)
                    }
                    .tint(colors.accent)
                    .skinToggleStyle()
                    .onChange(of: travelOn) { _, new in
                        saveTravel()
                        if new, TravelMode.isActive() {
                            // Azonnal csend: a futó activity nem várja meg a következő syncet.
                            Task {
                                #if targetEnvironment(macCatalyst)
                                await SummitLiveActivityManager.shared.endAll()
                                #else
                                await SummitLiveActivityManager.shared.endAll(dismissalPolicy: .immediate)
                                #endif
                            }
                        }
                    }
                }
                if travelOn {
                    summitDivider
                    summitRow {
                        SkinDateRow(title: "Mettől", date: $travelFrom)
                            .skinFont(.subheadline, weight: .medium)
                            .tint(colors.accent)
                            .onChange(of: travelFrom) { _, _ in saveTravel() }
                    }
                    summitDivider
                    summitRow {
                        SkinDateRow(title: "Meddig", date: $travelTo, minDate: travelFrom)
                            .skinFont(.subheadline, weight: .medium)
                            .tint(colors.accent)
                            .onChange(of: travelTo) { _, _ in saveTravel() }
                    }
                }
            }

            summitIsland(header: "Dolgozat-pótlás", footer: "Ha a dolgozat napján hiányzol, a dolgozat a következő ilyen órára kerül, piros háttérrel. Ha arról is hiányzol, továbbmegy. Swipe-pal elvethető.") {
                summitRow {
                    Toggle(isOn: $examRollover) {
                        SkinLabel("Átütemezés hiányzáskor", systemImage: "calendar.badge.exclamationmark").skinFont(.subheadline, weight: .medium)
                    }
                    .tint(colors.accent)
                    .skinToggleStyle()
                    .onChange(of: examRollover) { _, _ in
                        // A store postolja a frissítő értesítést; a kapcsolgatás
                        // külön dirty-jelölést kap (mint a schoolEventsShow),
                        // hogy a blobok újraküldése nélkül menjen fel a syncbe.
                        ExamRollover.setEnabled(examRollover)
                        summitSync.markDirty(.examRollover)
                    }
                }
            }
        }
    }

    /// Beállítások 3. blokk: fiók.
    private var settingsAccountSection: some View {
        Group {
            summitIsland(header: "Fiók", tour: .account, tourActive: tourIs(.account)) {
                Button { SummitHaptics.selection(); withAnimation(SummitMotion.snappy) { accountExpanded.toggle() } } label: {
                    HStack {
                        SkinLabel("Fiók", systemImage: "person.crop.circle").skinFont(.subheadline, weight: .medium)
                        Spacer()
                        Text(session.displayName).skinFont(.caption).foregroundStyle(.secondary).lineLimit(1)
                        SkinIcon("chevron.down")
                            .skinFont(.caption, weight: .semibold).foregroundStyle(.secondary)
                            .rotationEffect(.degrees(accountExpanded ? 180 : 0))
                    }
                    .summitTapRow()
                }
                .buttonStyle(.skinPlain)
                .accessibilityValue(accountExpanded ? "kinyitva" : "zárva")
                if accountExpanded {
                summitDivider
                summitRow {
                    Button("Kijelentkezés", role: .destructive) { session.logout() }
                    .voxelInlineButton()
                }
                if session.selectedUser?.isDemo == true {
                    summitDivider
                    summitRow {
                        SkinLabel("Demo módban vagy — kijelentkezéssel kilépsz", systemImage: "flask.fill").skinFont(.subheadline).foregroundStyle(.secondary)
                    }
                }
                // Iskola-kód felülírás: a tokenből fejlett kód néha nem host
                // (pl. OM-azonosító) — olyankor minden DNS-hibával hal meg.
                // Ide a böngészős e-KRÉTA cím eleje kell: https://EZ.e-kreta.hu
                // Helyi backendes fióknál (demo / tesztfiók) rejtve: az
                // átállítás levenné a fiókot a helyi pipeline-ról, és a
                // hamis tokenekkel a valódi hálózaton csak lejárt-állapot
                // (piros sáv + popup) keletkezne — pont az, amit nem akarunk.
                if session.selectedUser?.isLocalBackend != true {
                    summitDivider
                    summitRow {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Iskola kód").skinFont(.caption, weight: .semibold).foregroundStyle(.secondary)
                            HStack {
                                TextField("pl. klik035454001", text: $draftIss, prompt: skinPrompt("pl. klik035454001"))
                                    .skinFont(.subheadline, design: .monospaced)
                                    .textInputAutocapitalization(.never)
                                    .autocorrectionDisabled()
                                    .summitInput()
                                    .onChange(of: draftIss) { _, _ in instituteMsg = "" }
                                Button("Mentés") {
                                    session.updateInstitute(draftIss)
                                    kreta.instituteCode = session.selectedUser?.instituteCode
                                    kreta.sessionExpired = false
                                    kreta.showExpiredAlert = false
                                    SummitHaptics.selection()
                                    instituteMsg = "Mentve: \(session.selectedUser?.instituteCode ?? draftIss) — húzd le a listákat."
                                }
                                .skinFont(.subheadline, weight: .bold)
                                // Üres kóddal minden KRÉTA-hívás elhalna.
                                .disabled(draftIss.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                                .voxelInlineButton()
                            }
                            if !instituteMsg.isEmpty {
                                Text(instituteMsg).skinFont(.caption2).foregroundStyle(.secondary)
                            }
                            Text("Ha minden üres, ez a kód rossz — utána frissíts lehúzással.")
                                .skinFont(.caption2).foregroundStyle(.tertiary)
                            HStack {
                                Button("Automatikus javítás") {
                                    Task { await repairInstitute() }
                                }
                                .skinFont(.caption, weight: .bold)
                                .disabled(repairRunning)
                                .voxelInlineButton()
                                if repairRunning { SkinProgress().scaleEffect(0.8) }
                                if !repairMsg.isEmpty {
                                    Text(repairMsg).skinFont(.caption2).foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                    summitDivider
                    summitRow {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Iskola neve a térképhez").skinFont(.caption, weight: .semibold).foregroundStyle(.secondary)
                            HStack {
                                TextField("pl. Siófoki SZC Mathiász János Technikum", text: $draftSchoolName, prompt: skinPrompt("pl. Siófoki SZC Mathiász János Technikum"))
                                    .skinFont(.subheadline)
                                    .summitInput()
                                    .onChange(of: draftSchoolName) { _, _ in schoolNameMsg = "" }
                                Button("Mentés") {
                                    session.setSchoolOverride(draftSchoolName)
                                    SummitHaptics.selection()
                                    schoolNameMsg = draftSchoolName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                                        ? "Kézi név törölve — a KRÉTA-beli név él."
                                        : "Mentve."
                                    Task {
                                        await session.refreshSchoolName(kreta: kreta)
                                        analytics.recordEvent(schoolName: session.heartbeatSchoolName, event: "consent", instituteCode: session.selectedUser?.instituteCode)
                                    }
                                }
                                .skinFont(.subheadline, weight: .bold)
                                .voxelInlineButton()
                            }
                            if !schoolNameMsg.isEmpty {
                                Text(schoolNameMsg).skinFont(.caption2).foregroundStyle(.secondary)
                            }
                            Text("Csak ha a Diagnosztika szerint nincs név. Hivatalos, városos név kell.")
                                .skinFont(.caption2).foregroundStyle(.tertiary)
                        }
                    }
                }
                // Meta AI-kulcs: ugyanaz a tár, mint a Watch-tab tetején —
                // a mentés szinkronértesítést postol, így a Summit-sync
                // automatikusan átviszi a többi eszközre.
                summitDivider
                summitRow {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Meta AI-kulcs").skinFont(.caption, weight: .semibold).foregroundStyle(.secondary)
                        HStack {
                            // Csak a user gépelése jelöl szerkesztettnek és törli az
                            // üzenetet — a kódbeli beírás (betöltés, Törlés) nem
                            // (korábban a „Törölve." azonnal el is tűnt).
                            SecureField("Meta API-kulcs", text: Binding(
                                get: { draftMetaAIKey },
                                set: { new in
                                    draftMetaAIKey = new
                                    metaAIKeyEdited = true
                                    metaAIKeyMsg = ""
                                }
                            ), prompt: skinPrompt("Meta API-kulcs"))
                                .skinFont(.subheadline, design: .monospaced)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                                .summitInput()
                            Button("Mentés") {
                                MetaAIKeyStore.save(draftMetaAIKey)
                                metaAIKeyEdited = false
                                metaAIKeyMsg = "Mentve — átmegy a többi eszközödre."
                            }
                            .skinFont(.subheadline, weight: .bold)
                            .disabled(draftMetaAIKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                            .voxelInlineButton()
                        }
                        if MetaAIKeyStore.hasKey {
                            HStack {
                                Text("Megadva — a jegyzetgenerálás működik.")
                                    .skinFont(.caption2).foregroundStyle(.secondary)
                                Spacer()
                                Button("Törlés", role: .destructive) {
                                    MetaAIKeyStore.clear()
                                    draftMetaAIKey = ""
                                    metaAIKeyEdited = false
                                    metaAIKeyMsg = "Törölve."
                                }
                                .skinFont(.caption, weight: .bold)
                                .voxelInlineButton()
                            }
                        }
                        if !metaAIKeyMsg.isEmpty {
                            Text(metaAIKeyMsg).skinFont(.caption2).foregroundStyle(.secondary)
                        }
                        Text("A kulcs a Summit-szinkronnal átmegy a többi eszközödre, az órára sosem kerül át. Kulcs nélkül a közös ingyenes Gemini dolgozik (gyengébb).")
                            .skinFont(.caption2).foregroundStyle(.tertiary)
                    }
                }
                .onAppear { if !metaAIKeyEdited { draftMetaAIKey = MetaAIKeyStore.apiKey } }
                .onReceive(NotificationCenter.default.publisher(for: MetaAIKeyStore.changedNotification)) { _ in
                    if !metaAIKeyEdited { draftMetaAIKey = MetaAIKeyStore.apiKey }
                }
                }
            }
        }
    }

    /// Beállítások 4. blokk: diagnosztika + fejlesztő + adatvédelem + lábléc.
    private var settingsBottomSection: some View {
        Group {
            summitIsland(header: "Diagnosztika", tour: .diagnostics, tourActive: tourIs(.diagnostics)) {
                NavigationLink { DiagnosticsView().voxelBackButton() } label: {
                    HStack {
                        SkinLabel("Diagnosztika", systemImage: "stethoscope")
                            .skinFont(.subheadline, weight: .medium)
                        Spacer()
                        if kreta.sessionExpired {
                            Text("hiba").skinFont(.caption2, weight: .bold).foregroundStyle(.red)
                        } else if !kreta.diagLog.isEmpty {
                            Text("\(kreta.diagLog.count)").skinFont(.caption2, design: .monospaced).foregroundStyle(.tertiary)
                        }
                        SkinIcon("chevron.right")
                            .skinFont(.caption, weight: .semibold).foregroundStyle(.tertiary)
                    }
                    .summitTapRow()
                }
                .tint(colors.accent)
            }

            if devEnabled {
                summitIsland(header: "Fejlesztő") {
                    NavigationLink { DeveloperView().voxelBackButton() } label: {
                        HStack {
                            SkinLabel("Fejlesztő", systemImage: "hammer.fill")
                                .skinFont(.subheadline, weight: .medium)
                            Spacer()
                            if isPreviewOn {
                                Text("idő-eltolás")
                                    .skinFont(.caption2, weight: .bold).foregroundStyle(colors.accent)
                            }
                            SkinIcon("chevron.right")
                                .skinFont(.caption, weight: .semibold).foregroundStyle(.tertiary)
                        }
                        .summitTapRow()
                    }
                    .tint(colors.accent)
                }
            }

            // Adatvédelem — a lista legeslegalján.
            summitIsland(header: "Adatvédelem", footer: "Névtelen statisztika + jelmondattal védett szinkron. Név, jegy, jelszó sosem megy fel.", tour: .sync, tourActive: tourIs(.sync)) {
                summitRow {
                    Toggle(isOn: Binding(
                        get: { analytics.isEnabled },
                        set: { analytics.setEnabled($0) }
                    )) {
                        SkinLabel("Névtelen használati statisztika", systemImage: "chart.bar.fill")
                            .skinFont(.subheadline, weight: .medium)
                    }
                    .tint(colors.accent)
                    .skinToggleStyle()
                }
                summitDivider
                summitRow {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Telepítés-azonosító").skinFont(.caption, weight: .semibold).foregroundStyle(.secondary)
                        Text(analytics.installId).skinFont(.caption2, design: .monospaced).foregroundStyle(.tertiary)
                            .textSelection(.enabled)
                        Text("Törlési kérelemhez ezt küldd el e-mailben.")
                            .skinFont(.caption2).foregroundStyle(.tertiary)
                    }
                }
                summitDivider
                summitRow { summitSyncSection }
            }

            Text("Summit • Gábor Csaba").skinFont(.caption2).foregroundStyle(.tertiary)
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity)
                .contentShape(Rectangle())
                .onTapGesture { registerDevTap() }
        }
    }

    var body: some View {
        ScrollViewReader { proxy in
        ScrollView {
            // Közös glass-konténer: az egy- és többsoros szigetek üvege
            // ugyanabban a mintavételi térben renderelődik, így az átlátszóság
            // (/blur) nem függ a sziget méretétől.
            SummitGlassGroup {
            VStack(spacing: 20) {
            // Típustörlés szekciónként: a négy szekció együttes nézet-típusa
            // a készülék stackjén túl mély a Swift runtime-nak (crash a
            // Beállítások megnyitásakor) — így mindegyik külön oldódik fel.
            AnyView(settingsTopSection)
            AnyView(settingsMidSection)
            AnyView(settingsAccountSection)
            AnyView(settingsBottomSection)
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 24)
            .frame(maxWidth: isPad ? MacSupport.contentWidth(ipad: 800, mac: 920) : .infinity)
            .padding(.horizontal, MacSupport.sidePadding)
            .frame(maxWidth: .infinity)
            }
        }
        .background {
            if theme.isVoxel {
                VoxelBackdrop(scrollOffset: scrollOffset, mountain: true)
            } else if theme.isNeon {
                NeonBackdrop()
            } else {
                SummitBackdrop(scrollOffset: scrollOffset)
            }
        }
        // Görgetés-vezérelt parallax a háttérképre: a ScrollView saját
        // geometriáját olvassuk (nincs köztes PreferenceKey-lánc, ami
        // elakadhat), a kép ≈25%-kal követi a teljes scroll-range-en.
        .onScrollGeometryChange(for: CGFloat.self, of: { $0.contentOffset.y }) { _, newY in
            scrollOffset = -newY
        }
        .navigationTitle("Beállítások")
        .navigationBarTitleDisplayMode(.large)
        .summitToolbarBackground()
        .toolbar {
            SkinToolbarItem(placement: .primaryAction) {
                Button { startTour() } label: {
                    SkinIcon("questionmark.circle")
                }
                .accessibilityLabel("Beállítások túra")
            }
        }
        .task { await loadSubjects() }
        .refreshable {
            await loadSubjects(force: true)
            SummitHaptics.light()
        }
        .onAppear {
            thresholds = GradingLogic.loadThresholds()
            loadTravel()
            if draftIss.isEmpty { draftIss = session.selectedUser?.instituteCode ?? "" }
            if draftSchoolName.isEmpty { draftSchoolName = session.selectedUser?.schoolNameOverride ?? "" }
            if draftNickname.isEmpty, let u = session.selectedUser { draftNickname = NicknameStore.load(for: u) ?? "" }
            // Első megnyitáskor magától indul a túra — utána csak a ? gombról.
            if !tourSeen, tourStep == nil {
                Task {
                    try? await Task.sleep(nanoseconds: 800_000_000)
                    guard !tourSeen else { return }
                    tourStep = 0
                }
            }
        }
        .alert("Fejlesztői mód bekapcsolva", isPresented: $showDevAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("A Beállításokban megjelent a Fejlesztő menü az összes tesztelőeszközzel.")
        }
        .fullScreenCover(
            isPresented: Binding(get: { cropImage != nil }, set: { if !$0 { cropImage = nil } })
        ) { cropSheet }
        .onChange(of: session.selectedId) { _, _ in
            // Fiókváltáskor a becenév-piszkozat is az új fiókhoz igazodik.
            if let u = session.selectedUser { draftNickname = NicknameStore.load(for: u) ?? "" }
            else { draftNickname = "" }
            Task { await loadSubjects(force: true) }
        }
        .onReceive(NotificationCenter.default.publisher(for: NicknameStore.changedNotification)) { _ in
            nicknameTick += 1
        }
        // Téma-változás: 2 mp-es összevont feltöltés, ha a szinkron él.
        // (Pull utáni alkalmazást a suppress-ablak szűri ki.)
        // Másik eszközről jött utazás-állítás: a kapcsoló kövesse.
        .onReceive(NotificationCenter.default.publisher(for: TravelMode.changedNotification)) { _ in loadTravel() }
        .onChange(of: theme.mode) { _, _ in summitSync.markDirty(.theme) }
        .onChange(of: theme.skin) { _, _ in summitSync.markDirty(.skin) }
        .onChange(of: theme.accentHex) { _, _ in summitSync.markDirty(.accentHex) }
        .onChange(of: theme.sizeCategoryKey) { _, _ in summitSync.markDirty(.sizeKey) }
        .onChange(of: tourStep) { _, new in
            guard let n = new, SettingsTour.steps.indices.contains(n) else { return }
            // A lenyíló szigeteknél (Fiók, Iskolai események) a túra
            // szövege a rejtett tartalomról szól — azt ki is nyitjuk.
            switch SettingsTour.steps[n].anchor {
            case .account: withAnimation(SummitMotion.snappy) { accountExpanded = true }
            case .events: withAnimation(SummitMotion.snappy) { calendarExpanded = true }
            default: break
            }
            withAnimation(SummitMotion.gentle) {
                proxy.scrollTo(AnyHashable(SettingsTour.steps[n].anchor), anchor: .center)
            }
        }
        .safeAreaInset(edge: .bottom) {
            SettingsTourCard(step: $tourStep, accent: colors.accent) {
                tourSeen = true
            }
        }
        } // ScrollViewReader
    }

    /// Túra indítása a ? gombról — a `seen` flaget nem bántja.
    private func startTour() {
        tourStep = 0
    }

    // MARK: - Utazás mód

    /// Mentett intervallum betöltése a kapcsolóba (lejárt beállítás magától eltűnik).
    private func loadTravel() {
        let d = UserDefaults.standard
        if d.object(forKey: TravelMode.fromKey) != nil, d.object(forKey: TravelMode.toKey) != nil {
            travelOn = true
            travelFrom = Date(timeIntervalSince1970: d.double(forKey: TravelMode.fromKey))
            travelTo = Date(timeIntervalSince1970: d.double(forKey: TravelMode.toKey))
        } else {
            travelOn = false
        }
    }

    /// Kapcsoló/dátum mentése + szinkron-dirty. Kikapcsolás törli az intervallumot.
    private func saveTravel() {
        if travelOn {
            TravelMode.set(from: travelFrom, to: travelTo)
        } else {
            TravelMode.clear()
        }
        summitSync.markDirty(.travelMode)
    }

    /// Fejlesztői mód feloldása: 10 tap a "Summit • Gábor Csaba" láblécre
    /// (2 mp-es ablakban — lassú pötyögés nem számít). Kikapcsolni a
    /// Fejlesztő képernyő tetején lehet.
    private func registerDevTap() {
        guard !devEnabled else { return }
        devTaps += 1
        devTapReset?.cancel()
        if devTaps >= 10 {
            devTaps = 0
            devEnabled = true
            showDevAlert = true
            return
        }
        devTapReset = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            guard !Task.isCancelled else { return }
            devTaps = 0
        }
    }

    /// Üveg sziget-szekció: fejléc + egybefüggő liquid glass kártya + lábléc —
    /// mint az insetGrouped lista, csak az EGÉSZ sziget egy üveg,
    /// nem soronkénti csíkok. Mögötte átlátszik a SummitBackdrop.
    /// `tour` horgonnyal a Beállítások-túra tud rágörgetni és highlightolni.
    private func summitIsland<Content: View>(header: String? = nil, footer: String? = nil, tour anchor: SettingsTour.Anchor? = nil, tourActive: Bool = false, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            if let header {
                SettingsIslandHeader(text: header)
                    .padding(.horizontal, 4)
            }
            VStack(alignment: .leading, spacing: 0) {
                content()
            }
            .summitGlassRow(cornerRadius: 20)
            // A túra-kiemelés csak az üvegkártyát keretezi — a fejléc/
            // lábléc körbebekerítése lógott a levegőben, furán nézett ki.
            .tourHighlight(active: tourActive, accent: colors.accent)
            if let footer {
                Text(footer).skinFont(.caption2).skinSecondaryOnSky()
                    .padding(.horizontal, 4)
            }
        }
        .id(anchor.map(AnyHashable.init))
    }

    /// Egykoppintásos institut-javítás a beragadt (rövid kódos) userhez:
    /// a token jelöltjeit száraz próbával végigmegy, az első működőt menti.
    private func repairInstitute() async {
        repairRunning = true
        defer { repairRunning = false }
        guard let at = session.selectedUser?.accessToken else { repairMsg = "nincs token"; return }
        var candidates = JWT.allInstituteCandidates(from: at)
        if candidates.isEmpty, let info = await kreta.fetchUserInfo() {
            candidates = JWT.allInstituteCandidates(fromUserInfo: info)
        }
        kreta.diag("javítás jelöltek: \(candidates.joined(separator: ","))")
        for cand in candidates.prefix(8) {
            if await kreta.probeInstitute(cand) != nil {
                session.updateInstitute(cand)
                kreta.instituteCode = cand
                kreta.sessionExpired = false
                kreta.showExpiredAlert = false
                draftIss = cand
                repairMsg = "kész: \(cand) — húzd le a listákat"
                return
            }
        }
        repairMsg = "nincs működő jelölt — írd be kézzel"
    }
    /// Aktuális becenév a kiválasztott fiókhoz (nil = nincs).
    /// A `nicknameTick` a SwiftUI-frissítést hajtja (UserDefaults nem published).
    private var currentNickname: String? {
        _ = nicknameTick
        guard let u = session.selectedUser else { return nil }
        return NicknameStore.load(for: u)
    }

    private func saveNickname() {
        guard let u = session.selectedUser else { return }
        SummitHaptics.selection()
        NicknameStore.save(draftNickname, for: u)
    }

    private func clearNickname() {
        guard let u = session.selectedUser else { return }
        SummitHaptics.selection()
        NicknameStore.clear(for: u)
        draftNickname = ""
    }

    /// Profilkép-koppintás: kép nélkül egyből a fotóválasztó, képpel a
    /// csere/törlés választó.
    private func avatarTapped() {
        if profileStore.hasImage(for: summitProfileKey) {
            showPhotoOptions = true
        } else {
            showPhotoPicker = true
        }
    }

    private func summitRow<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 0) { content() }
            .padding(.horizontal, 16)
            .padding(.vertical, 11)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var summitDivider: some View {
        if theme.isVoxel {
            Rectangle().fill(Color.black.opacity(0.22)).frame(height: VoxelTheme.px)
        } else if theme.isNeon {
            // Vékony, halvány vörös HUD-vonal a sorok között.
            Rectangle().fill(NeonTheme.red.opacity(0.2)).frame(height: 1).padding(.horizontal, 14)
        } else {
            Divider().padding(.leading, 16)
        }
    }

    private func handlePhotoChange(_ item: PhotosPickerItem?) async {
        guard let item else { return }
        // Sikertelen betöltésnél is ürül: különben ugyanazt a képet újra
        // kiválasztva az `onChange` nem sülne el, a választás néma maradna.
        defer { selectedPhoto = nil }
        guard let data = try? await item.loadTransferable(type: Data.self), let ui = UIImage(data: data),
              session.selectedUser?.id != nil else { return }
        // Mentés előtt rendszer-fotós kivágó — a kész képet 512-re méretezzük.
        // Előtte álló tájolásra rajzolva: a kivágó a CGImage nyers pixeleiből
        // vág, ami az elforgatott (pl. álló kamerás) fotónál rossz részletet adott.
        cropImage = ProfileCropView.prepared(ui)
    }

    @ViewBuilder
    private var cropSheet: some View {
        if let img = cropImage {
            ProfileCropView(
                image: img,
                onDone: { out in
                    // Stabil kulcs (JWT-alapú): a másik eszköz és egy új
                    // belépés is ugyanazt a képet találja meg. A mentés
                    // SummitSync-értesítést postol → delta-feltöltés.
                    profileStore.save(image: resize(image: out, maxSize: 512), for: summitProfileKey)
                    cropImage = nil
                },
                onCancel: { cropImage = nil }
            )
        }
    }

    private func resize(image: UIImage, maxSize: CGFloat) -> UIImage {
        let s = max(image.size.width, image.size.height)
        guard s > maxSize else { return image }
        let scale = maxSize / s
        let newSize = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let r = UIGraphicsImageRenderer(size: newSize)
        return r.image { _ in image.draw(in: CGRect(origin: .zero, size: newSize)) }
    }

    private func loadSubjects(force: Bool = false) async {
        // Egy adatsáv: demo usert is a KretaClient szolgálja ki helyből
        // (fetchAllSubjectNames) — a közös cache-be demo módban SOHA nem
        // írunk, különben a demo-tárgyak leakelnek valós módba.
        let isDemo = session.selectedUser?.isDemo == true
        if !force, let cached = UserDefaults.standard.stringArray(forKey: "firka.cachedSubjects.v1"), !cached.isEmpty, !isDemo {
            // still fetch in background, but show cached first
            subjects = cached; isLoadingSubjects = false
        }
        isLoadingSubjects = subjects.isEmpty
        guard let user = session.selectedUser else { isLoadingSubjects = false; return }
        let iss = user.instituteCode.isEmpty ? (JWT.instituteCode(from: user.accessToken) ?? "") : user.instituteCode
        let net = Set(await kreta.fetchAllSubjectNames(iss: iss))
        // Halott hálózatnál (átlag 500/403, órarend 400, 0 jegy) a helyben
        // tudott tárgyak tartják meg a számlálót — lásd TeacherRoundingView.
        var collected = net
        if !isDemo {
            collected.formUnion(UserDefaults.standard.stringArray(forKey: "firka.cachedSubjects.v1") ?? [])
        }
        collected.formUnion(GradingLogic.loadThresholds().keys)
        collected.formUnion(ExemptedStore.load())
        // filter out empty / unknown
        let filtered = collected.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty && $0 != "Ismeretlen" }.sorted()
        if !filtered.isEmpty || subjects.isEmpty {
            subjects = filtered
        }
        isLoadingSubjects = false
        if !filtered.isEmpty, !isDemo { UserDefaults.standard.set(filtered, forKey: "firka.cachedSubjects.v1") }
    }

    // MARK: - SummitSync (Blaze-mentes beállítás-szinkron, Spark)

    /// Téma + kiemelőszín + szövegméret + profilkép az összes bejelentkezett
    /// eszköz között. Kulcs: SHA256(stabil KRÉTA-azonosító + jelmondat) —
    /// az azonosító és a jelmondat sosem hagyja el a telefont.
    /// Delta-elv: egy szerkesztés csak a saját mezőjét tölti fel, a
    /// "Frissítés most" pedig csak lehúz (a helyi állapotot nem tolja fel).
    private var summitSyncSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Toggle(isOn: Binding(
                get: { summitSync.isEnabled },
                set: { v in
                    if v { Task { await summitSyncEnable() } }
                    else { summitSync.isEnabled = false; summitSync.status = "kikapcsolva" }
                }
            )) {
                SkinLabel("Beállítások szinkronizálása", systemImage: "arrow.triangle.2.circlepath")
                    .skinFont(.subheadline, weight: .medium)
            }
            .tint(colors.accent)
            .skinToggleStyle()
            .disabled(summitSyncBusy || session.selectedUser?.isDemo == true)
            Text("Egy jelmondat köti össze az eszközeidet. A jelmondat csak ezen a telefonon van.")
                .skinFont(.caption2).foregroundStyle(.tertiary)
            if SummitSync.isPassphraseFallbackActive {
                Text("Fejlesztői Mac-build: a kulcstároló nem elérhető, a jelmondat helyben tárolódik.")
                    .skinFont(.caption2).foregroundStyle(.tertiary)
            }
            if session.selectedUser?.isDemo == true {
                Text("Demo módban nem elérhető.")
                    .skinFont(.caption2).foregroundStyle(.secondary)
            } else if !summitSync.isEnabled {
                SecureField("Szinkron-jelmondat (min. 8 karakter)", text: $summitSyncPassphrase, prompt: skinPrompt("Szinkron-jelmondat (min. 8 karakter)"))
                    .skinFont(.subheadline)
                    .textContentType(.newPassword)
                    .summitInput()
                    .disabled(summitSyncBusy)
                    .onChange(of: summitSyncPassphrase) { _, _ in syncEnableFailed = false }
            }
            HStack(spacing: 12) {
                if summitSync.isEnabled {
                    Button("Frissítés most") { Task { await summitSyncPullNow() } }
                        .skinFont(.caption, weight: .bold)
                        .disabled(summitSyncBusy)
                        .voxelInlineButton()
                    Button("Szinkron törlése", role: .destructive) { confirmSyncDelete = true }
                        .skinFont(.caption, weight: .bold)
                        .disabled(summitSyncBusy)
                        .voxelInlineButton()
                        .confirmationDialog("Törlöd a szinkront?", isPresented: $confirmSyncDelete, titleVisibility: .visible) {
                            Button("Szinkron törlése", role: .destructive) { Task { await summitSyncDelete() } }
                            Button("Mégse", role: .cancel) {}
                        } message: {
                            Text("A szerveren tárolt titkosított beállítások törlődnek, és ezen az eszközön kikapcsol a szinkron. A helyi beállításaid megmaradnak.")
                        }
                }
                if summitSyncBusy { SkinProgress().scaleEffect(0.8) }
                if !summitSync.isEnabled {
                    Text(summitSyncStatusText).skinFont(.caption2).foregroundStyle(.secondary)
                } else {
                    Text(summitSync.status).skinFont(.caption2).foregroundStyle(.secondary)
                    if summitSync.realtimeActive {
                        Text("• élő").skinFont(.caption2, weight: .bold).foregroundStyle(colors.accent)
                    }
                }
            }
        }
        .onAppear {
            if summitSyncPassphrase.isEmpty, let saved = SummitSync.loadPassphrase() {
                summitSyncPassphrase = saved
            }
            // Csendes frissítés (listener vagy egyszeri pull).
            if let at = summitSyncToken {
                summitSync.refresh(accessToken: at, theme: theme,
                                   profile: profileStore, completed: completed,
                                   userId: session.selectedUser?.id)
            }
        }
    }

    private var summitSyncStatusText: String {
        if syncEnableFailed { return summitSync.status }
        if SummitSync.loadPassphrase() != nil { return "jelszó mentve — kapcsolhatod" }
        return summitSync.status
    }

    private var summitSyncToken: String? { session.selectedUser?.accessToken }

    /// Eszközfüggetlen profilkép-kulcs (lásd `ProfileImageStore.key`).
    private var summitProfileKey: String {
        ProfileImageStore.key(userId: session.selectedUser?.id,
                              accessToken: session.selectedUser?.accessToken)
    }

    /// "Frissítés most": LEHÚZÁS a szerverről (a másik eszköz újdonságai).
    /// Direkt nem tölt fel — egy friss eszköz alapértelmezései így nem
    /// írhatják felül a többi eszköz beállításait.
    private func summitSyncPullNow() async {
        guard let at = summitSyncToken else { return }
        summitSync.configure(accessToken: at, theme: theme, profile: profileStore,
                             completed: completed, userId: session.selectedUser?.id)
        summitSyncBusy = true
        defer { summitSyncBusy = false }
        switch await summitSync.pullNow() {
        case "applied": summitSync.status = "frissítve"
        case "fresh": summitSync.status = "nincs újdonság"
        case "nodoc": summitSync.status = "nincs szerver-oldali adat"
        default: summitSync.status = "frissítés hiba"
        }
    }

    private func summitSyncEnable() async {
        // Minden kimenetnél: ha nem kapcsolt be, a hiba-státusz látsszon.
        defer { syncEnableFailed = !summitSync.isEnabled }
        guard let at = summitSyncToken else { summitSync.status = "nincs munkamenet"; return }
        guard summitSyncPassphrase.count >= SummitSync.minPassphraseLength else {
            summitSync.status = "min. 8 karakteres jelmondat kell"
            return
        }
        guard SummitSync.canSync(accessToken: at, passphrase: summitSyncPassphrase) else {
            summitSync.status = "nem olvasható a fiókazonosító"
            return
        }
        SummitSync.savePassphrase(summitSyncPassphrase)
        summitSync.configure(accessToken: at, theme: theme, profile: profileStore,
                             completed: completed, userId: session.selectedUser?.id)
        summitSyncBusy = true
        defer { summitSyncBusy = false }
        // Ha van szerver-oldali állapot, az nyer (másik eszköz már szinkronizál);
        // ha nincs, az itteni beállítások mennek fel (minden mező piszkos).
        let r = await summitSync.pullNow()
        if r == "applied" || r == "fresh" {
            // A szerver nyert — a függő helyi jelölések mehetnek.
            summitSync.discardPendingEdits()
            summitSync.isEnabled = true
        } else if r == "nodoc" {
            summitSync.markAllDirty()
            // A debounce-ra nem várunk: ez tudatos, teljes feltöltés.
            summitSyncBusy = false
            let ok = await summitSync.pushNow()
            summitSyncBusy = true
            if ok { summitSync.isEnabled = true }
        }
        if summitSync.isEnabled {
            summitSync.startListener()
        } else if r != "nodoc" {
            // pullNow "error"-ral tért vissza (kulcs- vagy hálózathiba).
            // Ez korábban néma ág volt — a kapcsoló üzenet nélkül ugrott
            // vissza. ("nodoc" esetén a pushNow már állított státuszt.)
            summitSync.status = SummitSync.loadPassphrase() == nil ? "nincs kulcs" : "hálózati hiba"
        }
    }

    private func summitSyncDelete() async {
        guard let at = summitSyncToken else { return }
        summitSyncBusy = true
        defer { summitSyncBusy = false }
        _ = await summitSync.deleteRemote(accessToken: at)
    }
}

/// Közös Liquid Glass konténer a beállítások szigetei köré (iOS 26+):
/// a rendszer ilyenkor egyben rendereli a szigetek üvegét, így az egysoros
/// és a többsoros sziget átlátszósága/blurje nem válik szét. Régebbi
/// rendszeren sima átengedő csoport.
private struct SummitGlassGroup<Content: View>: View {
    var content: Content
    init(@ViewBuilder content: () -> Content) { self.content = content() }
    var body: some View {
        if VoxelTheme.isActive || NeonTheme.isActive {
            content
        } else if #available(iOS 26.0, *) {
            GlassEffectContainer { content }
        } else {
            content
        }
    }
}

// MARK: - Live Activity toggle — csak a kapcsoló, státusz nélkül
private struct LiveActivitySettingsRow: View {
    @EnvironmentObject var theme: ThemeStore
    @EnvironmentObject var summitSync: SummitSync
    @Environment(\.colorScheme) var scheme
    @StateObject private var manager = SummitLiveActivityManager.shared
    @AppStorage("liveActivity.enabled") private var enabled: Bool = true
    @State private var showSystemAlert = false

    var body: some View {
        Group {
            #if targetEnvironment(macCatalyst)
            SkinLabel("Live Activity (Mac-en nem elérhető)", systemImage: "clock.badge.checkmark")
                .skinFont(.subheadline, weight: .medium)
                .foregroundStyle(.secondary)
                .padding(.vertical, 2)
            #else
            Toggle(isOn: Binding(
                get: { enabled },
                set: { new in
                    enabled = new
                    manager.setAppEnabled(new)
                    if new { Task { await tryStartPreview() } }
                    manager.refreshSystemState()
                    if new && !manager.isSystemEnabled { showSystemAlert = true }
                    summitSync.markDirty(.liveActivity)
                }
            )) {
                SkinLabel("Live Activity", systemImage: "clock.badge.checkmark")
                    .skinFont(.subheadline, weight: .medium)
            }
            .tint(theme.colors(for: scheme).accent)
            .skinToggleStyle()
            .padding(.vertical, 2)
            #endif
        }
        .onAppear { manager.refreshSystemState() }
        .alert("Live Activities tiltva", isPresented: $showSystemAlert) {
            Button("Beállítások") { manager.openSystemSettings() }
            Button("OK", role: .cancel) {}
        } message: {
            Text("iOS Beállítások → Summit → Live Activities kapcsolót kapcsold BE, különben nem jelenik meg a Lock Screen-en / Dynamic Islanden.")
        }
    }

    private func tryStartPreview() async {
        // Ne itt indítsunk valódi órát — csak jogosultság próba (üres nem indít)
        // A valódi indítás a HomeView-ban történik, amikor van aktuális óra.
        manager.refreshSystemState()
    }
}

private extension View {
    /// Koppintható sziget-sor (gomb / link címkéje): a `summitRow` margója a
    /// címkén BELÜL van, és a teljes téglalap találati felület — így a sor
    /// közepe (Spacer) és széle is reagál, nem csak a felirat pixelei.
    func summitTapRow() -> some View {
        self
            .padding(.horizontal, 16)
            .padding(.vertical, 11)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
    }
}

/// Sziget-fejléc a Beállításokban — egy típus, a skin a belsejében dől el
/// (a sok sziget miatt itt nem mélyülhet a nézet-típus, lásd dcfe1eb).
/// Neonban `NeonSectionHeader` egy stabil, a címből képzett kóddal.
private struct SettingsIslandHeader: View {
    var text: String

    var body: some View {
        if VoxelTheme.isActive {
            Text(text).voxelHeader(size: 12).skinSecondaryOnSky()
        } else if NeonTheme.isActive {
            NeonSectionHeader(text, code: Self.code(for: text))
        } else {
            Text(text).voxelSectionHeader()
        }
    }

    /// Determinisztikus „CFG_xx" kód a címből (a `hashValue` futásonként
    /// változna, ezért a Unicode-skalárok összege).
    static func code(for text: String) -> String {
        let sum = text.unicodeScalars.reduce(0) { $0 &+ Int($1.value) }
        return String(format: "CFG_%02X", sum % 256)
    }
}

/// Felület-választó: három előnézeti csempe, mindegyik a SAJÁT skinje
/// stílusában (Summit: kék üveg-ég, lekerekítve; Voxel: fű + föld,
/// éles pixel-sarok, Monocraft; Neon: fekete, levágott sarok, sárga
/// Rajdhani). A kijelölt csempe az aktív skin kiemelőszínű keretét kapja
/// pipával — így a választó mindhárom aktív skinben egyformán működik.
/// Neonra váltáskor a gyökér lejátssza a belépő átmenetet.
private struct SkinChoiceTiles: View {
    @Binding var selection: VisualSkin
    var accent: Color

    var body: some View {
        HStack(spacing: 10) {
            ForEach(VisualSkin.allCases) { skin in
                let on = skin == selection
                Button {
                    guard skin != selection else { return }
                    VoxelSound.play(.click)
                    SummitHaptics.selection()
                    selection = skin
                    if skin == .neon {
                        NotificationCenter.default.post(name: NeonTheme.bootRequest, object: nil)
                    }
                } label: {
                    tile(skin)
                        .frame(maxWidth: .infinity)
                        .frame(height: 74)
                        .clipShape(Self.shape(skin))
                        .overlay(Self.shape(skin).stroke(on ? accent : Color.primary.opacity(0.18), lineWidth: on ? 2.5 : 1))
                        .overlay(alignment: .topTrailing) {
                            if on {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 10, weight: .heavy))
                                    .foregroundStyle(Color.black)
                                    .frame(width: 18, height: 18)
                                    .background(accent, in: Self.shape(skin))
                                    .padding(5)
                            }
                        }
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Felület: \(skin.title)")
                .accessibilityAddTraits(on ? [.isSelected, .isButton] : .isButton)
            }
        }
    }

    private static func shape(_ skin: VisualSkin) -> AnyShape {
        switch skin {
        case .summit: return AnyShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        case .voxel: return AnyShape(Rectangle())
        case .neon: return AnyShape(NeonChamferShape(cut: 12, corners: [.topLeft, .bottomRight]))
        }
    }

    /// Kép-alapú csempe: a skin neve a képbe van renderelve
    /// (`img_tile_*` assetek, mindegyik a saját skinje tipográfiájával),
    /// nem SwiftUI `Text` — így minden aktív skinben azonosan jelenik meg.
    private func tile(_ skin: VisualSkin) -> some View {
        Image(skin.tileAsset)
            .resizable()
            .scaledToFill()
    }
}
