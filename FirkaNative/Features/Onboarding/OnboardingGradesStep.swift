import SwiftUI

/// Bemutató — Jegyek lépés: a valódi Jegyek képernyő (`GradesView`)
/// évközi nézete a demo jegyekből (`DemoData.gradesExpanded()`), a valódi
/// elemekkel: átlag-összefoglaló sor (`gradeSummaryLabel`, `cpHero`,
/// `voxelSummaryRow`), havi grafikon (`GradeChartView`, ugyanúgy
/// paraméterezve), tantárgy-sorok (`GradesSubjectRow` /
/// iPaden `GradesSubjectCard`) és a lábléc-számláló.
///
/// Mozgás: a félév jegyei időrendben „beérkeznek" — minden új jegy
/// után a valódi `GradingLogic` újraszámolja az összátlagot és a
/// kerekítettet (a számok `numericText`-tel gördülnek), a grafikon pedig
/// a bővülő adatsorral rajzolódik ki. Közben a tantárgy-sorok egyenként
/// csúsznak be a végleges értékeikkel. A végén egy halk haptika.
/// Reduce Motion mellett azonnal a végállapot látszik.
struct OnboardingGradesStep: View {
    @EnvironmentObject var theme: ThemeStore
    @Environment(\.colorScheme) var scheme
    @Environment(\.horizontalSizeClass) private var hSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Az eddig „beérkezett" jegyek száma (időrendben).
    @State private var revealed = 0
    /// Az eddig megjelent tantárgy-sorok száma.
    @State private var visibleRows = 0

    private var isPad: Bool { hSize == .regular }
    private var colors: AppColors { theme.colors(for: scheme) }

    /// A demo adatkészlet, ahogy a Jegyek tab demo módban kapja:
    /// a jegyek, és a tárgylista (jegyek + mai órák tárgyai + az üres
    /// „Etika", mint a `KretaClient.fetchAllSubjectNames` demo-ága).
    private struct Model {
        /// Évközi, értékelhető jegyek dátum szerint növekvőben.
        let chronological: [GradeItem]
        /// Kijelzett tárgynév → évközi jegyek dátum szerint (végállapot).
        let grouped: [String: [GradeItem]]
        /// A sorok sorrendje (a Jegyek tab rendezése szerint).
        let subjects: [String]
        let names: [String: String]

        init() {
            let grades = DemoData.gradesExpanded()
            var subjectSet = Set(grades.map(\.subject))
            subjectSet.formUnion(DemoData.lessonsToday().map(\.subject))
            subjectSet.insert("Etika")
            let subjects = subjectSet
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty && $0 != "Ismeretlen" }
                .sorted()
            names = GradesView.displayNames(grades: grades, subjects: subjects)
            chronological = grades.filter { GradesView.isCountedEvkozi($0) }.sorted { $0.date < $1.date }
            grouped = Self.group(chronological, names: names)
            self.subjects = Set(grouped.keys).union(names.values)
                .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
        }

