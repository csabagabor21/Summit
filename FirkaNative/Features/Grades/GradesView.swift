import SwiftUI

enum GradeTab: String, CaseIterable, Identifiable {
    case evkozi = "Évközi"
    case felevi = "Félévi"
    case evvegi = "Év végi"
    var id: String { rawValue }
}

/// Jegy nélküli tantárgy jelvénye: Summitban üres karika, Voxelben
/// üres inventory-slot (a játék szürke rekesze) kötőjellel, Neonban
/// szaggatott, levágott sarkú üres HUD-foglalat.
private struct EmptySubjectBadge: View {
    let scheme: ColorScheme
    var body: some View {
        ZStack {
            if VoxelTheme.isActive {
                VoxelInventorySlot().frame(width: 44, height: 44)
            } else if NeonTheme.isActive {
                NeonChamferShape(cut: 44 * 0.22, corners: [.topLeft, .bottomRight])
                    .fill(NeonTheme.bg)
                    .overlay(NeonChamferShape(cut: 44 * 0.22, corners: [.topLeft, .bottomRight])
                        .strokeBorder(NeonTheme.dim.opacity(0.55), style: StrokeStyle(lineWidth: 1, dash: [3, 3])))
                    .frame(width: 44, height: 44)
            } else {
                Circle().fill(Color.clear)
                    .overlay(Circle().strokeBorder(Color.primary.opacity(scheme == .dark ? 0.14 : 0.10), lineWidth: 1.2))
                    .frame(width: 44, height: 44)
            }
            Text("—").voxelDisplay(18).foregroundStyle(.tertiary)
        }.frame(width: 44, height: 44)
    }
}

struct GradesView: View {
    @EnvironmentObject var theme: ThemeStore
    @EnvironmentObject var session: SessionStore
    @EnvironmentObject var kreta: KretaClient
    /// Jegyek + tárgylista a közös gyorstárból (KretaStore). `@StateObject`:
    /// a kezdőérték EGYSZER olvasódik be (tabra lépéskor azonnal látszik a
    /// mentett adat), és nem a MainTabView body-jában — így a store minden
    /// írása nem értékeli újra a teljes tab-fát (lásd `GradesModel`).
    @StateObject private var model = GradesModel()
    private var grades: [GradeItem] { model.grades }
    private var allSubjects: [String] { model.subjects }
    private var isLoading: Bool { model.isLoading }
    @State private var selectedTab: GradeTab = .evkozi
    // Explicit path: adat-újratöltéskor a value-less linkek állapota átsiklott
    // sorok között, a vissza gomb így végigment a tárgyakon. Path-szal egy pop = egy szint.
    @State private var path = NavigationPath()
    @Environment(\.colorScheme) var scheme
    @Environment(\.horizontalSizeClass) private var hSize
    private var isPad: Bool { hSize == .regular }
    var colors: AppColors { theme.colors(for: scheme) }

