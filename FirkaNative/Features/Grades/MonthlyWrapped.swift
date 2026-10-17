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
        /// Hiányzások (db), ebből igazolatlan.
        var absences: Int
        var unjustified: Int
        /// Késések (db) és késési percek összege.
        var lateCount: Int
        var lateMinutes: Int
        /// Dolgozatok a hónapban (bejelentett + pótolt, kijelzett dátum szerint).
        var exams: Int
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
    /// A dolgozatok/hiányzások a kijelzett dátum hónapja szerint számítanak.
    static func stats(grades: [GradeItem], month: Month, exams: [ExamItem] = [], absences: [AbsenceItem] = [], calendar: Calendar = .current) -> Stats {
        func inMonth(_ d: Date, _ m: Month) -> Bool {
            let c = calendar.dateComponents([.year, .month], from: d)
            return c.year == m.year && c.month == m.month
        }
        func inMonthGrade(_ g: GradeItem, _ m: Month) -> Bool {
            inMonth(g.date, m) && g.value != 0
        }
        let mine = grades.filter { inMonthGrade($0, month) }
        let monthAbsences = absences.filter { inMonth($0.date, month) }
        let monthExams = exams.filter { inMonth($0.date, month) }
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
        let prevBySubject = Dictionary(grouping: grades.filter { inMonthGrade($0, prev) }, by: { $0.subject })
        let improved: (name: String, delta: Double)? = bySubject.compactMap { (subject, list) -> (String, Double)? in
            guard let old = prevBySubject[subject], !old.isEmpty else { return nil }
            let d = GradingLogic.weightedAverage(list) - GradingLogic.weightedAverage(old)
            return d > 0.005 ? (subject, d) : nil
        }.max { $0.1 < $1.1 }
        let lates = monthAbsences.compactMap { $0.delay }.filter { $0 > 0 }
        return Stats(count: mine.count, avg: avg, fives: dist[5] ?? 0,
                     distribution: dist, bestSubject: best, mostImproved: improved,
                     absences: monthAbsences.count,
                     unjustified: monthAbsences.filter { !$0.isJustified }.count,
                     lateCount: lates.count, lateMinutes: lates.reduce(0, +),
                     exams: monthExams.count)
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

// MARK: - Wrapped-kártya (fullscreen, ellenőrző-könyv editorial)
//
// Nem középre rendezett csillogás: balra zárt óriás-átlag, alatta
// surface-csempék (az app kártyanyelvén), egybefüggő eloszlás-sáv,
// jobb fent megosztás + bezárás. Belépés lépcsőzve (stagger).
struct MonthlyWrappedCard: View {
    let month: MonthlyWrapped.Month
    let stats: MonthlyWrapped.Stats
    var onClose: () -> Void
    @EnvironmentObject var theme: ThemeStore
    @Environment(\.colorScheme) var scheme
    @State private var appeared = false
    @State private var shareItems: [Any] = []
    @State private var showShare = false

    var colors: AppColors { theme.colors(for: scheme) }
    /// Az átlag színe az 1–5 skálán (mint a jegykörök).
    var avgColor: Color { colors.gradeColor(for: Int(stats.avg.rounded())) }
    /// Eloszlás-színek a megosztott képnek is (explicit, env-független).
    var distColors: [Int: Color] {
        Dictionary(uniqueKeysWithValues: (1...5).map { ($0, colors.gradeColor(for: $0)) })
    }

    var body: some View {
        ZStack {
            colors.background.ignoresSafeArea()
            VStack(spacing: 0) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        // Felső sor: kicker + megosztás/bezárás (semleges körök)
                        HStack(alignment: .center) {
                            Text(month.wrappedTitle.uppercased())
                                .font(.caption2.weight(.semibold))
                                .tracking(2)
                                .foregroundStyle(.secondary)
                            Spacer()
                            Button {
                                SummitHaptics.selection()
                                share()
                            } label: {
                                Image(systemName: "square.and.arrow.up")
                                    .font(.system(size: 15, weight: .semibold))
                                    .foregroundStyle(.secondary)
                                    .frame(width: 34, height: 34)
                                    .background(Circle().fill(Color.primary.opacity(0.08)))
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Megosztás")
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

                    // Hős: hónap + átlag — az egyetlen színes pont a képernyőn
                    VStack(alignment: .leading, spacing: 2) {
                        Text(month.title)
                            .font(.system(size: 32, weight: .bold, design: .rounded))
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                        Text("\(stats.count) jegy • \(stats.exams) dolgozat")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 14)
                    .stagger(appeared, 0)
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(String(format: "%.1f", stats.avg))
                            .font(.system(size: 80, weight: .bold, design: .rounded))
                            .foregroundStyle(avgColor)
                            .monospacedDigit()
                            .lineLimit(1)
                            .minimumScaleFactor(0.6)
                        Text("átlag")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 2)
                    .stagger(appeared, 0.08)

                    // Csempék: monokróm, mint az app sorai — számok primary,
                    // feliratok secondary, ikonok egységesen secondary
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                        wrappedTile(icon: "star", value: "\(stats.fives)", label: "ötös",
                                    sub: "\(stats.count) jegyből")
                        wrappedTile(icon: "clock", value: "\(stats.absences)", label: "hiányzás",
                                    sub: stats.unjustified == 0 ? "mind igazolt" : "\(stats.unjustified) igazolatlan")
                        wrappedTile(icon: "alarm", value: "\(stats.lateCount)", label: "késés",
                                    sub: stats.lateCount == 0 ? "egyszer sem" : "\(stats.lateMinutes) perc")
                        wrappedTile(icon: "doc.text", value: "\(stats.exams)", label: "dolgozat",
                                    sub: "e hónapban")
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 20)
                    .stagger(appeared, 0.16)

                    // Sorok: legjobb + legtöbbet javult (semleges ikonokkal)
                    VStack(spacing: 0) {
                        if let best = stats.bestSubject {
                            wrappedRow(icon: "trophy", title: "Legjobb tárgyad",
                                       value: "\(best.name) • \(String(format: "%.1f", best.avg))")
                            if stats.mostImproved != nil { Divider().padding(.leading, 48) }
                        }
                        if let imp = stats.mostImproved {
                            wrappedRow(icon: "chart.line.uptrend.xyaxis", title: "Legtöbbet javultál",
                                       value: "\(imp.name) • +\(String(format: "%.1f", imp.delta))")
                        }
                    }
                    .background(colors.surface)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                    .padding(.horizontal, 20)
                    .padding(.top, 20)
                    .stagger(appeared, 0.24)

                    // Eloszlás: vékony sáv + visszafogott jelmagyarázat
                    VStack(alignment: .leading, spacing: 8) {
                        Text("ELOSZLÁS")
                            .font(.caption2.weight(.semibold))
                            .tracking(1)
                            .foregroundStyle(.secondary)
                        WrappedDistBar(distribution: stats.distribution, colors: distColors)
                        HStack(spacing: 12) {
                            ForEach([5, 4, 3, 2, 1], id: \.self) { v in
                                HStack(spacing: 4) {
                                    Text("\(v)").font(.caption.weight(.semibold))
                                        .foregroundStyle(.secondary)
                                    Text("×\(stats.distribution[v] ?? 0)")
                                        .font(.caption2.monospacedDigit())
                                        .foregroundStyle(.tertiary)
                                }
                            }
                            Spacer()
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 22)
                    .padding(.bottom, 24)
                    .stagger(appeared, 0.32)
                    }
                }
                // Lábléc: lehorgonyozza az alját — nincs lógó űr
                Text("SUMMIT • \(month.title.uppercased())")
                    .font(.caption2.weight(.semibold))
                    .tracking(2)
                    .foregroundStyle(.tertiary)
                    .padding(.bottom, 18)
            }
        }
        .onAppear {
            SummitHaptics.success()
            withAnimation(SummitMotion.gentle) { appeared = true }
        }
        .sheet(isPresented: $showShare) {
            ShareSheet(items: shareItems)
                .presentationDetents([.medium, .large])
        }
    }

    private func wrappedTile(icon: String, value: String, label: String, sub: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.secondary)
                Text(label)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            Text(value)
                .font(.system(size: 28, weight: .bold, design: .rounded))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(sub)
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(colors.surface)
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    private func wrappedRow(icon: String, title: String, value: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                Text(value).font(.subheadline.weight(.semibold)).lineLimit(1)
            }
            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    // MARK: Megosztás

    /// Kártyakép + szöveg a rendszer-megosztóba (pl. üzenet, Insta-sztori).
    private func share() {
        let image = WrappedShareImage(
            title: month.wrappedTitle, avg: stats.avg, avgColor: avgColor,
            count: stats.count, fives: stats.fives,
            absences: stats.absences, lateCount: stats.lateCount,
            lateMinutes: stats.lateMinutes, exams: stats.exams,
            bestSubject: stats.bestSubject?.name, bestAvg: stats.bestSubject?.avg,
            distribution: stats.distribution, distColors: distColors
        )
        let renderer = ImageRenderer(content: image.frame(width: 390, height: 600))
        renderer.scale = 3
        var items: [Any] = []
        if let uiImage = renderer.uiImage {
            items.append(uiImage)
        }
        items.append("\(month.wrappedTitle): \(String(format: "%.1f", stats.avg)) átlag, \(stats.count) jegy — Summit")
        AnalyticsStore.recordStep("wrapped_share", detail: month.id)
        shareItems = items
        showShare = true
    }
}

