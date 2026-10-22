import SwiftUI

struct SubjectDetailView: View {
    let subject: String
    @State var grades: [GradeItem] // sorted by date
    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var theme: ThemeStore
    @Environment(\.colorScheme) var scheme
    @Environment(\.horizontalSizeClass) private var hSize
    private var isPad: Bool { hSize == .regular }
    var colors: AppColors { theme.colors(for: scheme) }

    @State private var phantom: [GradeItem] = []
    /// Lecserélt valódi jegyek ID-i + fantomID → eredetiID kapcsolat.
    @State private var replacedIds: Set<String> = []
    @State private var phantomLinks: [String: String] = [:]
    @State private var showAdd = false
    @State private var addValue: Int = 5
    @State private var addWeight: Int = 100
    @State private var replaceTarget: GradeItem?
    @State private var replaceValue: Int = 5
    @State private var graphRange: GraphRange = .threeMonths

    private var threshold: Double { GradingLogic.threshold(for: subject) }
    private var validGrades: [GradeItem] { grades.filter { $0.value != 0 } }
    private var allGrades: [GradeItem] { (validGrades.filter { !replacedIds.contains($0.id) } + phantom).sorted { $0.date < $1.date } }
    private var hasPhantom: Bool { !phantom.isEmpty }
    private var rawAvg: Double { GradingLogic.weightedAverage(allGrades) }
    private var rounded: Int { GradingLogic.roundedGrade(raw: rawAvg, threshold: threshold) }
    private var baseRaw: Double { GradingLogic.weightedAverage(validGrades) }

    private var chartGrades: [GradeItem] {
        let base = allGrades
        guard let latest = base.map(\.date).max() else { return base }
        let cutoff: Date? = {
            switch graphRange {
            case .month: return Calendar.current.date(byAdding: .month, value: -1, to: latest)
            case .threeMonths: return Calendar.current.date(byAdding: .month, value: -3, to: latest)
            case .halfYear: return Calendar.current.date(byAdding: .month, value: -6, to: latest)
            case .full: return nil
            }
        }()
        let filtered: [GradeItem]
        if let c = cutoff {
            filtered = base.filter { $0.date >= c }
            return filtered.count >= 2 ? filtered : base
        }
        return base
    }

    // Delta az első és utolsó futó átlag között — Home-szerű finom visszajelzés
    private var deltaText: (text: String, color: Color)? {
        let pts = runningPoints(for: chartGrades)
        guard pts.count >= 2, let first = pts.first?.avg, let last = pts.last?.avg else { return nil }
        let d = last - first
        if abs(d) < 0.03 { return nil }
        let sign = d > 0 ? "+" : ""
        let txt = String(format: "%@%.2f", sign, d)
        if d > 0 { return (txt, colors.green) }
        if d < 0 { return (txt, colors.red) }
        return nil
    }
    private func runningPoints(for g: [GradeItem]) -> [(date: Date, avg: Double)] {
        var pts: [(Date,Double)] = []
        for idx in 0..<g.count { pts.append((g[idx].date, GradingLogic.weightedAverage(Array(g.prefix(idx+1))))) }
        return pts
    }

    /// Fantom elvetése swipe-pal: a fantom törlődik, az eredeti jegy visszajön.
    private func dismissPhantom(_ g: GradeItem) {
        withAnimation(SummitMotion.gentle) {
            phantom.removeAll { $0.id == g.id }
            if let orig = phantomLinks[g.id] { replacedIds.remove(orig) }
            phantomLinks.removeValue(forKey: g.id)
        }
    }

