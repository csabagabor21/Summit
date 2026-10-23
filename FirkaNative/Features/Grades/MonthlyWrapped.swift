import SwiftUI
import ImageIO

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
    /// Fiók-ID a keveréshez (minden fiók más sorrendet kap).
    var userId: String = ""
    /// A diák teljes neve („Nagy Csaba") — a címben a keresztneve szerepel
    /// („Csaba Wrappedje") a hegy neve helyett.
    var studentName: String = ""
    @EnvironmentObject var theme: ThemeStore
    @Environment(\.colorScheme) var scheme
    @Environment(\.accessibilityReduceTransparency) var reduceTransparency
    @State private var appeared = false
    @State private var showPicker = false
    /// A megnyitás pillanatában rögzített forgatási pozíció: a kártya egy
    /// megnyitáson belül stabil képet mutat (a számlálót az onAppear lépteti
    /// a KÖVETKEZŐ megnyitásra — különben minden újrarajzolás képet váltana).
    @State private var openIndex: Int? = nil
    /// Csillag-változás (helyi vagy syncelt) utáni újrarajzoláshoz.
    @State private var starsTick = 0

    var colors: AppColors { theme.colors(for: scheme) }
    /// Keresztnév magyar névsorrendből („Nagy Csaba" → „Csaba").
    var firstName: String {
        studentName.split(separator: " ").last.map(String.init) ?? "Diák"
    }
    /// „Csaba Wrappedje" — a kártya és a megosztó címe a hegy neve helyett.
    var personTitle: String { "\(firstName) Wrappedje" }
    /// A most mutatott kép: csillagozott hónapra a rögzített, különben a
    /// forgatás aktuális kockája. (A `starsTick` olvasása köti a nézetet a
    /// csillag-értesítéshez.)
    var shownArt: WrappedPeakArt {
        _ = starsTick
        if let name = WrappedStarStore.starredArt(monthId: month.id),
           let pinned = WrappedPeakArtCatalog.byName(name) { return pinned }
        let idx = openIndex ?? WrappedStarStore.openCount(monthId: month.id)
        return WrappedPeakArtCatalog.rotated(month: month, userId: userId, offset: idx)
    }
    /// Visszafelé kompatibilis név a fotó-nézeteknek.
    var art: WrappedPeakArt { shownArt }
    var isStarred: Bool {
        _ = starsTick
        return WrappedStarStore.starredArt(monthId: month.id) == shownArt.name
    }

    /// Csillag fel/le: a rögzített kép addig marad, amíg le nem veszik.
    /// A SummitSync a store-értesítésen át magától viszi a többi eszközre.
    private func toggleStar() {
        SummitHaptics.selection()
        WrappedStarStore.setStar(monthId: month.id, artName: isStarred ? nil : shownArt.name)
    }
    /// Fotó fölött minden szöveg fehér (bold + bright), tömör háttérnél
    /// a rendszer-színsémát tartjuk (Reduce Transparency-esés).
    var photo: Bool { !reduceTransparency }
    /// Az átlag színe az 1–5 skálán (mint a jegykörök).
    var avgColor: Color { colors.gradeColor(for: Int(stats.avg.rounded())) }
    /// Eloszlás-színek a megosztott képnek is (explicit, env-független).
    var distColors: [Int: Color] {
        Dictionary(uniqueKeysWithValues: (1...5).map { ($0, colors.gradeColor(for: $0)) })
    }

    var body: some View {
        Group {
            if MinecraftTheme.isActive {
                mcBody
            } else {
                summitBody
            }
        }
        .onAppear {
            SummitHaptics.success()
            // Forgatási pozíció rögzítése + számláló léptetése a következő
            // megnyitásra (csak egyszer — az openIndex őrzi a mostanit).
            if openIndex == nil {
                openIndex = WrappedStarStore.openCount(monthId: month.id)
                WrappedStarStore.bumpOpen(monthId: month.id)
            }
            withAnimation(SummitMotion.gentle) { appeared = true }
            // Minecraft: a kártya „toast-ként" érkezik (csak MC-skinben szól).
            McSound.play(.toastIn)
        }
        // Csillag-változás (ezen az eszközön vagy syncről): új kép/ikon.
        .onReceive(NotificationCenter.default.publisher(for: WrappedStarStore.changedNotification)) { _ in
            starsTick += 1
        }
        .fullScreenCover(isPresented: $showPicker) {
            WrappedSharePicker(month: month, stats: stats, distColors: distColors,
                               art: shownArt, personTitle: personTitle)
        }
    }

    // MARK: Summit ág (fotó + Liquid Glass) — változatlan

    private var summitBody: some View {
        ZStack {
            if photo {
                WrappedArtPhoto(art: art)
                // Olvashatósági sötétítés fent/lent (a fotó közepe szabadon marad)
                LinearGradient(
                    colors: [.black.opacity(0.55), .black.opacity(0.12),
                             .black.opacity(0.12), .black.opacity(0.62)],
                    startPoint: .top, endPoint: .bottom
                )
                .ignoresSafeArea()
            } else {
                colors.background.ignoresSafeArea()
            }
            VStack(spacing: 0) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        // Felső sor: kicker + megosztás/bezárás (élő glass körök)
                        HStack(alignment: .center) {
                            Text(month.wrappedTitle.uppercased())
                                .font(.caption2.weight(.semibold))
                                .tracking(2)
                                .foregroundStyle(photo ? .white.opacity(0.85) : .secondary)
                            Spacer()
                            Button(action: toggleStar) {
                                Image(systemName: isStarred ? "star.fill" : "star")
                                    .font(.system(size: 15, weight: .semibold))
                                    .foregroundStyle(isStarred ? .yellow : (photo ? .white : .secondary))
                                    .frame(width: 34, height: 34)
                                    .glassEffect(.regular.interactive(), in: Circle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(isStarred ? "Csillag levétele (a kép újra forog)" : "Kép rögzítése erre a hónapra")
                            Button {
                                SummitHaptics.selection()
                                share()
                            } label: {
                                Image(systemName: "square.and.arrow.up")
                                    .font(.system(size: 15, weight: .semibold))
                                    .foregroundStyle(photo ? .white : .secondary)
                                    .frame(width: 34, height: 34)
                                    .glassEffect(.regular.interactive(), in: Circle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Megosztás")
                            Button(action: onClose) {
                                Image(systemName: "xmark")
                                    .font(.system(size: 15, weight: .bold))
                                    .foregroundStyle(photo ? .white : .secondary)
                                    .frame(width: 34, height: 34)
                                    .glassEffect(.regular.interactive(), in: Circle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Bezárás")
                        }
                        .padding(.top, 8)

                    // Hős: hónap + átlag — fotó fölött fehér, tömörnél színes
                    VStack(alignment: .leading, spacing: 2) {
                        Text(month.title)
                            .mcDisplay(32)
                            .foregroundStyle(photo ? .white : .primary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                        Text("\(stats.count) jegy • \(stats.exams) dolgozat")
                            .font(.subheadline)
                            .foregroundStyle(photo ? .white.opacity(0.8) : .secondary)
                    }
                    .padding(.top, 14)
                    .shadow(color: photo ? .black.opacity(0.35) : .clear, radius: 8)
                    .stagger(appeared, 0)
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(String(format: "%.1f", stats.avg))
                            .mcDisplay(80)
                            .foregroundStyle(photo ? .white : avgColor)
                            .monospacedDigit()
                            .lineLimit(1)
                            .minimumScaleFactor(0.6)
                        Text("átlag")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(photo ? .white.opacity(0.8) : .secondary)
                    }
                    .padding(.top, 2)
                    .shadow(color: photo ? .black.opacity(0.35) : .clear, radius: 8)
                    .stagger(appeared, 0.08)

                    // Csempék: az oszlop teljes szélességében (rács tölti ki)
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
                    .padding(.top, 20)
                    .stagger(appeared, 0.16)

                    // Sorok: legjobb + legtöbbet javult — egy üveglapon,
                    // az oszlop teljes szélességében
                    VStack(spacing: 0) {
                        if let best = stats.bestSubject {
                            wrappedRow(icon: "trophy", title: "Legjobb tárgyad",
                                       value: "\(best.name) • \(String(format: "%.1f", best.avg))")
                            if stats.mostImproved != nil {
                                Divider()
                                    .overlay(photo ? .white.opacity(0.25) : Color.primary.opacity(0.12))
                                    .padding(.leading, 48)
                            }
                        }
                        if let imp = stats.mostImproved {
                            wrappedRow(icon: "chart.line.uptrend.xyaxis", title: "Legtöbbet javultál",
                                       value: "\(imp.name) • +\(String(format: "%.1f", imp.delta))")
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 4)
                    .wrappedGlass(photo: photo, surface: colors.surface)
                    .padding(.top, 12)
                    .stagger(appeared, 0.24)

                    // Eloszlás üveglapon
                    VStack(alignment: .leading, spacing: 8) {
                        Text("ELOSZLÁS")
                            .font(.caption2.weight(.semibold))
                            .tracking(1)
                            .foregroundStyle(photo ? .white.opacity(0.8) : .secondary)
                        WrappedDistBar(distribution: stats.distribution, colors: distColors)
                        HStack(spacing: 10) {
                            ForEach([5, 4, 3, 2, 1], id: \.self) { v in
                                HStack(spacing: 4) {
                                    Text("\(v)").font(.caption.weight(.semibold))
                                        .foregroundStyle(photo ? .white : .secondary)
                                    Text("×\(stats.distribution[v] ?? 0)")
                                        .font(.caption2.monospacedDigit())
                                        .foregroundStyle(photo ? .white.opacity(0.7) : Color(.tertiaryLabel))
                                }
                            }
                            Spacer(minLength: 0)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(14)
                    .wrappedGlass(photo: photo, surface: colors.surface)
                    .padding(.top, 12)
                    .padding(.bottom, 24)
                    .stagger(appeared, 0.32)
                    }
                    // Egyetlen vízszintes padding az egész oszlopra: semmi
                    // sem lóghat túl a képernyőn (a túllógó tartalom
                    // középre csúszik és két oldalt vágódik).
                    .padding(.horizontal, 20)
                }
                // Lábléc: hegy • fotós egy sorban („Fotó:" előtag nélkül) —
                // lehorgonyozza az alját. A diáknév felül, a hősnél marad.
                Text("\(art.name.uppercased()) • \(art.author)")
                    .font(.caption2.weight(.semibold))
                    .tracking(2)
                    .foregroundStyle(photo ? .white.opacity(0.75) : Color(.tertiaryLabel))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                .shadow(color: photo ? .black.opacity(0.4) : .clear, radius: 6)
                .padding(.bottom, 18)
            }
        }
    }

    // MARK: Minecraft ág — az advancements-képernyő hangulata

    /// A hónap statisztikája a játék nyelvén: menü-háttér, sötét pala-panelek,
    /// advancement-keretes item-ikonok, toast-fejléc, XP-sáv.
    private var mcBody: some View {
        ZStack {
            McMenuBackground()
            VStack(spacing: 0) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        HStack(alignment: .center, spacing: 8) {
                            Text(month.wrappedTitle.uppercased())
                                .mcInk(0xAAAAAA, .caption2)
                                .lineLimit(1)
                                .minimumScaleFactor(0.7)
                            Spacer()
                            Button(action: toggleStar) {
                                SkinIcon("star", size: 24).opacity(isStarred ? 1 : 0.45)
                            }
                            .buttonStyle(McButtonStyle(compact: true))
                            .accessibilityLabel(isStarred ? "Csillag levétele (a kép újra forog)" : "Kép rögzítése erre a hónapra")
                            Button {
                                SummitHaptics.selection()
                                share()
                            } label: {
                                SkinIcon("square.and.arrow.up", size: 24)
                            }
                            .buttonStyle(McButtonStyle(compact: true))
                            .accessibilityLabel("Megosztás")
                            Button(action: onClose) {
                                SkinIcon("xmark", size: 24)
                            }
                            .buttonStyle(McButtonStyle(compact: true))
                            .accessibilityLabel("Bezárás")
                        }
                        .padding(.top, 8)

                        // Hős: toast-fejléc (item + sárga cím) + az átlag
                        // XP-szintként, alatta az 1–5 skálán töltött sávval.
                        VStack(alignment: .leading, spacing: 10) {
                            HStack(spacing: 12) {
                                McSprite(name: "mc_item_nether_star", size: 16 * MinecraftTheme.px)
                                VStack(alignment: .leading, spacing: 3) {
                                    Text("Előrelépés elérve!")
                                        .mcInk(0xFFFF00, .subheadline)
                                    Text(month.title)
                                        .mcInk(0xFFFFFF, .title3)
                                        .lineLimit(1)
                                        .minimumScaleFactor(0.6)
                                    Text("\(stats.count) jegy • \(stats.exams) dolgozat")
                                        .mcInk(0xAAAAAA, .footnote)
                                }
                                Spacer(minLength: 0)
                            }
                            HStack(alignment: .firstTextBaseline, spacing: 8) {
                                Text(String(format: "%.1f", stats.avg))
                                    .mcDisplay(64)
                                    .foregroundStyle(Color(hex: 0x80FF20))
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.6)
                                Text("átlag").mcInk(0xAAAAAA, .subheadline)
                            }
                            McProgressBar(value: stats.avg / 5)
                        }
                        .padding(.horizontal, 8 * MinecraftTheme.px)
                        .padding(.vertical, 8 * MinecraftTheme.px)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(McNineSlice("mc_toast_advancement", top: 2, left: 2, bottom: 0, right: 2))
                        .padding(.top, 14)
                        .stagger(appeared, 0)

                        // Csempék: egy-egy advancement-keret az itemmel
                        LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible())], spacing: 12) {
                            mcTile(item: "mc_item_nether_star", frame: "mc_adv_task_frame", value: "\(stats.fives)",
                                   label: "ötös", sub: "\(stats.count) jegyből")
                            mcTile(item: "mc_item_clock", frame: "mc_adv_task_frame", value: "\(stats.absences)",
                                   label: "hiányzás", sub: stats.unjustified == 0 ? "mind igazolt" : "\(stats.unjustified) igazolatlan")
                            mcTile(item: "mc_item_bell", frame: "mc_adv_task_frame", value: "\(stats.lateCount)",
                                   label: "késés", sub: stats.lateCount == 0 ? "egyszer sem" : "\(stats.lateMinutes) perc")
                            mcTile(item: "mc_item_paper", frame: "mc_adv_task_frame", value: "\(stats.exams)",
                                   label: "dolgozat", sub: "e hónapban")
                        }
                        .padding(.top, 20)
                        .stagger(appeared, 0.16)

                        // Legjobb + legtöbbet javult: goal / challenge keretes sorok
                        VStack(spacing: 0) {
                            if let best = stats.bestSubject {
                                mcRow(item: "mc_item_diamond", frame: "mc_adv_goal_frame",
                                      title: "Legjobb tárgyad",
                                      value: "\(best.name) • \(String(format: "%.1f", best.avg))")
                                if stats.mostImproved != nil {
                                    Rectangle().fill(Color.black.opacity(0.55)).frame(height: MinecraftTheme.px)
                                }
                            }
                            if let imp = stats.mostImproved {
                                mcRow(item: "mc_item_experience_bottle", frame: "mc_adv_challenge_frame",
                                      title: "Legtöbbet javultál",
                                      value: "\(imp.name) • +\(String(format: "%.1f", imp.delta))")
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 6)
                        .background(McWrappedPanel())
                        .padding(.top, 12)
                        .stagger(appeared, 0.24)

                        // Eloszlás: jegyszínű blokk-sáv + darabszámok
                        VStack(alignment: .leading, spacing: 10) {
                            Text("ELOSZLÁS").mcInk(0xAAAAAA, .caption2)
                            WrappedDistBar(distribution: stats.distribution, colors: distColors)
                            HStack(spacing: 10) {
                                ForEach([5, 4, 3, 2, 1], id: \.self) { v in
                                    HStack(spacing: 4) {
                                        Text("\(v)").mcInk(0xFFFFFF, .caption)
                                        Text("×\(stats.distribution[v] ?? 0)").mcInk(0xAAAAAA, .caption2)
                                    }
                                }
                                Spacer(minLength: 0)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(14)
                        .background(McWrappedPanel())
                        .padding(.top, 12)
                        .padding(.bottom, 24)
                        .stagger(appeared, 0.32)
                    }
                    .padding(.horizontal, 20)
                }
                // Lábléc: a diák Wrappedje (fotó nincs, így fotós sem).
                Text(personTitle.uppercased())
                    .mcInk(0x7E7E7E, .caption2)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .padding(.bottom, 18)
            }
        }
    }

    /// Advancement-keretes item: a 26×26-os keret 2×-es nagyításban, a
    /// 16×16-os item a közepén (a játék a kereten belül 5 px-re rajzolja).
    private func mcFrameIcon(item: String, frame: String) -> some View {
        ZStack {
            McSprite(name: frame, size: 52)
            McSprite(name: item, size: 32)
        }
        .frame(width: 52, height: 52)
        .accessibilityHidden(true)
    }

    private func mcTile(item: String, frame: String, value: String, label: String, sub: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                mcFrameIcon(item: item, frame: frame)
                Text(value)
                    .mcDisplay(28)
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
            }
            Text(label).mcInk(0xFFFFFF, .caption).lineLimit(1)
            Text(sub).mcInk(0xAAAAAA, .caption2).lineLimit(1).minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(McWrappedPanel())
        .accessibilityElement(children: .combine)
    }

    private func mcRow(item: String, frame: String, title: String, value: String) -> some View {
        HStack(spacing: 12) {
            mcFrameIcon(item: item, frame: frame)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).mcInk(0xAAAAAA, .caption)
                Text(value).mcInk(0xFFFFFF, .subheadline).lineLimit(1).minimumScaleFactor(0.7)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .accessibilityElement(children: .combine)
    }

    private func wrappedTile(icon: String, value: String, label: String, sub: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(photo ? .white.opacity(0.85) : .secondary)
                Text(label)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(photo ? .white.opacity(0.85) : .secondary)
            }
            Text(value)
                .mcDisplay(28)
                .foregroundStyle(photo ? .white : .primary)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(sub)
                .font(.caption2)
                .foregroundStyle(photo ? .white.opacity(0.65) : Color(.tertiaryLabel))
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .wrappedGlass(photo: photo, surface: colors.surface)
    }

    private func wrappedRow(icon: String, title: String, value: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(photo ? .white.opacity(0.85) : .secondary)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.caption.weight(.semibold))
                    .foregroundStyle(photo ? .white.opacity(0.75) : .secondary)
                Text(value).font(.subheadline.weight(.semibold))
                    .foregroundStyle(photo ? .white : .primary)
                    .lineLimit(1)
            }
            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    // MARK: Megosztás-választó (swipe 5 hegy között)

    /// A kártya Megosztás gombja a hegyválasztót nyitja — a renderelés
    /// és a rendszer-sheet a pickerben történik, az aktuális háttérrel.
    private func share() {
        showPicker = true
    }
}

