import SwiftUI

struct SubjectDetailView: View {
    let subject: String
    /// A tárgy évközi jegyei dátum szerint. NEM `@State`: az egyszeri
    /// másolat a push pillanatában befagyott (ha akkor még nem volt meg a
    /// lista, a részlet üres maradt). Így a hívó (Jegyek lista / Főoldal)
    /// friss adata élőben átjön; a fantomok külön állapotban élnek.
    let grades: [GradeItem]
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
                            Text(allGrades.isEmpty ? "Még nincs jegy ebből a tárgyból" : String(format: "Nyers átlag %.2f → kerekítve %d-es", rawAvg, rounded))
                                .skinFont(.caption, weight: .medium)
                                .foregroundStyle(.secondary)
                            Text(String(format: "Kerekítés %.2f-től • %d jegy", threshold, allGrades.count))
                                .skinFont(.caption2, weight: .medium)
                                .foregroundStyle(.tertiary)
                        }
                        Spacer()
                        if allGrades.isEmpty {
                            // Jegy nélkül nincs átlag: nem „0-s" / „1-es" kör.
                            Text("—")
                                .mcDisplay(22)
                                .foregroundStyle(.tertiary)
                                .frame(width: 50, height: 50)
                        } else if CyberpunkTheme.isActive {
                            CPGradeBadge(value: rounded, size: 50)
                        } else if MinecraftTheme.isActive {
                            McGradeBlock(value: rounded, size: 50, fontSize: 22)
                        } else {
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
                    }

                    if CyberpunkTheme.isActive { CPDivider() } else if MinecraftTheme.isActive { McSeparator(footer: true) } else { Divider().opacity(0.45) }

                    // Szűrő — Home Tab stílusú, compact
                    SkinSegmentedPicker(selection: $graphRange, options: GraphRange.allCases.map { ($0, $0.title) })
                        .controlSize(.small)

                    // Grafikon — prémium morph, nem vágja le a tetejét (domain 1...5.45 + 14pt top inset)
                    GradeChartView(grades: chartGrades, accent: colors.accent, showTarget: nil, height: 190, editorial: false)

                    // Lábjegyzet — Home LiveCard ihletésű, finom progress jelleg
                    HStack(spacing: 6) {
                        MinecraftTheme.dot.fill(colors.accent).frame(width: 6, height: 6)
                        Text(allGrades.isEmpty ? "Nincs átlag" : String(format: "Jelenlegi átlag %.2f", rawAvg))
                            .skinFont(.caption, weight: .semibold)
                            .foregroundStyle(.secondary)
                        Spacer()
                        if let d = deltaText {
                            Text(d.text).skinFontDigits(.caption2, weight: .bold).foregroundStyle(d.color)
                                .padding(.horizontal, 7).padding(.vertical, 3)
                                .background(MinecraftTheme.capsule.fill(d.color.opacity(0.12)))
                        } else {
                            Text("stabil").skinFont(.caption2, weight: .medium).foregroundStyle(.tertiary)
                        }
                    }
                    if hasPhantom {
                        HStack(spacing: 6) {
                            Text("FANTOM ELŐNÉZET").skinFont(.caption2, weight: .bold).foregroundStyle(.orange)
                                .padding(.horizontal, 7).padding(.vertical, 3)
                                .background(MinecraftTheme.capsule.fill(Color.orange.opacity(0.14)))
                            Text(String(format: "eredeti %.2f → most %.2f", baseRaw, rawAvg))
                                .skinFont(.caption2, weight: .medium).foregroundStyle(.secondary)
                            Spacer()
                        }
                    }
                }
                .padding(.vertical, 4)
                .summitRowSurface(colors: colors)
                .listRowInsets(MinecraftTheme.rowInsets(EdgeInsets(top: 14, leading: 16, bottom: 14, trailing: 16)))
            } header: {
                Text("Átlag és grafikon").mcSectionHeader()
            }

            Section {
                if allGrades.isEmpty {
                    // Jegy nélküli tárgy: üres szekció helyett magyarázat.
                    Text("Ebből a tárgyból még nincs évközi jegyed. A + gombbal fantom jegyet adhatsz hozzá, és megnézheted, hogyan alakulna az átlagod.")
                        .skinFont(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .mcListRow(fill: colors.surface)
                }
                ForEach(allGrades.sorted(by: { $0.date > $1.date })) { g in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 10) {
                            if CyberpunkTheme.isActive {
                                CPGradeBadge(value: g.value, size: 30)
                                    .opacity(g.id.hasPrefix("phantom") ? 0.6 : 1)
                            } else if MinecraftTheme.isActive {
                                McGradeBlock(value: g.value, size: 30, fontSize: 12)
                                    .opacity(g.id.hasPrefix("phantom") ? 0.6 : 1)
                            } else {
                            Text("\(g.value)").skinFontDigits(.caption, weight: .bold).foregroundStyle(colors.gradeColor(for: g.value))
                            .frame(width: 28, height: 28)
                            .background {
                                Circle().fill(Color.clear).glassEffect(.clear, in: .circle)
                            }
                            .overlay(Circle().strokeBorder(colors.border.opacity(0.9), lineWidth: 1))
                            .opacity(g.id.hasPrefix("phantom") ? 0.6 : 1)
                            }
                            VStack(alignment: .leading, spacing: 2) {
                                Text(g.date.formatted(date: .abbreviated, time: .omitted) + " • \(g.weight)%").skinFont(.caption, weight: .medium)
                                if g.plainTopic.isEmpty {
                                    Text(friendlyGradeType(g.type)).skinFont(.caption2).foregroundStyle(.secondary)
                                }
                            }
                            Spacer()
                            if g.id.hasPrefix("phantom") {
                                Text("fantom").skinFont(.caption2, weight: .bold).foregroundStyle(.orange).padding(.horizontal, 6).padding(.vertical, 2).background(MinecraftTheme.capsule.fill(Color.orange.opacity(0.14)))
                            }
                        }
                        if !g.plainTopic.isEmpty {
                            Text(g.plainTopic).skinFont(.caption).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.top, 2)
                        }
                    }
                    .padding(.vertical, 2)
                    .mcListRow(fill: colors.surface)
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
                Button { showAdd = true } label: { SkinIcon("plus.circle.fill", size: 22).skinFont(.title3) }
                .skinToolbarItem()
                .tint(colors.accent)
            }
            .skinToolbarBackground()
        }
        .sheet(isPresented: $showAdd) {
            NavigationStack {
                Form {
                    SkinFormSection(title: "Érték", fill: colors.surface) { SkinSegmentedPicker(selection: $addValue, options: (1...5).map { ($0, "\($0)") }, accessibilityTitle: "Jegy").summitSelectionHaptic(trigger: addValue) }
                    SkinFormSection(title: "Súly", fill: colors.surface) { SkinSegmentedPicker(selection: $addWeight, options: [(100, "100%"), (200, "200%"), (50, "50%")], accessibilityTitle: "Súly").summitSelectionHaptic(trigger: addWeight) }
                    Section { Text("Előnézet átlag: \(String(format: "%.2f", GradingLogic.weightedAverage(allGrades + [GradeItem(id: "phantom-\(UUID())", subject: subject, value: addValue, valueText: "\(addValue)", date: Date(), teacher: "", type: "Fantom", weight: addWeight, topic: "")])))").skinFont(.callout).foregroundStyle(.secondary).mcListRow(fill: colors.surface) }
                }
                .skinFormBackground()
                .navigationTitle("Fantom jegy")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Mégse") { showAdd = false }.skinToolbarItem() }
                        .skinToolbarBackground()
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Hozzáadás") {
                            let g = GradeItem(id: "phantom-\(UUID())", subject: subject, value: addValue, valueText: "\(addValue)", date: Date().addingTimeInterval(Double(phantom.count)*60), teacher: "Fantom", type: "Fantom", weight: addWeight, topic: "")
                            withAnimation(SummitMotion.gentle) { phantom.append(g) }
                            // Fantom felvéve = ünnepelt kimenet (beesik a listába).
                            SummitHaptics.success()
                            showAdd = false
                        }.skinToolbarItem().tint(colors.accent)
                    }
                    .skinToolbarBackground()
                }
            }
            .skinSheetBackground()
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
    private var colors: AppColors { theme.colors(for: scheme) }

    private var preview: Double {
        let cand = GradeItem(id: "preview", subject: subject, value: value,
                             valueText: "\(value)", date: original.date,
                             teacher: "", type: "", weight: original.weight, topic: "")
        return GradingLogic.weightedAverage(grades.filter { $0.id != original.id } + [cand])
    }

    var body: some View {
        NavigationStack {
            Form {
                SkinFormSection(title: "Eredeti jegy", fill: colors.surface) {
                    Text("\(original.value) • \(original.weight)%")
                        .skinFont(.headline)
                }
                SkinFormSection(title: "Mi lett volna ha", fill: colors.surface) {
                    SkinSegmentedPicker(selection: $value, options: (1...5).map { ($0, "\($0)") }, accessibilityTitle: "Fantom jegy")
                        .summitSelectionHaptic(trigger: value)
                }
                SkinFormSection(title: "Előnézet", fill: colors.surface) {
                    Text(String(format: "Átlag: %.2f → kerekítve %d-es",
                                preview, GradingLogic.roundedGrade(raw: preview, threshold: threshold)))
                        .skinFont(.callout).foregroundStyle(.secondary)
                }
            }
            .skinFormBackground()
            .navigationTitle("Mi lett volna ha")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Mégse") { dismiss() }.skinToolbarItem() }
                    .skinToolbarBackground()
                ToolbarItem(placement: .confirmationAction) {
                    Button("Csere fantomra") {
                        SummitHaptics.success()
                        onReplace(value); dismiss()
                    }
                        .skinToolbarItem()
                        .tint(theme.colors(for: scheme).accent)
                }
                .skinToolbarBackground()
            }
        }
        .skinSheetBackground()
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

private extension MinecraftTheme {
    /// Kis pont-jelző: Summitban kör, Minecraftban négyzet (pixel),
    /// Cyberpunkban kis rombusz (HUD-jelölő).
    static var dot: AnyShape {
        if isActive { return AnyShape(Rectangle()) }
        if CyberpunkTheme.isActive { return AnyShape(CPChamferShape(cut: 3, corners: .all)) }
        return AnyShape(Circle())
    }
}
