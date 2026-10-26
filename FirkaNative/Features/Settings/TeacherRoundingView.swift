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
            Section(footer: Text("Koppints egy tárgyra a kerekítés finomhangolásához. 0,50 = 3,50-től 4-es, 0,80 = csak 3,80-tól 4-es.").skinFont(.caption2).foregroundStyle(.secondary)) {
                if isLoading {
                    ForEach(0..<3, id: \.self) { _ in
                        HStack { Text("Betöltés…").redacted(reason: .placeholder); Spacer() }
                    }
                } else if subjects.isEmpty {
                    Text("Nincs elérhető tantárgy. Jelentkezz be vagy frissíts.").skinFont(.subheadline).foregroundStyle(.secondary)
                } else {
                    ForEach(subjects, id: \.self) { subj in
                        let thr = thresholds[subj] ?? GradingLogic.defaultThreshold
                        SkinNavLink { RoundingDetailView(subject: subj) } label: {
                            HStack {
                                Text(subj).skinFont(.subheadline, weight: .semibold).lineLimit(1)
                                Spacer()
                                Text(String(format: "%.2f", thr))
                                    .font(Self.thresholdFont).monospacedDigit()
                                    .foregroundStyle(theme.isNeon ? AnyShapeStyle(NeonTheme.yellow) : AnyShapeStyle(.secondary))
                            }
                        }
                    }
                }
            }
            .voxelListRowComfy(fill: colors.surface)

            Section {
                Button("Összes visszaállítása (0,50)") {
                    for s in subjects { GradingLogic.setThreshold(GradingLogic.defaultThreshold, for: s) }
                    thresholds = GradingLogic.loadThresholds()
                }
                .tint(.red)
                .roundingResetAllButton()
            } footer: {
                Text("Minden tantárgy kerekítését visszaállítja az alapértelmezett 0,50-re.").skinFont(.caption2).foregroundStyle(.secondary)
            }
            .voxelListRowComfy(fill: colors.surface)
        }
        .listStyle(.insetGrouped)
        .summitListChrome(colors: colors)
        .navigationTitle("Tanári kerekítés")
        .navigationBarTitleDisplayMode(.large)
        .summitToolbarBackground()
        .task { await loadSubjects() }
        .refreshable {
            await loadSubjects(force: true)
            SummitHaptics.light()
        }
        .onAppear { thresholds = GradingLogic.loadThresholds() }
        .onChange(of: session.selectedId) { _, _ in Task { await loadSubjects(force: true) } }
    }

    /// Tárgysor küszöb-értéke: Summitban/Voxelben a korábbi
    /// `skinFont(.caption, weight: .medium)`, Neonban egyenközű kód.
    private static var thresholdFont: Font {
        VoxelTheme.isActive ? VoxelTheme.font(.caption)
            : NeonTheme.isActive ? NeonTheme.mono(size: 12, relativeTo: .caption)
            : Font.system(.caption, weight: .medium)
    }

    private func loadSubjects(force: Bool = false) async {
        // Egy adatsáv: demo usert is a KretaClient szolgálja ki helyből
        // (fetchAllSubjectNames) — a közös cache-be demo módban SOHA nem
        // írunk, különben a demo-tárgyak leakelnek valós módba.
        let isDemo = session.selectedUser?.isDemo == true
        if !force, let cached = UserDefaults.standard.stringArray(forKey: "firka.cachedSubjects.v1"), !cached.isEmpty, !isDemo {
            subjects = cached; isLoading = false
        }
        isLoading = subjects.isEmpty
        guard let user = session.selectedUser else { isLoading = false; return }
        let iss = user.instituteCode.isEmpty ? (JWT.instituteCode(from: user.accessToken) ?? "") : user.instituteCode
        let net = Set(await kreta.fetchAllSubjectNames(iss: iss))
        // A hálózat most halott lehet (átlag-végpontok 500/403, órarend
        // időnként 400, új tanévben 0 jegy) — ilyenkor a helyben tudott
        // tárgyak (cache, kerekítési küszöbök, felmentések) tartják meg a
        // listát, hogy a felmentés mindig beállítható maradjon.
        var collected = net
        if !isDemo {
            collected.formUnion(UserDefaults.standard.stringArray(forKey: "firka.cachedSubjects.v1") ?? [])
        }
        collected.formUnion(GradingLogic.loadThresholds().keys)
        collected.formUnion(ExemptedStore.load())
        let filtered = collected.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty && $0 != "Ismeretlen" }.sorted()
        // Üres hálózati kör nem törölheti a már mutatott listát (GradesView-minta).
        if !filtered.isEmpty || subjects.isEmpty {
            subjects = filtered
        }
        isLoading = false
        if !filtered.isEmpty, !isDemo { UserDefaults.standard.set(filtered, forKey: "firka.cachedSubjects.v1") }
    }
}

private extension View {
    /// „Összes visszaállítása": Neonban vörös (destruktív) CP-gomb,
    /// egyébként a meglévő `voxelInlineButton`.
    @ViewBuilder
    func roundingResetAllButton() -> some View {
        if NeonTheme.isActive {
            self.buttonStyle(NeonButtonStyle(kind: .destructive, compact: true))
        } else {
            self.voxelInlineButton()
        }
    }
}
