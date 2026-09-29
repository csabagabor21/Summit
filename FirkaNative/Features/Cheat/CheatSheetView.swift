import SwiftUI
import UniformTypeIdentifiers
import PDFKit

// MARK: - Jegyzetlap részletező — anyagok + témánkénti jegyzetek
// Több anyag tölthető fel (txt/md/pdf); a "Jegyzet készítése" a
// Meta AI-kulccsal csinál belőlük témánkénti jegyzeteket. Egy téma
// egy jegyzet (cím + szöveg) — nincs mélyebb szint: koppintásra
// egyből a szöveg nyílik, ott szerkeszthető is. Kulcs nélkül is
// teljes értékű kézi jegyzetként.
struct CheatSheetView: View {
    @EnvironmentObject var theme: ThemeStore
    let sheetID: String
    let exams: [ExamItem]
    let subjects: [String]
    @State private var sheet: CheatSheet?
    @State private var importing = false
    @State private var importError: String?
    @State private var generating = false
    @State private var genError: String?
    @State private var showingAddTopic = false
    @State private var newTopicTitle = ""
    @State private var editingTopic: CheatTopic?
    @Environment(\.colorScheme) var scheme
    var colors: AppColors { theme.colors(for: scheme) }

    var body: some View {
        Group {
            if let s = sheet {
                List {
                    if let ex = exams.first(where: { $0.id == s.examId }) {
                        Section {
                            Label("\(ex.subject) • \(ex.mode)", systemImage: "doc.text")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(colors.accent)
                            if !ex.plainDescription.isEmpty {
                                Text(ex.plainDescription)
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                    Section {
                        ForEach(s.materials) { m in
                            NavigationLink {
                                MaterialTextView(name: m.name, text: m.text)
                            } label: {
                                Label("\(m.name) • \(m.text.count) kar.", systemImage: "doc.fill")
                                    .font(.subheadline)
                                    .lineLimit(1)
                            }
                        }
                        .onDelete { idx in
                            var c = s
                            c.materials.remove(atOffsets: idx)
                            persist(c)
                        }
                        Button { importing = true } label: {
                            Label("Anyag feltöltése", systemImage: "square.and.arrow.down")
                                .foregroundStyle(colors.accent)
                        }
                        if let err = importError {
                            Text(err).font(.caption).foregroundStyle(.red)
                        }
                    } header: {
                        Text("Feltöltött anyagok • \(s.materials.count) db")
                    }
                    Section {
                        Button {
                            Task { await generate() }
                        } label: {
                            HStack {
                                if generating { ProgressView().scaleEffect(0.8) }
                                Label(generating ? "Készül…" : "Jegyzet készítése AI-jal",
                                      systemImage: "sparkles")
                                    .foregroundStyle(colors.accent)
                            }
                        }
                        .disabled(generating || s.materials.isEmpty || !MetaAIKeyStore.hasKey)
                        if !MetaAIKeyStore.hasKey {
                            Text("Ehhez Meta AI-kulcs kell — a Watch-tab tetején adhatod meg.")
                                .font(.caption).foregroundStyle(.secondary)
                        } else if s.materials.isEmpty {
                            Text("Előbb tölts fel legalább egy anyagot.")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        if let err = genError {
                            Text(err).font(.caption).foregroundStyle(.red)
                        }
                        Button { showingAddTopic = true } label: {
                            Label("Téma kézi felvétele", systemImage: "plus")
                                .foregroundStyle(colors.accent)
                        }
                    } header: {
                        Text("Témák • \(s.topics.count) db")
                    }
                    if !s.topics.isEmpty {
                        Section {
                            ForEach(s.topics) { t in
                                Button { editingTopic = t } label: {
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(t.title)
                                            .font(.subheadline.weight(.semibold))
                                            .foregroundStyle(.primary)
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                        if t.body.isEmpty {
                                            Text("(üres — koppints a szerkesztéshez)")
                                                .font(.caption).foregroundStyle(.tertiary)
                                        } else {
                                            Text(t.body)
                                                .font(.callout).foregroundStyle(.secondary)
                                                .lineLimit(4)
                                                .frame(maxWidth: .infinity, alignment: .leading)
                                        }
                                    }
                                    .padding(.vertical, 2)
                                }
                            }
                            .onDelete { idx in
                                var c = s
                                c.topics.remove(atOffsets: idx)
                                persist(c)
                            }
                        }
                    }
                }
                .navigationTitle(s.title)
                .navigationBarTitleDisplayMode(.large)
                .fileImporter(isPresented: $importing,
                              allowedContentTypes: [.plainText, .pdf],
                              allowsMultipleSelection: true) { result in
                    handleImport(result, into: s)
                }
                .alert("Új téma", isPresented: $showingAddTopic) {
                    TextField("Téma címe (pl. Életrajza)", text: $newTopicTitle)
                    Button("Hozzáadás") {
                        let t = newTopicTitle.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !t.isEmpty else { return }
                        var c = s
                        let nt = CheatTopic(title: t)
                        c.topics.append(nt)
                        newTopicTitle = ""
                        persist(c)
                        editingTopic = nt
                    }
                    Button("Mégse", role: .cancel) { newTopicTitle = "" }
                }
                .sheet(item: $editingTopic) { t in
                    TopicEditView(title: t.title, noteBody: t.body) { nt, nb in
                        guard var c = CheatStore.load().first(where: { $0.id == s.id }),
                              let ti = c.topics.firstIndex(where: { $0.id == t.id }) else { return }
                        c.topics[ti].title = nt
                        c.topics[ti].body = nb
                        persist(c)
                    }
                }
            } else {
                ContentUnavailableView("A lapot törölték", systemImage: "trash")
            }
        }
        .onAppear { sheet = CheatStore.load().first { $0.id == sheetID } }
        .onReceive(NotificationCenter.default.publisher(for: CheatStore.changedNotification)) { _ in
            sheet = CheatStore.load().first { $0.id == sheetID }
        }
    }

    private func persist(_ s: CheatSheet) {
        CheatStore.upsert(s)
        sheet = CheatStore.load().first { $0.id == s.id }
    }

    private func generate() async {
        guard var c = sheet, !generating else { return }
        generating = true
        genError = nil
        defer { generating = false }
        do {
            let topics = try await MetaAIClient.generateTopics(
                subject: c.subject, title: c.title, materials: c.materials)
            c.topics = topics
            persist(c)
        } catch {
            genError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    private func handleImport(_ result: Result<[URL], Error>, into s: CheatSheet) {
        importError = nil
        switch result {
        case .failure(let e):
            importError = "Import-hiba: \(e.localizedDescription)"
        case .success(let urls):
            var c = s
            var added = 0
            for url in urls {
                guard url.startAccessingSecurityScopedResource() else { continue }
                defer { url.stopAccessingSecurityScopedResource() }
                if let text = Self.readText(from: url), !text.isEmpty {
                    c.materials.append(CheatMaterial(name: url.lastPathComponent, text: text))
                    added += 1
                }
                if c.materials.count >= CheatStore.maxMaterialsPerSheet { break }
            }
            if added == 0 {
                importError = "Egyik fájlból sem sikerült szöveget kiolvasni (txt/md/pdf kell)."
            } else {
                persist(c)
            }
        }
    }

    /// Szövegkinyerés: txt/md sima olvasás, pdf oldalanként (PDFKit).
    static func readText(from url: URL) -> String? {
        if url.pathExtension.lowercased() == "pdf" {
            guard let doc = PDFDocument(url: url) else { return nil }
            var out = ""
            for i in 0..<doc.pageCount {
                if let p = doc.page(at: i)?.string { out += p + "\n" }
                if out.count > CheatStore.maxMaterialChars * 2 { break }
            }
            return out.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        // txt, md és társai — több kódolással próbálva.
        if let s = try? String(contentsOf: url, encoding: .utf8), !s.isEmpty { return s }
        if let s = try? String(contentsOf: url, encoding: .isoLatin2), !s.isEmpty { return s }
        if let s = try? String(contentsOf: url, encoding: .windowsCP1250), !s.isEmpty { return s }
        return nil
    }
}

// MARK: - Téma szerkesztő (cím + jegyzetszöveg)
private struct TopicEditView: View {
    @State var title: String
    @State var noteBody: String
    let onSave: (String, String) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section("Cím") { TextField("Téma címe", text: $title) }
                Section("Jegyzet") {
                    TextEditor(text: $noteBody)
                        .frame(minHeight: 220)
                }
            }
            .navigationTitle("Téma szerkesztése")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Mégse") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Kész") {
                        onSave(title.trimmingCharacters(in: .whitespacesAndNewlines), noteBody)
                        dismiss()
                    }
                    .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }
}

// MARK: - Feltöltött anyag olvasója
private struct MaterialTextView: View {
    let name: String
    let text: String

    var body: some View {
        ScrollView {
            Text(text)
                .font(.callout)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
        }
        .navigationTitle(name)
        .navigationBarTitleDisplayMode(.inline)
    }
}
