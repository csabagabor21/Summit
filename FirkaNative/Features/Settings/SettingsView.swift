import SwiftUI
import PhotosUI

struct SettingsView: View {
    @EnvironmentObject var session: SessionStore
    @EnvironmentObject var theme: ThemeStore
    @EnvironmentObject var kreta: KretaClient
    @EnvironmentObject var profileStore: ProfileImageStore
    @Environment(\.colorScheme) var scheme
    @State private var thresholds: [String: Double] = GradingLogic.loadThresholds()
    @State private var subjects: [String] = []
    @State private var isLoadingSubjects = true
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var showPhotoOptions = false
    @AppStorage("home.demoOverride") private var demoOverride = false
    var colors: AppColors { theme.colors(for: scheme) }

    var body: some View {
        List {
            Section {
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
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
                .confirmationDialog("Profilkép", isPresented: $showPhotoOptions, titleVisibility: .visible) {
                    // PhotosPicker is already in row; dialog for remove
                    if profileStore.hasImage(for: session.selectedUser?.id) {
                        Button("Kép törlése", role: .destructive) {
                            if let id = session.selectedUser?.id { profileStore.remove(for: id) }
                        }
                    }
                    Button("Mégse", role: .cancel) {}
                } message: { Text("Válassz új képet a Módosítás gombbal, vagy töröld a jelenlegit.") }
            }

            Section(header: Text("Tanári kerekítés").font(.caption.weight(.semibold)).foregroundStyle(.secondary).textCase(.uppercase),
                    footer: Text(subjects.isEmpty && !isLoadingSubjects ? "Még nincs tantárgy — húzd le frissíteni." : "Koppints egy tárgyra a kerekítés finomhangolásához.").font(.caption2).foregroundStyle(.secondary)) {
                if isLoadingSubjects {
                    ForEach(0..<3, id: \.self) { _ in HStack { Text("Betöltés…").redacted(reason: .placeholder); Spacer() } }
                } else if subjects.isEmpty {
                    Text("Nincs elérhető tantárgy. Jelentkezz be vagy frissíts.").font(.subheadline).foregroundStyle(.secondary)
                } else {
                    ForEach(subjects, id: \.self) { subj in
                        let thr = thresholds[subj] ?? GradingLogic.defaultThreshold
                        NavigationLink { RoundingDetailView(subject: subj) } label: {
                            HStack {
                                Text(subj).font(.subheadline.weight(.semibold))
                                Spacer()
                                Text(String(format: "%.2f", thr)).font(.caption.monospacedDigit().weight(.medium)).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }

            Section(header: Text("Megjelenés").font(.caption.weight(.semibold)).foregroundStyle(.secondary).textCase(.uppercase)) {
                Picker("Téma", selection: Binding(get: { theme.mode }, set: { theme.mode = $0 })) {
                    ForEach(AppThemeMode.allCases) { m in
                        Label(m.title, systemImage: m.icon).tag(m)
                    }
                }
                .pickerStyle(.segmented)

                // Accent —简单 színválasztó
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

            Section(header: Text("Fiók").font(.caption.weight(.semibold)).foregroundStyle(.secondary).textCase(.uppercase)) {
                Button("Kijelentkezés", role: .destructive) { session.logout() }
                if session.selectedUser?.isDemo != true {
                    Toggle(isOn: $demoOverride) {
                        Label(demoOverride ? "Demo adatok" : "Valós adatok", systemImage: demoOverride ? "flask.fill" : "person.crop.rectangle.stack.fill")
                            .font(.subheadline.weight(.medium))
                    }
                    .tint(colors.accent)
                } else {
                    // demo user esetén csak jelzés, nincs toggle
                    Label("Demo módban vagy", systemImage: "flask.fill").font(.subheadline).foregroundStyle(.secondary)
                }
            }

            Section(footer: Text("FirkaNative • iOS 26 • Liquid Glass • \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0")").font(.caption2).foregroundStyle(.tertiary).frame(maxWidth:.infinity)) {
                Link("Adatkezelés", destination: URL(string: "https://firka.app/privacy")!)
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(colors.background)
        .navigationTitle("Beállítások")
        .navigationBarTitleDisplayMode(.large)
        .toolbarBackground(.visible, for: .navigationBar)
        .task { await loadSubjects() }
        .refreshable { await loadSubjects(force: true) }
        .onAppear { thresholds = GradingLogic.loadThresholds() }
        .onChange(of: session.selectedId) { _, _ in Task { await loadSubjects(force: true) } }
    }

    private func handlePhotoChange(_ item: PhotosPickerItem?) async {
        guard let item, let data = try? await item.loadTransferable(type: Data.self), let ui = UIImage(data: data),
              let id = session.selectedUser?.id else { return }
        // resize to max 512 to save storage
        let resized = resize(image: ui, maxSize: 512)
        profileStore.save(image: resized, for: id)
        selectedPhoto = nil
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
        if !force, let cached = UserDefaults.standard.stringArray(forKey: "firka.cachedSubjects.v1"), !cached.isEmpty, session.selectedUser?.isDemo == false {
            // still fetch in background, but show cached first
            subjects = cached; isLoadingSubjects = false
        } else if !force, session.selectedUser?.isDemo == true {
            let s = Set(DemoData.gradesExpanded().map(\.subject))
            subjects = s.sorted(); isLoadingSubjects = false
            return
        }
        isLoadingSubjects = subjects.isEmpty
        var collected = Set<String>()
        // thresholds already saved subjects
        collected.formUnion(GradingLogic.loadThresholds().keys)
        if let cached = UserDefaults.standard.stringArray(forKey: "firka.cachedSubjects.v1") { collected.formUnion(cached) }

        if session.selectedUser?.isDemo == true {
            collected.formUnion(DemoData.gradesExpanded().map(\.subject))
            collected.formUnion(DemoData.lessonsToday().map(\.subject))
        } else if let user = session.selectedUser {
            let iss = user.instituteCode.isEmpty ? (JWT.instituteCode(from: user.accessToken) ?? "") : user.instituteCode
            if !iss.isEmpty {
                let grades = await kreta.fetchGrades(iss: iss)
                collected.formUnion(grades.map(\.subject))
                // also timetable last 14 days for subjects without grades yet
                let start = Calendar.current.date(byAdding: .day, value: -14, to: Date())!
                let end = Calendar.current.date(byAdding: .day, value: 14, to: Date())!
                let lessons = await kreta.fetchTimetable(iss: iss, from: start, to: end)
                collected.formUnion(lessons.map(\.subject))
            }
        } else {
            // not logged in -> show demo subjects so UI is not empty
            collected.formUnion(DemoData.gradesExpanded().map(\.subject))
        }
        // filter out empty / unknown
        let filtered = collected.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty && $0 != "Ismeretlen" }.sorted()
        subjects = filtered
        isLoadingSubjects = false
        if !filtered.isEmpty { UserDefaults.standard.set(filtered, forKey: "firka.cachedSubjects.v1") }
    }
}
