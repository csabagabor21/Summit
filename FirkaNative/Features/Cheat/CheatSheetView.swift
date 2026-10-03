import SwiftUI
import UniformTypeIdentifiers
import PDFKit

// MARK: - Jegyzetlap részletező — anyagok + témánkénti jegyzetek
// Több anyag tölthető fel (txt/md/pdf/kép); a "Jegyzet készítése" a
// Meta AI-kulccsal csinál belőlük témánkénti jegyzeteket — a modell
// a TELJES pdf-et (oldalanként képként) és a fotókat is megkapja. Egy téma
// egy jegyzet (cím + szöveg) — nincs mélyebb szint: koppintásra
// egyből a szöveg nyílik, ott szerkeszthető is. Kulcs nélkül is
// teljes értékű kézi jegyzetként.
struct CheatSheetView: View {
    @EnvironmentObject var theme: ThemeStore
    let sheetID: String
    let exams: [ExamItem]
    let subjects: [String]
    /// Sheetként nyitva (órarend-részletező, dolgozat-sor) kell a zárógomb —
    /// különben csak lehúzással csukható. (NavigationLinknél nem kell.)
    let showCloseButton: Bool
    @Environment(\.dismiss) private var dismiss
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
                                MaterialTextView(material: m)
                            } label: {
                                Label("\(m.name) • \(m.isImage ? "kép" : "\(m.text.count) kar.\(m.isPDF ? " + teljes pdf" : "")")", systemImage: m.isImage ? "photo.fill" : "doc.fill")
                                    .font(.subheadline)
                                    .lineLimit(1)
                            }
                        }
                        .onDelete { idx in
                            var c = s
                            let gone = idx.map { c.materials[$0].id }
                            c.materials.remove(atOffsets: idx)
                            persist(c)
                            gone.forEach { CheatStore.removePayload(id: $0) }
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
                        .disabled(generating || s.materials.isEmpty)
                        if !MetaAIKeyStore.hasKey {
                            Text("Saját kulcs nélkül a közös, ingyenes Gemini készíti (gyenge!) — saját Meta AI-kulccsal jobb. Kulcs a Watch-tab tetején adható meg.")
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
                .toolbar {
                    if showCloseButton {
                        // X a sarokban (az ünneplőkártya mintája): swipe
                        // nélkül is egyértelmű a kiút a sheetből.
                        ToolbarItem(placement: .topBarTrailing) {
                            Button { dismiss() } label: {
                                Image(systemName: "xmark")
                                    .font(.system(size: 15, weight: .bold))
                                    .foregroundStyle(.secondary)
                                    .frame(width: 34, height: 34)
                                    .background(Circle().fill(Color.primary.opacity(0.08)))
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Bezárás")
                        }
                    }
                }
                .fileImporter(isPresented: $importing,
                              allowedContentTypes: [.plainText, .pdf, .image],
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
            // Dolgozathoz kötött lapnál a dolgozat szövege is kontextus —
            // ugyanaz a súlyozás, mint az automatikus gyártásnál.
            let ex = exams.first(where: { $0.id == c.examId })
            let context = CheatAutoNote.taskContext(exam: ex, homework: nil)
            let topics = try await MetaAIClient.generateTopics(
                subject: c.subject, title: c.title, materials: c.materials,
                context: context)
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
                let ext = url.pathExtension.lowercased()
                if ["png", "jpg", "jpeg", "heic", "webp", "gif"].contains(ext),
                   let data = try? Data(contentsOf: url),
                   let ui = UIImage(data: data),
                   let jpg = Self.jpeg(ui, maxSide: 2048) {
                    // Kép: a bináris a lemez-tárba, a modell képként kapja.
                    let m = CheatMaterial(name: url.lastPathComponent, text: "", kind: "image")
                    c.materials.append(m)
                    CheatStore.saveFullPayload(id: m.id, text: nil, pdf: nil, image: jpg)
                    added += 1
                } else if ext == "pdf",
                          let data = try? Data(contentsOf: url),
                          let text = Self.readText(from: url), !text.isEmpty {
                    // PDF: az EREDETI bináris + a TELJES szöveg a lemez-tárba
                    // (a UserDefaults/sync továbbra is a vágott 15k-t viszi).
                    let m = CheatMaterial(name: url.lastPathComponent, text: text, kind: "pdf")
                    c.materials.append(m)
                    CheatStore.saveFullPayload(id: m.id, text: text, pdf: data, image: nil)
                    added += 1
                } else if let text = Self.readText(from: url), !text.isEmpty {
                    let m = CheatMaterial(name: url.lastPathComponent, text: text)
                    c.materials.append(m)
                    CheatStore.saveFullPayload(id: m.id, text: text, pdf: nil, image: nil)
                    added += 1
                }
                if c.materials.count >= CheatStore.maxMaterialsPerSheet { break }
            }
            if added == 0 {
                importError = "Egyik fájlból sem sikerült anyagot kiolvasni (txt/md/pdf/kép kell)."
            } else {
                persist(c)
            }
        }
    }

    /// Szövegkinyerés: txt/md sima olvasás, pdf oldalanként (PDFKit).
    /// Direkt TELJES (nincs vágás): a 15k-s vágás csak a tároláskor
    /// (CheatStore.cap) történik, a generálás a lemez-tárból dolgozik.
    static func readText(from url: URL) -> String? {
        if url.pathExtension.lowercased() == "pdf" {
            guard let doc = PDFDocument(url: url) else { return nil }
            var out = ""
            for i in 0..<doc.pageCount {
                if let p = doc.page(at: i)?.string { out += p + "\n" }
            }
            return out.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        // txt, md és társai — több kódolással próbálva.
        if let s = try? String(contentsOf: url, encoding: .utf8), !s.isEmpty { return s }
        if let s = try? String(contentsOf: url, encoding: .isoLatin2), !s.isEmpty { return s }
        if let s = try? String(contentsOf: url, encoding: .windowsCP1250), !s.isEmpty { return s }
        return nil
    }

    /// Kép leskálázása + JPEG: az importált fotók egységes, kicsi alaka.
    static func jpeg(_ ui: UIImage, maxSide: CGFloat) -> Data? {
        let s = max(ui.size.width, ui.size.height)
        let img: UIImage
        if s > maxSide, s > 0 {
            let k = maxSide / s
            let ns = CGSize(width: ui.size.width * k, height: ui.size.height * k)
            let r = UIGraphicsImageRenderer(size: ns)
            img = r.image { _ in ui.draw(in: CGRect(origin: .zero, size: ns)) }
        } else {
            img = ui
        }
        return img.jpegData(compressionQuality: 0.85)
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

// MARK: - Feltöltött anyag olvasója (szöveg vagy kép)
private struct MaterialTextView: View {
    let material: CheatMaterial

    var body: some View {
        ScrollView {
            if material.isImage,
               let data = CheatStore.imageData(id: material.id),
               let ui = UIImage(data: data) {
                Image(uiImage: ui)
                    .resizable()
                    .scaledToFit()
                    .padding()
            } else {
                Text(material.text)
                    .font(.callout)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
            }
        }
        .navigationTitle(material.name)
        .navigationBarTitleDisplayMode(.inline)
    }
}
