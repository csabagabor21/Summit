import SwiftUI

// MARK: - Üzenetek (KRÉTA postaláda): lista + részlet törzzsel és csatolmányokkal
//
// A lista a meglévő fetchMessages-kapun jön (demo-ban helyből), a törzs és
// a csatolmányok a részlet-hívásból. Csatolt PDF/más fájl koppintásra
// QuickLook-ban nyílik (demo-ban helyben generált minta-PDF).

struct MessagesView: View {
    @EnvironmentObject var theme: ThemeStore
    @EnvironmentObject var session: SessionStore
    @EnvironmentObject var kreta: KretaClient
    @Environment(\.colorScheme) var scheme
    @Environment(\.horizontalSizeClass) private var hSize
    private var isPad: Bool { hSize == .regular }
    var colors: AppColors { theme.colors(for: scheme) }
    /// Felső váltó: 0 = Üzenetek (postaláda: beérkezett/elküldött/törölt),
    /// 1 = Feljegyzések (KRÉTA-wide elektronikus üzenetek mindenkinek).
    @State private var topTab = 0
    @State private var box: KretaAPI.Mailbox = .incoming
    /// A beérkezett doboz mentett listája a közös gyorstárból — azonnal,
    /// a helyi olvasott-jelölésekkel (a frissítés a háttérben jön).
    @State private var messages: [MessageItem] = MessagesView.storedIncoming()
    @State private var notes: [NoteItem] = []
    @State private var isLoadingMessages = KretaStore.shared.messages == nil

    private static func storedIncoming() -> [MessageItem] {
        let read = Set(UserDefaults.standard.stringArray(forKey: "firka.readMessages.v1") ?? [])
        let list: [MessageItem] = KretaStore.shared.value(.messages) ?? []
        return list.map { read.contains($0.id) ? $0.withRead() : $0 }
    }
    @State private var isLoadingNotes = true
    @State private var expandedNoteIDs: Set<String> = []