/// Wrapped-panel Minecraftban: sötét pala-blokk fekete körvonallal, lépcsős
/// sarokkal. Az árnyalatok explicitek (nem a színsémából jönnek), így a
/// képernyő és a megosztott kép (ImageRenderer, mindig világos séma) ugyanaz.
private struct McWrappedPanel: View {
    var body: some View {
        McBlockPanel(face: Color(hex: 0x2E2E33), outline: .black,
                     highlight: .white.opacity(0.10), shade: .black.opacity(0.35))
    }
}

private extension View {
    /// Játékbeli szöveg: Monocraft + a szín negyed fényerejű, 1 px-es kemény
    /// árnyéka (fehér → #3F3F3F, mint a gombfeliratoknál).
    func mcInk(_ hex: UInt, _ style: Font.TextStyle) -> some View {
        let shadow = ((hex >> 16 & 0xFF) / 4) << 16 | ((hex >> 8 & 0xFF) / 4) << 8 | (hex & 0xFF) / 4
        return self
            .font(MinecraftTheme.font(style))
            .foregroundStyle(Color(hex: hex))
            .shadow(color: Color(hex: shadow), radius: 0, x: MinecraftTheme.px / 1.5, y: MinecraftTheme.px / 1.5)
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

    /// Wrapped-üveglap: fotó fölött VALÓDI Liquid Glass, tömör háttérnél
    /// (Reduce Transparency) a régi surface-kártya. Padding KÍVÜL marad —
    /// a glass a nézet határai mögé mintáz (lásd liquid-glass skill).
    @ViewBuilder
    func wrappedGlass(photo: Bool, surface: Color, cornerRadius: CGFloat = 18) -> some View {
        if photo {
            self.glassEffect(.regular, in: .rect(cornerRadius: cornerRadius))
        } else {
            self.background(surface, in: RoundedRectangle(cornerRadius: cornerRadius))
        }
    }
}

/// Egybefüggő eloszlás-sáv (5→1, jegyszínekkel), nulla darabbal is stabil.
struct WrappedDistBar: View {
    var distribution: [Int: Int]
    var colors: [Int: Color]
    var body: some View {
        if MinecraftTheme.isActive {
            mcBar
        } else {
            summitBar
        }
    }

