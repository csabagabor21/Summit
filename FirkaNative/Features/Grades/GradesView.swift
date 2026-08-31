import SwiftUI

struct GradesView: View {
    @EnvironmentObject var theme: ThemeStore
    @EnvironmentObject var session: SessionStore
    @EnvironmentObject var kreta: KretaClient
    @State private var grades: [GradeItem] = []
    @State private var isLoading = true
    @Environment(\.colorScheme) var scheme
    var colors: AppColors { theme.colors(for: scheme) }

    var body: some View {
        NavigationStack {
            List {
                if isLoading {
                    ForEach(0..<3, id: \.self) { _ in Text("Betöltés…").redacted(reason: .placeholder) }
                } else if grades.isEmpty {
                    ContentUnavailableView("Nincs jegy", systemImage: "star.slash", description: Text("Még nem érkezett értékelés."))
                } else {
                    // Overall = average of subject averages (as spec)
                    Section {
                        HStack(alignment: .firstTextBaseline) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("ÖSSZÁTLAG").font(.caption2.weight(.semibold)).foregroundStyle(.secondary).tracking(1)
                                Text(String(format: "%.2f", overall)).font(.system(size: 34, weight: .bold, design: .rounded))
                            }
                            Spacer()
                            VStack(alignment: .trailing, spacing: 2) {
                                Text("\(grades.count) jegy • \(grouped.count) tárgy").font(.caption).foregroundStyle(.secondary)
                                Text(trend).font(.caption.weight(.bold)).foregroundStyle(trendColor)
                            }
                        }
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                        .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                    }

                    // Compact rows: left rounded avg + name + chevron — liquid glass
                    ForEach(grouped.keys.sorted(), id: \.self) { subject in
                        let items = grouped[subject]!
                        let raw = GradingLogic.weightedAverage(items)
                        let thr = GradingLogic.threshold(for: subject)
                        let rnd = GradingLogic.roundedGrade(raw: raw, threshold: thr)
                        NavigationLink {
                            SubjectDetailView(subject: subject, grades: items.sorted { $0.date < $1.date })
                        } label: {
                            HStack(spacing: 12) {
                                ZStack {
                                    Circle()
                                        .fill(Color.clear)
                                        .glassEffect(.clear, in: .circle)
                                        .overlay(Circle().strokeBorder(colors.border.opacity(0.9), lineWidth: 1.2))
                                        .frame(width: 44, height: 44)
                                    Text("\(rnd)")
                                        .font(.system(size: 18, weight: .bold, design: .rounded))
                                        .foregroundStyle(colors.gradeColor(for: rnd))
                                }
                                .frame(width: 44, height: 44)
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(subject).font(.subheadline.weight(.semibold)).lineLimit(1)
                                    Text(String(format: "%.2f • %d jegy • kerekítés %.2f-től", raw, items.count, thr)).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                                }
                                Spacer()
                            }
                            .padding(.vertical, 2)
                        }
                        .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
                    }
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(colors.background)
            .refreshable { await load() }
            .task { await load() }
            .navigationTitle("Jegyek")
            .navigationBarTitleDisplayMode(.large)
            .toolbarBackground(.visible, for: .navigationBar)
        }
        .tint(colors.accent)
    }

    var grouped: [String: [GradeItem]] { Dictionary(grouping: grades, by: { $0.subject }) }
    var overall: Double { GradingLogic.overallAverage(grouped: grouped) }
    var trend: String { overall >= 4 ? "Kiváló" : overall >= 3.5 ? "Jó" : "Fejlődő" }
    var trendColor: Color { overall >= 4 ? colors.green : overall >= 3.5 ? colors.yellow : colors.orange }

    func load() async {
        guard let user = session.selectedUser, !user.isDemo else { grades = DemoData.gradesExpanded(); isLoading=false; return }
        isLoading=true
        let iss = user.instituteCode.isEmpty ? (JWT.instituteCode(from: user.accessToken) ?? "") : user.instituteCode
        grades = await kreta.fetchGrades(iss: iss); isLoading=false
    }
}
