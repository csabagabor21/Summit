import SwiftUI
import PhotosUI

struct SettingsView: View {
    @EnvironmentObject var session: SessionStore
    @EnvironmentObject var theme: ThemeStore
    @EnvironmentObject var kreta: KretaClient
    @EnvironmentObject var profileStore: ProfileImageStore
    @Environment(\.colorScheme) var scheme
    @Environment(\.horizontalSizeClass) private var hSize
    private var isPad: Bool { hSize == .regular }
    @State private var thresholds: [String: Double] = GradingLogic.loadThresholds()
    @State private var subjects: [String] = []
    @State private var isLoadingSubjects = true
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var cropImage: UIImage?
    @State private var showPhotoOptions = false
    @AppStorage("notify.grades") private var notifyGrades = true
    @AppStorage("notify.tasks") private var notifyTasks = true
    @AppStorage("notify.absences") private var notifyAbsences = true
    @State private var notifStatus = "Ismeretlen"
    @State private var simMessage: String?
    @State private var showSimAlert = false
    @State private var draftIss = ""
    @State private var repairMsg = ""
    @State private var repairRunning = false
    @State private var scrollOffset: CGFloat = 0 // parallax háttérhez (onScrollGeometryChange)
    var colors: AppColors { theme.colors(for: scheme) }