    // Tab helyett a Főoldal toolbar-csengőjéből push-olva nyílik —
    // ezért nincs saját NavigationStack-je (a Home adja).
    var body: some View {
        List {
                Section {
                    if theme.isNeon {
                        cpStatusLine
                            .listRowBackground(Color.clear)
                            .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 0, trailing: 16))
                            .listRowSeparator(.hidden)
                    }
                    SkinSegmented(selection: $topTab, options: [
                        SkinOption(value: 0, title: "Üzenetek"), SkinOption(value: 1, title: "Feljegyzések"),
                    ])
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 4, trailing: 16))
                    .listRowSeparator(.hidden)
                    .animation(SummitMotion.gentle, value: topTab)
                }

                if topTab == 0 {
                    Section {
                        SkinSegmented(selection: $box, options: [
                            SkinOption(value: KretaAPI.Mailbox.incoming, title: "Beérkezett"),
                            SkinOption(value: KretaAPI.Mailbox.sent, title: "Elküldött"),
                            SkinOption(value: KretaAPI.Mailbox.trash, title: "Törölt"),
                        ])
                        .listRowBackground(Color.clear)
                        .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 4, trailing: 16))
                        .listRowSeparator(.hidden)
                        .animation(SummitMotion.gentle, value: box)
                        .onChange(of: box) { _, _ in
                            // Dobozváltáskor az előző doboz sorai nem maradhatnak
                            // kint (és nem nyithatók): váz, amíg az új betölt.
                            messages = []
                            isLoadingMessages = true
                            Task { await loadMessages() }
                        }
                    }

                    if isLoadingMessages {
                        ForEach(0..<3, id: \.self) { _ in
                            HStack { Text("Betöltés…").redacted(reason: .placeholder) }
                                .summitRowSurface(colors: colors)
                                .voxelRowChrome()
                        }
                    } else if messages.isEmpty {
                        Section {
                            SkinEmptyState(title: "Nincs üzenet", systemImage: "envelope",
                                description: Text(box == .incoming ? "A beérkezett postaláda üres."
                                    : box == .sent ? "Nincs elküldött üzenet." : "A kuka üres."))
                                .frame(maxWidth: .infinity, minHeight: 220)
                                .padding(.vertical, 16)
                                .listRowBackground(Color.clear)
                                .listRowSeparator(.hidden)
                                .listRowInsets(EdgeInsets(top: 24, leading: 16, bottom: 24, trailing: 16))
                        }
                    } else {
                        Section {
                            ForEach(messages) { m in
                                SkinNavLink {
                                    MessageDetailView(message: m)
                                } label: {
                                    HStack(spacing: 10) {
                                        SkinIcon(m.isRead ? "envelope.open" : "envelope.fill")
                                            .skinFont(.subheadline)
                                            .foregroundStyle(m.isRead ? .secondary : colors.accent)
                                            .frame(width: 24)
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(m.sender).skinFont(.subheadline, weight: .semibold).lineLimit(1)
                                                .cpgContact(unread: !m.isRead)
                                            Text(m.subject).skinFont(.caption).foregroundStyle(.secondary).lineLimit(2)
                                            HStack(spacing: 6) {
                                                Text(theme.isNeon ? cpStamp(m.date) : m.date.formatted(date: .abbreviated, time: .omitted))
                                                    .cpgMono(.caption2, size: 10).foregroundStyle(.tertiary)
                                                if !m.attachments.isEmpty {
                                                    if theme.isNeon {
                                                        NeonLabel("ATT \(m.attachments.count)", color: NeonTheme.cyan)
                                                    } else {
                                                        SkinLabel("\(m.attachments.count)", systemImage: "paperclip")
                                                            .skinFont(.caption2, weight: .medium).foregroundStyle(.secondary)
                                                    }
                                                }
                                            }
                                        }
                                        Spacer(minLength: 4)
                                        if !m.isRead {
                                            if theme.isNeon { NeonLabel("NEW", color: NeonTheme.yellow) }
                                            SkinDot(color: colors.accent, size: 8)
                                        }
                                    }
                                }
                                .cpgThreadRow(unread: !m.isRead)
                            }
                        }
                        .voxelListRowComfy(fill: colors.surface)
                    }
                } else {
                    if isLoadingNotes {
                        ForEach(0..<3, id: \.self) { _ in
                            HStack { Text("Betöltés…").redacted(reason: .placeholder) }
                                .summitRowSurface(colors: colors)
                                .voxelRowChrome()
                        }
                    } else if notes.isEmpty {
                        Section {
                            SkinEmptyState(title: "Nincs feljegyzés", systemImage: "note.text",
                                description: Text("Az iskola nem küldött elektronikus feljegyzést."))
                                .frame(maxWidth: .infinity, minHeight: 220)
                                .padding(.vertical, 16)
                                .listRowBackground(Color.clear)
                                .listRowSeparator(.hidden)
                                .listRowInsets(EdgeInsets(top: 24, leading: 16, bottom: 24, trailing: 16))
                        }
                    } else {
                        Section {
                            ForEach(notes) { n in
                                noteRow(n)
                            }
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .frame(maxWidth: isPad ? MacSupport.contentWidth(ipad: 1280, mac: 1150) : .infinity)
            .padding(.horizontal, MacSupport.sidePadding)
            .frame(maxWidth: .infinity)
            .summitListChrome(colors: colors)
            .navigationTitle("Üzenetek")
            .navigationBarTitleDisplayMode(.large)
            .summitToolbarBackground()
            .task { await loadAll() }
            .refreshable {
                await loadAll(force: true)
                SummitHaptics.light()
            }
            .onChange(of: kreta.readMessageIDs) { _, ids in
                messages = messages.map { ids.contains($0.id) ? $0.withRead() : $0 }
            }
            .tint(colors.accent)
    }

    @ViewBuilder
    private func noteRow(_ n: NoteItem) -> some View {
        let expanded = expandedNoteIDs.contains(n.id)
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(n.title).skinFont(.subheadline, weight: .semibold).lineLimit(expanded ? nil : 2)
                Spacer(minLength: 8)
                Button { toggleNote(n.id, expanded: expanded) } label: {
                    SkinIcon(expanded ? "chevron.up" : "chevron.down")
                        .skinFont(.caption, weight: .semibold).foregroundStyle(.tertiary)
                }
                .buttonStyle(.skinPlain)
            }
            .contentShape(Rectangle())
            .onTapGesture { toggleNote(n.id, expanded: expanded) }
            HStack(spacing: 6) {
                Text(n.displayType).cpgMono(.caption2, size: 10, weight: .semibold)
                    .cpgTag(NeonTheme.coral)
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .skinPill(fill: theme.isNeon ? NeonTheme.coral.opacity(0.10) : colors.accent.opacity(0.14),
                              stroke: theme.isNeon ? NeonTheme.coral.opacity(0.7) : nil)
                if !n.teacher.isEmpty {
                    Text(n.teacher).skinFont(.caption2).foregroundStyle(.secondary).lineLimit(1)
                }
                Text(huDate(n.date))
                    .cpgMono(.caption2, size: 10).foregroundStyle(.tertiary)
            }
            if expanded {
                if n.plainBody.isEmpty {
                    Text("Nincs megjeleníthető szöveg.").skinFont(.callout).foregroundStyle(.tertiary)
                } else {
                    Text(n.plainBody).skinFont(.callout).textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            } else if !n.plainBody.isEmpty {
                Text(n.plainBody).skinFont(.callout).foregroundStyle(.secondary).lineLimit(3)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                    .onTapGesture { toggleNote(n.id, expanded: expanded) }
            }
        }
        .padding(.vertical, 4)
        // Csukott kártyán az egész sor nyit (a típus/tanár/dátum-sor is,
        // ami korábban halott volt); nyitva csak a fejléc csuk, hogy a
        // kijelölhető törzsszövegre koppintás ne zárja be.
        .contentShape(Rectangle())
        .onTapGesture { if !expanded { toggleNote(n.id, expanded: expanded) } }
        .summitRowSurface(colors: colors)
        .voxelRowChrome()
    }

    // Magyar dátum — az eszköz nyelve angol is lehet (a szimulátoron is),
    // a feljegyzés-dátum ezért fix hu_HU formátumú ("2026. szept. 2."),
    // nem a rendszer "2026. Sep 2."-ja.
    private func huDate(_ d: Date) -> String {
        let f = DateFormatter(); f.locale = Locale(identifier: "hu_HU"); f.dateFormat = "yyyy. MMM d."
        return f.string(from: d)
    }

    // MARK: Neon — a játékbeli telefon MESSAGES-appjának fejléce

    /// Apró HUD-státuszsor a szegmensek fölött: rendszer-kód balra, a
    /// darabszámok egyenközű betűvel jobbra. Tabváltáskor egyszer rándul
    /// (a `cpGlitch` Reduce Motion mellett néma).
    private var cpStatusLine: some View {
        let unread = messages.filter { !$0.isRead }.count
        let count = topTab == 0
            ? "\(messages.count) MSG · \(unread) NEW"
            : "\(notes.count) NOTES"
        return HStack(spacing: 8) {
            NeonLabel(topTab == 0 ? "// MESSAGES.SYS" : "// NOTICES.SYS",
                    color: NeonTheme.yellow, bracketed: false)
                .cpGlitch(trigger: topTab)
            Rectangle().fill(NeonTheme.red.opacity(0.35)).frame(height: 1)
            NeonLabel(count, color: NeonTheme.dim, bracketed: false)
                .fixedSize()
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(topTab == 0 ? "\(messages.count) üzenet, \(unread) olvasatlan" : "\(notes.count) feljegyzés")
    }

    /// HUD-időbélyeg a listasorba: `24.10.2026 // 14:02`.
    private func cpStamp(_ d: Date) -> String {
        let f = DateFormatter(); f.locale = Locale(identifier: "hu_HU"); f.dateFormat = "dd.MM.yyyy // HH:mm"
        return f.string(from: d)
    }

    private func toggleNote(_ id: String, expanded: Bool) {
        withAnimation(SummitMotion.snappy) {
            if expanded { expandedNoteIDs.remove(id) } else { expandedNoteIDs.insert(id) }
        }
    }

    private func instituteCode() -> String {
        guard let user = session.selectedUser else { return "" }
        if !user.instituteCode.isEmpty { return user.instituteCode }
        return JWT.instituteCode(from: user.accessToken) ?? ""
    }

    /// Tabváltáskor a `.task` újra lefut — friss gyorstár-találatnál ez
    /// hálózat nélkül tér vissza. A váz csak üres listánál jön; egyébként
    /// a régi üzenetek maradnak, az új dinamikusan beíródik.
    func loadAll(force: Bool = false) async {
        // A postaláda (e-Ügyintézés) és a feljegyzések (intézeti Ellenőrző)
        // két külön host — párhuzamosan, nem egymásra várva.
        async let m: Void = loadMessages(force: force)
        async let n: Void = loadNotes(force: force)
        _ = await (m, n)
    }

    func loadMessages(force: Bool = false) async {
        guard session.selectedUser != nil else { isLoadingMessages = false; return }
        if messages.isEmpty { isLoadingMessages = true }
        let requested = box
        let fetched = await kreta.fetchMessages(box: requested, force: force)
        // Közben másik dobozra váltott: a lassabban beérkező régi válasz
        // nem írhatja felül az újat.
        guard requested == box else { return }
        messages = fetched
        isLoadingMessages = false
    }

    func loadNotes(force: Bool = false) async {
        let iss = instituteCode()
        guard !iss.isEmpty else { isLoadingNotes = false; return }
        if notes.isEmpty { isLoadingNotes = true }
        notes = await kreta.fetchNotes(iss: iss, force: force)
        isLoadingNotes = false
    }
}

private struct MessageDetailView: View {
    let message: MessageItem
    @EnvironmentObject var theme: ThemeStore
    @EnvironmentObject var kreta: KretaClient
    @Environment(\.colorScheme) var scheme
    @Environment(\.horizontalSizeClass) private var hSize
    private var isPad: Bool { hSize == .regular }
    var colors: AppColors { theme.colors(for: scheme) }
    @State private var detail: MessageItem?
    @State private var isLoading = false
    @StateObject private var attStore = AttachmentStore()

    private var shown: MessageItem { detail ?? message }

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    if theme.isNeon {
                        NeonLabel("INCOMING // SECURE CHANNEL", color: NeonTheme.cyan, bracketed: false)
                    }
                    Text(shown.subject)
                        .skinFont(.headline)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    HStack(spacing: 6) {
                        Text(shown.sender).skinFont(.caption, weight: .semibold)
                            .cpgContact(unread: true)
                            .foregroundStyle(.secondary)
                        Text("•").foregroundStyle(.tertiary)
                        Text(shown.date.formatted(date: .abbreviated, time: .shortened))
                            .cpgMono(.caption, size: 11).foregroundStyle(.secondary)
                    }
                    SkinDivider().opacity(0.5)
                    if isLoading && shown.body.isEmpty {
                        Text("Betöltés…").redacted(reason: .placeholder).skinFont(.callout)
                    } else if shown.plainBody.isEmpty {
                        Text("Nincs megjeleníthető szöveg.").skinFont(.callout).foregroundStyle(.tertiary)
                    } else {
                        Text(shown.plainBody).skinFont(.callout).textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .cpgBubble()
                    }
                }
                .padding(.vertical, 4)
            }
            .voxelListRowComfy(fill: colors.surface)
            if !shown.attachments.isEmpty {
                Section {
                    ForEach(shown.attachments) { att in
                        AttachmentRow(att: att, store: attStore)
                    }
                    if let err = attStore.errorText {
                        SkinLabel(err, systemImage: "exclamationmark.triangle.fill")
                            .skinFont(.caption).foregroundStyle(theme.isNeon ? NeonTheme.red : Color.orange)
                    }
                } header: {
                    if theme.isNeon {
                        NeonSectionHeader("Csatolmányok", code: String(format: "%02d", shown.attachments.count), accent: NeonTheme.cyan)
                    } else {
                        Text("Csatolmányok (\(shown.attachments.count))")
                    }
                }
                .voxelListRowComfy(fill: colors.surface)
            }
        }
        .listStyle(.insetGrouped)
        .frame(maxWidth: isPad ? MacSupport.contentWidth(ipad: 1280, mac: 1150) : .infinity)
        .padding(.horizontal, MacSupport.sidePadding)
        .frame(maxWidth: .infinity)
        .summitListChrome(colors: colors)
        .navigationTitle("Üzenet")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            // Megnyitás → olvasott: a lista sora és a főoldali jelvény is
            // azonnal átbillen (a szerver legközelebbi lehúzáskor követ).
            kreta.markMessageRead(message.id)
        }
        .task {
            // A lista demo-ban már hoz törzset; élesben a részlet tölti.
            if message.body.isEmpty && message.attachments.isEmpty {
                isLoading = true
                detail = await kreta.fetchMessageDetail(message)
                isLoading = false
            }
        }
        .sheet(isPresented: $attStore.isPreviewing) {
            if let url = attStore.previewURL {
                QuickLookPreview(url: url)
                    .ignoresSafeArea()
            }
        }
    }
}