    /// Minecraft: fekete keretes sáv, a jegyszínű szakaszok kemény élű
    /// blokkok 1 px-es világos felső éllel, köztük 1 px-es fekete osztás.
    private var mcBar: some View {
        let u = MinecraftTheme.px
        return GeometryReader { geo in
            let total = max(1, distribution.values.reduce(0, +))
            let live = [5, 4, 3, 2, 1].filter { (distribution[$0] ?? 0) > 0 }
            let inner = max(0, geo.size.width - 2 * u - u * CGFloat(max(0, live.count - 1)))
            HStack(spacing: u) {
                ForEach(live, id: \.self) { v in
                    let n = distribution[v] ?? 0
                    Rectangle()
                        .fill(colors[v] ?? .gray)
                        .overlay(alignment: .top) { Rectangle().fill(Color.white.opacity(0.38)).frame(height: u) }
                        .overlay(alignment: .bottom) { Rectangle().fill(Color.black.opacity(0.28)).frame(height: u) }
                        .frame(width: max(2 * u, inner * CGFloat(n) / CGFloat(total)))
                }
            }
            .padding(u)
            .frame(width: geo.size.width, alignment: .leading)
            .background(Color.black)
        }
        .frame(height: 7 * u)
        .accessibilityHidden(true)
    }