    var body: some View {
        ScrollView {
            // Közös glass-konténer: az egy- és többsoros szigetek üvege
            // ugyanabban a mintavételi térben renderelődik, így az átlátszóság
            // (/blur) nem függ a sziget méretétől.
            SettingsGlassGroup {
            VStack(spacing: 20) {
            // Profil-sziget (fejléc nélkül, mint eddig)
            HStack(spacing: 12) {
                ZStack(alignment: .bottomTrailing) {
                    ProfileImageView(name: session.selectedUser?.name ?? "Diák", userId: session.selectedUser?.id, size: 56).frame(width: 56, height: 56)
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
            .confirmationDialog("Profilkép", isPresented: $showPhotoOptions, titleVisibility: .visible) {
                // PhotosPicker is already in row; dialog for remove
                if profileStore.hasImage(for: session.selectedUser?.id) {
                    Button("Kép törlése", role: .destructive) {
                        if let id = session.selectedUser?.id { profileStore.remove(for: id) }
                    }
                }
                Button("Mégse", role: .cancel) {}
                } message: { Text("Válassz új képet a Módosítás gombbal, vagy töröld a jelenlegit.") }

            island(header: "Tanári kerekítés", footer: "Tantárgyanként állítható, hogy a tanár mikortól kerekít fel — külön menüben.") {
                row {
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

            island(header: "Live Activity", footer: "Lock Screen + Dynamic Island — szünetben a következőt mutatja. Rendszer tiltás esetén a Beállításokban engedélyezd.") {
                row { LiveActivitySettingsRow() }
            }

            island(header: "Értesítések", footer: "A KRÉTA nem küld push-t, ezért az app minden adatfrissítéskor (megnyitás, lehúzás, háttér-ébresztés) megnézi, mi az új, és arra küld helyi értesítést.") {
                row {
                    Toggle(isOn: $notifyGrades) {
                        Label("Új jegy", systemImage: "star.fill").font(.subheadline.weight(.medium))
                    }
                    .tint(colors.accent)
                    .onChange(of: notifyGrades) { _, new in
                        if new { Task { await NotificationManager.shared.requestPermission() } }
                    }
                }
                settingsDivider
                row {
                    Toggle(isOn: $notifyTasks) {
                        Label("Új házi / dolgozat", systemImage: "checklist").font(.subheadline.weight(.medium))
                    }
                    .tint(colors.accent)
                    .onChange(of: notifyTasks) { _, new in
                        if new { Task { await NotificationManager.shared.requestPermission() } }
                    }
                }
                settingsDivider
                row {
                    Toggle(isOn: $notifyAbsences) {
                        Label("Új hiányzás", systemImage: "person.crop.rectangle.stack").font(.subheadline.weight(.medium))
                    }
                    .tint(colors.accent)
                    .onChange(of: notifyAbsences) { _, new in
                        if new { Task { await NotificationManager.shared.requestPermission() } }
                    }
                }
                if session.selectedUser?.isDemo == true {
                    settingsDivider
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
                            await NotificationManager.shared.sendTest(userId: session.selectedUser?.id ?? "demo-user")
                            notifStatus = NotificationManager.shared.permissionStatus
                        } }
                        .tint(colors.accent)
                    }
                }
                if session.selectedUser?.isDemo == true {
                    settingsDivider
                    row {
                        Button("Új demo jegy szimulálása (5-ös Matek + kártya)") { Task {
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
            }

            island(header: "Megjelenés") {
                row {
                    Picker("Téma", selection: Binding(get: { theme.mode }, set: { theme.mode = $0 })) {
                        ForEach(AppThemeMode.allCases) { m in
                            Label(m.title, systemImage: m.icon).tag(m)
                        }
                    }
                    .pickerStyle(.segmented)
                }
                settingsDivider
                // Accent —简单 színválasztó
                row {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Kiemelés színe").font(.subheadline.weight(.medium))
                        HStack(spacing: 10) {
                            ForEach(ThemeStore.presets, id: \.self) { hex in
                                let c = Color(hex: UInt(hex))
                                Circle().fill(c).frame(width: 30, height: 30)
                                    .overlay(Circle().strokeBorder(Color.primary.opacity(theme.accentHex == hex ? 0.9 : 0.18), lineWidth: theme.accentHex == hex ? 2 : 1))
                                    .scaleEffect(theme.accentHex == hex ? 1.12 : 1)
                                    .onTapGesture { withAnimation(.spring(response: 0.3)) { theme.accentHex = hex } }
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
                    .padding(.vertical, 4)
                }
                settingsDivider
                // Szövegméret — Macen (iPad-app Macen) alapból nagyobb
                row {
                    Picker("Szövegméret", selection: Binding(get: { theme.sizeCategoryKey }, set: { theme.sizeCategoryKey = $0 })) {
                        ForEach(ThemeStore.sizeSteps, id: \.key) { step in
                            Text(step.title).tag(step.key)
                        }
                    }
                    .pickerStyle(.navigationLink)
                    .padding(.vertical, 4)
                }
            }

            island(header: "Fiók") {
                row {
                    Button("Kijelentkezés", role: .destructive) { session.logout() }
                }
                if session.selectedUser?.isDemo == true {
                    settingsDivider
                    row {
                        Label("Demo módban vagy — kijelentkezéssel kilépsz", systemImage: "flask.fill").font(.subheadline).foregroundStyle(.secondary)
                    }
                }
                // Iskola-kód felülírás: a tokenből fejlett kód néha nem host
                // (pl. OM-azonosító) — olyankor minden DNS-hibával hal meg.
                // Ide a böngészős e-KRÉTA cím eleje kell: https://EZ.e-kreta.hu
                if session.selectedUser?.isDemo != true {
                    settingsDivider
                    row {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Iskola kód").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                            HStack {
                                TextField("pl. klik035454001", text: $draftIss)
                                    .font(.subheadline.monospaced())
                                    .textInputAutocapitalization(.never)
                                    .autocorrectionDisabled()
                                Button("Mentés") {
                                    session.updateInstitute(draftIss)
                                    kreta.instituteCode = session.selectedUser?.instituteCode
                                    kreta.sessionExpired = false
                                    kreta.showExpiredAlert = false
                                }
                                .font(.subheadline.weight(.bold))
                            }
                            Text("Ha minden üres, ez a kód a rossz — utána húzd le a listákat a frissítéshez.")
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
                }
            }

            island(header: "Diagnosztika") {
                row {
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

            Text("Summit • Gábor Csaba").font(.caption2).foregroundStyle(.tertiary).frame(maxWidth: .infinity)
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 24)
            .frame(maxWidth: isPad ? MacSupport.contentWidth(ipad: 800, mac: 920) : .infinity)
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
        .toolbarBackground(.visible, for: .navigationBar)
        .task { await loadSubjects() }
        .refreshable { await loadSubjects(force: true) }
        .onAppear {
            thresholds = GradingLogic.loadThresholds()
            if draftIss.isEmpty { draftIss = session.selectedUser?.instituteCode ?? "" }
            Task {
                await NotificationManager.shared.refreshPermission()
                notifStatus = NotificationManager.shared.permissionStatus
            }
        }
        .alert("Demo értesítés", isPresented: $showSimAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(simMessage ?? "")
        }
        .fullScreenCover(
            isPresented: Binding(get: { cropImage != nil }, set: { if !$0 { cropImage = nil } })
        ) { cropSheet }
        .onChange(of: session.selectedId) { _, _ in Task { await loadSubjects(force: true) } }
    }

    /// Üveg sziget-szekció: fejléc + egybefüggő liquid glass kártya + lábléc —
    /// mint az insetGrouped lista, csak az EGÉSZ sziget egy üveg,
    /// nem soronkénti csíkok. Mögötte átlátszik a SummitBackdrop.
    private func island<Content: View>(header: String? = nil, footer: String? = nil, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            if let header {
                Text(header).font(.caption.weight(.semibold)).foregroundStyle(.secondary).textCase(.uppercase)
                    .padding(.horizontal, 4)
            }
            VStack(alignment: .leading, spacing: 0) {
                content()
            }
            .summitGlassRow(cornerRadius: 20)
            if let footer {
                Text(footer).font(.caption2).foregroundStyle(.secondary)
                    .padding(.horizontal, 4)
            }
        }
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
    private func row<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 0) { content() }
            .padding(.horizontal, 16)
            .padding(.vertical, 11)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var settingsDivider: some View {
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
                    if let id = session.selectedUser?.id {
                        profileStore.save(image: resize(image: out, maxSize: 512), for: id)
                    }
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
        var collected = Set(await kreta.fetchAllSubjectNames(iss: iss))
        collected.formUnion(GradingLogic.loadThresholds().keys.filter { collected.contains($0) })
        // filter out empty / unknown
        let filtered = collected.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty && $0 != "Ismeretlen" }.sorted()
        subjects = filtered
        isLoadingSubjects = false
        if !filtered.isEmpty, !isDemo { UserDefaults.standard.set(filtered, forKey: "firka.cachedSubjects.v1") }
    }
}

/// Közös Liquid Glass konténer a beállítások szigetei köré (iOS 26+):
/// a rendszer ilyenkor egyben rendereli a szigetek üvegét, így az egysoros
/// és a többsoros sziget átlátszósága/blurje nem válik szét. Régebbi
/// rendszeren sima átengedő csoport.
private struct SettingsGlassGroup<Content: View>: View {
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
    @Environment(\.colorScheme) var scheme
    @StateObject private var manager = SummitLiveActivityManager.shared
    @AppStorage("liveActivity.enabled") private var enabled: Bool = true
    @State private var showSystemAlert = false

    var body: some View {
        Toggle(isOn: Binding(
            get: { enabled },
            set: { new in
                enabled = new
                manager.setAppEnabled(new)
                if new { Task { await tryStartPreview() } }
                manager.refreshSystemState()
                if new && !manager.isSystemEnabled { showSystemAlert = true }
            }
        )) {
            Label("Live Activity", systemImage: "clock.badge.checkmark")
                .font(.subheadline.weight(.medium))
        }
        .tint(theme.colors(for: scheme).accent)
        .padding(.vertical, 2)
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