/// Lépcsőzött belépés egy blokkra (késleltetett fade + csúszás).
private struct Stagger: ViewModifier {
    var appeared: Bool
    var delay: Double
    func body(content: Content) -> some View {
        content
            .opacity(appeared ? 1 : 0)
            .offset(y: appeared ? 0 : 14)
            .animation(SummitMotion.entrance(delay: delay), value: appeared)
    }
}

private extension View {
    func stagger(_ appeared: Bool, _ delay: Double) -> some View {
        modifier(Stagger(appeared: appeared, delay: delay))
    }
}

/// Egybefüggő eloszlás-sáv (5→1, jegyszínekkel), nulla darabbal is stabil.
struct WrappedDistBar: View {
    var distribution: [Int: Int]
    var colors: [Int: Color]
    var body: some View {
        GeometryReader { geo in
            let total = max(1, distribution.values.reduce(0, +))
            HStack(spacing: 2) {
                ForEach([5, 4, 3, 2, 1], id: \.self) { v in
                    let n = distribution[v] ?? 0
                    if n > 0 {
                        RoundedRectangle(cornerRadius: 4)
                            .fill((colors[v] ?? .secondary).opacity(0.85))
                            .frame(width: max(8, geo.size.width * CGFloat(n) / CGFloat(total)))
                            .frame(height: 8)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(height: 8)
    }
}

/// Megosztott kép (env-független, fix méret): sötét kártya, óriás-átlag,
/// négy stat-sor, eloszlás-sáv, Summit-jel.
struct WrappedShareImage: View {
    var title: String
    var avg: Double
    var avgColor: Color
    var count: Int
    var fives: Int
    var absences: Int
    var lateCount: Int
    var lateMinutes: Int
    var exams: Int
    var bestSubject: String?
    var bestAvg: Double?
    var distribution: [Int: Int]
    var distColors: [Int: Color]

    private var lateLabel: String {
        if lateCount == 0 { return "késés" }
        return "késés • \(lateMinutes) perc"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title.uppercased())
                .font(.system(size: 15, weight: .bold))
                .tracking(4)
                .foregroundStyle(.white.opacity(0.6))
            Text(String(format: "%.1f", avg))
                .font(.system(size: 140, weight: .bold, design: .rounded))
                .padding(.top, 4)
                .foregroundStyle(avgColor)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text("\(count) jegy • \(fives) ötös • \(exams) dolgozat")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(.white.opacity(0.75))
                .padding(.top, 2)
            if let best = bestSubject, let ba = bestAvg {
                Text("Legjobb: \(best) • \(String(format: "%.1f", ba))")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.75))
                    .padding(.top, 2)
            }
            Spacer(minLength: 16)
            VStack(alignment: .leading, spacing: 8) {
                shareLine(value: "\(absences)", label: "hiányzás")
                shareLine(value: "\(lateCount)", label: lateLabel)
            }
            WrappedDistBar(distribution: distribution, colors: distColors)
                .padding(.top, 18)
            Spacer(minLength: 20)
            Text("SUMMIT")
                .font(.system(size: 16, weight: .bold))
                .tracking(6)
                .foregroundStyle(.white.opacity(0.45))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(30)
        .background(
            LinearGradient(
                colors: [Color(white: 0.12), Color(white: 0.05)],
                startPoint: .top, endPoint: .bottom
            )
        )
    }

    private func shareLine(value: String, label: String) -> some View {
        HStack(spacing: 8) {
            Text(value)
                .font(.system(size: 20, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .monospacedDigit()
            Text(label)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(.white.opacity(0.65))
        }
    }
}

/// Rendszer-megosztó (UIActivityViewController) SwiftUI-ból.
struct ShareSheet: UIViewControllerRepresentable {
    var items: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        let vc = UIActivityViewController(activityItems: items, applicationActivities: nil)
        // iPad: felugró horgony nélkül crashel — a billentyűzet fölé tesszük.
        if let pop = vc.popoverPresentationController,
           let window = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .flatMap({ $0.windows })
            .first(where: { $0.isKeyWindow }) {
            pop.sourceView = window.rootViewController?.view ?? window
            let b = (window.rootViewController?.view ?? window).bounds
            pop.sourceRect = CGRect(x: b.midX, y: b.maxY, width: 0, height: 0)
            pop.permittedArrowDirections = []
        }
        return vc
    }
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
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
    @State private var exams: [ExamItem] = []
    @State private var absences: [AbsenceItem] = []
    @State private var opened: MonthlyWrapped.Month?
    var colors: AppColors { theme.colors(for: scheme) }

    var body: some View {
        List {
            if grades.isEmpty {
                Text("Még nincs jegy — az első hónap után itt lesz a Wrapped.")
                    .font(.subheadline).foregroundStyle(.secondary)
            } else {
                ForEach(MonthlyWrapped.months(grades: grades), id: \.id) { m in
                    let st = MonthlyWrapped.stats(grades: grades, month: m, exams: exams, absences: absences)
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
                stats: MonthlyWrapped.stats(grades: grades, month: m, exams: exams, absences: absences),
                onClose: { opened = nil }
            )
            .environmentObject(theme)
        }
    }

    private func load() async {
        guard let user = session.selectedUser else { return }
        let iss = user.instituteCode.isEmpty ? (JWT.instituteCode(from: user.accessToken) ?? "") : user.instituteCode
        guard !iss.isEmpty, iss != "unknown" else { return }
        // Gyorstáras lehúzások (tipikusan hálózat nélkül jönnek).
        async let g = kreta.fetchGrades(iss: iss)
        async let e = kreta.fetchExams(iss: iss)
        async let a = kreta.fetchAbsences(iss: iss)
        grades = await g
        exams = await e
        absences = await a
    }
}
