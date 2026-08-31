import SwiftUI

struct AbsencesView: View {
    @EnvironmentObject var theme: ThemeStore
    @EnvironmentObject var session: SessionStore
    @EnvironmentObject var kreta: KretaClient
    @State private var absences: [AbsenceItem] = []
    @State private var isLoading = true
    @Environment(\.colorScheme) var scheme
    var colors: AppColors { theme.colors(for: scheme) }
    var grouped: [String: [AbsenceItem]] { Dictionary(grouping: absences, by: { $0.subject }) }

    var body: some View {
        NavigationStack {
            List {
                if isLoading {
                    ForEach(0..<3, id: \.self) { _ in Text("").redacted(reason: .placeholder) }
                } else if absences.isEmpty {
                    ContentUnavailableView("Nincs hiányzás", systemImage: "checkmark.shield.fill", description: Text("Szép munka"))
                } else {
                    Section {
                        HStack(spacing: 0) {
                            Stat(value: "\(absences.count)", label: "Összes")
                            Stat(value: "\(absences.filter { $0.type.lowercased().contains("igazolt") }.count)", label: "Igazolt")
                            Stat(value: "\(absences.filter { $0.type.lowercased().contains("igazolatlan") }.count)", label: "Igazolatlan")
                        }
                    }
                    ForEach(grouped.keys.sorted(), id: \.self) { subject in
                        let items = grouped[subject]!
                        Section(header: HStack { Text(subject).font(.subheadline.weight(.semibold)); Spacer(); Text("\(items.count) óra").font(.caption2.weight(.bold)).foregroundStyle(.secondary) }) {
                            ForEach(items.sorted(by: { $0.date > $1.date }).prefix(3)) { a in
                                HStack {
                                    Circle().fill(a.type.lowercased().contains("igazolatlan") ? colors.red : colors.orange).frame(width: 8, height: 8)
                                    Text(a.date.formatted(date: .abbreviated, time: .omitted)).font(.caption).foregroundStyle(.secondary)
                                    Spacer()
                                    Text(a.type).font(.caption.weight(.medium))
                                }
                            }
                            if items.count > 3 { Text("+\(items.count-3) további").font(.caption.weight(.medium)).foregroundStyle(colors.accent) }
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(colors.background)
            .navigationTitle("Hiányzások")
            .navigationBarTitleDisplayMode(.large)
            .toolbarBackground(.visible, for: .navigationBar)
            .task { await load() }
            .refreshable { await load() }
        }
        .tint(colors.accent)
    }
    func load() async {
        guard let user = session.selectedUser, !user.isDemo else { absences=DemoData.absences(); isLoading=false; return }
        isLoading=true; let iss=user.instituteCode.isEmpty ? (JWT.instituteCode(from: user.accessToken) ?? "") : user.instituteCode
        absences = await kreta.fetchAbsences(iss: iss); isLoading=false
    }
}
private struct Stat: View {
    let value: String; let label: String
    var body: some View { VStack(spacing: 2) { Text(value).font(.title3.weight(.bold).monospacedDigit()); Text(label).font(.caption2.weight(.semibold)).foregroundStyle(.secondary).textCase(.uppercase) }.frame(maxWidth: .infinity) }
}
