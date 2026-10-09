import SwiftUI

// MARK: - Jegyzetek az órán — a telefonos Watch-tab lapjainak tükre
// Dolgozatok listája, koppintásra a témák — egy téma egy jegyzet
// (cím + lenyitható szöveg), mélyebb szint nincs. Felül a "Most"
// szekció: ha az aktuális óra tárgyához van lap, az kerül előre —
// az órán elég lenyitni, nem kell keresgélni. Csak olvasható
// (a szerkesztés a telefonon van), koronával görgethető natív lista.
struct CheatWatchView: View {
    @EnvironmentObject var store: WatchSyncStore

    private var sheets: [WatchCheatSheet] {
        store.cheat?.sheets.sorted { $0.subject < $1.subject } ?? []
    }

    private func topics(of sheetID: String) -> [WatchCheatTopic] {
        store.cheat?.topics[sheetID] ?? []
    }

    /// Aktuális óra tárgya (az órarend-snapshotból, fejlesztői
    /// idő-eltolással is számolva) — az ehhez passzoló lapoké a "Most".
    private func currentSubject(now: Date) -> String? {
        let day = Calendar.current.startOfDay(for: now)
        return store.timetable?.lessons.first {
            Calendar.current.isDate($0.start, inSameDayAs: day)
            && $0.start <= now && now < $0.end
        }?.subject
    }

    private func isNowSheet(_ s: WatchCheatSheet, nowSubject: String?) -> Bool {
        guard let n = nowSubject else { return false }
        return SubjectMatcher.same(s.subject, n)
    }

    var body: some View {
        // NavigationStack nélkül a sorok koppintása nem nyit új lapot
        // (GradesWatchView-minta, érték-alapú linkekkel).
        NavigationStack {
        TimelineView(.periodic(from: Date(), by: 60)) { timeline in
            let now = store.previewNow ?? timeline.date
            let nowSubject = currentSubject(now: now)
            let nowSheets = sheets.filter { isNowSheet($0, nowSubject: nowSubject) }
            let otherSheets = sheets.filter { !isNowSheet($0, nowSubject: nowSubject) }
            Group {
                if sheets.isEmpty {
                    ContentUnavailableView(
                        "Nincs jegyzet",
                        systemImage: "applewatch",
                        description: Text("Vegyél fel lapot iPhone-on, a Watch-tabon.")
                    )
                } else {
                    List {
                        if let err = store.lastSyncError {
                            Section {
                                Text(err)
                                    .font(.caption2)
                                    .foregroundStyle(.orange)
                            }
                        }
                        if !nowSheets.isEmpty {
                            Section("Most") {
                                ForEach(nowSheets) { s in
                                    NavigationLink(value: s.id) {
                                        WatchCheatRow(sheet: s, topicCount: topics(of: s.id).count, highlight: true)
                                    }
                                }
                            }
                        }
                        if !otherSheets.isEmpty {
                            Section(nowSheets.isEmpty ? "Lapok" : "Többi") {
                                ForEach(otherSheets) { s in
                                    NavigationLink(value: s.id) {
                                        WatchCheatRow(sheet: s, topicCount: topics(of: s.id).count, highlight: false)
                                    }
                                }
                            }
                        }
                    }
                    .listStyle(.plain)
                    .refreshable { await store.requestSyncNow() }
                }
            }
            .navigationTitle("Jegyzet")
            }
            .navigationDestination(for: String.self) { sheetID in
                if let s = sheets.first(where: { $0.id == sheetID }) {
                    CheatSheetTopicsView(sheet: s, topics: topics(of: s.id))
                }
            }
        }
    }
}

// MARK: - Lap-sor — becsukva tárgy + cím + témaszám
private struct WatchCheatRow: View {
    let sheet: WatchCheatSheet
    let topicCount: Int
    let highlight: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 9) {
            Image(systemName: "doc.text.fill")
                .font(.subheadline)
                .foregroundStyle(highlight ? .green : .blue)
                .padding(.top, 2)
            VStack(alignment: .leading, spacing: 2) {
                Text(sheet.subject)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                Text(sheet.title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                Text(topicCount == 0 ? "még nincs téma" : "\(topicCount) téma")
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(highlight ? .green : .secondary)
                    .lineLimit(1)
            }
        }
        .padding(.vertical, 3)
    }
}