    private var summitBar: some View {
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

// MARK: - Wrapped-hegykatalógus (30 távoli fotó, nyitásonkénti forgatással)
//
// Minden fiók a 30 kép egyedi keverését kapja (FNV-1a rangsor), és a
// megnyitás-számláló szerint lépeget benne — minden megnyitásra más kép.
// Forrás: Wikimedia Commons (szabad licenc), a fotós neve a láblécben szerepel.
// Betöltésig / offline nincs helyettesítő kép: a sötét alap + üveglapok
// látszanak (a bundle-fotó beflashelése ki van szedve).
struct WrappedPeakArt: Hashable {
    var name: String
    var author: String
    var url: URL
}

enum WrappedPeakArtCatalog {
    /// Mind a 30 eredeti, teljes felbontású fájl (retina iPadre is éles —
    /// a bélyegkép-verziók helyett az eredetik; a betöltő 3200 px-re
    /// korlátozva dekódol, így az óriásfájlok sem eszik meg a memóriát).
    static let all: [WrappedPeakArt] = [
        .init(name: "Matterhorn", author: "Zacharie Grossen", url: URL(string: "https://upload.wikimedia.org/wikipedia/commons/6/60/Matterhorn_from_Domh%C3%BCtte_-_2.jpg")!),
        .init(name: "Mont Blanc", author: "Hseugut", url: URL(string: "https://upload.wikimedia.org/wikipedia/commons/a/a2/Mont_Blanc_Aiguille.jpg")!),
        .init(name: "Eiger", author: "Terra3", url: URL(string: "https://upload.wikimedia.org/wikipedia/commons/f/fc/North_face.jpg")!),
        .init(name: "Tre Cime", author: "Tiia Monto", url: URL(string: "https://upload.wikimedia.org/wikipedia/commons/4/4f/2019_Tre_Cime.jpg")!),
        .init(name: "Kirkjufell", author: "Anjali Kiggal", url: URL(string: "https://upload.wikimedia.org/wikipedia/commons/d/df/Kirkjufell_in_Iceland.jpg")!),
        .init(name: "Fudzsi", author: "Suicasmo", url: URL(string: "https://upload.wikimedia.org/wikipedia/commons/f/f8/View_of_Mount_Fuji_from_%C5%8Cwakudani_20211202.jpg")!),
        .init(name: "Zugspitze", author: "Octagon", url: URL(string: "https://upload.wikimedia.org/wikipedia/commons/7/7e/Zugspitze_2.JPG")!),
        .init(name: "Triglav", author: "Andrej Jakobčič", url: URL(string: "https://upload.wikimedia.org/wikipedia/commons/0/0a/Triglav.jpg")!),
        .init(name: "Gerlach", author: "Jakub Krajňák", url: URL(string: "https://upload.wikimedia.org/wikipedia/commons/0/06/Gerlachovsk%C3%BD_%C5%A1t%C3%ADt_z_Gran%C3%A1tovej_l%C3%A1vky.jpg")!),
        .init(name: "Rysy", author: "Krzysztof Dudzik-Górnicki", url: URL(string: "https://upload.wikimedia.org/wikipedia/commons/a/ad/Rysy%2C_wierzcholek_slowacki.jpg")!),
        .init(name: "Jungfrau", author: "4000er", url: URL(string: "https://upload.wikimedia.org/wikipedia/commons/d/d7/Jungfrau03.jpg")!),
        .init(name: "Bernina", author: "Jphoto", url: URL(string: "https://upload.wikimedia.org/wikipedia/commons/1/1b/PizBernina3.jpg")!),
        .init(name: "Ortler", author: "Pierre Lavaurs", url: URL(string: "https://upload.wikimedia.org/wikipedia/commons/5/56/L%27Ortler.jpg")!),
        .init(name: "Marmolada", author: "Michael", url: URL(string: "https://upload.wikimedia.org/wikipedia/commons/0/06/Marmolata%2C_3343m.jpg")!),
        .init(name: "Kilimandzsáró", author: "Sergey Pesterev", url: URL(string: "https://upload.wikimedia.org/wikipedia/commons/6/6c/Kilimanjaro_from_Amboseli.jpg")!),
        .init(name: "Everest", author: "Rdevany", url: URL(string: "https://upload.wikimedia.org/wikipedia/commons/1/15/Mt._Everest_from_Gokyo_Ri_November_5%2C_2012.jpg")!),
        .init(name: "Annapurna", author: "PrajwalMohan", url: URL(string: "https://upload.wikimedia.org/wikipedia/commons/f/f2/South_Face_of_Annapurna_I_%28Main%29.jpg")!),
        .init(name: "Denali", author: "Denali National Park and Preserve", url: URL(string: "https://upload.wikimedia.org/wikipedia/commons/9/91/Wonder_Lake_and_Denali.jpg")!),
        .init(name: "Aconcagua", author: "Bjørn Christian Tørrissen", url: URL(string: "https://upload.wikimedia.org/wikipedia/commons/4/4e/Aconcagua2016.jpg")!),
        .init(name: "Elbrusz", author: "Aleksandr Markin", url: URL(string: "https://upload.wikimedia.org/wikipedia/commons/c/c0/Mount_Elbrus_%28cropped%29.jpg")!),
        .init(name: "Vinson", author: "Christian Stangl", url: URL(string: "https://upload.wikimedia.org/wikipedia/commons/c/c6/Mount_Vinson_from_NW_at_Vinson_Plateau_by_Christian_Stangl_%28flickr%29.jpg")!),
        .init(name: "Tábla-hegy", author: "Danie van der Merwe", url: URL(string: "https://upload.wikimedia.org/wikipedia/commons/d/dc/Table_Mountain_DanieVDM.jpg")!),
        .init(name: "Ben Nevis", author: "Thincat", url: URL(string: "https://upload.wikimedia.org/wikipedia/commons/0/09/BenNevis2005.jpg")!),
        .init(name: "Olümposz", author: "kallerna", url: URL(string: "https://upload.wikimedia.org/wikipedia/commons/e/e8/Olympus_National_Park_30.jpg")!),
        .init(name: "Teide", author: "Thomas Wolf", url: URL(string: "https://upload.wikimedia.org/wikipedia/commons/a/a5/Roque_Cinchado_und_Teide.jpg")!),
        .init(name: "Muszala", author: "Deyan Vasilev", url: URL(string: "https://upload.wikimedia.org/wikipedia/commons/c/c5/Musala_IMG_1447.jpg")!),
        .init(name: "Trolltunga", author: "kallerna", url: URL(string: "https://upload.wikimedia.org/wikipedia/commons/b/b6/Trolltunga_2017.jpg")!),
        .init(name: "Preikestolen", author: "Clementp.fr", url: URL(string: "https://upload.wikimedia.org/wikipedia/commons/8/85/Lyse_Fjord_et_Preikestolen.jpg")!),
        .init(name: "Lofoten", author: "Lukas Beck", url: URL(string: "https://upload.wikimedia.org/wikipedia/commons/5/59/Moskenes_Reinebringen_lub_2025-07-21_img09_Aussicht.jpg")!),
        .init(name: "Dolomitok", author: "kallerna", url: URL(string: "https://upload.wikimedia.org/wikipedia/commons/3/36/Faloria_Cortina_d%27Ampezzo_10.jpg")!),
    ]

    /// Név szerinti keresés (a csillagozott rögzítés feloldásához).
    static func byName(_ name: String) -> WrappedPeakArt? {
        all.first { $0.name == name }
    }

    /// Nyitásonkénti forgatás: minden fiók a 30 kép EGYEDI keverését kapja
    /// (FNV-1a rangsor — direkt nem a Swift.Hasher, mert az futásonként
    /// más seedet kap), és a megnyitás-számláló szerint lépeget benne.
    /// Így minden megnyitásra MÁS kép jön (egymás után sosem ismétlődik,
    /// amíg a 30 el nem fogy), más fiók más sorrendet kap — szerver-oldali
    /// állapot nélkül, offline is. A csillagozott hónapra nem vonatkozik
    /// (azt a kártya külön kezeli).
    static func rotated(month: MonthlyWrapped.Month, userId: String, offset: Int) -> WrappedPeakArt {
        let ranked = all.indices.map { ($0, hash("\(userId)#\($0)")) }
            .sorted { $0.1 < $1.1 }
        let pos = ((offset % all.count) + all.count) % all.count
        return all[ranked[pos].0]
    }

    /// FNV-1a (stabil, nem a véletlen seedű Swift.Hasher).
    static func hash(_ s: String) -> UInt64 {
        var h: UInt64 = 14695981039346656037
        for b in s.utf8 {
            h ^= UInt64(b)
            h &*= 1099511628211
        }
        return h
    }
}

/// Távoli wrapped-fotók töltése + memóriában tartása (a lemez-gyorstárat a
/// megosztott URLCache adja). Az ImageRendererbe nem megy át élő hálózati
/// kép, ezért a megosztás az itt előtöltött UIImage-et kapja.
/// A katalógus eredeti, teljes felbontású fájlokat mutat (iPad-retinához
/// is elég): dekódoláskor a hosszú él 3200 px-re van korlátozva, így egy
/// 6000 px-es óriás sem eszi meg a memóriát (a 13"-es iPad 2752 px-e
/// így is kényelmesen belefér).
@MainActor
final class WrappedArtLoader: ObservableObject {
    static let shared = WrappedArtLoader()
    /// Dekódolt hosszú él plafon (px) — retina iPadre is elég, óriásfájlokra is biztonságos.
    static let maxPixelSize: CGFloat = 3200
    /// Letöltési plafon (bájt) — ennél nagyobb fájlt nem kérünk le.
    static let maxDownloadBytes = 25 * 1024 * 1024
    @Published private(set) var loaded: [URL: UIImage] = [:]
    private var inflight = Set<URL>()
    private lazy var session: URLSession = {
        let config = URLSessionConfiguration.default
        config.urlCache = URLCache(memoryCapacity: 64 * 1024 * 1024,
                                   diskCapacity: 300 * 1024 * 1024,
                                   diskPath: "wrapped-art")
        config.requestCachePolicy = .returnCacheDataElseLoad
        return URLSession(configuration: config)
    }()

    func image(for art: WrappedPeakArt) -> UIImage? { loaded[art.url] }

    /// Háttér-előtöltés a kártya megnyitásakor (megosztáskor már kész).
    func prefetch(_ art: WrappedPeakArt) {
        guard loaded[art.url] == nil, !inflight.contains(art.url) else { return }
        inflight.insert(art.url)
        Task {
            if let img = await download(art.url) { loaded[art.url] = img }
            inflight.remove(art.url)
        }
    }

    /// Renderhez: memóriából azonnal, különben hálózatról (cache-el).
    func resolved(_ art: WrappedPeakArt) async -> UIImage? {
        if let img = loaded[art.url] { return img }
        if let img = await download(art.url) {
            loaded[art.url] = img
            return img
        }
        return nil
    }

    private func download(_ url: URL) async -> UIImage? {
        guard let (data, response) = try? await session.data(from: url),
              (response as? HTTPURLResponse)?.statusCode == 200,
              data.count <= Self.maxDownloadBytes else { return nil }
        return Self.downsampled(data)
    }

    /// Memóriabiztos dekódolás: a hosszú él legfeljebb `maxPixelSize`.
    /// Kis kép változatlanul jön át (felnagyítás nincs).
    static func downsampled(_ data: Data) -> UIImage? {
        let opts: CFDictionary = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let src = CGImageSourceCreateWithData(data as CFData, opts) else { return nil }
        let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any]
        let w = (props?[kCGImagePropertyPixelWidth] as? CGFloat) ?? 0
        let h = (props?[kCGImagePropertyPixelHeight] as? CGFloat) ?? 0
        let longEdge = max(w, h)
        guard longEdge > 0 else { return UIImage(data: data) }
        guard longEdge > maxPixelSize else { return UIImage(data: data) }
        let thumbOpts: CFDictionary = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
        ] as CFDictionary
        guard let cg = CGImageSourceCreateThumbnailAtIndex(src, 0, thumbOpts) else {
            return UIImage(data: data)
        }
        return UIImage(cgImage: cg)
    }
}

/// Wrapped-háttérfotó: csak a távoli kép, ha megjött — addig üres (sötét
/// alap). Bundle-tartalék nincs: a betöltés alatti beflashelés ki van szedve.
/// GeometryReader + explicit méret (a keret nélküli kép szétnyomná a ZStacket).
struct WrappedArtPhoto: View {
    var art: WrappedPeakArt
    @ObservedObject private var loader = WrappedArtLoader.shared
    var body: some View {
        GeometryReader { geo in
            Group {
                if let img = loader.image(for: art) {
                    Image(uiImage: img).resizable().scaledToFill()
                } else {
                    Color.clear
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .clipped()
        }
        .ignoresSafeArea()
        .onAppear { loader.prefetch(art) }
    }
}

/// Egy megosztó-oldal: hegyfotó + Liquid Glass kockák.
/// Ua. a nézet megy a képernyőre és az ImageRendererbe:
/// képernyőn VALÓDI .glassEffect (élő mintavétel), renderhez anyag-háttér
/// (`forRender: true`), mert a glass a statikus képben eltűnik —
/// headless-próba igazolta. A háttér a kártyán mutatott kép (a forgatás
/// aktuális kockája vagy a csillagozott rögzítés).
struct WrappedPeakPage: View {
    var art: WrappedPeakArt
    /// „Csaba Wrappedje" — fejléc a hegy neve helyett.
    var personTitle: String
    var stats: MonthlyWrapped.Stats
    var distColors: [Int: Color]
    /// Render-példány (ImageRenderer): anyag-háttér, nem élő glass.
    var forRender = false
    /// Render-példány háttérképe (előtöltött távoli fotó, végső esetben
    /// bundle-tartalék) — az ImageRenderer a hálózati képet nem várja meg.
    var renderImage: UIImage? = nil

    private var lateLabel: String {
        if stats.lateCount == 0 { return "késés" }
        return "késés • \(stats.lateMinutes) perc"
    }
    private var absenceSub: String {
        stats.unjustified == 0 ? "mind igazolt" : "\(stats.unjustified) igazolatlan"
    }

    var body: some View {
        if MinecraftTheme.isActive {
            mcBody
        } else {
            summitBody
        }
    }

    /// Minecraft: menü-háttér, pala-panelek, advancement-keretes ikonok —
    /// fotó és üveg nélkül (a megosztott képen is ugyanez, ezért a render-
    /// példánynak sincs külön ága: a panelek eleve tömörek).
    private var mcBody: some View {
        ZStack {
            McMenuBackground()
            VStack(alignment: .leading, spacing: 0) {
                Text(personTitle.uppercased())
                    .mcInk(0xFFFF00, .footnote)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .padding(.top, 8)
                Spacer(minLength: 8)
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 10) {
                        McSprite(name: "mc_item_nether_star", size: 16 * MinecraftTheme.px)
                        Text("\(stats.count) jegy • \(stats.exams) dolgozat")
                            .mcInk(0xAAAAAA, .subheadline)
                            .lineLimit(2)
                        Spacer(minLength: 0)
                    }
                    Text(String(format: "%.1f", stats.avg))
                        .mcDisplay(84)
                        .foregroundStyle(Color(hex: 0x80FF20))
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                    McProgressBar(value: stats.avg / 5)
                    if let best = stats.bestSubject {
                        Text("Legjobb: \(best.name) • \(String(format: "%.1f", best.avg))")
                            .mcInk(0xFFFFFF, .subheadline)
                            .lineLimit(2)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(18)
                .background(McNineSlice("mc_toast_advancement", top: 2, left: 2, bottom: 0, right: 2))
                Spacer(minLength: 10)
                HStack(spacing: 10) {
                    mcMini(item: "mc_item_nether_star", value: "\(stats.fives)", label: "ötös", sub: "\(stats.count) jegyből")
                    mcMini(item: "mc_item_clock", value: "\(stats.absences)", label: "hiányzás", sub: absenceSub)
                    mcMini(item: "mc_item_bell", value: "\(stats.lateCount)", label: lateLabel)
                }
                VStack(alignment: .leading, spacing: 10) {
                    WrappedDistBar(distribution: stats.distribution, colors: distColors)
                    HStack(spacing: 10) {
                        ForEach([5, 4, 3, 2, 1], id: \.self) { v in
                            HStack(spacing: 3) {
                                Text("\(v)").mcInk(0xFFFFFF, .caption)
                                Text("×\(stats.distribution[v] ?? 0)").mcInk(0xAAAAAA, .caption2)
                            }
                        }
                        Spacer()
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(14)
                .background(McWrappedPanel())
                .padding(.top, 10)
                Spacer(minLength: 10)
                Text("SUMMIT")
                    .mcInk(0x7E7E7E, .caption)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.bottom, 4)
            }
            .padding(.horizontal, 20)
            .padding(.top, 56)
            .padding(.bottom, 16)
        }
    }

    private func mcMini(item: String, value: String, label: String, sub: String? = nil) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            McSprite(name: item, size: 24)
            Text(value)
                .mcDisplay(26)
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(label).mcInk(0xFFFFFF, .caption).lineLimit(1).minimumScaleFactor(0.6)
            Text(sub ?? " ")
                .mcInk(0xAAAAAA, .caption2)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .opacity(sub == nil ? 0 : 1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(McWrappedPanel())
    }

    private var summitBody: some View {
        ZStack {
            if let renderImage {
                // Render-út: kész UIImage (távoli fotó vagy bundle-tartalék).
                GeometryReader { geo in
                    Image(uiImage: renderImage)
                        .resizable()
                        .scaledToFill()
                        .frame(width: geo.size.width, height: geo.size.height)
                        .clipped()
                }
                .ignoresSafeArea()
            } else {
                // Képernyő: távoli fotó ha megjött, addig bundle-tartalék.
                WrappedArtPhoto(art: art)
            }
            // Olvashatósági sötétítés fent/lent (a fotó közepe szabadon marad)
            LinearGradient(
                colors: [.black.opacity(0.55), .clear, .clear, .black.opacity(0.6)],
                startPoint: .top, endPoint: .bottom
            )
            VStack(alignment: .leading, spacing: 0) {
                Text(personTitle.uppercased())
                    .font(.system(size: 13, weight: .bold))
                    .tracking(3)
                    .foregroundStyle(.white.opacity(0.85))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .padding(.top, 8)
                Spacer(minLength: 8)
                // Hős + minik + eloszlás. GlassEffectContainer NINCS:
                // az szétnyomja az oszlopot (teljes szélesség + vágás) —
                // csempénként külön glass, az renderel helyesen.
                heroTile
                Spacer(minLength: 10)
                // Egyforma magas csempék: a késésnek nincs alcíme, helyette
                // láthatatlan helykitöltő sor tartja a magasságot (nyújtás
                // nélkül — az szétnyomná az egész sort).
                HStack(spacing: 10) {
                    peakMini(icon: "star", value: "\(stats.fives)", label: "ötös",
                             sub: "\(stats.count) jegyből")
                    peakMini(icon: "clock", value: "\(stats.absences)", label: "hiányzás",
                             sub: absenceSub)
                    peakMini(icon: "alarm", value: "\(stats.lateCount)", label: lateLabel)
                }
                distTile.padding(.top, 10)
                Spacer(minLength: 10)
                // Lábléc: hegy • fotós egy sorban („Fotó:" előtag nélkül).
                // A hónap a megosztó-szövegben szerepel.
                Text("\(art.name.uppercased()) • \(art.author)")
                    .font(.caption.weight(.bold))
                    .tracking(2)
                    .foregroundStyle(.white.opacity(0.75))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.bottom, 4)
            }
            .padding(.horizontal, 20)
            // Felül a státuszsáv alá kell férni (az oldal ignoresSafeArea-val megy).
            .padding(.top, 56)
            .padding(.bottom, 16)
        }
    }

    /// Hős üveglap: átlag + jegy/dolgozat + legjobb tárgy.
    private var heroTile: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(String(format: "%.1f", stats.avg))
                .mcDisplay(84)
                .foregroundStyle(.white)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text("\(stats.count) jegy • \(stats.exams) dolgozat")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white.opacity(0.8))
            if let best = stats.bestSubject {
                Text("Legjobb: \(best.name) • \(String(format: "%.1f", best.avg))")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.8))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .peakTile(forRender: forRender)
    }

