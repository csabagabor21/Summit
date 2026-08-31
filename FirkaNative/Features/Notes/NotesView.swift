import SwiftUI

struct NotesView: View {
    @EnvironmentObject var theme: ThemeStore
    @EnvironmentObject var session: SessionStore
    @EnvironmentObject var kreta: KretaClient
    @EnvironmentObject var completed: CompletedStore
    @State private var homeworks: [HomeworkItem] = []
    @State private var isLoading = true
    @State private var filter = 0
    @Environment(\.colorScheme) var scheme
    var colors: AppColors { theme.colors(for: scheme) }

    var body: some View {
        NavigationStack {
            List {
                Picker("", selection: $filter) {
                    Text("Mind").tag(0); Text("Határidős").tag(1); Text("Kész").tag(2)
                }
                .pickerStyle(.segmented)
                .listRowBackground(Color.clear).listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 4, trailing: 16)).listRowSeparator(.hidden)

                if isLoading {
                    ForEach(0..<3, id: \.self) { _ in Text("").redacted(reason: .placeholder) }
                } else if filtered.isEmpty {
                    ContentUnavailableView("Nincs feladat", systemImage: "checklist", description: Text("Minden kész"))
                } else {
                    ForEach(filtered) { hw in
                        let done = completed.isHomeworkDone(hw.id) || hw.isDone
                        HStack(spacing: 10) {
                            Button { withAnimation(.spring(response: 0.3)) { completed.toggleHomework(hw.id) } } label: {
                                Image(systemName: done ? "checkmark.circle.fill" : "circle")
                                    .font(.system(size: 22))
                                    .foregroundStyle(done ? Color.green : .secondary)
                            }
                            .buttonStyle(.plain)
                            VStack(alignment: .leading, spacing: 6) {
                                HStack { Text(hw.subject).font(.subheadline.weight(.semibold)); Spacer(); Text(hw.deadline.formatted(date: .abbreviated, time: .omitted)).font(.caption2).foregroundStyle(.secondary).padding(.horizontal, 8).padding(.vertical, 4).background(Capsule().fill(Color.primary.opacity(0.06))) }
                                Text(hw.title.isEmpty ? "(nincs leírás)" : hw.title).font(.callout).foregroundStyle(.secondary).lineLimit(3)
                            }
                        }
                        .listRowBackground(done ? Color.green.opacity(scheme == .dark ? 0.10 : 0.07) : Color.clear)
                    }
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(colors.background)
            .navigationTitle("Feladatok")
            .navigationBarTitleDisplayMode(.large)
            .toolbarBackground(.visible, for: .navigationBar)
            .task { await load() }
            .refreshable { await load() }
        }
        .tint(colors.accent)
    }

    var filtered: [HomeworkItem] {
        let base: [HomeworkItem]
        switch filter {
        case 1: base = homeworks.filter { $0.deadline > Date() && !completed.isHomeworkDone($0.id) }.sorted { $0.deadline < $1.deadline }
        case 2: base = homeworks.filter { completed.isHomeworkDone($0.id) || $0.isDone }.sorted { $0.deadline < $1.deadline }
        default:
            // "Mind" — kipipált ne jelenjen meg (eltűnik a Feladatok tabról), Home-on marad zölden
            base = homeworks.filter { !completed.isHomeworkDone($0.id) }.sorted { $0.deadline < $1.deadline }
        }
        return base
    }
    func load() async {
        guard let user = session.selectedUser, !user.isDemo else { homeworks=DemoData.homeworks(); isLoading=false; return }
        isLoading=true; let iss=user.instituteCode.isEmpty ? (JWT.instituteCode(from: user.accessToken) ?? "") : user.instituteCode
        homeworks = await kreta.fetchHomework(iss: iss); isLoading=false
    }
}