// MARK: - Neon-részletek (csak Neon-skinben hatnak)
//
// Egyszintű kapcsolók: Summitban és Voxelben a modifier az eredeti
// láncot adja vissza változatlanul (a `cpgMono` ott a régi `skinFont`).

private extension View {
    /// Egyenközű HUD-betű (dátum, kód, darabszám) Neonban; máshol a
    /// korábbi `skinFont(style, weight:)`.
    @ViewBuilder
    func cpgMono(_ style: Font.TextStyle, size: CGFloat, weight: Font.Weight? = nil) -> some View {
        if NeonTheme.isActive {
            self.font(NeonTheme.mono(size: size, relativeTo: style)).tracking(0.6)
        } else {
            self.skinFont(style, weight: weight)
        }
    }

    /// Feladó mint telefon-kontakt: nagybetűs, ritkított; olvasatlannál a
    /// jellegzetes sárga, olvasottnál a sima HUD-szövegszín.
    @ViewBuilder
    func cpgContact(unread: Bool) -> some View {
        if NeonTheme.isActive {
            self.textCase(.uppercase).tracking(1)
                .foregroundStyle(unread ? NeonTheme.yellow : NeonTheme.text)
        } else {
            self
        }
    }

    /// Kis címke-szöveg színe + nagybetű (pl. feljegyzés-típus) Neonban.
    @ViewBuilder
    func cpgTag(_ color: Color) -> some View {
        if NeonTheme.isActive {
            self.textCase(.uppercase).foregroundStyle(color)
        } else {
            self
        }
    }