    /// Eloszlás üveglap.
    private var distTile: some View {
        VStack(alignment: .leading, spacing: 8) {
            WrappedDistBar(distribution: stats.distribution, colors: distColors)
            HStack(spacing: 10) {
                ForEach([5, 4, 3, 2, 1], id: \.self) { v in
                    HStack(spacing: 3) {
                        Text("\(v)")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.white)
                        Text("×\(stats.distribution[v] ?? 0)")
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(.white.opacity(0.7))
                    }
                }
                Spacer()
            }
        }
        .padding(14)
        .peakTile(forRender: forRender)
    }

    private func peakMini(icon: String, value: String, label: String, sub: String? = nil) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white.opacity(0.85))
            Text(value)
                .mcDisplay(26)
                .foregroundStyle(.white)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(label)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.white.opacity(0.8))
                .lineLimit(1)
            Text(sub ?? " ")
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.65))
                .lineLimit(1)
                .opacity(sub == nil ? 0 : 1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .peakTile(forRender: forRender)
    }
}

/// Megosztó-üveglap: képernyőn VALÓDI Liquid Glass, renderben anyag-háttér
/// + fehér hajszálkeret (a glass az ImageRendererben nem látszik).
private struct PeakTile: ViewModifier {
    var forRender: Bool
    func body(content: Content) -> some View {
        if forRender {
            content
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18))
                .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(.white.opacity(0.35), lineWidth: 1))
        } else {
            content
                .glassEffect(.regular, in: .rect(cornerRadius: 18))
        }
    }
}

