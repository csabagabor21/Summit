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
    @State private var messages: [MessageItem] = []
    @State private var isLoading = true

    var body: some View {
        NavigationStack {
            List {
                if isLoading {
                    ForEach(0..<3, id: \.self) { _ in
                        HStack { Text("Betöltés…").redacted(reason: .placeholder) }
                            .listRowBackground(colors.surface)
                    }
                } else if messages.isEmpty {
                    Section {
                        ContentUnavailableView("Nincs üzenet", systemImage: "envelope",
                            description: Text("A KRÉTA-postaláda üres."))
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
            }
            .listStyle(.insetGrouped)
            .frame(maxWidth: isPad ? MacSupport.contentWidth(ipad: 1000, mac: 1150) : .infinity)
            .frame(maxWidth: .infinity)
            .scrollContentBackground(.hidden)
            .background(colors.background)
            .navigationTitle("Üzenetek")
            .navigationBarTitleDisplayMode(.large)
            .toolbarBackground(.visible, for: .navigationBar)
            .task { await load() }
            .refreshable { await load() }
        }
        .tint(colors.accent)
    }

    func load() async {
        guard session.selectedUser != nil else { isLoading = false; return }
        isLoading = true
        messages = await kreta.fetchMessages()
        isLoading = false
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
        .frame(maxWidth: .infinity)
        .scrollContentBackground(.hidden)
        .background(colors.background)
        .navigationTitle("Üzenet")
        .navigationBarTitleDisplayMode(.inline)
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
