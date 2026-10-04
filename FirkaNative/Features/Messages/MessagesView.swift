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
    @State private var messages: [MessageItem] = []
    @State private var notes: [NoteItem] = []
    @State private var isLoadingMessages = true
    @State private var isLoadingNotes = true
    @State private var expandedNoteIDs: Set<String> = []

    // Tab helyett a Főoldal toolbar-csengőjéből push-olva nyílik —
    // ezért nincs saját NavigationStack-je (a Home adja).
    var body: some View {
        List {
                Section {
                    Picker("", selection: $topTab) {
                        Text("Üzenetek").tag(0); Text("Feljegyzések").tag(1)
                    }
                    .pickerStyle(.segmented)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 4, trailing: 16))
                    .listRowSeparator(.hidden)
                    .animation(SummitMotion.gentle, value: topTab)
                }

                if topTab == 0 {
                    Section {
                        Picker("", selection: $box) {
                            Text("Beérkezett").tag(KretaAPI.Mailbox.incoming)
                            Text("Elküldött").tag(KretaAPI.Mailbox.sent)
                            Text("Törölt").tag(KretaAPI.Mailbox.trash)
                        }
                        .pickerStyle(.segmented)
                        .listRowBackground(Color.clear)
                        .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 4, trailing: 16))
                        .listRowSeparator(.hidden)
                        .animation(SummitMotion.gentle, value: box)
                        .onChange(of: box) { _, _ in Task { await loadMessages() } }
                    }

                    if isLoadingMessages {
                        ForEach(0..<3, id: \.self) { _ in
                            HStack { Text("Betöltés…").redacted(reason: .placeholder) }
                                .summitRowSurface(colors: colors)
                        }
                    } else if messages.isEmpty {
                        Section {
                            ContentUnavailableView("Nincs üzenet", systemImage: "envelope",
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
                                NavigationLink {
                                    MessageDetailView(message: m)
                                } label: {
                                    HStack(spacing: 10) {
                                        Image(systemName: m.isRead ? "envelope.open" : "envelope.fill")
                                            .font(.subheadline)
                                            .foregroundStyle(m.isRead ? .secondary : colors.accent)
                                            .frame(width: 24)
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(m.sender).font(.subheadline.weight(.semibold)).lineLimit(1)
                                            Text(m.subject).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                                            HStack(spacing: 6) {
                                                Text(m.date.formatted(date: .abbreviated, time: .omitted))
                                                    .font(.caption2).foregroundStyle(.tertiary)
                                                if !m.attachments.isEmpty {
                                                    Label("\(m.attachments.count)", systemImage: "paperclip")
                                                        .font(.caption2.weight(.medium)).foregroundStyle(.secondary)
                                                }
                                            }
                                        }
                                        Spacer(minLength: 4)
                                        if !m.isRead {
                                            Circle().fill(colors.accent).frame(width: 8, height: 8)
                                        }
                                    }
                                }
                            }
                        }
                    }
                } else {
                    if isLoadingNotes {
                        ForEach(0..<3, id: \.self) { _ in
                            HStack { Text("Betöltés…").redacted(reason: .placeholder) }
                                .summitRowSurface(colors: colors)
                        }
                    } else if notes.isEmpty {
                        Section {
                            ContentUnavailableView("Nincs feljegyzés", systemImage: "note.text",
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
            .frame(maxWidth: isPad ? MacSupport.contentWidth(ipad: 1000, mac: 1150) : .infinity)
            .padding(.horizontal, MacSupport.sidePadding)
            .frame(maxWidth: .infinity)
            .summitListChrome(colors: colors)
            .navigationTitle("Üzenetek")
            .navigationBarTitleDisplayMode(.large)
            .summitToolbarBackground()
            .task { await loadAll() }
            .refreshable {
                await loadAll()
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
                Text(n.title).font(.subheadline.weight(.semibold)).lineLimit(expanded ? nil : 2)
                Spacer(minLength: 8)
                Button { toggleNote(n.id, expanded: expanded) } label: {
                    Image(systemName: expanded ? "chevron.up" : "chevron.down")
                        .font(.caption.weight(.semibold)).foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
            }
            .contentShape(Rectangle())
            .onTapGesture { toggleNote(n.id, expanded: expanded) }
            HStack(spacing: 6) {
                Text(n.displayType).font(.caption2.weight(.semibold))
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(Capsule().fill(colors.accent.opacity(0.14)))
                if !n.teacher.isEmpty {
                    Text(n.teacher).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                }
                Text(huDate(n.date))
                    .font(.caption2).foregroundStyle(.tertiary)
            }
            if expanded {
                if n.plainBody.isEmpty {
                    Text("Nincs megjeleníthető szöveg.").font(.callout).foregroundStyle(.tertiary)
                } else {
                    Text(n.plainBody).font(.callout).textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            } else if !n.plainBody.isEmpty {
                Text(n.plainBody).font(.callout).foregroundStyle(.secondary).lineLimit(3)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                    .onTapGesture { toggleNote(n.id, expanded: expanded) }
            }
        }
        .padding(.vertical, 4)
        .summitRowSurface(colors: colors)
    }

    // Magyar dátum — az eszköz nyelve angol is lehet (a szimulátoron is),
    // a feljegyzés-dátum ezért fix hu_HU formátumú ("2026. szept. 2."),
    // nem a rendszer "2026. Sep 2."-ja.
    private func huDate(_ d: Date) -> String {
        let f = DateFormatter(); f.locale = Locale(identifier: "hu_HU"); f.dateFormat = "yyyy. MMM d."
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

    func loadAll() async {
        await loadMessages()
        await loadNotes()
    }

    func loadMessages() async {
        guard session.selectedUser != nil else { isLoadingMessages = false; return }
        isLoadingMessages = true
        messages = await kreta.fetchMessages(box: box)
        isLoadingMessages = false
    }

    func loadNotes() async {
        let iss = instituteCode()
        guard !iss.isEmpty else { isLoadingNotes = false; return }
        isLoadingNotes = true
        notes = await kreta.fetchNotes(iss: iss)
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
    @State private var showPreview = false

    private var shown: MessageItem { detail ?? message }

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Text(shown.subject)
                        .font(.headline)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    HStack(spacing: 6) {
                        Text(shown.sender).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                        Text("•").foregroundStyle(.tertiary)
                        Text(shown.date.formatted(date: .abbreviated, time: .shortened))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Divider().opacity(0.5)
                    if isLoading && shown.body.isEmpty {
                        Text("Betöltés…").redacted(reason: .placeholder).font(.callout)
                    } else if shown.plainBody.isEmpty {
                        Text("Nincs megjeleníthető szöveg.").font(.callout).foregroundStyle(.tertiary)
                    } else {
                        Text(shown.plainBody).font(.callout).textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding(.vertical, 4)
            }
            if !shown.attachments.isEmpty {
                Section {
                    ForEach(shown.attachments) { att in
                        AttachmentRow(att: att, store: attStore)
                    }
                    if let err = attStore.errorText {
                        Label(err, systemImage: "exclamationmark.triangle.fill")
                            .font(.caption).foregroundStyle(.orange)
                    }
                } header: {
                    Text("Csatolmányok (\(shown.attachments.count))")
                }
            }
        }
        .listStyle(.insetGrouped)
        .frame(maxWidth: isPad ? MacSupport.contentWidth(ipad: 1000, mac: 1150) : .infinity)
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
        .sheet(isPresented: $showPreview) {
            if let url = attStore.previewURL {
                QuickLookPreview(url: url)
                    .ignoresSafeArea()
            }
        }
        .onChange(of: attStore.previewURL) { _, new in
            showPreview = new != nil
        }
    }
}
