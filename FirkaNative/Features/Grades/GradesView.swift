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
    @State private var isLoading = true
    @State private var selectedTab: GradeTab = .evkozi
    @Environment(\.colorScheme) var scheme
    var colors: AppColors { theme.colors(for: scheme) }

    var body: some View {
        NavigationStack {
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
                        if evkoziGrades.isEmpty {
                            ContentUnavailableView("Nincs évközi jegy", systemImage: "star.slash", description: Text("Még nem érkezett évközi értékelés."))
                        } else {
                            Section {
                                HStack(alignment: .lastTextBaseline, spacing: 16) {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text("ÖSSZÁTLAG").font(.caption2.weight(.semibold)).foregroundStyle(.secondary).tracking(1)
                                        Text(String(format: "%.2f", overallEvkozi)).font(.system(size: 34, weight: .bold, design: .rounded))
                                    }
                                    Spacer()
                                    VStack(alignment: .trailing, spacing: 2) {
                                        Text("KEREKÍTVE").font(.caption2.weight(.semibold)).foregroundStyle(.secondary).tracking(1)
                                        Text(String(format: "%.2f", overallRoundedEvkozi)).font(.system(size: 34, weight: .bold, design: .rounded))
                                    }
                                }
                                .listRowBackground(Color.clear).listRowSeparator(.hidden).listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                            }
                            // Évközi grafikon — editorial, havi, minimal
                            Section {
                                GradeChartView(grades: evkoziGrades.sorted { $0.date < $1.date }, accent: colors.accent, height: 150, monthly: true, editorial: true)
                                    .listRowBackground(Color.clear)
                                    .listRowSeparator(.hidden)
                                    .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
                            } header: { Text("Átlag alakulása — havi").font(.caption.weight(.semibold)).foregroundStyle(.secondary).textCase(.uppercase) }
                            ForEach(groupedEvkozi.keys.sorted(), id: \.self) { subject in
                                let items = groupedEvkozi[subject]!
                                let raw = GradingLogic.weightedAverage(items)
                                let thr = GradingLogic.threshold(for: subject)
                                let rnd = GradingLogic.roundedGrade(raw: raw, threshold: thr)
                                NavigationLink {
                                    SubjectDetailView(subject: subject, grades: items.sorted { $0.date < $1.date })
                                } label: {
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
                            }
                            Section {
                                Text("\(evkoziGrades.count) jegy • \(groupedEvkozi.count) tárgy").font(.subheadline).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .center).multilineTextAlignment(.center)
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
            .scrollContentBackground(.hidden)
            .background(colors.background)
            .refreshable { await load() }
            .task { await load() }
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
    var groupedFelevi: [String: [GradeItem]] { Dictionary(grouping: feleviGrades, by: { $0.subject }) }
    var groupedEvvegi: [String: [GradeItem]] { Dictionary(grouping: evvegiGrades, by: { $0.subject }) }

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
        guard let user = session.selectedUser, !user.isDemo else { grades = DemoData.gradesExpanded(); isLoading=false; return }
        isLoading=true
        let iss = user.instituteCode.isEmpty ? (JWT.instituteCode(from: user.accessToken) ?? "") : user.instituteCode
        grades = await kreta.fetchGrades(iss: iss); isLoading=false
    }
}