private extension View {
    func peakTile(forRender: Bool) -> some View { modifier(PeakTile(forRender: forRender)) }
    /// Régi név, csak a render-ághoz (az élő nézet `peakTile`-t használ).
    func glassTile() -> some View { modifier(PeakTile(forRender: true)) }
}

/// Megosztó-előnézet: a kártyán mutatott kép + Megosztás gomb.
/// A picker nem sorsol — a kártya forgatási kockáját (vagy a csillagozott
/// rögzítést) kapja meg, a gomb pontosan ezt az oldalt rendereli.
struct WrappedSharePicker: View {
    var month: MonthlyWrapped.Month
    var stats: MonthlyWrapped.Stats
    var distColors: [Int: Color]
    /// A kártyán látható kép (forgatás / csillag).
    var art: WrappedPeakArt
    /// „Csaba Wrappedje" — fejléc + lábléc + megosztó-szöveg.
    var personTitle: String = ""
    @State private var shareItems: [Any] = []
    @State private var showShare = false
    @Environment(\.dismiss) var dismiss

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            WrappedPeakPage(art: art, personTitle: personTitle, stats: stats, distColors: distColors)
                .ignoresSafeArea()
            VStack {
                HStack {
                    Spacer()
                    if MinecraftTheme.isActive {
                        Button { dismiss() } label: { SkinIcon("xmark", size: 24) }
                            .buttonStyle(McButtonStyle(compact: true))
                            .accessibilityLabel("Bezárás")
                    } else {
                    Button { dismiss() } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(width: 34, height: 34)
                            .glassEffect(.regular.interactive(), in: Circle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Bezárás")
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 10)
                Spacer()
                if MinecraftTheme.isActive {
                    Button {
                        SummitHaptics.selection()
                        Task { await renderAndShare() }
                    } label: {
                        SkinLabel("Megosztás", systemImage: "square.and.arrow.up")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(McButtonStyle(prominent: true))
                    .padding(.horizontal, 20)
                    .padding(.bottom, 20)
                } else {
                Button {
                    SummitHaptics.selection()
                    Task { await renderAndShare() }
                } label: {
                    Label("Megosztás", systemImage: "square.and.arrow.up")
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 18))
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 20)
                .padding(.bottom, 20)
                }
            }
        }
        .sheet(isPresented: $showShare) {
            ShareSheet(items: shareItems)
                .presentationDetents([.medium, .large])
        }
    }

    private func renderAndShare() async {
        // Render-példány: anyag-háttérrel, mert az élő glass a képen eltűnne;
        // háttér az előtöltött távoli fotó (ha nincs meg, csak a sötét alap —
        // bundle-tartalék nincs). A megosztó-szövegben a hónap is szerepel.
        let bg = await WrappedArtLoader.shared.resolved(art)
        let page = WrappedPeakPage(art: art, personTitle: personTitle, stats: stats, distColors: distColors, forRender: true, renderImage: bg)
        let renderer = ImageRenderer(content: page.frame(width: 390, height: 680))
        renderer.scale = 3
        var items: [Any] = []
        if let uiImage = renderer.uiImage { items.append(uiImage) }
        items.append("\(month.title) • \(personTitle): \(String(format: "%.1f", stats.avg)) átlag, \(stats.count) jegy — Summit")
        shareItems = items
        showShare = true
    }
}