    var body: some View {
        List {
            // MARK: - Összefoglaló + grafikon — EGY szekció, EGY header (nincs duplikáció, nincs levágás)
            Section {
                // Fejléc: tantárgy + nagy jegykarikán + nyers átlag
                VStack(alignment: .leading, spacing: 10) {
                    HStack(alignment: .center, spacing: 12) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(subject).mcDisplay(22).lineLimit(2)
                            Text(String(format: "Nyers átlag %.2f → kerekítve %d-es", rawAvg, rounded))
                                .font(.caption.weight(.medium))
                                .foregroundStyle(.secondary)
                            Text(String(format: "Kerekítés %.2f-től • %d jegy", threshold, allGrades.count))
                                .font(.caption2.weight(.medium))
                                .foregroundStyle(.tertiary)
                        }
                        Spacer()
                        Text("\(rounded)")
                            .mcDisplay(22)
                            .foregroundStyle(colors.gradeColor(for: rounded))
                            .frame(width: 50, height: 50)
                            .background {
                                Circle().fill(Color.clear).glassEffect(.clear, in: .circle)
                            }
                            .overlay(Circle().strokeBorder(colors.border.opacity(0.9), lineWidth: 1.2))
                            .shadow(color: colors.gradeColor(for: rounded).opacity(0.18), radius: 10, y: 4)
                    }

                    Divider().opacity(0.45)

                    // Szűrő — Home Tab stílusú, compact
                    Picker("", selection: $graphRange) {
                        ForEach(GraphRange.allCases) { r in Text(r.title).tag(r) }
                    }
                    .pickerStyle(.segmented)
                    .controlSize(.small)

                    // Grafikon — prémium morph, nem vágja le a tetejét (domain 1...5.45 + 14pt top inset)
                    GradeChartView(grades: chartGrades, accent: colors.accent, showTarget: nil, height: 190, editorial: false)

                    // Lábjegyzet — Home LiveCard ihletésű, finom progress jelleg
                    HStack(spacing: 6) {
                        Circle().fill(colors.accent).frame(width: 6, height: 6)
                        Text(String(format: "Jelenlegi átlag %.2f", rawAvg))
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                        Spacer()
                        if let d = deltaText {
                            Text(d.text).font(.caption2.weight(.bold).monospacedDigit()).foregroundStyle(d.color)
                                .padding(.horizontal, 7).padding(.vertical, 3)
                                .background(Capsule().fill(d.color.opacity(0.12)))
                        } else {
                            Text("stabil").font(.caption2.weight(.medium)).foregroundStyle(.tertiary)
                        }
                    }
                    if hasPhantom {
                        HStack(spacing: 6) {
                            Text("FANTOM ELŐNÉZET").font(.caption2.weight(.bold)).foregroundStyle(.orange)
                                .padding(.horizontal, 7).padding(.vertical, 3)
                                .background(Capsule().fill(Color.orange.opacity(0.14)))
                            Text(String(format: "eredeti %.2f → most %.2f", baseRaw, rawAvg))
                                .font(.caption2.weight(.medium)).foregroundStyle(.secondary)
                            Spacer()
                        }
                    }
                }
                .padding(.vertical, 4)
                .summitRowSurface(colors: colors)
                .listRowInsets(EdgeInsets(top: 14, leading: 16, bottom: 14, trailing: 16))
            } header: {
                Text("Átlag és grafikon")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
            }

