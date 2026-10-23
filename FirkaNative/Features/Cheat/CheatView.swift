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
                if !MetaAIKeyStore.hasKey {
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
                            .mcInlineButton()
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
                                        Spacer()
                                        if sheet.topics.isEmpty {
                                            Text("\(sheet.materials.count) anyag")
                                                .skinFont(.caption2).foregroundStyle(.secondary)
                                        } else {
                                            Text("\(sheet.topics.count) téma")
                                                .skinFont(.caption2).foregroundStyle(.secondary)
                                        }
                                    }
                                    Text(sheet.title)
                                        .skinFont(.callout).foregroundStyle(.secondary)
                                        .lineLimit(2)
                                    if let examTitle = linkedExamTitle(for: sheet) {
                                        SkinLabel(examTitle, systemImage: "doc.text")
                                            .skinFont(.caption).skinAccent(colors.accent)
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
                        Text("Jegyzetlapok • \(sheets.count) db")
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
                // A kulcs-sor eltűnéséhez / megjelenéséhez elég az újrarajz.
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

    var body: some View {
        NavigationStack {
            Form {
                Section("Miről szól") {
                    TextField("Cím (pl. Babits Mihály)", text: $title, prompt: skinPrompt("Cím (pl. Babits Mihály)"))
                        .mcInput()
                    SkinMenuPicker(
                        title: "Tantárgy",
                        selection: $subject,
                        options: [SkinOption(value: "", title: "Válassz…")] + subjects.map { SkinOption(value: $0, title: $0) }
                    )
                }
                .mcListRowComfy(fill: colors.surface)
                Section("Dolgozat (opcionális)") {
                    SkinMenuPicker(
                        title: "Kapcsolt dolgozat",
                        selection: $examID,
                        options: [SkinOption(value: nil as String?, title: "Nincs")]
                            + exams.map { SkinOption(value: $0.id as String?, title: "\($0.subject) • \($0.mode) • \(huDate($0.date))") },
                        navigationStyle: true
                    )
                }
                .mcListRowComfy(fill: colors.surface)
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
                        guard !t.isEmpty, !subject.isEmpty else { return }
                        let ex = exams.first { $0.id == examID }
                        onSave(CheatSheet(examId: examID, subject: subject, title: t, date: ex?.date))
                        dismiss()
                    }
                    .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || subject.isEmpty)
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