    /// Üzenet-szál sora: a panel bal belső élén 2 pt-os jelzősáv — olvasatlan
    /// sárga, olvasott halvány. Overlay, így a sor elrendezése nem változik.
    @ViewBuilder
    func cpgThreadRow(unread: Bool) -> some View {
        if NeonTheme.isActive {
            self.overlay(alignment: .leading) {
                Rectangle()
                    .fill(unread ? NeonTheme.yellow : NeonTheme.dim.opacity(0.35))
                    .frame(width: 2)
                    .padding(.vertical, 2)
                    .offset(x: -12)
                    .accessibilityHidden(true)
            }
        } else {
            self
        }
    }

    /// Bejövő üzenet buborékja: levágott sarkú mély panel, cián bal szegéllyel
    /// — mint a játék telefonjának beszélgetés-nézete.
    @ViewBuilder
    func cpgBubble() -> some View {
        if NeonTheme.isActive {
            let shape = NeonChamferShape(cut: 10, corners: [.topLeft, .bottomRight])
            self.padding(.leading, 14).padding(.trailing, 12).padding(.vertical, 12)
                .background(shape.fill(NeonTheme.bgDeep))
                .overlay(shape.strokeBorder(NeonTheme.cyan.opacity(0.35), lineWidth: 1))
                .overlay(alignment: .leading) {
                    Rectangle().fill(NeonTheme.cyan).frame(width: 2).padding(.vertical, 10)
                        .accessibilityHidden(true)
                }
        } else {
            self
        }
    }
}
