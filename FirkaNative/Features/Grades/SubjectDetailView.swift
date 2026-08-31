import SwiftUI
import Charts

struct SubjectDetailView: View {
    let subject: String
    @State var grades: [GradeItem] // sorted by date
    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var theme: ThemeStore
    @Environment(\.colorScheme) var scheme
    var colors: AppColors { theme.colors(for: scheme) }

    @State private var phantom: [GradeItem] = []
    @State private var showAdd = false
    @State private var addValue: Int = 5
    @State private var addWeight: Int = 100
    @State private var targetGrade: Int = 5
    @State private var graphRange: GraphRange = .threeMonths

    private var threshold: Double { GradingLogic.threshold(for: subject) }
    private var allGrades: [GradeItem] { (grades + phantom).sorted { $0.date < $1.date } }
    private var rawAvg: Double { GradingLogic.weightedAverage(allGrades) }
    private var rounded: Int { GradingLogic.roundedGrade(raw: rawAvg, threshold: threshold) }
    private var baseRaw: Double { GradingLogic.weightedAverage(grades) }

    private var chartGrades: [GradeItem] {
        let now = Date()
        let cutoff: Date? = {
            switch graphRange {
            case .month: return Calendar.current.date(byAdding: .month, value: -1, to: now)
            case .threeMonths: return Calendar.current.date(byAdding: .month, value: -3, to: now)
            case .halfYear: return Calendar.current.date(byAdding: .month, value: -6, to: now)
            case .full: return nil
            }
        }()
        let filtered: [GradeItem]
        if let c = cutoff {
            filtered = allGrades.filter { $0.date >= c }
            // ha túl kevés, mutasd az összeset hogy ne legyen üres
            return filtered.count >= 2 ? filtered : allGrades
        }
        return allGrades
    }
    private var chartXDomain: ClosedRange<Date> {
        guard let min = chartGrades.map(\.date).min(), let max = chartGrades.map(\.date).max() else {
            let now = Date(); return now.addingTimeInterval(-30*86400)...now
        }
        // kis padding
        let pad = max.timeIntervalSince(min) * 0.05
        return min.addingTimeInterval(-pad)...max.addingTimeInterval(pad)
    }

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text(subject).font(.title3.weight(.bold))
                        Spacer()
                        ZStack {
                            Circle().fill(Color.clear).glassEffect(.clear, in: .circle)
                                .overlay(Circle().strokeBorder(colors.border.opacity(0.9), lineWidth: 1.2))
                                .frame(width: 44, height: 44)
                            Text("\(rounded)")
                                .font(.system(size: 20, weight: .bold, design: .rounded))
                                .foregroundStyle(colors.gradeColor(for: rounded))
                        }
                        .frame(width: 44, height: 44)
                    }
                    Text(String(format: "Nyers átlag %.2f → kerekítve %d-es", rawAvg, rounded)).font(.caption).foregroundStyle(.secondary)
                }
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)

                // Graph — szebb, havi bontás, range picker
                Picker("", selection: $graphRange) {
                    ForEach(GraphRange.allCases) { r in Text(r.title).tag(r) }
                }
                .pickerStyle(.segmented)
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)

                if chartGrades.count >= 2 {
                    Chart {
                        // running average line with gradient
                        ForEach(Array(chartGrades.enumerated()), id: \.element.id) { idx, g in
                            let running = GradingLogic.weightedAverage(Array(chartGrades.prefix(idx+1)))
                            LineMark(x: .value("Dátum", g.date), y: .value("Átlag", running))
                                .foregroundStyle(LinearGradient(colors: [colors.accent, colors.accent.opacity(0.6)], startPoint: .leading, endPoint: .trailing))
                                .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
                                .interpolationMethod(.catmullRom)
                        }
                        // area under line
                        ForEach(Array(chartGrades.enumerated()), id: \.element.id) { idx, g in
                            let running = GradingLogic.weightedAverage(Array(chartGrades.prefix(idx+1)))
                            AreaMark(x: .value("Dátum", g.date), y: .value("Átlag", running))
                                .foregroundStyle(LinearGradient(colors: [colors.accent.opacity(0.22), colors.accent.opacity(0.02)], startPoint: .top, endPoint: .bottom))
                                .interpolationMethod(.catmullRom)
                        }
                        ForEach(chartGrades, id: \.id) { g in
                            PointMark(x: .value("Dátum", g.date), y: .value("Jegy", Double(g.value)))
                                .foregroundStyle(g.id.hasPrefix("phantom") ? Color.orange : colors.gradeColor(for: g.value).opacity(0.95))
                                .symbolSize(28)
                        }
                        RuleMark(y: .value("Cél", Double(targetGrade))).lineStyle(StrokeStyle(lineWidth: 1, dash: [4,4])).foregroundStyle(.secondary.opacity(0.5))
                    }
                    .frame(height: 180)
                    .chartYScale(domain: 1...5)
                    .chartXScale(domain: chartXDomain)
                    .chartXAxis {
                        AxisMarks(values: .stride(by: .month, count: 1)) { v in
                            AxisGridLine().foregroundStyle(Color.primary.opacity(0.06))
                            if let d = v.as(Date.self) {
                                AxisValueLabel(format: .dateTime.month(.abbreviated)).font(.caption2)
                            }
                        }
                    }
                    .chartYAxis {
                        AxisMarks(position: .leading, values: [1,2,3,4,5]) { v in
                            AxisGridLine().foregroundStyle(Color.primary.opacity(0.06))
                            AxisValueLabel().font(.caption2)
                        }
                    }
                    .chartPlotStyle { plot in
                        plot.background(Color.primary.opacity(0.02)).clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                    .padding(.vertical, 4)
                } else if allGrades.count >= 2 {
                    ContentUnavailableView("Nincs adat ebben az időszakban", systemImage: "calendar", description: Text("Válassz nagyobb időtávot vagy adj hozzá jegyet."))
                } else {
                    ContentUnavailableView("Nincs elég adat a grafikonhoz", systemImage: "chart.line.downtrend.xyaxis", description: Text("Adj hozzá fantom jegyet a + gombbal"))
                }
            } header: { Text("Átlag és grafikon").font(.caption.weight(.semibold)).foregroundStyle(.secondary).textCase(.uppercase) }

            Section {
                ForEach(allGrades.sorted(by: { $0.date > $1.date })) { g in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 10) {
                            ZStack {
                                Circle().fill(Color.clear).glassEffect(.clear, in: .circle)
                                    .overlay(Circle().strokeBorder(colors.border.opacity(0.9), lineWidth: 1))
                                    .frame(width: 28, height: 28)
                                Text("\(g.value)").font(.caption.weight(.bold).monospacedDigit()).foregroundStyle(colors.gradeColor(for: g.value))
                            }
                            .frame(width: 28, height: 28)
                            .opacity(g.id.hasPrefix("phantom") ? 0.6 : 1)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(g.date.formatted(date: .abbreviated, time: .omitted) + " • \(g.weight)%").font(.caption.weight(.medium))
                                if g.topic.isEmpty {
                                    Text(g.type).font(.caption2).foregroundStyle(.secondary)
                                }
                            }
                            Spacer()
                            if g.id.hasPrefix("phantom") {
                                Text("fantom").font(.caption2.weight(.bold)).foregroundStyle(.orange).padding(.horizontal, 6).padding(.vertical, 2).background(Capsule().fill(Color.orange.opacity(0.14)))
                                Button(role: .destructive) { phantom.removeAll { $0.id == g.id } } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary) }
                            }
                        }
                        if !g.topic.isEmpty {
                            Text(g.topic).font(.caption).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.top, 2)
                        }
                    }
                    .padding(.vertical, 2)
                }
            } header: { Text("Jegyek").font(.caption.weight(.semibold)).foregroundStyle(.secondary).textCase(.uppercase) }


        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(colors.background)
        .navigationTitle(subject)
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { showAdd = true } label: { Image(systemName: "plus.circle.fill").font(.title3) }
                .tint(colors.accent)
            }
        }
        .sheet(isPresented: $showAdd) {
            NavigationStack {
                Form {
                    Section("Érték") { Picker("Jegy", selection: $addValue) { ForEach(1...5, id: \.self) { Text("\($0)").tag($0) } }.pickerStyle(.segmented) }
                    Section("Súly") { Picker("Súly", selection: $addWeight) { Text("100%").tag(100); Text("200%").tag(200); Text("50%").tag(50) }.pickerStyle(.segmented) }
                    Section { Text("Előnézet átlag: \(String(format: "%.2f", GradingLogic.weightedAverage(allGrades + [GradeItem(id: "phantom-\(UUID())", subject: subject, value: addValue, valueText: "\(addValue)", date: Date(), teacher: "", type: "Fantom", weight: addWeight, topic: "")])))").font(.callout).foregroundStyle(.secondary) }
                }
                .navigationTitle("Fantom jegy")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Mégse") { showAdd = false } }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Hozzáadás") {
                            let g = GradeItem(id: "phantom-\(UUID())", subject: subject, value: addValue, valueText: "\(addValue)", date: Date().addingTimeInterval(Double(phantom.count)*60), teacher: "Fantom", type: "Fantom", weight: addWeight, topic: "")
                            phantom.append(g); showAdd = false
                        }.tint(colors.accent)
                    }
                }
            }
            .presentationDetents([.medium])
        }
    }
}

enum GraphRange: String, CaseIterable, Identifiable {
    case month = "Havi"
    case threeMonths = "3 havi"
    case halfYear = "Féléves"
    case full = "Teljes"
    var id: String { rawValue }
    var title: String { rawValue }
}