private extension View {
    /// Minecraftban az égbolt-háttér a lista mögött (mint a többi
    /// lista-képernyőn); Summitban semmi nem változik.
    @ViewBuilder
    func mcArchiveChrome(colors: AppColors) -> some View {
        if MinecraftTheme.isActive {
            self.summitListChrome(colors: colors)
        } else {
            self
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
                    .skinFont(.subheadline).foregroundStyle(.secondary)
                    .mcListRow(fill: colors.surface)
            } else {
                ForEach(MonthlyWrapped.months(grades: grades), id: \.id) { m in
                    let st = MonthlyWrapped.stats(grades: grades, month: m, exams: exams, absences: absences)
                    Button {
                        SummitHaptics.selection()
                        opened = m
                    } label: {
                        HStack(spacing: 12) {
                            Text(String(format: "%.1f", st.avg))
                                .mcDisplay(20)
                                .foregroundStyle(colors.gradeColor(for: Int(st.avg.rounded())))
                                .monospacedDigit()
                                .frame(width: 52)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(m.title).skinFont(.subheadline, weight: .semibold)
                                Text("\(st.count) jegy • \(st.fives) ötös")
                                    .skinFont(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            SkinIcon("chevron.right")
                                .skinFont(.caption, weight: .semibold).foregroundStyle(.tertiary)
                        }
                    }
                    .buttonStyle(.plain)
                    .mcListRow(fill: colors.surface)
                }
            }
        }
        .mcArchiveChrome(colors: colors)
        .navigationTitle("Havi összefoglalók")
        .navigationBarTitleDisplayMode(.inline)
        .summitToolbarBackground()
        .task { await load() }
        .fullScreenCover(item: $opened) { m in
            MonthlyWrappedCard(
                month: m,
                stats: MonthlyWrapped.stats(grades: grades, month: m, exams: exams, absences: absences),
                onClose: { opened = nil },
                userId: session.selectedUser?.id ?? "",
                studentName: session.selectedUser?.name ?? ""
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
