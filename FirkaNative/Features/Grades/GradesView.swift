import SwiftUI

enum GradeTab: String, CaseIterable, Identifiable {
    case evkozi = "Évközi"
    case felevi = "Félévi"
    case evvegi = "Év végi"
    var id: String { rawValue }
}

/// Jegy nélküli tantárgy jelvénye: Summitban üres karika, Minecraftban
/// üres inventory-slot (a játék szürke rekesze) kötőjellel.
private struct EmptySubjectBadge: View {
    let scheme: ColorScheme
    var body: some View {
        ZStack {
            if MinecraftTheme.isActive {
                McInventorySlot().frame(width: 44, height: 44)
            } else {
                Circle().fill(Color.clear)
                    .overlay(Circle().strokeBorder(Color.primary.opacity(scheme == .dark ? 0.14 : 0.10), lineWidth: 1.2))
                    .frame(width: 44, height: 44)
            }
            Text("—").mcDisplay(18).foregroundStyle(.tertiary)
        }.frame(width: 44, height: 44)
    }
}

struct GradesView: View {
    @EnvironmentObject var theme: ThemeStore
    @EnvironmentObject var session: SessionStore
    @EnvironmentObject var kreta: KretaClient
    /// A mentett jegyek a közös gyorstárból (KretaStore): tabra lépéskor
    /// azonnal látszanak, a váz csak akkor jön, ha még semmi nincs mentve.
    @State private var grades: [GradeItem] = KretaStore.shared.value(.grades) ?? []
    @State private var allSubjects: [String] = GradesView.storedSubjects()
    @State private var isLoading = KretaStore.shared.grades == nil