    var body: some View {
        NavigationStack(path: $path) {
            List {
                // Tabs — csak ha van félévi, különben teljesen rejtve
                if !isLoading && !feleviGrades.isEmpty {
                    Section {
                        // Egyedi binding: csak user-koppintásra tick —
                        // az üres tabra való visszaugrás (onChange) néma.
                        SkinSegmentedPicker(selection: Binding(
                            get: { selectedTab },
                            set: { if $0 != selectedTab { SummitHaptics.selection() }; selectedTab = $0 }
                        ), options: gradeTabOptions)
                        .listRowBackground(Color.clear)
                        .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 4, trailing: 16))
                        .listRowSeparator(.hidden)
                        .animation(SummitMotion.snappy, value: selectedTab)
                    }
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }

                if isLoading {
                    ForEach(0..<3, id: \.self) { _ in Text("Betöltés…").redacted(reason: .placeholder).voxelListRow(fill: colors.surface) }
                } else {
                    Group {
                        switch selectedTab {
                    case .evkozi:
                        if displayEvkoziSubjects.isEmpty {
                            SkinEmptyState(title: "Nincs tantárgy", systemImage: "books.vertical", description: Text("Még nincs felvett tantárgy.")).voxelListRow(fill: colors.surface)
                        } else {
                            // Átlag + grafikon — mindig látszik, akkor is ha nincs jegy (üres állapot)
                            Section {
                                HStack(alignment: .lastTextBaseline, spacing: 16) {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text("ÖSSZÁTLAG").gradeSummaryLabel()
                                        Text(groupedEvkozi.isEmpty ? "—" : String(format: "%.2f", overallEvkozi)).voxelDisplay(34).cpHero(NeonTheme.yellow)
                                    }
                                    Spacer()
                                    VStack(alignment: .trailing, spacing: 2) {
                                        Text("KEREKÍTVE").gradeSummaryLabel()
                                        Text(groupedEvkozi.isEmpty ? "—" : String(format: "%.2f", overallRoundedEvkozi)).voxelDisplay(34).cpHero(NeonTheme.cyanBright, chromatic: false)
                                    }
                                }
                                .voxelSummaryRow(fill: colors.surface)
                            }
                            Section {
                                GradeChartView(grades: derived.evkoziChart, accent: colors.accent, height: 150, monthly: true, editorial: true)
                                    .listRowBackground(Color.clear)
                                    .listRowSeparator(.hidden)
                                    .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
                            } header: { Text("Átlag alakulása — havi").voxelSectionHeader() }
                            // iPad: adaptív rács — a sáv szélességétől függően
                            // 2–3 oszlop, kihasználja a szélességet.
                            // Gomb + path-reset NavigationLink helyett: a link
                            // rendszer-chevronje a kártyán KÍVÜL is megjelent
                            // (dupla chevron), és a stack néha többedikre állt
                            // (vissza végigment az előző tárgyakon). Így egy
                            // koppintás = egy szint, vissza egyből a listára —
                            // chevron csak a kártyán belül marad.
                            if isPad {
                                let subjects = displayEvkoziSubjects
                                let cols = [GridItem(.adaptive(minimum: 330), spacing: 12)]
                                LazyVGrid(columns: cols, spacing: 12) {
                                    ForEach(subjects, id: \.self) { subject in
                                        if let items = groupedEvkozi[subject] {
                                            let raw = GradingLogic.weightedAverage(items)
                                            let thr = GradingLogic.threshold(for: subject)
                                            let rnd = GradingLogic.roundedGrade(raw: raw, threshold: thr)
                                            Button {
                                                openSubject(subject)
                                            } label: {
                                                HStack(spacing: 12) {
                                                    GradeCircle(value: rnd, size: 44)
                                                    VStack(alignment: .leading, spacing: 3) { Text(subject).skinFont(.subheadline, weight: .semibold).lineLimit(1); Text(String(format: "%.2f • %d jegy", raw, items.count)).skinFont(.caption2).foregroundStyle(.secondary).lineLimit(1) }
                                                    Spacer()
                                                    SkinIcon("chevron.right", size: 14).skinFont(.caption2, weight: .semibold).foregroundStyle(.tertiary)
                                                }.padding(12).background(VoxelCardBackground(fill: colors.surface, cornerRadius: 14)).contentShape(Rectangle())
                                            }.buttonStyle(.skinPlain)
                                        } else {
                                            Button {
                                                openSubject(subject)
                                            } label: {
                                                HStack(spacing: 12) {
                                                    EmptySubjectBadge(scheme: scheme)
                                                    VStack(alignment: .leading, spacing: 3) { Text(subject).skinFont(.subheadline, weight: .semibold).lineLimit(1); Text("Nincs jegy").skinFont(.caption2).foregroundStyle(.tertiary).lineLimit(1) }
                                                    Spacer()
                                                    SkinIcon("chevron.right", size: 14).skinFont(.caption2, weight: .semibold).foregroundStyle(.tertiary)
                                                }.padding(12).background(VoxelCardBackground(fill: colors.surface, cornerRadius: 14)).contentShape(Rectangle())
                                            }.buttonStyle(.skinPlain)
                                        }
                                    }
                                }.padding(.horizontal, 16).padding(.vertical, 8)
                                // A rács a saját kártyáit rajzolja: nincs mögötte
                                // rendszer-sorháttér / elválasztó.
                                .listRowBackground(Color.clear)
                                .listRowInsets(EdgeInsets())
                                .listRowSeparator(.hidden)
                            } else {
                            ForEach(displayEvkoziSubjects, id: \.self) { subject in
                                if let items = groupedEvkozi[subject] {
                                    let raw = GradingLogic.weightedAverage(items)
                                    let thr = GradingLogic.threshold(for: subject)
                                    let rnd = GradingLogic.roundedGrade(raw: raw, threshold: thr)
                                    subjectRow(subject) {
                                        HStack(spacing: 12) {
                                            GradeCircle(value: rnd, size: 44)
                                            VStack(alignment: .leading, spacing: 3) {
                                                Text(subject).skinFont(.subheadline, weight: .semibold).lineLimit(1)
                                                Text(String(format: "%.2f • %d jegy • kerekítés %.2f-től", raw, items.count, thr)).skinFont(.caption2).foregroundStyle(.secondary).lineLimit(1)
                                            }
                                            Spacer()
                                        }.padding(.vertical, 2)
                                    }
                                    .subjectRowChrome(fill: colors.surface)
                                } else {
                                    // Nincs még jegy — KRÉTA tudja a tantárgyat, üresen mutatjuk
                                    subjectRow(subject) {
                                        HStack(spacing: 12) {
                                            EmptySubjectBadge(scheme: scheme)
                                            VStack(alignment: .leading, spacing: 3) {
                                                Text(subject).skinFont(.subheadline, weight: .semibold).lineLimit(1)
                                                Text("Nincs jegy").skinFont(.caption2).foregroundStyle(.tertiary).lineLimit(1)
                                            }
                                            Spacer()
                                        }.padding(.vertical, 2)
                                    }
                                    .subjectRowChrome(fill: colors.surface)
                                }
                            }
                            }
                            Section {
                                let gradedCount = groupedEvkozi.count
                                let totalCount = displayEvkoziSubjects.count
                                if gradedCount == totalCount {
                                    Text("\(evkoziGrades.count) jegy • \(gradedCount) tárgy").gradeFooterText().frame(maxWidth: .infinity, alignment: .center).multilineTextAlignment(.center)
                                } else {
                                    Text("\(evkoziGrades.count) jegy • \(gradedCount)/\(totalCount) tárgy értékelve").gradeFooterText().frame(maxWidth: .infinity, alignment: .center).multilineTextAlignment(.center)
                                }
                            }
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                        }
                    case .felevi:
                        if feleviGrades.isEmpty {
                            SkinEmptyState(title: "Nincs félévi jegy", systemImage: "star.slash", description: Text("Még nem érkezett félévi értékelés.")).voxelListRow(fill: colors.surface)
                        } else {
                            Section {
                                HStack(alignment: .firstTextBaseline) {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text("FÉLÉVI ÁTLAG").gradeSummaryLabel()
                                        Text(String(format: "%.2f", overallFelevi)).voxelDisplay(34).cpHero(NeonTheme.yellow)
                                    }
                                    Spacer()
                                }
                                .voxelSummaryRow(fill: colors.surface)
                            }
                            ForEach(groupedFelevi.keys.sorted(), id: \.self) { subject in
                                let items = groupedFelevi[subject]!
                                let latest = items.sorted { $0.date > $1.date }.first!
                                HStack(spacing: 12) {
                                    GradeCircle(value: latest.value, size: 44)
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(subject).skinFont(.subheadline, weight: .semibold).lineLimit(1)
                                        Text("Félévkor \(latest.value)-es lettél").skinFont(.caption).foregroundStyle(.secondary).lineLimit(1)
                                        Text(latest.date.formatted(date: .abbreviated, time: .omitted)).skinFont(.caption2).foregroundStyle(.tertiary)
                                    }
                                    Spacer()
                                }
                                .padding(.vertical, 2)
                                .listRowInsets(VoxelTheme.rowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16)))
                                .voxelListRow(fill: colors.surface)
                            }
                            Section {
                                Text("\(feleviGrades.count) jegy • \(groupedFelevi.count) tárgy").gradeFooterText().frame(maxWidth: .infinity, alignment: .center).multilineTextAlignment(.center)
                            }
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                        }
                    case .evvegi:
                        if evvegiGrades.isEmpty {
                            SkinEmptyState(title: "Nincs év végi jegy", systemImage: "star.slash", description: Text("Még nem érkezett év végi értékelés.")).voxelListRow(fill: colors.surface)
                        } else {
                            Section {
                                HStack(alignment: .firstTextBaseline) {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text("ÉV VÉGI ÁTLAG").gradeSummaryLabel()
                                        Text(String(format: "%.2f", overallEvvegi)).voxelDisplay(34).cpHero(NeonTheme.yellow)
                                    }
                                    Spacer()
                                }
                                .voxelSummaryRow(fill: colors.surface)
                            }
                            ForEach(groupedEvvegi.keys.sorted(), id: \.self) { subject in
                                let items = groupedEvvegi[subject]!
                                let latest = items.sorted { $0.date > $1.date }.first!
                                HStack(spacing: 12) {
                                    GradeCircle(value: latest.value, size: 44)
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(subject).skinFont(.subheadline, weight: .semibold).lineLimit(1)
                                        Text("Év végén \(latest.value)-es lettél").skinFont(.caption).foregroundStyle(.secondary).lineLimit(1)
                                        Text(latest.date.formatted(date: .abbreviated, time: .omitted)).skinFont(.caption2).foregroundStyle(.tertiary)
                                    }
                                    Spacer()
                                }
                                .padding(.vertical, 2)
                                .listRowInsets(VoxelTheme.rowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16)))
                                .voxelListRow(fill: colors.surface)
                            }
                        }
                    }
                    }
                    .transition(.asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity), removal: .move(edge: .leading).combined(with: .opacity)))
                }
            }
            .animation(SummitMotion.gentle, value: selectedTab)
            .listStyle(.insetGrouped)
            .frame(maxWidth: isPad ? MacSupport.contentWidth(ipad: 1280, mac: 1150) : .infinity)
            .padding(.horizontal, MacSupport.sidePadding)
            .frame(maxWidth: .infinity)
            .summitListChrome(colors: colors)
            .refreshable {
                await load(force: true)
                SummitHaptics.light()
            }
            .task { await load() }
            // A közös gyorstár figyelése (mint a Főoldalon): a máshonnan
            // (Főoldal, háttérfrissítés) érkező jegyek is azonnal beíródnak —
            // a nyitott tantárgy-részlet is, mert az a lista állapotából él.
            .background {
                KretaStoreWatcher(kinds: [.grades, .subjects]) { model.syncFromStore() }
            }
            .navigationDestination(for: String.self) { subject in
                SubjectDetailView(subject: subject, grades: gradesFor(subject)).voxelBackButton()
            }
            .onChange(of: grades) { _, _ in
                if selectedTab == .felevi && feleviGrades.isEmpty { selectedTab = .evkozi }
                if selectedTab == .evvegi && evvegiGrades.isEmpty { selectedTab = .evkozi }
            }
            .navigationTitle("Jegyek")
            .navigationBarTitleDisplayMode(.large)
            .summitToolbarBackground()
        }
        .tint(colors.accent)
    }

    /// Szegmens-választó opciói: az Év végi csak akkor jelenik meg, ha van.
    private var gradeTabOptions: [(value: GradeTab, title: String)] {
        var opts: [(value: GradeTab, title: String)] = [(.evkozi, GradeTab.evkozi.rawValue), (.felevi, GradeTab.felevi.rawValue)]
        if !evvegiGrades.isEmpty { opts.append((.evvegi, GradeTab.evvegi.rawValue)) }
        return opts
    }

    /// Tantárgy megnyitása: a verem PONTOSAN egy szintre áll (gyors dupla
    /// koppintás sem tol két részletet egymásra, vissza egyből a listára).
    private func openSubject(_ subject: String) {
        SummitHaptics.selection()
        path = NavigationPath([subject])
    }

    /// Tantárgy-sor: gomb, ami a `path`-ra tolja a tárgyat — mindkét skinben.
    /// Korábban `NavigationLink(value:)` volt (Voxelben egy rejtett,
    /// nulla méretű link a sor alatt): az a lista sor-kiválasztására
    /// támaszkodott, ami a sorra/listára kerülő bármely gesztussal (és
    /// frissítés közbeni újrarajzolással) elnyelődhetett — „többször kell
    /// rányomni, mire megnyílik". A gomb saját, determinisztikus találati
    /// felülettel dolgozik: a margó a címkében van, a `contentShape` a
    /// teljes sort fedi. Voxelben a `.skinPlain` adja a kattanást.
    @ViewBuilder
    private func subjectRow<Content: View>(_ subject: String, @ViewBuilder content: () -> Content) -> some View {
        let base = EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16)
        Button {
            openSubject(subject)
        } label: {
            HStack(spacing: 8) {
                content()
                SkinIcon("chevron.right", size: 14)
                    .skinFont(.footnote, weight: .semibold)
                    .foregroundStyle(.tertiary)
            }
            .padding(VoxelTheme.rowInsets(base) ?? base)
            .contentShape(Rectangle())
        }
        .buttonStyle(.skinPlain)
        .accessibilityAddTraits(.isLink)
    }

    // MARK: - Filtering by típus (nyers kód és szép név is: "evkozi_jegy_ertekeles" / "Évközi értékelés")
    private static func isEvkozi(_ g: GradeItem) -> Bool {
        let t = g.type.lowercased()
        return t.contains("evkozi") || t.contains("évközi") || (!t.contains("felevi") && !t.contains("félévi") && !t.contains("év végi") && !t.contains("evvegi") && !t.contains("évvégi"))
    }
    private static func isFelevi(_ g: GradeItem) -> Bool {
        let t = g.type.lowercased()
        return t.contains("felevi") || t.contains("félévi")
    }
    private static func isEvvegi(_ g: GradeItem) -> Bool {
        let t = g.type.lowercased()
        return t.contains("evvegi") || t.contains("év végi") || t.contains("évvégi")
    }
    /// Évközi, értékelhető (nem 0-s) jegy?
    static func isCountedEvkozi(_ g: GradeItem) -> Bool { g.value != 0 && isEvkozi(g) }

    /// Egy tárgy évközi jegyei dátum szerint — a Főoldal „Legújabb jegyek"
    /// sora is ezt adja a részletnek, így a két belépési pont ugyanazt az
    /// átlagot / grafikont mutatja (eddig a Főoldal a félévit is beleszámolta).
    /// Tárgy-egyezés kanonikus névvel (kis/nagybetű, ékezet, szóköz, alias).
    static func evkoziGrades(for subject: String, in all: [GradeItem]) -> [GradeItem] {
        let key = SubjectMatcher.canonical(subject)
        return all.filter { isCountedEvkozi($0) && SubjectMatcher.canonical($0.subject) == key }
            .sorted { $0.date < $1.date }
    }

    /// Szűrés, csoportosítás, átlagok EGYSZER adatváltozásonként — eddig
    /// minden hozzáférés (soronként többször) újra szűrt és csoportosított.
    /// Memó a bemenetekre (jegyek, tárgyak, kerekítési küszöbök verziója).
    ///
    /// A tárgyak KANONIKUS kulcs (`SubjectMatcher.canonical`) szerint
    /// egyesülnek: a jegyek (`Tantargy.Nev`), az átlag-végpont és az
    /// órarend ugyanazt a tárgyat eltérő alakban is adhatja (záró szóköz,
    /// kis/nagybetű). Eddig pontos szöveg-egyezés volt a kulcs, így egy
    /// tárgy kétszer jelent meg — a „Nincs jegy" ikerre koppintva a részlet
    /// üresen nyílt, pedig volt jegy. A kijelzett név a jegyeké (ha van).
    private struct Derived {
        var evkozi: [GradeItem] = []
        var felevi: [GradeItem] = []
        var evvegi: [GradeItem] = []
        /// Kijelzett név → évközi jegyek dátum szerint növekvőben.
        var groupedEvkozi: [String: [GradeItem]] = [:]
        var groupedFelevi: [String: [GradeItem]] = [:]
        var groupedEvvegi: [String: [GradeItem]] = [:]
        /// Kanonikus kulcs → kijelzett név (a részlet-kereséshez).
        var nameForKey: [String: String] = [:]
        var displayEvkoziSubjects: [String] = []
        var overallEvkozi: Double = 0
        var overallRoundedEvkozi: Double = 0
        var overallFelevi: Double = 0
        var overallEvvegi: Double = 0
        var evkoziChart: [GradeItem] = []
    }
    private struct DerivedKey: Equatable {
        var grades: [GradeItem]
        var subjects: [String]
        var thresholdsRevision: Int
    }
    @MainActor private static var derivedMemo: (key: DerivedKey, value: Derived)?

    /// Kanonikus kulcs → kijelzett név: a jegyekben leggyakoribb (vágott)
    /// alak nyer, jegy nélküli tárgynál a tárgylista alakja.
    private static func displayNames(grades: [GradeItem], subjects: [String]) -> [String: String] {
        var counts: [String: [String: Int]] = [:]
        for g in grades {
            let name = g.subject.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty else { continue }
            counts[SubjectMatcher.canonical(name), default: [:]][name, default: 0] += 1
        }
        var out: [String: String] = [:]
        for (key, names) in counts {
            out[key] = names.max { $0.value != $1.value ? $0.value < $1.value : $0.key > $1.key }?.key
        }
        for s in subjects {
            let name = s.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty, name != "Ismeretlen" else { continue }
            let key = SubjectMatcher.canonical(name)
            if out[key] == nil { out[key] = name }
        }
        return out
    }

    private var derived: Derived {
        let key = DerivedKey(grades: grades, subjects: allSubjects, thresholdsRevision: GradingLogic.revision)
        if let m = Self.derivedMemo, m.key == key { return m.value }
        var d = Derived()
        d.nameForKey = Self.displayNames(grades: grades, subjects: allSubjects)
        let names = d.nameForKey
        func displayName(_ g: GradeItem) -> String {
            names[SubjectMatcher.canonical(g.subject)] ?? g.subject.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        d.evkozi = grades.filter { Self.isCountedEvkozi($0) }
        d.felevi = grades.filter { $0.value != 0 && Self.isFelevi($0) }
        d.evvegi = grades.filter { $0.value != 0 && Self.isEvvegi($0) }
        d.groupedEvkozi = Dictionary(grouping: d.evkozi, by: displayName).mapValues { $0.sorted { $0.date < $1.date } }
        d.groupedFelevi = Dictionary(grouping: d.felevi, by: displayName)
        d.groupedEvvegi = Dictionary(grouping: d.evvegi, by: displayName)
        // KRÉTA tudja a tantárgyakat akkor is ha nincs bennük jegy — display minden felvett tárgyat mutat
        d.displayEvkoziSubjects = Set(d.groupedEvkozi.keys).union(names.values)
            .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
        // overall csak évköziből, félévi/évvégi nem számít bele az évközi átlagba
        d.overallEvkozi = GradingLogic.overallAverage(grouped: d.groupedEvkozi)
        d.overallRoundedEvkozi = GradingLogic.overallRoundedAverage(grouped: d.groupedEvkozi)
        func latestAverage(_ g: [String: [GradeItem]]) -> Double {
            let avgs = g.values.compactMap { $0.max { $0.date < $1.date }?.value }.map(Double.init)
            return avgs.isEmpty ? 0 : avgs.reduce(0, +) / Double(avgs.count)
        }
        d.overallFelevi = latestAverage(d.groupedFelevi)
        d.overallEvvegi = latestAverage(d.groupedEvvegi)
        d.evkoziChart = d.evkozi.sorted { $0.date < $1.date }
        Self.derivedMemo = (key, d)
        return d
    }

    var evkoziGrades: [GradeItem] { derived.evkozi }
    var feleviGrades: [GradeItem] { derived.felevi }
    var evvegiGrades: [GradeItem] { derived.evvegi }

    var groupedEvkozi: [String: [GradeItem]] { derived.groupedEvkozi }

    /// A részlet jegyei: a kijelzett névre, különben kanonikus egyezéssel
    /// (pl. egy régebbi alakkal a verembe került tárgy is megtalálja a jegyeit).
    private func gradesFor(_ subject: String) -> [GradeItem] {
        let d = derived
        if let hit = d.groupedEvkozi[subject] { return hit }
        if let name = d.nameForKey[SubjectMatcher.canonical(subject)], let hit = d.groupedEvkozi[name] { return hit }
        return []
    }
    var groupedFelevi: [String: [GradeItem]] { derived.groupedFelevi }
    var groupedEvvegi: [String: [GradeItem]] { derived.groupedEvvegi }

    var displayEvkoziSubjects: [String] { derived.displayEvkoziSubjects }

    var overallEvkozi: Double { derived.overallEvkozi }
    var overallRoundedEvkozi: Double { derived.overallRoundedEvkozi }
    var overallFelevi: Double { derived.overallFelevi }
    var overallEvvegi: Double { derived.overallEvvegi }
    var trendEvkozi: String { overallEvkozi >= 4 ? "Kiváló" : overallEvkozi >= 3.5 ? "Jó" : "Fejlődő" }
    var trendFelevi: String { overallFelevi >= 4 ? "Kiváló" : overallFelevi >= 3.5 ? "Jó" : "Fejlődő" }
    var trendEvvegi: String { overallEvvegi >= 4 ? "Kiváló" : overallEvvegi >= 3.5 ? "Jó" : "Fejlődő" }
    var trendColorEvkozi: Color { overallEvkozi >= 4 ? colors.green : overallEvkozi >= 3.5 ? colors.yellow : colors.orange }
    var trendColorFelevi: Color { overallFelevi >= 4 ? colors.green : overallFelevi >= 3.5 ? colors.yellow : colors.orange }
    var trendColorEvvegi: Color { overallEvvegi >= 4 ? colors.green : overallEvvegi >= 3.5 ? colors.yellow : colors.orange }

    // legacy for compatibility ( évközi )
    var grouped: [String: [GradeItem]] { groupedEvkozi }
    var overall: Double { overallEvkozi }
    var trend: String { trendEvkozi }
    var trendColor: Color { trendColorEvkozi }

    /// Tabváltáskor a `.task` újra lefut — de a gyorstár friss találatánál
    /// ez hálózat nélkül, azonnal visszatér. A váz (placeholder) csak akkor
    /// jön, ha még semmi mutatnivaló nincs; egyébként a régi jegyek
    /// maradnak, és a háttérben érkező új adat dinamikusan beíródik.
    /// Lehúzás (`force`) mindent megkerül — az tényleges frissítés.
    ///
    /// A megjelenített jegyek forrása a közös gyorstár: sikeres letöltés
    /// után az új lista, hibánál a legutóbbi mentett marad (a `fetchGrades`
    /// hibánál `lastKnown ?? []`-et ad — eddig egy ilyen üres válasz a
    /// tárgylista sikere mellett az összes jegyet kitörölte a képernyőről).
    func load(force: Bool = false) async {
        // Egy adatsáv: demo usert is a KretaClient szolgálja ki helyből.
        guard let user = session.selectedUser else { model.finishLoading(); return }
        let iss = user.instituteCode.isEmpty ? (JWT.instituteCode(from: user.accessToken) ?? "") : user.instituteCode
        if iss.isEmpty || iss == "unknown" { model.finishLoading(); return }
        KretaStore.shared.activate(user)
        // Új adat jött-e (mentési idő szerint) — a diff és az órára küldés
        // csak ilyenkor fut, a puszta tabváltás nem ismétli.
        let gradesBefore = KretaStore.shared.savedAt(.grades)
        async let gradesTask = kreta.fetchGrades(iss: iss, force: force)
        async let subjectsTask = kreta.fetchAllSubjectNames(iss: iss, force: force)
        let (g, s) = await (gradesTask, subjectsTask)
        model.apply(fetchedGrades: g, fetchedSubjects: s)
        let freshGrades = KretaStore.shared.savedAt(.grades) != gradesBefore
        // Lehúzáskor új jegy → ünneplő kártya (elsőre csak magot vet, duplán nem jelez)
        if freshGrades { NotificationManager.shared.checkGrades(g, userId: user.id) }
        // A közös tárgy-cache (Felmentés / Kerekítés listái) csak valós
        // backend hálózati tárgyaival frissül — demo-tárgy nem kerülhet bele.
        if !s.isEmpty, !user.isLocalBackend { KretaClient.mergeCachedSubjects(s) }
        // Apple Watch: a friss jegyek + tárgyak + kerekítések mennek az órára is.
        if freshGrades { WatchSyncSender.pushGrades(grades: grades, subjects: allSubjects) }
    }
}

