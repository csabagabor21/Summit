import SwiftUI

// MARK: - Havi Wrapped („szeptembered számokban")
//
// Egy hónap jegyeiből számolt megosztható kártya: átlag, darabszám,
// ötösök, legjobb tárgy, legtöbbet javult tárgy, eloszlás.
// Adat: csak a jegyek dátuma/értéke/tárgya — új hálózat, új szinkron,
// új kapcsoló nincs (a banner magától lejár 6-án).
enum MonthlyWrapped {
    /// Hónap-azonosító (év + hónap), időrendbe rendezhető.
    struct Month: Hashable, Identifiable {
        var year: Int
        var month: Int
        var id: String { "\(year)-\(month)" }
        /// A hónap első napja (szűréshez, címhez).
        func start(calendar: Calendar = .current) -> Date {
            calendar.date(from: DateComponents(year: year, month: month, day: 1)) ?? Date()
        }
        /// „2026. október" — kártyacímnek, bannernek.
        var title: String {
            let f = DateFormatter()
            f.locale = Locale(identifier: "hu_HU")
            f.dateFormat = "yyyy. MMMM"
            return f.string(from: start()).capitalized
        }
        /// „Októberi Wrapped" — banner-címnek.
        var wrappedTitle: String {
            let f = DateFormatter()
            f.locale = Locale(identifier: "hu_HU")
            f.dateFormat = "MMMM"
            let m = f.string(from: start()).capitalized
            // „Október" → „Októberi": toldalékolás az -r végű hónapokra is jó.
            return m + "i Wrapped"
        }
    }

    struct Stats {
        var count: Int
        var avg: Double
        var fives: Int
        /// Eloszlás: jegyérték → darab (csak a nem-nullák).
        var distribution: [Int: Int]
        /// Legjobb tárgy (név, átlag) — min. 2 jegy kell, különben a legtöbb jegyes.
        var bestSubject: (name: String, avg: Double)?
        /// Legtöbbet javult tárgy az előző hónaphoz (név, delta).
        var mostImproved: (name: String, delta: Double)?
    }

    /// Hónapok a jegyekből (csak nem-0 jegyek, csökkenő sorrend).
    static func months(grades: [GradeItem], calendar: Calendar = .current) -> [Month] {
        let keys = Set(grades.filter { $0.value != 0 }.map {
            let c = calendar.dateComponents([.year, .month], from: $0.date)
            return Month(year: c.year ?? 0, month: c.month ?? 0)
        })
        return keys.sorted {
            $0.year != $1.year ? $0.year > $1.year : $0.month > $1.month
        }
    }

    /// Egy hónap statisztikája (az előző havi javuláshoz az összes jegy kell).
    static func stats(grades: [GradeItem], month: Month, calendar: Calendar = .current) -> Stats {
        func inMonth(_ g: GradeItem, _ m: Month) -> Bool {
            let c = calendar.dateComponents([.year, .month], from: g.date)
            return c.year == m.year && c.month == m.month && g.value != 0
        }
        let mine = grades.filter { inMonth($0, month) }
        let avg = mine.isEmpty ? 0 : GradingLogic.weightedAverage(mine)
        var dist: [Int: Int] = [:]
        for g in mine { dist[g.value, default: 0] += 1 }
        // Legjobb tárgy: min. 2 jegyesek közül a legjobb átlag, különben a legtöbb jegy tárgya.
        let bySubject = Dictionary(grouping: mine, by: { $0.subject })
        let best: (name: String, avg: Double)? = {
            let ranked = bySubject.map { (name: $0.key, avg: GradingLogic.weightedAverage($0.value), n: $0.value.count) }
                .sorted { $0.avg != $1.avg ? $0.avg > $1.avg : $0.n > $1.n }
            if let two = ranked.first(where: { $0.n >= 2 }) { return (two.name, two.avg) }
            return ranked.first.map { ($0.name, $0.avg) }
        }()
        // Javulás: tárgyankénti átlag-delta az előző hónaphoz (ott is ≥1 jegy kell).
        let prev: Month = {
            month.month == 1
                ? Month(year: month.year - 1, month: 12)
                : Month(year: month.year, month: month.month - 1)
        }()
        let prevBySubject = Dictionary(grouping: grades.filter { inMonth($0, prev) }, by: { $0.subject })
        let improved: (name: String, delta: Double)? = bySubject.compactMap { (subject, list) -> (String, Double)? in
            guard let old = prevBySubject[subject], !old.isEmpty else { return nil }
            let d = GradingLogic.weightedAverage(list) - GradingLogic.weightedAverage(old)
            return d > 0.005 ? (subject, d) : nil
        }.max { $0.1 < $1.1 }
        return Stats(count: mine.count, avg: avg, fives: dist[5] ?? 0,
                     distribution: dist, bestSubject: best, mostImproved: improved)
    }

