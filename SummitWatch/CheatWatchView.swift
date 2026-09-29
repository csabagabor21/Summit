import SwiftUI

// MARK: - Jegyzetek az órán — a telefonos Watch-tab lapjainak tükre
// Dolgozatok listája, koppintásra a témák, azon belül az altémák
// (pl. "Babits Mihály" → "Életrajza"). Felül a "Most" szekció: ha
// az aktuális óra tárgyához van lap, az kerül előre — az órán
// elég lenyitni, nem kell keresgélni. Csak olvasható (a szerkesztés
// a telefonon van), koronával görgethető natív lista.
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
                                    NavigationLink {
                                        CheatSheetTopicsView(sheet: s, topics: topics(of: s.id))
                                    } label: {
                                        WatchCheatRow(sheet: s, topicCount: topics(of: s.id).count, highlight: true)
                                    }
                                }
                            }
                        }
                        if !otherSheets.isEmpty {
                            Section(nowSheets.isEmpty ? "Lapok" : "Többi") {
                                ForEach(otherSheets) { s in
                                    NavigationLink {
                                        CheatSheetTopicsView(sheet: s, topics: topics(of: s.id))
                                    } label: {
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

// MARK: - Dolgozat → témák
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
                        CheatTopicSubsView(topic: t)
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(t.title)
                                .font(.subheadline.weight(.semibold))
                            Text("\(t.subtopics.count) altéma")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 2)
                    }
                }
                .listStyle(.plain)
            }
        }
        .navigationTitle(sheet.title)
    }
}

// MARK: - Téma → altémák (lenyitható törzsekkel)
private struct CheatTopicSubsView: View {
    let topic: WatchCheatTopic
    @State private var expandedIDs = Set<String>()

    var body: some View {
        Group {
            if topic.subtopics.isEmpty {
                ContentUnavailableView(
                    "Még nincs altéma",
                    systemImage: "list.bullet",
                    description: Text("A telefonon bővítsd ezt a témát.")
                )
            } else {
                List(topic.subtopics) { st in
                    let expanded = expandedIDs.contains(st.id)
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 5) {
                            Text(st.title)
                                .font(.subheadline.weight(.semibold))
                            Spacer(minLength: 2)
                            if !st.body.isEmpty {
                                Image(systemName: expanded ? "chevron.up" : "chevron.down")
                                    .font(.caption2.weight(.bold))
                                    .foregroundStyle(.tertiary)
                            }
                        }
                        .contentShape(Rectangle())
                        .onTapGesture {
                            withAnimation {
                                if expanded { expandedIDs.remove(st.id) }
                                else { expandedIDs.insert(st.id) }
                            }
                        }
                        if expanded && !st.body.isEmpty {
                            Text(st.body)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 3)
                }
                .listStyle(.plain)
            }
        }
        .navigationTitle(topic.title)
    }
}