        /// Csoportosítás a kijelzett (kanonikus) névre — mint a Jegyek tab.
        static func group(_ grades: [GradeItem], names: [String: String]) -> [String: [GradeItem]] {
            Dictionary(grouping: grades) { g in
                names[SubjectMatcher.canonical(g.subject)] ?? g.subject.trimmingCharacters(in: .whitespacesAndNewlines)
            }.mapValues { $0.sorted { $0.date < $1.date } }
        }
    }

    @State private var model = Model()

    /// Az eddig beérkezett jegyek tárgyanként (az átlag-sorhoz).
    private var groupedSoFar: [String: [GradeItem]] {
        Model.group(Array(model.chronological.prefix(revealed)), names: model.names)
    }

    /// A grafikon adatsora: legalább két pont, hogy a grafikon már az
    /// első képkockán rajzoljon (ne az üres állapotot villantsa fel).
    private var chartGrades: [GradeItem] {
        Array(model.chronological.prefix(max(2, revealed)))
    }

    var body: some View {
        List {
            summarySection
            chartSection
            subjectRows
            footerSection
        }
        .listStyle(.insetGrouped)
        .frame(maxWidth: isPad ? MacSupport.contentWidth(ipad: 1280, mac: 1150) : .infinity)
        .padding(.horizontal, MacSupport.sidePadding)
        .frame(maxWidth: .infinity)
        .summitListChrome(colors: colors)
        .onAppear {
            if reduceMotion {
                revealed = model.chronological.count
                visibleRows = model.subjects.count
            }
        }
        .task { await play() }
    }

    // MARK: - A Jegyek tab szekciói

    /// ÖSSZÁTLAG / KEREKÍTVE — a Jegyek tab összefoglaló sora, a számok
    /// a beérkező jegyekkel gördülnek.
    private var summarySection: some View {
        let grouped = groupedSoFar
        let overall = GradingLogic.overallAverage(grouped: grouped)
        let rounded = GradingLogic.overallRoundedAverage(grouped: grouped)
        return Section {
            HStack(alignment: .lastTextBaseline, spacing: 16) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("ÖSSZÁTLAG").gradeSummaryLabel()
                    Text(grouped.isEmpty ? "—" : String(format: "%.2f", overall))
                        .voxelDisplay(34).cpHero(NeonTheme.yellow)
                        .contentTransition(.numericText(value: overall))
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text("KEREKÍTVE").gradeSummaryLabel()
                    Text(grouped.isEmpty ? "—" : String(format: "%.2f", rounded))
                        .voxelDisplay(34).cpHero(NeonTheme.cyanBright, chromatic: false)
                        .contentTransition(.numericText(value: rounded))
                }
            }
            .summitEntrance(delay: 0.05)
            .voxelSummaryRow(fill: colors.surface)
        }
    }

    /// „Átlag alakulása — havi" — a valódi grafikon, ugyanúgy paraméterezve.
    private var chartSection: some View {
        Section {
            GradeChartView(grades: chartGrades, accent: colors.accent, height: 150, monthly: true, editorial: true)
                .summitEntrance(delay: 0.12)
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
                .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
        } header: { Text("Átlag alakulása — havi").voxelSectionHeader() }
    }

    /// Tantárgy-sorok (iPaden rács-kártyák) — egyenként jelennek meg.
    /// Koppintásra a bemutatóban nem nyílik részlet.
    @ViewBuilder
    private var subjectRows: some View {
        let shown = Array(model.subjects.prefix(visibleRows))
        if isPad {
            let cols = [GridItem(.adaptive(minimum: 330), spacing: 12)]
            LazyVGrid(columns: cols, spacing: 12) {
                ForEach(shown, id: \.self) { subject in
                    GradesSubjectCard(subject: subject, items: model.grouped[subject], fill: colors.surface) {}
                        .transition(.opacity.combined(with: .scale(scale: 0.97)))
                }
            }.padding(.horizontal, 16).padding(.vertical, 8)
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets())
            .listRowSeparator(.hidden)
        } else {
            ForEach(shown, id: \.self) { subject in
                GradesSubjectRow(subject: subject, items: model.grouped[subject]) {}
                    .subjectRowChrome(fill: colors.surface)
            }
        }
    }

    /// Lábléc-számláló („12 jegy • 6/7 tárgy értékelve"), a sorok után.
    private var footerSection: some View {
        let gradedCount = model.grouped.count
        let totalCount = model.subjects.count
        let text = gradedCount == totalCount
            ? "\(model.chronological.count) jegy • \(gradedCount) tárgy"
            : "\(model.chronological.count) jegy • \(gradedCount)/\(totalCount) tárgy értékelve"
        return Section {
            if visibleRows >= totalCount {
                Text(text).gradeFooterText().frame(maxWidth: .infinity, alignment: .center).multilineTextAlignment(.center)
                    .transition(.opacity)
            }
        }
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
    }

    // MARK: - Koreográfia

    /// A jegyek időrendi „beérkezése" és a sorok lépcsőzetes megjelenése,
    /// egymásba fésülve. Lépésváltáskor (a nézet eltűnésekor) a `.task`
    /// megszakad, így félbehagyott animáció nem fut tovább.
    private func play() async {
        guard !reduceMotion else { return }
        let total = model.chronological.count
        let rows = model.subjects.count
        // A fejléc és a grafikon belépője előtt egy rövid levegővétel.
        guard await pause(0.45) else { return }
        var step = 0
        while revealed < total || visibleRows < rows {
            if revealed < total {
                withAnimation(SummitMotion.snappy) { revealed += 1 }
            }
            // A második ütemtől ütemenként egy új sor (a sorok előbb
            // érnek véget, mint a jegyek — a szem fentről lefelé halad).
            if step >= 1, visibleRows < rows {
                withAnimation(SummitMotion.gentle) { visibleRows += 1 }
            }
            step += 1
            guard await pause(0.15) else { return }
        }
        SummitHaptics.light()
    }

    /// Megszakítható várakozás; `false`, ha a lépést közben elhagyták.
    private func pause(_ seconds: Double) async -> Bool {
        try? await Task.sleep(for: .seconds(seconds))
        return !Task.isCancelled
    }
}