/// A Jegyek tab adatállapota. Osztály + `@StateObject`, hogy a kezdőérték
/// (a gyorstár olvasása) egyszer, a nézet telepítésekor fusson — a korábbi
/// `@State x = KretaStore.shared...` kezdőértékek a MainTabView body-jában
/// értékelődtek ki, így a store MINDEN írása (bármely adattípus frissítése)
/// újraépítette a teljes tab-fát.
@MainActor
final class GradesModel: ObservableObject {
    @Published private(set) var grades: [GradeItem]
    @Published private(set) var subjects: [String]
    @Published private(set) var isLoading: Bool
    /// A legutóbbi tárgylista-letöltés (a demo-backend nem menti a store-ba).
    private var fetchedSubjects: [String] = []
    private var account: String?

    init() {
        let store = KretaStore.shared
        let g: [GradeItem]? = store.value(.grades)
        grades = g ?? []
        subjects = Self.clean(store.value(.subjects) ?? [])
        isLoading = g == nil
        account = store.accountHash
    }

    private static func clean(_ names: [String]) -> [String] {
        Array(Set(names.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && $0 != "Ismeretlen" })).sorted()
    }

    /// A gyorstár változott (bármely forrásból: Főoldal, háttérfrissítés,
    /// lehúzás): a mentett jegyek azonnal beíródnak. Fiókváltáskor a másik
    /// fiók adata nem maradhat a képernyőn.
    func syncFromStore() {
        let store = KretaStore.shared
        let stored: [GradeItem]? = store.value(.grades)
        let storedSubjects: [String] = store.value(.subjects) ?? []
        if store.accountHash != account {
            account = store.accountHash
            fetchedSubjects = []
            set(grades: stored ?? [], subjects: Self.clean(storedSubjects))
            isLoading = stored == nil
            return
        }
        if let stored {
            set(grades: stored, subjects: Self.clean(storedSubjects + fetchedSubjects))
            isLoading = false
        } else if !storedSubjects.isEmpty {
            set(grades: grades, subjects: Self.clean(storedSubjects + fetchedSubjects))
        }
    }

    /// Letöltés vége: a store a mérvadó (siker = új lista, hiba = a régi
    /// marad). Ha a store nem vette át (pl. épp más fiók aktív), a nem üres
    /// letöltött lista jelenik meg; az üres válasz sosem töröl.
    func apply(fetchedGrades: [GradeItem], fetchedSubjects s: [String]) {
        let store = KretaStore.shared
        if !s.isEmpty { fetchedSubjects = s }
        let stored: [GradeItem]? = store.value(.grades)
        let newGrades = stored ?? (fetchedGrades.isEmpty ? grades : fetchedGrades)
        let storedSubjects: [String] = store.value(.subjects) ?? []
        let merged = Self.clean(storedSubjects + fetchedSubjects)
        set(grades: newGrades, subjects: merged.isEmpty ? subjects : merged)
        isLoading = false
    }

    func finishLoading() { isLoading = false }

    private func set(grades g: [GradeItem], subjects s: [String]) {
        if grades != g { grades = g }
        if subjects != s { subjects = s }
    }
}

