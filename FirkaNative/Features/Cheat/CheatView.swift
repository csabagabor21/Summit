import SwiftUI

// MARK: - Watch — tanulójegyzetek (SummitCheat)
// Dolgozatonkénti lapok: feltöltött anyagokból Meta AI-kulccsal
// generált (vagy kézzel írt) témánkénti jegyzetek
// (pl. "Babits Mihály" → "Életrajza", "Novellái"). A lapok az órára
// is átmennek (Watch-szinkron → Jegyzet tab), a kulcs nélkül is
// használható kézi jegyzetként. Belépő: a Feladatok tetején,
// a + gombbal szembeni toolbar-gomb (csak órával látszik).
struct CheatView: View {
    @EnvironmentObject var theme: ThemeStore
    @EnvironmentObject var session: SessionStore
    @EnvironmentObject var kreta: KretaClient
    @EnvironmentObject var completed: CompletedStore
    @State private var sheets: [CheatSheet] = []
    @State private var exams: [ExamItem] = []
    @State private var subjects: [String] = []
    @State private var isLoading = true
    @State private var showingAdd = false
    @State private var apiKeyDraft = ""
    @State private var showKeyField = false
    /// A kulcs statikus tárban él (nem publikált): a változás-értesítés
    /// ezt lépteti, hogy a kulcs-szekció tényleg újrarajzolódjon.
    @State private var keyTick = 0
    /// Sheetben nyitva kell az X a csukáshoz (a Feladatok toolbar-
    /// gombja így nyitja) — tab-gyökérként nincs rá szükség.
    let showCloseButton: Bool
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) var scheme
    init(showCloseButton: Bool = false) {
        self.showCloseButton = showCloseButton
    }
    @Environment(\.horizontalSizeClass) private var hSize
    private var isPad: Bool { hSize == .regular }
    var colors: AppColors { theme.colors(for: scheme) }

    var body: some View {
        NavigationStack {
            List {
                if keyTick >= 0, !MetaAIKeyStore.hasKey {
                    Section {
                        Button { showKeyField.toggle() } label: {
                            SkinLabel("Meta AI-kulcs hozzáadása", systemImage: "key.fill")
                                .skinFont(.subheadline, weight: .semibold)
                                .skinAccent(colors.accent)
                        }
                        .mcInlineButton()
                        if showKeyField {
                            SecureField("Meta AI API-kulcs", text: $apiKeyDraft, prompt: skinPrompt("Meta AI API-kulcs"))
                                .textContentType(.password)
                                .autocorrectionDisabled()
                                .textInputAutocapitalization(.never)
                                .mcInput()
                            Button("Kulcs mentése") {
                                MetaAIKeyStore.save(apiKeyDraft)
                                apiKeyDraft = ""
                                showKeyField = false
                            }
                            .disabled(apiKeyDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                            .mcInlineButton(prominent: theme.isCyberpunk)
                        } else {
                            Text("Saját kulcs nélkül is megy: a közös ingyenes Gemini (gyenge) készíti a jegyzetet — saját kulccsal jobb minőség.")
                                .skinFont(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .mcListRowComfy(fill: colors.surface)
                }
                if isLoading {
                    ForEach(0..<3, id: \.self) { _ in
                        HStack { Text("Betöltés…").redacted(reason: .placeholder) }
                            .summitRowSurface(colors: colors)
                            .cpgRowChrome()
                    }
                } else if sheets.isEmpty {
                    Section {
                        SkinEmptyState(
                            title: "Nincs jegyzetlap",
                            systemImage: "applewatch",
                            description: Text("Vegyél fel egy lapot egy dolgozathoz (pl. Babits Mihály), tölts fel anyagokat, és az AI témánként jegyzetet csinál belőlük.")
                        )
                        .frame(maxWidth: .infinity, minHeight: 220)
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                    }
                } else {
                    Section {
                        ForEach(sheets) { sheet in
                            SkinNavLink {
                                CheatSheetView(sheetID: sheet.id, exams: exams, subjects: subjects)
                            } label: {
                                VStack(alignment: .leading, spacing: 4) {
                                    HStack {
                                        Text(sheet.subject)
                                            .skinFont(.subheadline, weight: .semibold)
                                            .cpgShardTitle()
                                        Spacer()
                                        if sheet.topics.isEmpty {
                                            Text(theme.isCyberpunk ? cpgCount(sheet.materials.count, "anyag") : "\(sheet.materials.count) anyag")
                                                .cpgMono(.caption2, size: 10).foregroundStyle(.secondary)
                                        } else {
                                            Text(theme.isCyberpunk ? cpgCount(sheet.topics.count, "téma") : "\(sheet.topics.count) téma")
                                                .cpgMono(.caption2, size: 10).foregroundStyle(.secondary)
                                        }
                                    }
                                    Text(sheet.title)
                                        .skinFont(.callout).foregroundStyle(.secondary)
                                        .lineLimit(2)
                                    if let examTitle = linkedExamTitle(for: sheet) {
                                        SkinLabel(examTitle, systemImage: "doc.text")
                                            .skinFont(.caption).skinAccent(theme.isCyberpunk ? CyberpunkTheme.cyan : colors.accent)
                                            .lineLimit(1)
                                    }
                                }
                                .padding(.vertical, 4)
                            }
                        }
                        .onDelete { idx in
                            var all = sheets
                            all.remove(atOffsets: idx)
                            CheatStore.save(all)
                        }
                    } header: {
                        if theme.isCyberpunk {
                            CPSectionHeader("Jegyzetlapok", code: "\(sheets.count) db")
                        } else {
                            Text("Jegyzetlapok • \(sheets.count) db")
                        }
                    }
                    .mcListRowComfy(fill: colors.surface)
                }
            }
            .listStyle(.insetGrouped)
            .frame(maxWidth: isPad ? MacSupport.contentWidth(ipad: 1000, mac: 1150) : .infinity)
            .padding(.horizontal, MacSupport.sidePadding)
            .frame(maxWidth: .infinity)
            .summitListChrome(colors: colors)
            .navigationTitle("Watch")
            .navigationBarTitleDisplayMode(.large)
            .summitToolbarBackground()
            .toolbar {
                if showCloseButton {
                    SkinToolbarItem(placement: .cancellationAction) {
                        Button { dismiss() } label: {
                            SkinIcon("xmark")
                        }
                        .accessibilityLabel("Bezárás")
                    }
                }
                SkinToolbarItem(placement: .topBarTrailing) {
                    Button { showingAdd = true } label: {
                        SkinIcon("plus")
                    }
                    .accessibilityLabel("Új jegyzetlap")
                }
            }
            .sheet(isPresented: $showingAdd) {
                AddCheatSheetView(exams: upcomingExams, subjects: subjects) { sheet in
                    CheatStore.upsert(sheet)
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: CheatStore.changedNotification)) { _ in
                sheets = CheatStore.load()
                CheatWatchPush.push(sheets)
            }
            .onReceive(NotificationCenter.default.publisher(for: MetaAIKeyStore.changedNotification)) { _ in
                // A kulcs-sor eltűnéséhez / megjelenéséhez újrarajz kell
                // (pl. a Beállításokban vagy szinkronból érkezett kulcs).
                keyTick += 1
            }
            .task { await load() }
            .refreshable {
                await load(force: true)
                SummitHaptics.light()
            }
        }
        .tint(colors.accent)
    }

    private var upcomingExams: [ExamItem] {
        let start = Calendar.current.startOfDay(for: Date())
        return exams.filter { $0.date >= start }.sorted { $0.date < $1.date }
    }

    private func linkedExamTitle(for sheet: CheatSheet) -> String? {
        guard let eid = sheet.examId,
              let ex = exams.first(where: { $0.id == eid }) else { return nil }
        return "\(ex.subject) • \(ex.mode)"
    }

    /// Újranyitáskor a `.task` újra lefut — friss gyorstár-találatnál ez
    /// hálózat nélkül tér vissza. A váz csak üres listánál jön.
    func load(force: Bool = false) async {
        sheets = CheatStore.load()
        CheatWatchPush.push(sheets)
        guard let user = session.selectedUser else { isLoading = false; return }
        if exams.isEmpty { isLoading = true }
        let iss = user.instituteCode.isEmpty ? (JWT.instituteCode(from: user.accessToken) ?? "") : user.instituteCode
        async let ex = kreta.fetchExams(iss: iss, force: force)
        async let subj = kreta.fetchAllSubjectNames(iss: iss, force: force)
        async let gr = kreta.fetchGrades(iss: iss, force: force)
        let (exR, subjR, grR) = await (ex, subj, gr)
        var all = exR + CustomTasksStore.examItems(from: CustomTasksStore.load())
        all.sort { $0.date < $1.date }
        exams = all
        let cached = UserDefaults.standard.stringArray(forKey: "firka.cachedSubjects.v1") ?? []
        subjects = Array(Set(subjR).union(cached).union(grR.map(\.subject))).sorted()
        isLoading = false
    }
}

// MARK: - Új lap felvétele — dolgozathoz kötve vagy anélkül
private struct AddCheatSheetView: View {
    let exams: [ExamItem]
    let subjects: [String]
    let onSave: (CheatSheet) -> Void
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var theme: ThemeStore
    @Environment(\.colorScheme) var scheme
    var colors: AppColors { theme.colors(for: scheme) }
    @State private var title = ""
    @State private var subject = ""
    @State private var examID: String? = nil

    /// Választható tárgyak: a Jegyek-tab köre + a dolgozatok tárgyai (egy
    /// dolgozathoz kötött lap tárgya akkor is választható, ha a tárgy épp
    /// nincs a jegyek között).
    private var subjectOptions: [String] {
        Array(Set(subjects).union(exams.map(\.subject)))
            .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
            .sorted()
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Cím (pl. Babits Mihály)", text: $title, prompt: skinPrompt("Cím (pl. Babits Mihály)"))
                        .mcInput()
                    if subjectOptions.isEmpty {
                        // Nincs még tantárgylista (friss belépés, offline):
                        // kézzel beírható, különben a lap fel sem vehető.
                        TextField("Tantárgy (pl. Irodalom)", text: $subject, prompt: skinPrompt("Tantárgy (pl. Irodalom)"))
                            .mcInput()
                    } else {
                        SkinMenuPicker(
                            title: "Tantárgy",
                            selection: $subject,
                            options: [SkinOption(value: "", title: "Válassz…")] + subjectOptions.map { SkinOption(value: $0, title: $0) }
                        )
                    }
                } header: {
                    cpgSectionHeader("Miről szól", code: "01")
                } footer: {
                    // A „Kész" cím és tárgy nélkül szürke — mondjuk is meg, miért.
                    if subjectOptions.isEmpty {
                        Text("Még nincs tantárgylista — írd be kézzel, vagy húzd le a Jegyek tabot.")
                    } else if title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || subject.isEmpty {
                        Text("A mentéshez cím és tantárgy kell.")
                    }
                }
                .mcListRowComfy(fill: colors.surface)
                Section {
                    SkinMenuPicker(
                        title: "Kapcsolt dolgozat",
                        selection: $examID,
                        options: [SkinOption(value: nil as String?, title: "Nincs")]
                            + exams.map { SkinOption(value: $0.id as String?, title: "\($0.subject) • \($0.mode) • \(huDate($0.date))") },
                        navigationStyle: true
                    )
                } header: {
                    cpgSectionHeader("Dolgozat (opcionális)", code: "02")
                }
                .mcListRowComfy(fill: colors.surface)
                .onChange(of: examID) { _, id in
                    // Dolgozat választásakor a tárgy magától kitöltődik,
                    // ha még nincs megadva.
                    if subject.isEmpty, let ex = exams.first(where: { $0.id == id }) {
                        subject = ex.subject
                    }
                }
            }
            .skinFormChrome()
            .navigationTitle("Új jegyzetlap")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                SkinToolbarItem(placement: .cancellationAction) {
                    Button("Mégse") { dismiss() }
                }
                SkinToolbarItem(placement: .confirmationAction) {
                    Button("Kész") {
                        let t = title.trimmingCharacters(in: .whitespacesAndNewlines)
                        let subj = subject.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !t.isEmpty, !subj.isEmpty else { return }
                        let ex = exams.first { $0.id == examID }
                        onSave(CheatSheet(examId: examID, subject: subj, title: t, date: ex?.date))
                        dismiss()
                    }
                    .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                              || subject.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }

    private func huDate(_ d: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "hu_HU")
        f.dateFormat = "MMM d."
        return f.string(from: d)
    }
}

// MARK: - Cyberpunk-részletek (Journal / adat-shard hangulat)
//
// Egyszintű kapcsolók: Summitban és Minecraftban az eredeti lánc fut
// változatlanul (a `cpgMono` ott a régi `skinFont`).

/// `[03] TÉMA` — HUD-darabszám a shard-sor jobb szélére.
private func cpgCount(_ n: Int, _ unit: String) -> String {
    String(format: "[%02d] ", n) + unit.uppercased()
}

/// Form-szekció fejléce: Cyberpunkban `CPSectionHeader` kóddal, máshol a
/// korábbi `Section("…")` fejléc-szövege.
@ViewBuilder
private func cpgSectionHeader(_ title: String, code: String) -> some View {
    if CyberpunkTheme.isActive {
        CPSectionHeader(title, code: code)
    } else {
        Text(LocalizedStringKey(title))
    }
}

private extension View {
    @ViewBuilder
    func cpgMono(_ style: Font.TextStyle, size: CGFloat) -> some View {
        if CyberpunkTheme.isActive {
            self.font(CyberpunkTheme.mono(size: size, relativeTo: style)).tracking(0.6)
        } else {
            self.skinFont(style)
        }
    }

    /// Shard-cím: nagybetűs, ritkított, jellegzetes sárga.
    @ViewBuilder
    func cpgShardTitle() -> some View {
        if CyberpunkTheme.isActive {
            self.textCase(.uppercase).tracking(1).foregroundStyle(CyberpunkTheme.yellow)
        } else {
            self
        }
    }

    /// Betöltés-váz sora Cyberpunkban a HUD-sor margóival (Summit és
    /// Minecraft változatlan).
    @ViewBuilder
    func cpgRowChrome() -> some View {
        if CyberpunkTheme.isActive { self.mcRowChrome() } else { self }
    }
}