    /// Mentett tárgylista (hálózati + tárgy-cache unió, mint a load-ban).
    private static func storedSubjects() -> [String] {
        let net: [String] = KretaStore.shared.value(.subjects) ?? []
        let cached = UserDefaults.standard.stringArray(forKey: KretaClient.cachedSubjectsKey) ?? []
        return Array(Set(net).union(cached)).sorted()
    }
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
                    ForEach(0..<3, id: \.self) { _ in Text("Betöltés…").redacted(reason: .placeholder).mcListRow(fill: colors.surface) }
                } else {
                    Group {
                        switch selectedTab {
                    case .evkozi:
                        if displayEvkoziSubjects.isEmpty {
                            SkinEmptyState(title: "Nincs tantárgy", systemImage: "books.vertical", description: Text("Még nincs felvett tantárgy.")).mcListRow(fill: colors.surface)
                        } else {
                            // Átlag + grafikon — mindig látszik, akkor is ha nincs jegy (üres állapot)
                            Section {
                                HStack(alignment: .lastTextBaseline, spacing: 16) {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text("ÖSSZÁTLAG").skinFont(.caption2, weight: .semibold).foregroundStyle(.secondary).tracking(1)
                                        Text(groupedEvkozi.isEmpty ? "—" : String(format: "%.2f", overallEvkozi)).mcDisplay(34)
                                    }
                                    Spacer()
                                    VStack(alignment: .trailing, spacing: 2) {
                                        Text("KEREKÍTVE").skinFont(.caption2, weight: .semibold).foregroundStyle(.secondary).tracking(1)
                                        Text(groupedEvkozi.isEmpty ? "—" : String(format: "%.2f", overallRoundedEvkozi)).mcDisplay(34)
                                    }
                                }
                                .mcSummaryRow(fill: colors.surface)
                            }
                            Section {
                                GradeChartView(grades: evkoziGrades.sorted { $0.date < $1.date }, accent: colors.accent, height: 150, monthly: true, editorial: true)
                                    .listRowBackground(Color.clear)
                                    .listRowSeparator(.hidden)
                                    .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
                            } header: { Text("Átlag alakulása — havi").mcSectionHeader() }
                            // iPad: két oszlopban, kihasználja a szélességet.
                            // Gomb + path-reset NavigationLink helyett: a link
                            // rendszer-chevronje a kártyán KÍVÜL is megjelent
                            // (dupla chevron), és a stack néha többedikre állt
                            // (vissza végigment az előző tárgyakon). Így egy
                            // koppintás = egy szint, vissza egyből a listára —
                            // chevron csak a kártyán belül marad.
                            if isPad {
                                let subjects = displayEvkoziSubjects
                                let cols = [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]
                                LazyVGrid(columns: cols, spacing: 12) {
                                    ForEach(subjects, id: \.self) { subject in
                                        if let items = groupedEvkozi[subject] {
                                            let raw = GradingLogic.weightedAverage(items)
                                            let thr = GradingLogic.threshold(for: subject)
                                            let rnd = GradingLogic.roundedGrade(raw: raw, threshold: thr)
                                            Button {
                                                SummitHaptics.selection()
                                                path = NavigationPath()
                                                path.append(subject)
                                            } label: {
                                                HStack(spacing: 12) {
                                                    GradeCircle(value: rnd, size: 44)
                                                    VStack(alignment: .leading, spacing: 3) { Text(subject).skinFont(.subheadline, weight: .semibold).lineLimit(1); Text(String(format: "%.2f • %d jegy", raw, items.count)).skinFont(.caption2).foregroundStyle(.secondary).lineLimit(1) }
                                                    Spacer()
                                                    SkinIcon("chevron.right", size: 14).skinFont(.caption2, weight: .semibold).foregroundStyle(.tertiary)
                                                }.padding(12).background(McCardBackground(fill: colors.surface, cornerRadius: 14))
                                            }.buttonStyle(.plain)
                                        } else {
                                            Button {
                                                SummitHaptics.selection()
                                                path = NavigationPath()
                                                path.append(subject)
                                            } label: {
                                                HStack(spacing: 12) {
                                                    EmptySubjectBadge(scheme: scheme)
                                                    VStack(alignment: .leading, spacing: 3) { Text(subject).skinFont(.subheadline, weight: .semibold).lineLimit(1); Text("Nincs jegy").skinFont(.caption2).foregroundStyle(.tertiary).lineLimit(1) }
                                                    Spacer()
                                                    SkinIcon("chevron.right", size: 14).skinFont(.caption2, weight: .semibold).foregroundStyle(.tertiary)
                                                }.padding(12).background(McCardBackground(fill: colors.surface, cornerRadius: 14))
                                            }.buttonStyle(.plain)
                                        }
                                    }
                                }.padding(.horizontal, 16).padding(.vertical, 8)
                            } else {
                            ForEach(displayEvkoziSubjects, id: \.self) { subject in
                                if let items = groupedEvkozi[subject] {
                                    let raw = GradingLogic.weightedAverage(items)
                                    let thr = GradingLogic.threshold(for: subject)
                                    let rnd = GradingLogic.roundedGrade(raw: raw, threshold: thr)
                                    subjectLink(subject) {
                                        HStack(spacing: 12) {
                                            GradeCircle(value: rnd, size: 44)
                                            VStack(alignment: .leading, spacing: 3) {
                                                Text(subject).skinFont(.subheadline, weight: .semibold).lineLimit(1)
                                                Text(String(format: "%.2f • %d jegy • kerekítés %.2f-től", raw, items.count, thr)).skinFont(.caption2).foregroundStyle(.secondary).lineLimit(1)
                                            }
                                            Spacer()
                                        }.padding(.vertical, 2)
                                    }
                                    .listRowInsets(MinecraftTheme.rowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16)))
                                    .mcListRow(fill: colors.surface)
                                } else {
                                    // Nincs még jegy — KRÉTA tudja a tantárgyat, üresen mutatjuk
                                    subjectLink(subject) {
                                        HStack(spacing: 12) {
                                            EmptySubjectBadge(scheme: scheme)
                                            VStack(alignment: .leading, spacing: 3) {
                                                Text(subject).skinFont(.subheadline, weight: .semibold).lineLimit(1)
                                                Text("Nincs jegy").skinFont(.caption2).foregroundStyle(.tertiary).lineLimit(1)
                                            }
                                            Spacer()
                                        }.padding(.vertical, 2)
                                    }
                                    .listRowInsets(MinecraftTheme.rowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16)))
                                    .mcListRow(fill: colors.surface)
                                }
                            }
                            }
                            Section {
                                let gradedCount = groupedEvkozi.count
                                let totalCount = displayEvkoziSubjects.count
                                if gradedCount == totalCount {
                                    Text("\(evkoziGrades.count) jegy • \(gradedCount) tárgy").skinFont(.subheadline).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .center).multilineTextAlignment(.center)
                                } else {
                                    Text("\(evkoziGrades.count) jegy • \(gradedCount)/\(totalCount) tárgy értékelve").skinFont(.subheadline).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .center).multilineTextAlignment(.center)
                                }
                            }
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                        }
                    case .felevi:
                        if feleviGrades.isEmpty {
                            SkinEmptyState(title: "Nincs félévi jegy", systemImage: "star.slash", description: Text("Még nem érkezett félévi értékelés.")).mcListRow(fill: colors.surface)
                        } else {
                            Section {
                                HStack(alignment: .firstTextBaseline) {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text("FÉLÉVI ÁTLAG").skinFont(.caption2, weight: .semibold).foregroundStyle(.secondary).tracking(1)
                                        Text(String(format: "%.2f", overallFelevi)).mcDisplay(34)
                                    }
                                    Spacer()
                                }
                                .mcSummaryRow(fill: colors.surface)
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
                                .listRowInsets(MinecraftTheme.rowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16)))
                                .mcListRow(fill: colors.surface)
                            }
                            Section {
                                Text("\(feleviGrades.count) jegy • \(groupedFelevi.count) tárgy").skinFont(.subheadline).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .center).multilineTextAlignment(.center)
                            }
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                        }
                    case .evvegi:
                        if evvegiGrades.isEmpty {
                            SkinEmptyState(title: "Nincs év végi jegy", systemImage: "star.slash", description: Text("Még nem érkezett év végi értékelés.")).mcListRow(fill: colors.surface)
                        } else {
                            Section {
                                HStack(alignment: .firstTextBaseline) {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text("ÉV VÉGI ÁTLAG").skinFont(.caption2, weight: .semibold).foregroundStyle(.secondary).tracking(1)
                                        Text(String(format: "%.2f", overallEvvegi)).mcDisplay(34)
                                    }
                                    Spacer()
                                }
                                .mcSummaryRow(fill: colors.surface)
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
                                .listRowInsets(MinecraftTheme.rowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16)))
                                .mcListRow(fill: colors.surface)
                            }
                        }
                    }
                    }
                    .transition(.asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity), removal: .move(edge: .leading).combined(with: .opacity)))
                }
            }
            .animation(SummitMotion.gentle, value: selectedTab)
            .listStyle(.insetGrouped)
            .frame(maxWidth: isPad ? MacSupport.contentWidth(ipad: 1000, mac: 1150) : .infinity)
            .padding(.horizontal, MacSupport.sidePadding)
            .frame(maxWidth: .infinity)
            .summitListChrome(colors: colors)
            .refreshable {
                await load(force: true)
                SummitHaptics.light()
            }
            .task { await load() }
            .navigationDestination(for: String.self) { subject in
                SubjectDetailView(subject: subject, grades: gradesFor(subject)).mcBackButton()
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

    /// Tantárgy-sor navigációval: Summitban a gyári `NavigationLink`,
    /// Minecraftban rejtett link + saját pixel-nyíl (a rendszer-chevron
    /// SF-ikon, az nem maradhat).
    @ViewBuilder
    private func subjectLink<Content: View>(_ subject: String, @ViewBuilder content: () -> Content) -> some View {
        if MinecraftTheme.isActive {
            ZStack {
                NavigationLink(value: subject) { EmptyView() }.opacity(0)
                HStack(spacing: 8) {
                    content()
                    SkinIcon("chevron.right", size: 14).foregroundStyle(.tertiary)
                }
            }
        } else {
            NavigationLink(value: subject) { content() }
        }
    }

    // MARK: - Filtering by típus (nyers kód és szép név is: "evkozi_jegy_ertekeles" / "Évközi értékelés")
    private func isEvkozi(_ g: GradeItem) -> Bool {
        let t = g.type.lowercased()
        return t.contains("evkozi") || t.contains("évközi") || (!t.contains("felevi") && !t.contains("félévi") && !t.contains("év végi") && !t.contains("evvegi") && !t.contains("évvégi"))
    }
    private func isFelevi(_ g: GradeItem) -> Bool {
        let t = g.type.lowercased()
        return t.contains("felevi") || t.contains("félévi")
    }
    private func isEvvegi(_ g: GradeItem) -> Bool {
        let t = g.type.lowercased()
        return t.contains("evvegi") || t.contains("év végi") || t.contains("évvégi")
    }
    var evkoziGrades: [GradeItem] { grades.filter { $0.value != 0 && isEvkozi($0) } }
    var feleviGrades: [GradeItem] { grades.filter { $0.value != 0 && isFelevi($0) } }
    var evvegiGrades: [GradeItem] { grades.filter { $0.value != 0 && isEvvegi($0) } }

    var groupedEvkozi: [String: [GradeItem]] { Dictionary(grouping: evkoziGrades, by: { $0.subject }) }

    private func gradesFor(_ subject: String) -> [GradeItem] {
        (groupedEvkozi[subject] ?? []).sorted { $0.date < $1.date }
    }
    var groupedFelevi: [String: [GradeItem]] { Dictionary(grouping: feleviGrades, by: { $0.subject }) }
    var groupedEvvegi: [String: [GradeItem]] { Dictionary(grouping: evvegiGrades, by: { $0.subject }) }

    // KRÉTA tudja a tantárgyakat akkor is ha nincs bennük jegy — display minden felvett tárgyat mutat
    var displayEvkoziSubjects: [String] {
        let graded = Set(groupedEvkozi.keys)
        let all = Set(allSubjects)
        return (graded.union(all)).sorted()
    }

    // overall csak évköziből, félévi/évvégi nem számít bele az évközi átlagba
    var overallEvkozi: Double { GradingLogic.overallAverage(grouped: groupedEvkozi) }
    var overallRoundedEvkozi: Double { GradingLogic.overallRoundedAverage(grouped: groupedEvkozi) }
    var overallFelevi: Double { guard !groupedFelevi.isEmpty else { return 0 }; let avgs = groupedFelevi.values.compactMap { $0.sorted { $0.date > $1.date }.first?.value }.map(Double.init); return avgs.isEmpty ? 0 : avgs.reduce(0, +) / Double(avgs.count) }
    var overallEvvegi: Double { guard !groupedEvvegi.isEmpty else { return 0 }; let avgs = groupedEvvegi.values.compactMap { $0.sorted { $0.date > $1.date }.first?.value }.map(Double.init); return avgs.isEmpty ? 0 : avgs.reduce(0, +) / Double(avgs.count) }
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
    func load(force: Bool = false) async {
        // Egy adatsáv: demo usert is a KretaClient szolgálja ki helyből.
        guard let user = session.selectedUser else { isLoading = false; return }
        let hadData = !grades.isEmpty
        if !hadData { isLoading = true }
        let iss = user.instituteCode.isEmpty ? (JWT.instituteCode(from: user.accessToken) ?? "") : user.instituteCode
        if iss.isEmpty || iss == "unknown" { isLoading=false; return }
        KretaStore.shared.activate(user)
        // Új adat jött-e (mentési idő szerint) — a diff és az órára küldés
        // csak ilyenkor fut, a puszta tabváltás nem ismétli.
        let gradesBefore = KretaStore.shared.savedAt(.grades)
        async let gradesTask = kreta.fetchGrades(iss: iss, force: force)
        async let subjectsTask = kreta.fetchAllSubjectNames(iss: iss, force: force)
        let (g, s) = await (gradesTask, subjectsTask)
        // Totális fetch-hiba (lejárt token, offline): a legutóbbi jegyek
        // maradnak, nem ürül ki a Jegyek tab egy sikertelen refresh-től.
        if g.isEmpty && s.isEmpty && !grades.isEmpty {
            isLoading=false
            return
        }
        if grades != g { grades = g }
        let freshGrades = KretaStore.shared.savedAt(.grades) != gradesBefore || KretaStore.shared.grades == nil
        // Lehúzáskor új jegy → ünneplő kártya (elsőre csak magot vet, duplán nem jelez)
        if freshGrades { NotificationManager.shared.checkGrades(g, userId: user.id) }
        // Megjelenítéshez a cache is jöhet (offline), de vissza csak hálózati tárgyakat
        // mentünk — a demo-módból beszennyezett cache így következő online loadkor kigyógyul.
        let cached = UserDefaults.standard.stringArray(forKey: KretaClient.cachedSubjectsKey) ?? []
        let subjectsUnion = Array(Set(s).union(cached)).sorted()
        if allSubjects != subjectsUnion { allSubjects = subjectsUnion }
        if !s.isEmpty { UserDefaults.standard.set(s.sorted(), forKey: KretaClient.cachedSubjectsKey) }
        // Apple Watch: a friss jegyek + tárgyak + kerekítések mennek az órára is.
        if freshGrades { WatchSyncSender.pushGrades(grades: grades, subjects: allSubjects) }
        isLoading=false
    }
}

private extension View {
    /// Átlag-összefoglaló sor: Summitban átlátszó, elválasztó nélküli sor
    /// (a háttéren lebeg), Minecraftban blokk-panel — az ég előtt a
    /// szám különben nem lenne olvasható.
    @ViewBuilder
    func mcSummaryRow(fill: Color) -> some View {
        if MinecraftTheme.isActive {
            self.mcListRow(fill: fill)
        } else {
            self.listRowBackground(Color.clear).listRowSeparator(.hidden)
                .listRowInsets(MinecraftTheme.rowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16)))
        }
    }
}