    /// Banner-hónap: a hónap első 5 napján az előző hónap (ha volt jegy).
    /// 6-ától nil — a banner magától eltűnik, archívum a profilból nyílik.
    static func bannerMonth(grades: [GradeItem], now: Date = Date(), calendar: Calendar = .current) -> Month? {
        guard calendar.component(.day, from: now) <= 5 else { return nil }
        let c = calendar.dateComponents([.year, .month], from: now)
        let prev = (c.month ?? 1) == 1
            ? Month(year: (c.year ?? 0) - 1, month: 12)
            : Month(year: c.year ?? 0, month: (c.month ?? 1) - 1)
        let has = grades.contains {
            let g = calendar.dateComponents([.year, .month], from: $0.date)
            return g.year == prev.year && g.month == prev.month && $0.value != 0
        }
        return has ? prev : nil
    }
}

// MARK: - Wrapped-kártya (fullscreen, a design nyelvén)
//
// Ünnepi háttér + liquid glass kör nagy átlagszámmal (mint az újjegy-
// kártya), alatta stat-sorok és eloszlás-sávok. Nincs konfetti:
// ez áttekintő, nem ünnep.
struct MonthlyWrappedCard: View {
    let month: MonthlyWrapped.Month
    let stats: MonthlyWrapped.Stats
    var onClose: () -> Void
    @EnvironmentObject var theme: ThemeStore
    @Environment(\.colorScheme) var scheme
    @State private var appeared = false

    var colors: AppColors { theme.colors(for: scheme) }
    /// Az átlag színe az 1–5 skálán (mint a jegykörök).
    private var avgColor: Color { colors.gradeColor(for: Int(stats.avg.rounded())) }

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [avgColor.opacity(scheme == .dark ? 0.38 : 0.28), colors.background],
                startPoint: .top, endPoint: .bottom
            )
            .ignoresSafeArea()
            VStack(spacing: 0) {
                HStack {
                    Spacer()
                    Button(action: onClose) {
                        Image(systemName: "xmark")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(.secondary)
                            .frame(width: 34, height: 34)
                            .background(Circle().fill(Color.primary.opacity(0.08)))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Bezárás")
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
                Text(month.wrappedTitle.uppercased())
                    .font(.caption.weight(.bold))
                    .tracking(3)
                    .foregroundStyle(.secondary)
                    .padding(.top, 6)
                Spacer(minLength: 12)
                // Hős: glass kör az átlaggal (új jegy-kártya stílus)
                ZStack {
                    Circle()
                        .fill(avgColor.opacity(0.25))
                        .blur(radius: 34)
                        .frame(width: 190, height: 190)
                    ZStack {
                        Circle().fill(Color.clear)
                            .glassEffect(.clear, in: .circle)
                            .overlay(Circle().strokeBorder(colors.border.opacity(0.9), lineWidth: 1.6))
                            .frame(width: 168, height: 168)
                        Text(String(format: "%.1f", stats.avg))
                            .font(.system(size: 64, weight: .bold, design: .rounded))
                            .foregroundStyle(avgColor)
                            .monospacedDigit()
                    }
                    .shadow(color: avgColor.opacity(0.35), radius: 24, y: 8)
                }
                .scaleEffect(appeared ? 1 : 0.6)
                .opacity(appeared ? 1 : 0)
                Text("\(stats.count) jegy • \(stats.fives) ötös")
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(.top, 12)
                    .opacity(appeared ? 1 : 0)
                Spacer(minLength: 16)
                // Stat-sorok + eloszlás
                VStack(alignment: .leading, spacing: 10) {
                    if let best = stats.bestSubject {
                        wrappedRow(icon: "trophy.fill", tint: .yellow,
                                   title: "Legjobb tárgyad",
                                   value: "\(best.name) • \(String(format: "%.1f", best.avg))")
                    }
                    if let imp = stats.mostImproved {
                        wrappedRow(icon: "chart.line.uptrend.xyaxis", tint: .green,
                                   title: "Legtöbbet javultál",
                                   value: "\(imp.name) • +\(String(format: "%.1f", imp.delta))")
                    }
                    distributionBars
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 28)
                .opacity(appeared ? 1 : 0)
                .animation(SummitMotion.entrance(delay: 0.15), value: appeared)
                Spacer(minLength: 20)
            }
        }
        .onAppear {
            SummitHaptics.success()
            withAnimation(SummitMotion.gentle) { appeared = true }
        }
    }

    private func wrappedRow(icon: String, tint: Color, title: String, value: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                Text(value).font(.subheadline.weight(.bold)).lineLimit(1)
            }
        }
    }

    private var distributionBars: some View {
        let maxCount = max(1, stats.distribution.values.max() ?? 1)
        return VStack(alignment: .leading, spacing: 6) {
            ForEach([5, 4, 3, 2, 1], id: \.self) { v in
                let n = stats.distribution[v] ?? 0
                HStack(spacing: 8) {
                    Text("\(v)")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(colors.gradeColor(for: v))
                        .frame(width: 12)
                    GeometryReader { geo in
                        RoundedRectangle(cornerRadius: 4)
                            .fill(colors.gradeColor(for: v).opacity(n == 0 ? 0.12 : 0.75))
                            .frame(width: max(8, geo.size.width * CGFloat(n) / CGFloat(maxCount)))
                            .frame(maxHeight: 10)
                    }
                    .frame(height: 10)
                    Text("\(n)")
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .frame(width: 20, alignment: .trailing)
                }
            }
        }
    }
}