// MARK: - Dolgozat → témák (koppintásra fullscreen jegyzet)
private struct CheatSheetTopicsView: View {
    let sheet: WatchCheatSheet
    let topics: [WatchCheatTopic]

    var body: some View {
        Group {
            if topics.isEmpty {
                ContentUnavailableView(
                    "Még nincs téma",
                    systemImage: "list.bullet",
                    description: Text("A telefonon generálj jegyzetet ehhez a laphoz.")
                )
            } else {
                List(topics) { t in
                    NavigationLink {
                        CheatTopicDetailView(topic: t)
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(t.title)
                                .font(.subheadline.weight(.semibold))
                            if t.body.isEmpty {
                                Text("(üres)")
                                    .font(.caption2)
                                    .foregroundStyle(.tertiary)
                            } else {
                                Text("Megnyitás")
                                    .font(.caption2)
                                    .foregroundStyle(.tertiary)
                            }
                        }
                        .padding(.vertical, 3)
                    }
                }
                .listStyle(.plain)
            }
        }
        .navigationTitle(sheet.title)
    }
}

// MARK: - Jegyzet fullscreen — OLED-fekete, Markdown-tagolással
// A body Markdown-forrás (AI generálja: ## címek, listák, kiemelések),
// ezért nem nyersen, hanem parsolva rajzoljuk — különben "##" látszana.
// Görgetés: korona + dupla koppintás (laponként lejjebb, a végén
// vissza a tetejére) — a kis kijelzőn a korona egyedül lassú.
private struct CheatTopicDetailView: View {
    let topic: WatchCheatTopic
    /// Dupla koppintás lapozó-pozíciója (bekezdés-index).
    @State private var pageIndex = 0

    /// Bekezdések külön tömbben: a Markdown bekezdés-távolsága az órán
    /// nem ad látható lukat, ezért minden bekezdés saját Text fix
    /// térközzel — a formázás (félkövér, címsor, lista) bekezdésenként
    /// parsolva megmarad.
    private var paragraphs: [Para] {
        splitMarkdownParagraphs(topic.body).map { Para(raw: $0) }
    }

    private var isEmpty: Bool {
        topic.body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            ScrollViewReader { proxy in
                ScrollView {
                    if isEmpty {
                        Text("(üres)")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                    } else {
                        VStack(alignment: .leading, spacing: 10) {
                            // Stabil index-ID-k: a Para.id minden
                            // kiértékeléskor új UUID lenne, arra nem
                            // lehet görgetni.
                            ForEach(paragraphs.indices, id: \.self) { i in
                                Text(paragraphs[i].rendered)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .id(i)
                            }
                            Text("Dupla koppintás: lapozás")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                                .frame(maxWidth: .infinity, alignment: .center)
                                .padding(.top, 6)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                    }
                }
                // Dupla koppintás = lapozás lefelé (a végén vissza a
                // tetejére). A user saját koppintása, ezért halk tick jár.
                .onTapGesture(count: 2) {
                    guard !isEmpty, !paragraphs.isEmpty else { return }
                    WatchHaptics.tick()
                    let next = pageIndex + 3
                    pageIndex = next >= paragraphs.count ? 0 : next
                    withAnimation { proxy.scrollTo(pageIndex, anchor: .top) }
                }
            }
        }
        .navigationTitle(topic.title)
        .containerBackground(.black, for: .navigation)
    }
}

/// Egy bekezdés + Markdown-renderelése (bekezdésenként parsolva, így a
/// soron belüli formázás megmarad; hibás Markdownnál nyers szöveg).
private struct Para: Identifiable, Hashable {
    let id = UUID()
    let raw: String
    var rendered: AttributedString {
        (try? AttributedString(markdown: raw)) ?? AttributedString(raw)
    }
}


