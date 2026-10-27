import SwiftUI

/// Bemutató — Hiányzások lépés. A valódi Hiányzások képernyő elemei
/// (`AbsencesSummaryCard`, `AbsenceListSection` a benne lévő
/// `AbsenceRow`-kkal) demo adatokkal, ugyanabban a listában és
/// ugyanazzal a krómmal, mint az `AbsencesView`. Mozgás: a kártya
/// beúszik, a sorok egyenként érkeznek (a kártya számlálói és a késés-
/// gyűrű velük együtt nőnek), végül az Igazolt szekció lenyílik.
/// Reduce Motion mellett rögtön a kész állapot látszik.
struct OnboardingAbsencesStep: View {
    @EnvironmentObject var theme: ThemeStore
    @Environment(\.colorScheme) private var scheme
    @Environment(\.horizontalSizeClass) private var hSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Hány demo tétel látszik már (a megjelenési sorrendben).
    @State private var revealed = 0
    @State private var unjustifiedExpanded = false
    @State private var justifiedExpanded = false

    private var isPad: Bool { hSize == .regular }
    private var colors: AppColors { theme.colors(for: scheme) }

    /// A közös demo hiányzások, kiegészítve pár tétellel, hogy az Igazolt
    /// szekció lenyitható legyen (3 felett) és a késés-gyűrű értelmes
    /// értéket mutasson. A dátumok a mai naphoz képest relatívak.
    private static let items: [AbsenceItem] = {
        let day: TimeInterval = 86400
        let extra = [
            AbsenceItem(id: "ob-a4", subject: "Fizika", date: Date().addingTimeInterval(-day * 3), type: "Késés", isJustified: false, delay: 15),
            AbsenceItem(id: "ob-a5", subject: "Biológia", date: Date().addingTimeInterval(-day * 9), type: "Orvosi igazolás", isJustified: true, delay: nil),
            AbsenceItem(id: "ob-a6", subject: "Irodalom", date: Date().addingTimeInterval(-day * 9 - 3600), type: "Orvosi igazolás", isJustified: true, delay: nil),
            AbsenceItem(id: "ob-a7", subject: "Földrajz", date: Date().addingTimeInterval(-day * 15), type: "iskolaerdeku_tavollet", isJustified: true, delay: nil),
        ]
        return DemoData.absences() + extra
    }()

    /// Megjelenési sorrend = a képernyő sorrendje: előbb az igazolatlanok,
    /// aztán az igazoltak, mindkettő a legfrissebbtől.
    private static let sequence: [AbsenceItem] = {
        let byDate: (AbsenceItem, AbsenceItem) -> Bool = { $0.date > $1.date }
        return items.filter { !$0.isJustified }.sorted(by: byDate)
            + items.filter { $0.isJustified }.sorted(by: byDate)
    }()

    private var shown: [AbsenceItem] { Array(Self.sequence.prefix(revealed)) }
    private var unjustifiedItems: [AbsenceItem] { shown.filter { !$0.isJustified } }
    private var justifiedItems: [AbsenceItem] { shown.filter { $0.isJustified } }
    private var totalDelay: Int { shown.compactMap(\.delay).reduce(0, +) }

    var body: some View {
        List {
            Section {
                AbsencesSummaryCard(totalDelay: totalDelay,
                                    justifiedCount: justifiedItems.count,
                                    unjustifiedCount: unjustifiedItems.count)
                    .summitEntrance(delay: 0.05)
            }
            // A szekció az első sorával együtt érkezik (a valódi képernyő
            // üres-állapota helyett) — a kész állapot ugyanaz.
            if !unjustifiedItems.isEmpty {
                AbsenceListSection(items: unjustifiedItems, isUnjustified: true, expanded: $unjustifiedExpanded)
            }
            if !justifiedItems.isEmpty {
                AbsenceListSection(items: justifiedItems, isUnjustified: false, expanded: $justifiedExpanded)
            }
        }
        .listStyle(.insetGrouped)
        .frame(maxWidth: isPad ? MacSupport.contentWidth(ipad: 1280, mac: 1150) : .infinity)
        .padding(.horizontal, MacSupport.sidePadding)
        .frame(maxWidth: .infinity)
        .summitListChrome(colors: colors)
        .animation(SummitMotion.gentle, value: revealed)
        .animation(SummitMotion.gentle, value: totalDelay)
        .task { await play() }
    }

    /// Koreográfia: kártya-belépés után soronként ~0,2 mp-es léptetés
    /// (a számlálók `.numericText()`-tel lépnek, a gyűrű rugóval telik),
    /// a végén az Igazolt szekció „További" lenyitása egy halk haptikával.
    private func play() async {
        guard revealed == 0 else { return }
        if reduceMotion {
            revealed = Self.sequence.count
            return
        }
        guard await pause(0.45) else { return }
        for i in 1...Self.sequence.count {
            withAnimation(SummitMotion.gentle) { revealed = i }
            guard await pause(0.22) else { return }
        }
        guard await pause(0.6) else { return }
        SummitHaptics.selection()
        withAnimation(SummitMotion.gentle) { justifiedExpanded = true }
    }

    /// Várakozás; `false`, ha a lépést közben elhagyták (a task törlődött).
    private func pause(_ seconds: Double) async -> Bool {
        try? await Task.sleep(for: .seconds(seconds))
        return !Task.isCancelled
    }
}
