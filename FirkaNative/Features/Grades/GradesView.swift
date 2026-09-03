import SwiftUI

enum GradeTab: String, CaseIterable, Identifiable {
    case evkozi = "Évközi"
    case felevi = "Félévi"
    case evvegi = "Év végi"
    var id: String { rawValue }
}

struct GradesView: View {
    @EnvironmentObject var theme: ThemeStore
    @EnvironmentObject var session: SessionStore
    @EnvironmentObject var kreta: KretaClient
    @State private var grades: [GradeItem] = []
    @State private var allSubjects: [String] = []
    @State private var isLoading = true
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
                        Picker("", selection: $selectedTab) {
                            Text(GradeTab.evkozi.rawValue).tag(GradeTab.evkozi)
                            Text(GradeTab.felevi.rawValue).tag(GradeTab.felevi)
                            if !evvegiGrades.isEmpty {
                                Text(GradeTab.evvegi.rawValue).tag(GradeTab.evvegi)
                            }
                        }
                        .pickerStyle(.segmented)
                        .listRowBackground(Color.clear)
                        .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 4, trailing: 16))
                        .listRowSeparator(.hidden)
                        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: selectedTab)
                    }
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }

                if isLoading {
                    ForEach(0..<3, id: \.self) { _ in Text("Betöltés…").redacted(reason: .placeholder) }
                } else {
                    Group {
                        switch selectedTab {
                    case .evkozi:
                        if displayEvkoziSubjects.isEmpty {
                            ContentUnavailableView("Nincs tantárgy", systemImage: "books.vertical", description: Text("Még nincs felvett tantárgy."))
                        } else {
                            // Átlag + grafikon — mindig látszik, akkor is ha nincs jegy (üres állapot)
                            Section {
                                HStack(alignment: .lastTextBaseline, spacing: 16) {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text("ÖSSZÁTLAG").font(.caption2.weight(.semibold)).foregroundStyle(.secondary).tracking(1)
                                        Text(groupedEvkozi.isEmpty ? "—" : String(format: "%.2f", overallEvkozi)).font(.system(size: 34, weight: .bold, design: .rounded))
                                    }
                                    Spacer()
                                    VStack(alignment: .trailing, spacing: 2) {
                                        Text("KEREKÍTVE").font(.caption2.weight(.semibold)).foregroundStyle(.secondary).tracking(1)
                                        Text(groupedEvkozi.isEmpty ? "—" : String(format: "%.2f", overallRoundedEvkozi)).font(.system(size: 34, weight: .bold, design: .rounded))
                                    }
                                }
                                .listRowBackground(Color.clear).listRowSeparator(.hidden).listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                            }
                            Section {
                                GradeChartView(grades: evkoziGrades.sorted { $0.date < $1.date }, accent: colors.accent, height: 150, monthly: true, editorial: true)
                                    .listRowBackground(Color.clear)
                                    .listRowSeparator(.hidden)
                                    .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
                            } header: { Text("Átlag alakulása — havi").font(.caption.weight(.semibold)).foregroundStyle(.secondary).textCase(.uppercase) }
                            // iPad: két oszlopban, kihasználja a szélességet
                            if isPad {
                                let subjects = displayEvkoziSubjects
                                let cols = [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]
                                LazyVGrid(columns: cols, spacing: 12) {
                                    ForEach(subjects, id: \.self) { subject in
                                        if let items = groupedEvkozi[subject] {
                                            let raw = GradingLogic.weightedAverage(items)
                                            let thr = GradingLogic.threshold(for: subject)
                                            let rnd = GradingLogic.roundedGrade(raw: raw, threshold: thr)
                                            NavigationLink(value: subject) {
                                                HStack(spacing: 12) {
                                                    ZStack { Circle().fill(Color.clear).overlay(Circle().strokeBorder(colors.border.opacity(0.9), lineWidth: 1.2)).frame(width: 44, height: 44); Text("\(rnd)").font(.system(size: 18, weight: .bold, design: .rounded)).foregroundStyle(colors.gradeColor(for: rnd)) }.frame(width: 44, height: 44)
                                                    VStack(alignment: .leading, spacing: 3) { Text(subject).font(.subheadline.weight(.semibold)).lineLimit(1); Text(String(format: "%.2f • %d jegy", raw, items.count)).font(.caption2).foregroundStyle(.secondary).lineLimit(1) }
                                                    Spacer()
                                                    Image(systemName: "chevron.right").font(.caption2.weight(.semibold)).foregroundStyle(.tertiary)
                                                }.padding(12).background(RoundedRectangle(cornerRadius: 14).fill(colors.surface).overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Color.primary.opacity(0.06), lineWidth: 1)))
                                            }.buttonStyle(.plain)
                                        } else {
                                            NavigationLink(value: subject) {
                                                HStack(spacing: 12) {
                                                    ZStack { Circle().fill(Color.clear).overlay(Circle().strokeBorder(Color.primary.opacity(scheme == .dark ? 0.14 : 0.10), lineWidth: 1.2)).frame(width: 44, height: 44); Text("—").font(.system(size: 18, weight: .bold, design: .rounded)).foregroundStyle(.tertiary) }.frame(width: 44, height: 44)
                                                    VStack(alignment: .leading, spacing: 3) { Text(subject).font(.subheadline.weight(.semibold)).lineLimit(1); Text("Nincs jegy").font(.caption2).foregroundStyle(.tertiary).lineLimit(1) }
                                                    Spacer()
                                                }.padding(12).background(RoundedRectangle(cornerRadius: 14).fill(colors.surface).overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Color.primary.opacity(0.06), lineWidth: 1)))
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
                                    NavigationLink(value: subject) {
                                        HStack(spacing: 12) {
                                            ZStack {
                                                Circle().fill(Color.clear).glassEffect(.clear, in: .circle)
                                                    .overlay(Circle().strokeBorder(colors.border.opacity(0.9), lineWidth: 1.2))
                                                    .frame(width: 44, height: 44)
                                                Text("\(rnd)").font(.system(size: 18, weight: .bold, design: .rounded)).foregroundStyle(colors.gradeColor(for: rnd))
                                            }.frame(width: 44, height: 44)
                                            VStack(alignment: .leading, spacing: 3) {
                                                Text(subject).font(.subheadline.weight(.semibold)).lineLimit(1)
                                                Text(String(format: "%.2f • %d jegy • kerekítés %.2f-től", raw, items.count, thr)).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                                            }
                                            Spacer()
                                        }.padding(.vertical, 2)
                                    }
                                    .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
                                } else {
                                    // Nincs még jegy — KRÉTA tudja a tantárgyat, üresen mutatjuk
                                    NavigationLink(value: subject) {
                                        HStack(spacing: 12) {
                                            ZStack {
                                                Circle().fill(Color.clear)
                                                    .overlay(Circle().strokeBorder(Color.primary.opacity(scheme == .dark ? 0.14 : 0.10), lineWidth: 1.2))
                                                    .frame(width: 44, height: 44)
                                                Text("—").font(.system(size: 18, weight: .bold, design: .rounded)).foregroundStyle(.tertiary)
                                            }.frame(width: 44, height: 44)
                                            VStack(alignment: .leading, spacing: 3) {
                                                Text(subject).font(.subheadline.weight(.semibold)).lineLimit(1)
                                                Text("Nincs jegy").font(.caption2).foregroundStyle(.tertiary).lineLimit(1)
                                            }
                                            Spacer()
                                        }.padding(.vertical, 2)
                                    }
                                    .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
                                }
                            }
                            }
                            Section {
                                let gradedCount = groupedEvkozi.count
                                let totalCount = displayEvkoziSubjects.count
                                if gradedCount == totalCount {
                                    Text("\(evkoziGrades.count) jegy • \(gradedCount) tárgy").font(.subheadline).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .center).multilineTextAlignment(.center)
                                } else {
                                    Text("\(evkoziGrades.count) jegy • \(gradedCount)/\(totalCount) tárgy értékelve").font(.subheadline).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .center).multilineTextAlignment(.center)
                                }
                            }
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                        }
                    case .felevi:
                        if feleviGrades.isEmpty {
                            ContentUnavailableView("Nincs félévi jegy", systemImage: "star.slash", description: Text("Még nem érkezett félévi értékelés."))
                        } else {
                            Section {
                                HStack(alignment: .firstTextBaseline) {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text("FÉLÉVI ÁTLAG").font(.caption2.weight(.semibold)).foregroundStyle(.secondary).tracking(1)
                                        Text(String(format: "%.2f", overallFelevi)).font(.system(size: 34, weight: .bold, design: .rounded))
                                    }
                                    Spacer()
                                }
                                .listRowBackground(Color.clear).listRowSeparator(.hidden).listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                            }
                            ForEach(groupedFelevi.keys.sorted(), id: \.self) { subject in
                                let items = groupedFelevi[subject]!
                                let latest = items.sorted { $0.date > $1.date }.first!
                                HStack(spacing: 12) {
                                    ZStack {
                                        Circle().fill(Color.clear).glassEffect(.clear, in: .circle)
                                            .overlay(Circle().strokeBorder(colors.border.opacity(0.9), lineWidth: 1.2))
                                            .frame(width: 44, height: 44)
                                        Text("\(latest.value)").font(.system(size: 18, weight: .bold, design: .rounded)).foregroundStyle(colors.gradeColor(for: latest.value))
                                    }.frame(width: 44, height: 44)
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(subject).font(.subheadline.weight(.semibold)).lineLimit(1)
                                        Text("Félévkor \(latest.value)-es lettél").font(.caption).foregroundStyle(.secondary).lineLimit(1)
                                        Text(latest.date.formatted(date: .abbreviated, time: .omitted)).font(.caption2).foregroundStyle(.tertiary)
                                    }
                                    Spacer()
                                }
                                .padding(.vertical, 2)
                                .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
                            }
                            Section {
                                Text("\(feleviGrades.count) jegy • \(groupedFelevi.count) tárgy").font(.subheadline).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .center).multilineTextAlignment(.center)
                            }
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                        }
                    case .evvegi:
                        if evvegiGrades.isEmpty {
                            ContentUnavailableView("Nincs év végi jegy", systemImage: "star.slash", description: Text("Még nem érkezett év végi értékelés."))
                        } else {
                            Section {
                                HStack(alignment: .firstTextBaseline) {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text("ÉV VÉGI ÁTLAG").font(.caption2.weight(.semibold)).foregroundStyle(.secondary).tracking(1)
                                        Text(String(format: "%.2f", overallEvvegi)).font(.system(size: 34, weight: .bold, design: .rounded))
                                    }
                                    Spacer()
                                }
                                .listRowBackground(Color.clear).listRowSeparator(.hidden).listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                            }
                            ForEach(groupedEvvegi.keys.sorted(), id: \.self) { subject in
                                let items = groupedEvvegi[subject]!
                                let latest = items.sorted { $0.date > $1.date }.first!
                                HStack(spacing: 12) {
                                    ZStack {
                                        Circle().fill(Color.clear).glassEffect(.clear, in: .circle)
                                            .overlay(Circle().strokeBorder(colors.border.opacity(0.9), lineWidth: 1.2))
                                            .frame(width: 44, height: 44)
                                        Text("\(latest.value)").font(.system(size: 18, weight: .bold, design: .rounded)).foregroundStyle(colors.gradeColor(for: latest.value))
                                    }.frame(width: 44, height: 44)
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(subject).font(.subheadline.weight(.semibold)).lineLimit(1)
                                        Text("Év végén \(latest.value)-es lettél").font(.caption).foregroundStyle(.secondary).lineLimit(1)
                                        Text(latest.date.formatted(date: .abbreviated, time: .omitted)).font(.caption2).foregroundStyle(.tertiary)
                                    }
                                    Spacer()
                                }
                                .padding(.vertical, 2)
                                .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
                            }
                        }
                    }
                    }
                    .transition(.asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity), removal: .move(edge: .leading).combined(with: .opacity)))
                }
            }
            .animation(.spring(response: 0.38, dampingFraction: 0.82), value: selectedTab)
            .listStyle(.insetGrouped)
            .frame(maxWidth: isPad ? 860 : .infinity)
            .frame(maxWidth: .infinity)
            .scrollContentBackground(.hidden)
            .background(colors.background)
            .refreshable { await load() }
            .task { await load() }
            .navigationDestination(for: String.self) { subject in
                SubjectDetailView(subject: subject, grades: gradesFor(subject))
            }
            .onChange(of: grades) { _, _ in
                if selectedTab == .felevi && feleviGrades.isEmpty { selectedTab = .evkozi }
                if selectedTab == .evvegi && evvegiGrades.isEmpty { selectedTab = .evkozi }
            }
            .navigationTitle("Jegyek")
            .navigationBarTitleDisplayMode(.large)
            .toolbarBackground(.visible, for: .navigationBar)
        }
        .tint(colors.accent)
    }

    // MARK: - Filtering by Tipus.Nev (evkozi_jegy_ertekeles / felevi / evvegi)
    private func isEvkozi(_ g: GradeItem) -> Bool {
        let t = g.type.lowercased()
        return t.contains("evkozi") || (!t.contains("felevi") && !t.contains("félévi") && !t.contains("év végi") && !t.contains("evvegi") && !t.contains("évvégi"))
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

    func load() async {
        guard let user = session.selectedUser, !user.isDemo else {
            grades = DemoData.gradesExpanded()
            // Demo: tantárgyak a demó órarendből + jegyekből is, hogy legyen "Nincs jegy" példa
            let demoSubjects = Set(DemoData.lessonsExpanded().map(\.subject)).union(DemoData.gradesExpanded().map(\.subject))
            // adjunk hozzá egy üres tárgyat demonstrációnak
            var s = demoSubjects.sorted()
            if !s.contains("Etika") { s.append("Etika"); s.sort() }
            allSubjects = s
            isLoading=false; return
        }
        isLoading=true
        let iss = user.instituteCode.isEmpty ? (JWT.instituteCode(from: user.accessToken) ?? "") : user.instituteCode
        if iss.isEmpty || iss == "unknown" { isLoading=false; return }
        async let gradesTask = kreta.fetchGrades(iss: iss)
        async let subjectsTask = kreta.fetchAllSubjectNames(iss: iss)
        let (g, s) = await (gradesTask, subjectsTask)
        grades = g
        // Megjelenítéshez a cache is jöhet (offline), de vissza csak hálózati tárgyakat
        // mentünk — a demo-módból beszennyezett cache így következő online loadkor kigyógyul.
        let cached = UserDefaults.standard.stringArray(forKey: "firka.cachedSubjects.v1") ?? []
        allSubjects = Array(Set(s).union(cached)).sorted()
        if !s.isEmpty { UserDefaults.standard.set(s.sorted(), forKey: "firka.cachedSubjects.v1") }
        isLoading=false
    }
}