// MARK: - Havi archívum (profilból)
//
// Minden jegyes hónap, csökkenő sorrendben. A jegyeket gyorstárból
// húzza (tipikusan hálózat nélkül), soronként átlag + darab.
struct MonthlyArchiveView: View {
    @EnvironmentObject var session: SessionStore
    @EnvironmentObject var kreta: KretaClient
    @EnvironmentObject var theme: ThemeStore
    @Environment(\.colorScheme) var scheme
    @State private var grades: [GradeItem] = []
    @State private var opened: MonthlyWrapped.Month?
    var colors: AppColors { theme.colors(for: scheme) }

    var body: some View {
        List {
            if grades.isEmpty {
                Text("Még nincs jegy — az első hónap után itt lesz a Wrapped.")
                    .font(.subheadline).foregroundStyle(.secondary)
            } else {
                ForEach(MonthlyWrapped.months(grades: grades), id: \.id) { m in
                    let st = MonthlyWrapped.stats(grades: grades, month: m)
                    Button {
                        SummitHaptics.selection()
                        AnalyticsStore.recordStep("wrapped_open", detail: m.id)
                        opened = m
                    } label: {
                        HStack(spacing: 12) {
                            Text(String(format: "%.1f", st.avg))
                                .font(.system(size: 20, weight: .bold, design: .rounded))
                                .foregroundStyle(colors.gradeColor(for: Int(st.avg.rounded())))
                                .monospacedDigit()
                                .frame(width: 52)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(m.title).font(.subheadline.weight(.semibold))
                                Text("\(st.count) jegy • \(st.fives) ötös")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.caption.weight(.semibold)).foregroundStyle(.tertiary)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .navigationTitle("Havi összefoglalók")
        .navigationBarTitleDisplayMode(.inline)
        .summitToolbarBackground()
        .task { await load() }
        .fullScreenCover(item: $opened) { m in
            MonthlyWrappedCard(
                month: m,
                stats: MonthlyWrapped.stats(grades: grades, month: m),
                onClose: { opened = nil }
            )
            .environmentObject(theme)
        }
    }

    private func load() async {
        guard let user = session.selectedUser else { return }
        let iss = user.instituteCode.isEmpty ? (JWT.instituteCode(from: user.accessToken) ?? "") : user.instituteCode
        guard !iss.isEmpty, iss != "unknown" else { return }
        grades = await kreta.fetchGrades(iss: iss)
    }
}