            Section {
                ForEach(allGrades.sorted(by: { $0.date > $1.date })) { g in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 10) {
                            Text("\(g.value)").font(.caption.weight(.bold).monospacedDigit()).foregroundStyle(colors.gradeColor(for: g.value))
                            .frame(width: 28, height: 28)
                            .background {
                                Circle().fill(Color.clear).glassEffect(.clear, in: .circle)
                            }
                            .overlay(Circle().strokeBorder(colors.border.opacity(0.9), lineWidth: 1))
                            .opacity(g.id.hasPrefix("phantom") ? 0.6 : 1)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(g.date.formatted(date: .abbreviated, time: .omitted) + " • \(g.weight)%").font(.caption.weight(.medium))
                                if g.plainTopic.isEmpty {
                                    Text(friendlyGradeType(g.type)).font(.caption2).foregroundStyle(.secondary)
                                }
                            }
                            Spacer()
                            if g.id.hasPrefix("phantom") {
                                Text("fantom").font(.caption2.weight(.bold)).foregroundStyle(.orange).padding(.horizontal, 6).padding(.vertical, 2).background(Capsule().fill(Color.orange.opacity(0.14)))
                            }
                        }
                        if !g.plainTopic.isEmpty {
                            Text(g.plainTopic).font(.caption).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.top, 2)
                        }
                    }
                    .padding(.vertical, 2)
                    // Fantom-vezérlés kizárólag swipe-pal: valódi jegyen a
                    // csere, fantomon az elvetés — kis x gomb nincs.
                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                        if g.id.hasPrefix("phantom") {
                            Button(role: .destructive) {
                                SummitHaptics.light()
                                dismissPhantom(g)
                            } label: {
                                Label("Elvetés", systemImage: "trash")
                            }
                        } else {
                            Button {
                                SummitHaptics.selection()
                                replaceTarget = g; replaceValue = g.value
                            } label: {
                                Label("Mi lett volna ha", systemImage: "wand.and.stars")
                            }
                            .tint(.orange)
                        }
                    }
                }
            } header: { Text("Jegyek").mcSectionHeader() }
        }
        .listStyle(.insetGrouped)
        .frame(maxWidth: isPad ? MacSupport.contentWidth(ipad: 1000, mac: 1150) : .infinity)
        .padding(.horizontal, MacSupport.sidePadding)
        .frame(maxWidth: .infinity)
        .summitListChrome(colors: colors)
        .navigationTitle(subject)
        .navigationBarTitleDisplayMode(.large)
        .animation(SummitMotion.gentle, value: graphRange)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { showAdd = true } label: { Image(systemName: "plus.circle.fill").font(.title3) }
                .tint(colors.accent)
            }
        }
        .sheet(isPresented: $showAdd) {
            NavigationStack {
                Form {
                    Section("Érték") { Picker("Jegy", selection: $addValue) { ForEach(1...5, id: \.self) { Text("\($0)").tag($0) } }.pickerStyle(.segmented).summitSelectionHaptic(trigger: addValue) }
                    Section("Súly") { Picker("Súly", selection: $addWeight) { Text("100%").tag(100); Text("200%").tag(200); Text("50%").tag(50) }.pickerStyle(.segmented).summitSelectionHaptic(trigger: addWeight) }
                    Section { Text("Előnézet átlag: \(String(format: "%.2f", GradingLogic.weightedAverage(allGrades + [GradeItem(id: "phantom-\(UUID())", subject: subject, value: addValue, valueText: "\(addValue)", date: Date(), teacher: "", type: "Fantom", weight: addWeight, topic: "")])))").font(.callout).foregroundStyle(.secondary) }
                }
                .navigationTitle("Fantom jegy")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Mégse") { showAdd = false } }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Hozzáadás") {
                            let g = GradeItem(id: "phantom-\(UUID())", subject: subject, value: addValue, valueText: "\(addValue)", date: Date().addingTimeInterval(Double(phantom.count)*60), teacher: "Fantom", type: "Fantom", weight: addWeight, topic: "")
                            withAnimation(SummitMotion.gentle) { phantom.append(g) }
                            // Fantom felvéve = ünnepelt kimenet (beesik a listába).
                            SummitHaptics.success()
                            showAdd = false
                        }.tint(colors.accent)
                    }
                }
            }
            .presentationDetents([.medium])
        }
        .sheet(item: $replaceTarget) { orig in
            ReplaceGradeSheet(subject: subject, original: orig, grades: allGrades,
                              threshold: threshold, value: $replaceValue) { newValue in
                let pid = "phantom-\(UUID().uuidString)"
                let pg = GradeItem(id: pid, subject: subject, value: newValue,
                                   valueText: "\(newValue)", date: orig.date,
                                   teacher: "Fantom", type: "Fantom • eredeti: \(orig.value)",
                                   weight: orig.weight, topic: "")
                withAnimation(SummitMotion.gentle) {
                    phantom.append(pg)
                    replacedIds.insert(orig.id)
                    phantomLinks[pid] = orig.id
                }
                replaceTarget = nil
            }
        }
    }
}

// MARK: - "Mi lett volna ha" csere-lap
// Valódi jegy lecserélése fantomra: az eredeti kikerül az átlagból,
// a választott értékű fantom bekerül — az előnézet mutatja az új átlagot.
private struct ReplaceGradeSheet: View {
    let subject: String
    let original: GradeItem
    let grades: [GradeItem]
    let threshold: Double
    @Binding var value: Int
    let onReplace: (Int) -> Void
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var theme: ThemeStore
    @Environment(\.colorScheme) var scheme

    private var preview: Double {
        let cand = GradeItem(id: "preview", subject: subject, value: value,
                             valueText: "\(value)", date: original.date,
                             teacher: "", type: "", weight: original.weight, topic: "")
        return GradingLogic.weightedAverage(grades.filter { $0.id != original.id } + [cand])
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Eredeti jegy") {
                    Text("\(original.value) • \(original.weight)%")
                        .font(.headline)
                }
                Section("Mi lett volna ha") {
                    Picker("Fantom jegy", selection: $value) {
                        ForEach(1...5, id: \.self) { Text("\($0)").tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .summitSelectionHaptic(trigger: value)
                }
                Section("Előnézet") {
                    Text(String(format: "Átlag: %.2f → kerekítve %d-es",
                                preview, GradingLogic.roundedGrade(raw: preview, threshold: threshold)))
                        .font(.callout).foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Mi lett volna ha")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Mégse") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Csere fantomra") {
                        SummitHaptics.success()
                        onReplace(value); dismiss()
                    }
                        .tint(theme.colors(for: scheme).accent)
                }
            }
        }
        .presentationDetents([.medium])
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
