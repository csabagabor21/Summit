import SwiftUI

// MARK: - Watch tab — tanulójegyzetek (SummitCheat)
// Dolgozatonkénti lapok: feltöltött anyagokból Meta AI-kulccsal
// generált (vagy kézzel írt) témánkénti jegyzetek
// (pl. "Babits Mihály" → "Életrajza", "Novellái"). A lapok az órára
// is átmennek (Watch-szinkron → Jegyzet tab), a kulcs nélkül is
// használható kézi jegyzetként. A Feladatok a Főoldalról nyílnak,
// a régi deep-linkek továbbra is ide mutatnak (coverben nyílik).
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
    @State private var showingTasks = false
    @State private var apiKeyDraft = ""
    @State private var showKeyField = false
    @Environment(\.colorScheme) var scheme
    @Environment(\.horizontalSizeClass) private var hSize
    private var isPad: Bool { hSize == .regular }
    private let switchToTasks = Notification.Name("summit.switchToTasks")
    var colors: AppColors { theme.colors(for: scheme) }

    var body: some View {
        NavigationStack {
            List {
                if !MetaAIKeyStore.hasKey {
                    Section {
                        Button { showKeyField.toggle() } label: {
                            Label("Meta AI-kulcs hozzáadása", systemImage: "key.fill")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(colors.accent)
                        }
                        if showKeyField {
                            SecureField("Meta AI API-kulcs", text: $apiKeyDraft)
                                .textContentType(.password)
                                .autocorrectionDisabled()
                                .textInputAutocapitalization(.never)
                            Button("Kulcs mentése") {
                                MetaAIKeyStore.save(apiKeyDraft)
                                apiKeyDraft = ""
                                showKeyField = false
                            }
                            .disabled(apiKeyDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        } else {
                            Text("Saját kulcs nélkül is megy: a közös ingyenes Gemini (gyenge) készíti a jegyzetet — saját kulccsal jobb minőség.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                if isLoading {
                    ForEach(0..<3, id: \.self) { _ in
                        HStack { Text("Betöltés…").redacted(reason: .placeholder) }
                            .summitRowSurface(colors: colors)
                    }
                } else if sheets.isEmpty {
                    Section {
                        ContentUnavailableView(
                            "Nincs jegyzetlap",
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
                            NavigationLink {
                                CheatSheetView(sheetID: sheet.id, exams: exams, subjects: subjects)
                            } label: {
                                VStack(alignment: .leading, spacing: 4) {
                                    HStack {
                                        Text(sheet.subject)
                                            .font(.subheadline.weight(.semibold))
                                        Spacer()
                                        if sheet.topics.isEmpty {
                                            Text("\(sheet.materials.count) anyag")
                                                .font(.caption2).foregroundStyle(.secondary)
                                        } else {
                                            Text("\(sheet.topics.count) téma")
                                                .font(.caption2).foregroundStyle(.secondary)
                                        }
                                    }
                                    Text(sheet.title)
                                        .font(.callout).foregroundStyle(.secondary)
                                        .lineLimit(2)
                                    if let examTitle = linkedExamTitle(for: sheet) {
                                        Label(examTitle, systemImage: "doc.text")
                                            .font(.caption).foregroundStyle(colors.accent)
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
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showingAdd = true } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel("Új jegyzetlap")
                }
            }
            .sheet(isPresented: $showingAdd) {
                AddCheatSheetView(exams: upcomingExams, subjects: subjects) { sheet in
                    CheatStore.upsert(sheet)
                }
            }
            // A régi Feladatok-tab deep-linkjei (Főoldal, Órarend,
            // értesítés) a 3-as tabra mutatnak — ez most a Watch:
            // a Feladatok-lap nyílik, a szegmens/villanás továbbmegy.
            .fullScreenCover(isPresented: $showingTasks) {
                // Coverben "Kész" gomb is kell — nélküle a dolgozat-pillből
                // ide jutva nincs kiút a nézetből.
                NotesView(showCloseButton: true)
                    .environmentObject(theme)
                    .environmentObject(session)
                    .environmentObject(kreta)
                    .environmentObject(completed)
            }
            .onReceive(NotificationCenter.default.publisher(for: switchToTasks)) { notif in
                // Őr a relé-hurok ellen: a saját újraküldésünk is ideér —
                // azt már nem küldjük tovább (különben 0,4 mp-enként
                // újraindulna a szegmens + villanás, örökké).
                guard !showingTasks else { return }
                showingTasks = true
                // A NotesView még nem él a coverben — a notifot
                // újraküldjük, hogy a szegmens + villanás hasson.
                if let info = notif.userInfo {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                        NotificationCenter.default.post(name: switchToTasks, object: nil, userInfo: info)
                    }
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
            .refreshable { await load() }
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

    func load() async {
        sheets = CheatStore.load()
        CheatWatchPush.push(sheets)
        guard let user = session.selectedUser else { isLoading = false; return }
        isLoading = true
        let iss = user.instituteCode.isEmpty ? (JWT.instituteCode(from: user.accessToken) ?? "") : user.instituteCode
        async let ex = kreta.fetchExams(iss: iss)
        async let subj = kreta.fetchAllSubjectNames(iss: iss)
        async let gr = kreta.fetchGrades(iss: iss)
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
    @State private var title = ""
    @State private var subject = ""
    @State private var examID: String? = nil

    var body: some View {
        NavigationStack {
            Form {
                Section("Miről szól") {
                    TextField("Cím (pl. Babits Mihály)", text: $title)
                    Picker("Tantárgy", selection: $subject) {
                        Text("Válassz…").tag("")
                        ForEach(subjects, id: \.self) { Text($0).tag($0) }
                    }
                }
                Section("Dolgozat (opcionális)") {
                    Picker("Kapcsolt dolgozat", selection: $examID) {
                        Text("Nincs").tag(nil as String?)
                        ForEach(exams, id: \.id) { ex in
                            Text("\(ex.subject) • \(ex.mode) • \(huDate(ex.date))").tag(ex.id as String?)
                        }
                    }
                    .pickerStyle(.navigationLink)
                }
            }
            .navigationTitle("Új jegyzetlap")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Mégse") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
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
