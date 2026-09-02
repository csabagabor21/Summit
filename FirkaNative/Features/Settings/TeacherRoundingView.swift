import SwiftUI

struct TeacherRoundingView: View {
    @EnvironmentObject var theme: ThemeStore
    @EnvironmentObject var kreta: KretaClient
    @EnvironmentObject var session: SessionStore
    @Environment(\.colorScheme) var scheme
    var colors: AppColors { theme.colors(for: scheme) }

    @State private var thresholds: [String: Double] = GradingLogic.loadThresholds()
    @State private var subjects: [String] = []
    @State private var isLoading = true

    var body: some View {
        List {
            Section(footer: Text("Koppints egy tárgyra a kerekítés finomhangolásához. 0,50 = 3,50-től 4-es, 0,80 = csak 3,80-tól 4-es.").font(.caption2).foregroundStyle(.secondary)) {
                if isLoading {
                    ForEach(0..<3, id: \.self) { _ in
                        HStack { Text("Betöltés…").redacted(reason: .placeholder); Spacer() }
                    }
                } else if subjects.isEmpty {
                    Text("Nincs elérhető tantárgy. Jelentkezz be vagy frissíts.").font(.subheadline).foregroundStyle(.secondary)
                } else {
                    ForEach(subjects, id: \.self) { subj in
                        let thr = thresholds[subj] ?? GradingLogic.defaultThreshold
                        NavigationLink { RoundingDetailView(subject: subj) } label: {
                            HStack {
                                Text(subj).font(.subheadline.weight(.semibold)).lineLimit(1)
                                Spacer()
                                Text(String(format: "%.2f", thr))
                                    .font(.caption.monospacedDigit().weight(.medium))
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }

            Section {
                Button("Összes visszaállítása (0,50)") {
                    for s in subjects { GradingLogic.setThreshold(GradingLogic.defaultThreshold, for: s) }
                    thresholds = GradingLogic.loadThresholds()
                }
                .tint(.red)
            } footer: {
                Text("Minden tantárgy kerekítését visszaállítja az alapértelmezett 0,50-re.").font(.caption2).foregroundStyle(.secondary)
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(colors.background)
        .navigationTitle("Tanári kerekítés")
        .navigationBarTitleDisplayMode(.large)
        .toolbarBackground(.visible, for: .navigationBar)
        .task { await loadSubjects() }
        .refreshable { await loadSubjects(force: true) }
        .onAppear { thresholds = GradingLogic.loadThresholds() }
        .onChange(of: session.selectedId) { _, _ in Task { await loadSubjects(force: true) } }
    }

    private func loadSubjects(force: Bool = false) async {
        if !force, let cached = UserDefaults.standard.stringArray(forKey: "firka.cachedSubjects.v1"), !cached.isEmpty, session.selectedUser?.isDemo == false {
            subjects = cached; isLoading = false
        } else if !force, session.selectedUser?.isDemo == true {
            let s = Set(DemoData.gradesExpanded().map(\.subject))
            subjects = s.sorted(); isLoading = false
            return
        }
        isLoading = subjects.isEmpty
        var collected = Set<String>()
        collected.formUnion(GradingLogic.loadThresholds().keys)
        if let cached = UserDefaults.standard.stringArray(forKey: "firka.cachedSubjects.v1") { collected.formUnion(cached) }

        if session.selectedUser?.isDemo == true {
            collected.formUnion(DemoData.gradesExpanded().map(\.subject))
            collected.formUnion(DemoData.lessonsToday().map(\.subject))
        } else if let user = session.selectedUser {
            let iss = user.instituteCode.isEmpty ? (JWT.instituteCode(from: user.accessToken) ?? "") : user.instituteCode
            if !iss.isEmpty {
                let grades = await kreta.fetchGrades(iss: iss)
                collected.formUnion(grades.map(\.subject))
                let start = Calendar.current.date(byAdding: .day, value: -14, to: Date())!
                let end = Calendar.current.date(byAdding: .day, value: 14, to: Date())!
                let lessons = await kreta.fetchTimetable(iss: iss, from: start, to: end)
                collected.formUnion(lessons.map(\.subject))
            }
        } else {
            collected.formUnion(DemoData.gradesExpanded().map(\.subject))
        }
        let filtered = collected.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty && $0 != "Ismeretlen" }.sorted()
        subjects = filtered
        isLoading = false
        if !filtered.isEmpty { UserDefaults.standard.set(filtered, forKey: "firka.cachedSubjects.v1") }
    }
}
