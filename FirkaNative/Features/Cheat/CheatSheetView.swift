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

    init(sheetID: String, exams: [ExamItem], subjects: [String]) {
        self.sheetID = sheetID
        self.exams = exams
        self.subjects = subjects
        // Már a push első képkockáján a lap látsszon — `onAppear`-ből
        // töltve egy pillanatra a „A lapot törölték" állapot villant fel.
        _sheet = State(initialValue: CheatStore.load().first { $0.id == sheetID })
    }

    var body: some View {
        Group {
            if let s = sheet {
                List {
                    if let ex = exams.first(where: { $0.id == s.examId }) {
                        Section {
                            if theme.isCyberpunk {
                                CPLabel("Kapcsolt dolgozat", color: CyberpunkTheme.coral)
                            }
                            SkinLabel("\(ex.subject) • \(ex.mode)", systemImage: "doc.text")
                                .skinFont(.subheadline, weight: .semibold)
                                .skinAccent(theme.isCyberpunk ? CyberpunkTheme.coral : colors.accent)
                            if !ex.plainDescription.isEmpty {
                                Text(ex.plainDescription)
                                    .skinFont(.caption).foregroundStyle(.secondary)
                            }
                        }
                        .mcListRowComfy(fill: colors.surface)
                    }
                    Section {
                        ForEach(s.materials) { m in
                            SkinNavLink {
                                MaterialTextView(material: m)
                            } label: {
                                if theme.isCyberpunk {
                                    cpgMaterialLabel(m)
                                } else {
                                    SkinLabel("\(m.name) • \(m.isImage ? "kép" : "\(m.text.count) kar.\(m.isPDF ? " + teljes pdf" : "")")", systemImage: m.isImage ? "photo.fill" : "doc.fill")
                                        .skinFont(.subheadline)
                                        .lineLimit(1)
                                }
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
                            SkinLabel("Anyag feltöltése", systemImage: "square.and.arrow.down")
                                .skinAccent(colors.accent)
                        }
                        .mcInlineButton()
                        if let err = importError {
                            Text(theme.isCyberpunk ? "ERR // \(err)" : err).cpgMono(.caption, size: 11)
                                .foregroundStyle(theme.isCyberpunk ? CyberpunkTheme.red : Color.red)
                        }
                    } header: {
                        if theme.isCyberpunk {
                            CPSectionHeader("Feltöltött anyagok", code: "\(s.materials.count) db", accent: CyberpunkTheme.cyan)
                        } else {
                            Text("Feltöltött anyagok • \(s.materials.count) db")
                        }
                    }
                    .mcListRowComfy(fill: colors.surface)
                    Section {
                        Button {
                            Task { await generate() }
                        } label: {
                            HStack {
                                if generating { SkinProgress().scaleEffect(0.8) }
                                SkinLabel(generating ? (theme.isCyberpunk ? "Feldolgozás…" : "Készül…") : "Jegyzet készítése AI-jal",
                                      systemImage: "sparkles")
                                    .skinAccent(colors.accent)
                            }
                        }
                        .mcInlineButton(prominent: theme.isCyberpunk)
                        .disabled(generating || s.materials.isEmpty)
                        if !MetaAIKeyStore.hasKey {
                            Text("Saját kulcs nélkül a közös, ingyenes Gemini készíti (gyenge!) — saját Meta AI-kulccsal jobb. Kulcs a Watch-tab tetején adható meg.")
                                .skinFont(.caption).foregroundStyle(.secondary)
                        } else if s.materials.isEmpty {
                            Text("Előbb tölts fel legalább egy anyagot.")
                                .skinFont(.caption).foregroundStyle(.secondary)
                        }
                        if let err = genError {
                            Text(theme.isCyberpunk ? "ERR // \(err)" : err).cpgMono(.caption, size: 11)
                                .foregroundStyle(theme.isCyberpunk ? CyberpunkTheme.red : Color.red)
                        }
                        Button { showingAddTopic = true } label: {
                            SkinLabel("Téma kézi felvétele", systemImage: "plus")
                                .skinAccent(colors.accent)
                        }
                        .mcInlineButton()
                    } header: {
                        if theme.isCyberpunk {
                            CPSectionHeader("Témák", code: "\(s.topics.count) db", accent: CyberpunkTheme.yellow)
                        } else {
                            Text("Témák • \(s.topics.count) db")
                        }
                    }
                    .mcListRowComfy(fill: colors.surface)
                    if !s.topics.isEmpty {
                        Section {
                            ForEach(s.topics) { t in
                                Button { editingTopic = t } label: {
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(t.title)
                                            .skinFont(.subheadline, weight: .semibold)
                                            .foregroundStyle(theme.isCyberpunk ? AnyShapeStyle(CyberpunkTheme.yellow) : AnyShapeStyle(.primary))
                                            .textCase(theme.isCyberpunk ? .uppercase : nil)
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                        if t.body.isEmpty {
                                            Text("(üres — koppints a szerkesztéshez)")
                                                .skinFont(.caption).foregroundStyle(.tertiary)
                                        } else {
                                            Text(t.body)
                                                .skinFont(.callout).foregroundStyle(.secondary)
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
                        .mcListRowComfy(fill: colors.surface)
                    }
                }
                .mcListChrome()
                .navigationTitle(s.title)
                .navigationBarTitleDisplayMode(.large)
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
                SkinEmptyState(title: "A lapot törölték", systemImage: "trash")
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
            // A generálás alatt (akár percekig) feltöltött anyag / átírt cím
            // ne vesszen el: a friss tárolt lapba írjuk a témákat, nem a
            // generálás előtti pillanatképbe.
            // (Ha közben törölték a lapot, nem támasztjuk fel.)
            guard let latest = CheatStore.load().first(where: { $0.id == c.id }) else { return }
            c = latest
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
    @EnvironmentObject var theme: ThemeStore
    @Environment(\.colorScheme) var scheme
    var colors: AppColors { theme.colors(for: scheme) }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Téma címe", text: $title, prompt: skinPrompt("Téma címe")).mcInput()
                } header: {
                    cpgSectionHeader("Cím", code: "01")
                }
                .mcListRowComfy(fill: colors.surface)
                Section {
                    topicEditor
                } header: {
                    cpgSectionHeader("Jegyzet", code: "02")
                }
                .mcListRowComfy(fill: colors.surface)
            }
            .skinFormChrome()
            .navigationTitle("Téma szerkesztése")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                SkinToolbarItem(placement: .cancellationAction) {
                    Button("Mégse") { dismiss() }
                }
                SkinToolbarItem(placement: .confirmationAction) {
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

extension TopicEditView {
    /// Jegyzet-szerkesztő: Minecraftban a játék szövegmező-kerete.
    @ViewBuilder
    fileprivate var topicEditor: some View {
        if MinecraftTheme.isActive || CyberpunkTheme.isActive {
            TextEditor(text: $noteBody)
                .scrollContentBackground(.hidden)
                .frame(minHeight: 220)
                .summitInput()
        } else {
            TextEditor(text: $noteBody)
                .frame(minHeight: 220)
        }
    }
}

// MARK: - Feltöltött anyag olvasója (szöveg vagy kép)
private struct MaterialTextView: View {
    let material: CheatMaterial
    @EnvironmentObject var theme: ThemeStore

    var body: some View {
        ScrollView {
            if material.isImage,
               let data = CheatStore.imageData(id: material.id),
               let ui = UIImage(data: data) {
                Image(uiImage: ui)
                    .resizable()
                    .scaledToFit()
                    .cpgImageFrame()
                    .padding()
            } else {
                Text(material.text)
                    .skinFont(.callout)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
                    .mcMaterialPanel()
            }
        }
        .background {
            if theme.isMinecraft { MinecraftBackdrop(ground: false) }
            else if theme.isCyberpunk { CPBackdrop() }
        }
        .navigationTitle(material.name)
        .navigationBarTitleDisplayMode(.inline)
    }
}

private extension View {
    /// Minecraftban az olvasott szöveg pixel-panelen ül (a háttér égbolt);
    /// Summitban semmi.
    @ViewBuilder
    func mcMaterialPanel() -> some View {
        if MinecraftTheme.isActive { self.minecraftCard().padding(.horizontal, 16) }
        else if CyberpunkTheme.isActive { self.cpPanel(accent: CyberpunkTheme.cyan, padding: nil).padding(.horizontal, 16) }
        else { self }
    }

    @ViewBuilder
    func cpgMono(_ style: Font.TextStyle, size: CGFloat) -> some View {
        if CyberpunkTheme.isActive {
            self.font(CyberpunkTheme.mono(size: size, relativeTo: style)).tracking(0.6)
        } else {
            self.skinFont(style)
        }
    }

    /// Kép-anyag Cyberpunkban: vékony cián, levágott sarkú keret + sarok-
    /// konzolok, mint a játék scanner-nézetében. Máshol semmi.
    @ViewBuilder
    func cpgImageFrame() -> some View {
        if CyberpunkTheme.isActive {
            self.padding(6)
                .overlay(CPChamferShape(cut: 10, corners: [.topLeft, .bottomRight])
                    .strokeBorder(CyberpunkTheme.cyan.opacity(0.6), lineWidth: 1))
                .overlay(alignment: .topTrailing) { CPLabel("SCAN", color: CyberpunkTheme.cyan).padding(8) }
        } else {
            self
        }
    }
}

// MARK: - Cyberpunk-részletek

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

/// Feltöltött anyag sora Cyberpunkban: fájltípus-kód (`[PDF]`, `[IMG]`,
/// `[TXT]`), név, jobbra egyenközű méret — mint egy adat-shard listája.
@ViewBuilder
private func cpgMaterialLabel(_ m: CheatMaterial) -> some View {
    HStack(spacing: 8) {
        CPLabel(m.isImage ? "IMG" : m.isPDF ? "PDF" : "TXT", color: CyberpunkTheme.cyan)
        Text(m.name)
            .font(CyberpunkTheme.font(.subheadline, weight: .semibold))
            .foregroundStyle(CyberpunkTheme.text)
            .lineLimit(1)
        Spacer(minLength: 4)
        if !m.isImage {
            Text("\(m.text.count) CHR")
                .font(CyberpunkTheme.mono(size: 10, relativeTo: .caption2))
                .foregroundStyle(CyberpunkTheme.dim)
                .lineLimit(1)
                .fixedSize()
        }
    }
    .accessibilityElement(children: .combine)
}
