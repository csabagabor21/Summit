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
    @AppStorage("exams.rolloverOnAbsence") private var examRollover = true
    @AppStorage("developer.enabled") private var devEnabled = false
    @AppStorage("home.demoPreviewActive") private var isPreviewOn = false
    @State private var devTaps = 0
    @State private var devTapReset: Task<Void, Never>?
    @State private var showDevAlert = false
    @State private var draftIss = ""
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
            Text("Kiemelés színe").font(.subheadline.weight(.medium))
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
        Picker("Szövegméret", selection: Binding(get: { theme.sizeCategoryKey }, set: { theme.sizeCategoryKey = $0 })) {
            ForEach(ThemeStore.sizeSteps, id: \.key) { step in
                Text(step.title).tag(step.key)
            }
        }
        .pickerStyle(.navigationLink)
        .padding(.vertical, 4)
    }

    var body: some View {
        ScrollViewReader { proxy in
        ScrollView {
            // Közös glass-konténer: az egy- és többsoros szigetek üvege
            // ugyanabban a mintavételi térben renderelődik, így az átlátszóság
            // (/blur) nem függ a sziget méretétől.
            SummitGlassGroup {
            VStack(spacing: 20) {
            // Profil-sziget (fejléc nélkül, mint eddig)
            HStack(spacing: 12) {
                ZStack(alignment: .bottomTrailing) {
                    ProfileImageView(name: session.selectedUser?.name ?? "Diák", userId: summitProfileKey, size: 56).frame(width: 56, height: 56)
                    Circle().fill(colors.accent).frame(width: 22, height: 22)
                        .overlay(Image(systemName: "camera.fill").font(.system(size: 10, weight: .bold)).foregroundStyle(.white))
                        .overlay(Circle().stroke(.white, lineWidth: 1.5))
                        .offset(x: 2, y: 2)
                }
                .onTapGesture { showPhotoOptions = true }
                VStack(alignment: .leading, spacing: 2) {
                    Text(session.selectedUser?.name ?? "Diák").font(.headline)
                    Text(session.selectedUser?.schoolName ?? "").font(.caption).foregroundStyle(.secondary)
                    Text("e-KRÉTA • \(session.selectedUser?.instituteCode ?? "-")").font(.caption2).foregroundStyle(.tertiary)
                }
                Spacer()
                PhotosPicker(selection: $selectedPhoto, matching: .images, photoLibrary: .shared()) {
                    Text("Módosítás").font(.caption.weight(.semibold))
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
            .confirmationDialog("Profilkép", isPresented: $showPhotoOptions, titleVisibility: .visible) {
                // PhotosPicker is already in row; dialog for remove
                // (a törlés SummitSync-értesítést postol → a `photo` mező
                // delta-feltöltése automatikus, kézi push nem kell)
                if profileStore.hasImage(for: summitProfileKey) {
                    Button("Kép törlése", role: .destructive) {
                        profileStore.remove(for: summitProfileKey)
                    }
                }
                Button("Mégse", role: .cancel) {}
                } message: { Text("Új kép a Módosítással, vagy töröld a jelenlegit.") }

            // Havi Wrapped-archívum: a banner csak elsejéig él, itt minden
            // jegyes hónap visszanézhető (a jegyek gyorstárból jönnek).
            summitIsland(header: "Havi összefoglalók") {
                summitRow {
                    NavigationLink {
                        MonthlyArchiveView()
                    } label: {
                        HStack {
                            Label("Havi összefoglalók", systemImage: "sparkles").font(.subheadline.weight(.medium))
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.caption.weight(.semibold)).foregroundStyle(.tertiary)
                        }
                    }
                    .tint(colors.accent)
                }
            }

            summitIsland(header: "Megjelenés", tour: .appearance, tourActive: tourIs(.appearance)) {
                summitRow {
                    Picker("Téma", selection: Binding(get: { theme.mode }, set: { theme.mode = $0 })) {
                        ForEach(AppThemeMode.allCases) { m in
                            Label(m.title, systemImage: m.icon).tag(m)
                        }
                    }
                    .pickerStyle(.segmented)
                }
                summitDivider
                // Accent —简单 színválasztó
                summitRow {
                    accentColorContent
                        .padding(.vertical, 4)
                }
                summitDivider
                // Szövegméret — Macen (iPad-app Macen) alapból nagyobb
                summitRow {
                    textSizeContent
                }
            }

            summitIsland(header: "Tanári kerekítés", footer: "Tantárgyanként külön állítható.", tour: .rounding, tourActive: tourIs(.rounding)) {
                summitRow {
                    NavigationLink { TeacherRoundingView() } label: {
                        HStack {
                            Label("Tanári kerekítés", systemImage: "slider.horizontal.below.rounded")
                                .font(.subheadline.weight(.medium))
                            Spacer()
                            if isLoadingSubjects {
                                ProgressView().scaleEffect(0.85)
                            } else if subjects.isEmpty {
                                Text("—").foregroundStyle(.tertiary).font(.caption)
                            } else {
                                Text("\(subjects.count) tárgy").font(.caption.weight(.medium)).foregroundStyle(.secondary)
                            }
                        }
                    }
                    .tint(colors.accent)
                }
            }

            summitIsland(header: "Értesítések", footer: "Helyi értesítés adatfrissítéskor — a KRÉTA nem küld push-t. A Live Activity a Lock Screen + Dynamic Island.", tour: .notifications, tourActive: tourIs(.notifications) || tourIs(.live)) {
                summitRow {
                    Toggle(isOn: $notifyEnabled) {
                        Label("Értesítések", systemImage: "bell.fill").font(.subheadline.weight(.medium))
                    }
                    .tint(colors.accent)
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
                summitRow {
                    Button { SummitHaptics.selection(); withAnimation(SummitMotion.snappy) { calendarExpanded.toggle() } } label: {
                        HStack {
                            Label("Tannaptár", systemImage: "calendar").font(.subheadline.weight(.medium))
                            Spacer()
                            Image(systemName: "chevron.down")
                                .font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                                .rotationEffect(.degrees(calendarExpanded ? 180 : 0))
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityValue(calendarExpanded ? "kinyitva" : "zárva")
                }
                if calendarExpanded {
                    summitDivider
                    summitRow { SchoolEventsSection() }
                }
            }

            summitIsland(header: "Utazás mód", footer: "Amíg tart: se értesítés, se Live Activity, a widget üreset mutat. Lejárat után magától kikapcsol.") {
                summitRow {
                    Toggle(isOn: $travelOn) {
                        Label("Utazás mód", systemImage: "airplane").font(.subheadline.weight(.medium))
                    }
                    .tint(colors.accent)
                    .onChange(of: travelOn) { _, new in
                        saveTravel()
                        if new, TravelMode.isActive() {
                            // Azonnal csend: a futó activity nem várja meg a következő syncet.
                            Task { await SummitLiveActivityManager.shared.endAll(dismissalPolicy: .immediate) }
                        }
                    }
                }
                if travelOn {
                    summitDivider
                    summitRow {
                        DatePicker("Mettől", selection: $travelFrom, displayedComponents: .date)
                            .font(.subheadline.weight(.medium))
                            .tint(colors.accent)
                            .onChange(of: travelFrom) { _, _ in saveTravel() }
                    }
                    summitDivider
                    summitRow {
                        DatePicker("Meddig", selection: $travelTo, in: travelFrom..., displayedComponents: .date)
                            .font(.subheadline.weight(.medium))
                            .tint(colors.accent)
                            .onChange(of: travelTo) { _, _ in saveTravel() }
                    }
                }
            }

            summitIsland(header: "Dolgozat-pótlás", footer: "Ha a dolgozat napján hiányzol, a dolgozat a következő ilyen órára kerül, piros háttérrel. Ha arról is hiányzol, továbbmegy. Swipe-pal elvethető.") {
                summitRow {
                    Toggle(isOn: $examRollover) {
                        Label("Átütemezés hiányzáskor", systemImage: "calendar.badge.exclamationmark").font(.subheadline.weight(.medium))
                    }
                    .tint(colors.accent)
                    .onChange(of: examRollover) { _, _ in
                        // A store postolja a frissítő értesítést; a kapcsolgatás
                        // külön dirty-jelölést kap (mint a schoolEventsShow),
                        // hogy a blobok újraküldése nélkül menjen fel a syncbe.
                        ExamRollover.setEnabled(examRollover)
                        summitSync.markDirty(.examRollover)
                    }
                }
            }

            summitIsland(header: "Fiók", tour: .account, tourActive: tourIs(.account)) {
                summitRow {
                    Button { SummitHaptics.selection(); withAnimation(SummitMotion.snappy) { accountExpanded.toggle() } } label: {
                        HStack {
                            Label("Fiók", systemImage: "person.crop.circle").font(.subheadline.weight(.medium))
                            Spacer()
                            Text(session.selectedUser?.name ?? "Diák").font(.caption).foregroundStyle(.secondary).lineLimit(1)
                            Image(systemName: "chevron.down")
                                .font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                                .rotationEffect(.degrees(accountExpanded ? 180 : 0))
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityValue(accountExpanded ? "kinyitva" : "zárva")
                }
                if accountExpanded {
                summitDivider
                summitRow {
                    Button("Kijelentkezés", role: .destructive) { session.logout() }
                }
                if session.selectedUser?.isDemo == true {
                    summitDivider
                    summitRow {
                        Label("Demo módban vagy — kijelentkezéssel kilépsz", systemImage: "flask.fill").font(.subheadline).foregroundStyle(.secondary)
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
                            Text("Iskola kód").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                            HStack {
                                TextField("pl. klik035454001", text: $draftIss)
                                    .font(.subheadline.monospaced())
                                    .textInputAutocapitalization(.never)
                                    .autocorrectionDisabled()
                                    .summitInput()
                                Button("Mentés") {
                                    session.updateInstitute(draftIss)
                                    kreta.instituteCode = session.selectedUser?.instituteCode
                                    kreta.sessionExpired = false
                                    kreta.showExpiredAlert = false
                                }
                                .font(.subheadline.weight(.bold))
                            }
                            Text("Ha minden üres, ez a kód rossz — utána frissíts lehúzással.")
                                .font(.caption2).foregroundStyle(.tertiary)
                            HStack {
                                Button("Automatikus javítás") {
                                    Task { await repairInstitute() }
                                }
                                .font(.caption.weight(.bold))
                                .disabled(repairRunning)
                                if repairRunning { ProgressView().scaleEffect(0.8) }
                                if !repairMsg.isEmpty {
                                    Text(repairMsg).font(.caption2).foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                    summitDivider
                    summitRow {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Iskola neve a térképhez").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                            HStack {
                                TextField("pl. Siófoki SZC Mathiász János Technikum", text: $draftSchoolName)
                                    .font(.subheadline)
                                    .summitInput()
                                Button("Mentés") {
                                    session.setSchoolOverride(draftSchoolName)
                                    Task {
                                        await session.refreshSchoolName(kreta: kreta)
                                        analytics.recordEvent(schoolName: session.heartbeatSchoolName, event: "consent", instituteCode: session.selectedUser?.instituteCode)
                                    }
                                }
                                .font(.subheadline.weight(.bold))
                            }
                            Text("Csak ha a Diagnosztika szerint nincs név. Hivatalos, városos név kell.")
                                .font(.caption2).foregroundStyle(.tertiary)
                        }
                    }
                }
                // Meta AI-kulcs: ugyanaz a tár, mint a Watch-tab tetején —
                // a mentés szinkronértesítést postol, így a Summit-sync
                // automatikusan átviszi a többi eszközre.
                summitDivider
                summitRow {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Meta AI-kulcs").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                        HStack {
                            SecureField("Meta API-kulcs", text: $draftMetaAIKey)
                                .font(.subheadline.monospaced())
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                                .summitInput()
                                .onChange(of: draftMetaAIKey) { _, _ in
                                    metaAIKeyEdited = true
                                    metaAIKeyMsg = ""
                                }
                            Button("Mentés") {
                                MetaAIKeyStore.save(draftMetaAIKey)
                                metaAIKeyEdited = false
                                metaAIKeyMsg = "Mentve — átmegy a többi eszközödre."
                            }
                            .font(.subheadline.weight(.bold))
                            .disabled(draftMetaAIKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        }
                        if MetaAIKeyStore.hasKey {
                            HStack {
                                Text("Megadva — a jegyzetgenerálás működik.")
                                    .font(.caption2).foregroundStyle(.secondary)
                                Spacer()
                                Button("Törlés", role: .destructive) {
                                    MetaAIKeyStore.clear()
                                    draftMetaAIKey = ""
                                    metaAIKeyEdited = false
                                    metaAIKeyMsg = "Törölve."
                                }
                                .font(.caption.weight(.bold))
                            }
                        }
                        if !metaAIKeyMsg.isEmpty {
                            Text(metaAIKeyMsg).font(.caption2).foregroundStyle(.secondary)
                        }
                        Text("A kulcs a Summit-szinkronnal átmegy a többi eszközödre, az órára sosem kerül át. Kulcs nélkül a közös ingyenes Gemini dolgozik (gyengébb).")
                            .font(.caption2).foregroundStyle(.tertiary)
                    }
                }
                .onAppear { if !metaAIKeyEdited { draftMetaAIKey = MetaAIKeyStore.apiKey } }
                .onReceive(NotificationCenter.default.publisher(for: MetaAIKeyStore.changedNotification)) { _ in
                    if !metaAIKeyEdited { draftMetaAIKey = MetaAIKeyStore.apiKey }
                }
                }
            }

            summitIsland(header: "Diagnosztika", tour: .diagnostics, tourActive: tourIs(.diagnostics)) {
                summitRow {
                    NavigationLink { DiagnosticsView() } label: {
                        HStack {
                            Label("Diagnosztika", systemImage: "stethoscope")
                                .font(.subheadline.weight(.medium))
                            Spacer()
                            if kreta.sessionExpired {
                                Text("hiba").font(.caption2.weight(.bold)).foregroundStyle(.red)
                            } else if !kreta.diagLog.isEmpty {
                                Text("\(kreta.diagLog.count)").font(.caption2.monospaced()).foregroundStyle(.tertiary)
                            }
                        }
                    }
                }
            }

            if devEnabled {
                summitIsland(header: "Fejlesztő") {
                    summitRow {
                        NavigationLink { DeveloperView() } label: {
                            HStack {
                                Label("Fejlesztő", systemImage: "hammer.fill")
                                    .font(.subheadline.weight(.medium))
                                Spacer()
                                if isPreviewOn {
                                    Text("idő-eltolás")
                                        .font(.caption2.weight(.bold)).foregroundStyle(colors.accent)
                                }
                            }
                        }
                    }
                }
            }

            // Adatvédelem — a lista legeslegalján.
            summitIsland(header: "Adatvédelem", footer: "Névtelen statisztika + jelmondattal védett szinkron. Név, jegy, jelszó sosem megy fel.", tour: .sync, tourActive: tourIs(.sync)) {
                summitRow {
                    Toggle(isOn: Binding(
                        get: { analytics.isEnabled },
                        set: { analytics.setEnabled($0) }
                    )) {
                        Label("Névtelen használati statisztika", systemImage: "chart.bar.fill")
                            .font(.subheadline.weight(.medium))
                    }
                    .tint(colors.accent)
                }
                summitDivider
                summitRow {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Telepítés-azonosító").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                        Text(analytics.installId).font(.caption2.monospaced()).foregroundStyle(.tertiary)
                            .textSelection(.enabled)
                        Text("Törlési kérelemhez ezt küldd el e-mailben.")
                            .font(.caption2).foregroundStyle(.tertiary)
                    }
                }
                summitDivider
                summitRow { summitSyncSection }
            }

            Text("Summit • Gábor Csaba").font(.caption2).foregroundStyle(.tertiary).frame(maxWidth: .infinity)
                .onTapGesture { registerDevTap() }
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 24)
            .frame(maxWidth: isPad ? MacSupport.contentWidth(ipad: 800, mac: 920) : .infinity)
            .padding(.horizontal, MacSupport.sidePadding)
            .frame(maxWidth: .infinity)
            }
        }
        .background { SummitBackdrop(scrollOffset: scrollOffset) }
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
            ToolbarItem(placement: .primaryAction) {
                Button { startTour() } label: {
                    Image(systemName: "questionmark.circle")
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
        .onChange(of: session.selectedId) { _, _ in Task { await loadSubjects(force: true) } }
        // Téma-változás: 2 mp-es összevont feltöltés, ha a szinkron él.
        // (Pull utáni alkalmazást a suppress-ablak szűri ki.)
        // Másik eszközről jött utazás-állítás: a kapcsoló kövesse.
        .onReceive(NotificationCenter.default.publisher(for: TravelMode.changedNotification)) { _ in loadTravel() }
        .onChange(of: theme.mode) { _, _ in summitSync.markDirty(.theme) }
        .onChange(of: theme.accentHex) { _, _ in summitSync.markDirty(.accentHex) }
        .onChange(of: theme.sizeCategoryKey) { _, _ in summitSync.markDirty(.sizeKey) }
        .onChange(of: tourStep) { _, new in
            guard let n = new, SettingsTour.steps.indices.contains(n) else { return }
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
                Text(header).font(.caption.weight(.semibold)).foregroundStyle(.secondary).textCase(.uppercase)
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
                Text(footer).font(.caption2).foregroundStyle(.secondary)
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
    private func summitRow<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 0) { content() }
            .padding(.horizontal, 16)
            .padding(.vertical, 11)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var summitDivider: some View {
        Divider().padding(.leading, 16)
    }

    private func handlePhotoChange(_ item: PhotosPickerItem?) async {
        guard let item, let data = try? await item.loadTransferable(type: Data.self), let ui = UIImage(data: data),
              session.selectedUser?.id != nil else { return }
        // Mentés előtt rendszer-fotós kivágó — a kész képet 512-re méretezzük
        cropImage = ui
        selectedPhoto = nil
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
                Label("Beállítások szinkronizálása", systemImage: "arrow.triangle.2.circlepath")
                    .font(.subheadline.weight(.medium))
            }
            .tint(colors.accent)
            .disabled(summitSyncBusy || session.selectedUser?.isDemo == true)
            Text("Egy jelmondat köti össze az eszközeidet. A jelmondat csak ezen a telefonon van.")
                .font(.caption2).foregroundStyle(.tertiary)
            if SummitSync.isPassphraseFallbackActive {
                Text("Fejlesztői Mac-build: a kulcstároló nem elérhető, a jelmondat helyben tárolódik.")
                    .font(.caption2).foregroundStyle(.tertiary)
            }
            if session.selectedUser?.isDemo == true {
                Text("Demo módban nem elérhető.")
                    .font(.caption2).foregroundStyle(.secondary)
            } else if !summitSync.isEnabled {
                SecureField("Szinkron-jelmondat (min. 8 karakter)", text: $summitSyncPassphrase)
                    .font(.subheadline)
                    .textContentType(.newPassword)
                    .summitInput()
                    .disabled(summitSyncBusy)
            }
            HStack(spacing: 12) {
                if summitSync.isEnabled {
                    Button("Frissítés most") { Task { await summitSyncPullNow() } }
                        .font(.caption.weight(.bold))
                        .disabled(summitSyncBusy)
                    Button("Szinkron törlése", role: .destructive) { Task { await summitSyncDelete() } }
                        .font(.caption.weight(.bold))
                        .disabled(summitSyncBusy)
                }
                if summitSyncBusy { ProgressView().scaleEffect(0.8) }
                if !summitSync.isEnabled {
                    Text(summitSyncStatusText).font(.caption2).foregroundStyle(.secondary)
                } else {
                    Text(summitSync.status).font(.caption2).foregroundStyle(.secondary)
                    if summitSync.realtimeActive {
                        Text("• élő").font(.caption2.weight(.bold)).foregroundStyle(colors.accent)
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
        guard let at = summitSyncToken else { summitSync.status = "nincs munkamenet"; return }
        guard summitSyncPassphrase.count >= SummitSync.minPassphraseLength else {
            summitSync.status = "min. 8 karakteres jelmondat kell"
            return
        }
        guard SummitSync.syncId(accessToken: at, passphrase: summitSyncPassphrase) != nil else {
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
        if #available(iOS 26.0, *) {
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
            Label("Live Activity (Mac-en nem elérhető)", systemImage: "clock.badge.checkmark")
                .font(.subheadline.weight(.medium))
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
                Label("Live Activity", systemImage: "clock.badge.checkmark")
                    .font(.subheadline.weight(.medium))
            }
            .tint(theme.colors(for: scheme).accent)
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