private extension View {
    /// Tantárgy-sor chrome: a margó a gomb címkéjében van (lásd
    /// `subjectRow`), így a sor teljes felülete koppintható — a sor-inset
    /// nulla. Voxelben blokk-panel, Neonban HUD-sor háttér
    /// (`skinRowBackground` mindkettőt tudja), rejtett elválasztó.
    @ViewBuilder
    func subjectRowChrome(fill: Color) -> some View {
        if VoxelTheme.isActive || NeonTheme.isActive {
            self.listRowBackground(VoxelTheme.skinRowBackground(fill))
                .listRowSeparator(.hidden)
                .listRowInsets(EdgeInsets())
        } else {
            self.listRowInsets(EdgeInsets())
        }
    }

    /// Átlag-összefoglaló sor: Summitban átlátszó, elválasztó nélküli sor
    /// (a háttéren lebeg), Voxelben blokk-panel — az ég előtt a
    /// szám különben nem lenne olvasható. Neonban sárga keretes
    /// HUD-panel akcent-füllel (a képernyő fő adat-blokkja).
    @ViewBuilder
    func voxelSummaryRow(fill: Color) -> some View {
        if NeonTheme.isActive {
            self.listRowBackground(
                NeonPanelBackground(accent: NeonTheme.yellow, fill: NeonTheme.panel, cut: 12)
                    .padding(.horizontal, NeonTheme.rowHorizontalInset)
                    .padding(.vertical, NeonTheme.rowVerticalInset)
            )
            .listRowSeparator(.hidden)
            .listRowInsets(NeonTheme.rowInsets(EdgeInsets(top: 12, leading: 16, bottom: 10, trailing: 16)))
        } else if VoxelTheme.isActive {
            self.voxelListRow(fill: fill)
        } else {
            self.listRowBackground(Color.clear).listRowSeparator(.hidden)
                .listRowInsets(VoxelTheme.rowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16)))
        }
    }

    /// Átlag-címke („ÖSSZÁTLAG"): Summit/Voxel a régi lánc, Neonban
    /// apró egyenközű, ritkított HUD-kódcímke.
    @ViewBuilder
    func gradeSummaryLabel() -> some View {
        if NeonTheme.isActive {
            self.font(NeonTheme.mono(size: 10, relativeTo: .caption2))
                .tracking(1.6)
                .foregroundStyle(NeonTheme.dim)
        } else {
            self.skinFont(.caption2, weight: .semibold).foregroundStyle(.secondary).tracking(1)
        }
    }

    /// Hero-szám Neonban: HUD-szín + (csak a fő számon) statikus
    /// vörös/cián szellemkép. Más skinben változatlan.
    @ViewBuilder
    func cpHero(_ color: Color, chromatic: Bool = true) -> some View {
        if NeonTheme.isActive {
            // A szellemkép a szín ELŐTT: különben a belső sárga nyerne a
            // vörös/cián másolatokon is.
            self.cpChromatic(chromatic ? 1 : 0).foregroundStyle(color)
        } else {
            self
        }
    }

    /// Lábléc-számláló („48 jegy • 9 tárgy"): Neonban egyenközű,
    /// nagybetűs adat-sor, egyébként a régi lánc.
    @ViewBuilder
    func gradeFooterText() -> some View {
        if NeonTheme.isActive {
            self.font(NeonTheme.mono(size: 11, relativeTo: .footnote))
                .tracking(1)
                .textCase(.uppercase)
                .foregroundStyle(NeonTheme.dim)
        } else {
            self.skinFont(.subheadline).foregroundStyle(.secondary)
        }
    }
}
