import SwiftUI

// MARK: - Friendly display for raw Kréta types (pl. "iskolaerdeku_tavollet" -> "Iskolaérdekű távollét")
private func friendlyAbsenceType(_ raw: String) -> String {
    let t = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    if t.isEmpty { return "Ismeretlen" }
    let lower = t.lowercased()
    if lower.contains("igazolatlan") { return "Igazolatlan" }
    if lower.contains("igazolt") { return "Igazolt" }
    if lower.contains("késés") || lower.contains("keses") { return "Késés" }
    // snake_case / raw kréta codok
    var s = t.replacingOccurrences(of: "_", with: " ")
              .replacingOccurrences(of: "-", with: " ")
    s = s.replacingOccurrences(of: "  ", with: " ")
    // ismert mappelések
    let map: [String:String] = [
        "iskolaerdeku tavollet": "Iskolaérdekű távollét",
        "iskola erdeku tavollet": "Iskolaérdekű távollét",
        "muveszeti tavollet": "Művészeti távollét",
        "hatosagi intezkedes": "Hatósági intézkedés",
        "kikero": "Kikérő",
        "orvosi igazolas": "Orvosi igazolás",
    ]
    if let m = map[s.lowercased()] { return m }
    // fallback: Capitalized szavak, de első betű nagy
    return s.prefix(1).uppercased() + s.dropFirst().lowercased()
}

struct AbsencesView: View {
    @EnvironmentObject var theme: ThemeStore
    @EnvironmentObject var session: SessionStore
    @EnvironmentObject var kreta: KretaClient
    @State private var absences: [AbsenceItem] = []
    @State private var isLoading = true
    @State private var unjustifiedExpanded = false
    @State private var justifiedExpanded = false
    @Environment(\.colorScheme) var scheme
    @Environment(\.horizontalSizeClass) private var hSize
    private var isPad: Bool { hSize == .regular }
    var colors: AppColors { theme.colors(for: scheme) }

    // MARK: Derived — 45 perc = 1 óra limit, kör a 45-ből mutatja mennyit késtél már
    private var totalDelay: Int { absences.compactMap(\.delay).reduce(0, +) }
    private var hoursFromDelay: Int { totalDelay / 45 }
    private var effectiveDelay: Int { totalDelay % 45 }
    // körben megjelenő érték: 45-ből mennyit késtél már (aktuális ciklusban)
    private var displayedDelay: Int {
        if totalDelay == 0 { return 0 }
        return effectiveDelay == 0 ? 45 : effectiveDelay
    }
    private var isFullCycle: Bool { totalDelay > 0 && displayedDelay == 45 }
    private var remaining: Int {
        if totalDelay == 0 { return 45 }
        return effectiveDelay == 0 ? 0 : 45 - effectiveDelay
    }
    private var ringProgress: Double {
        Double(displayedDelay) / 45.0
    }
    private var ringTrim: Double { min(ringProgress, 0.999) }

    private var totalCount: Int { absences.count }
    private var unjustifiedCount: Int { absences.filter { $0.type.lowercased().contains("igazolatlan") }.count }
    private var justifiedCount: Int { absences.filter { !$0.type.lowercased().contains("igazolatlan") && ($0.type.lowercased().contains("igazolt") || friendlyAbsenceType($0.type) == "Igazolt") }.count }
    private var delayCount: Int { absences.filter { ($0.type.lowercased().contains("késés") || $0.type.lowercased().contains("keses")) && $0.delay != nil }.count }

    private var unjustifiedItems: [AbsenceItem] { absences.filter { $0.type.lowercased().contains("igazolatlan") }.sorted { $0.date > $1.date } }
    private var justifiedItems: [AbsenceItem] { absences.filter { !$0.type.lowercased().contains("igazolatlan") }.sorted { $0.date > $1.date } }

    var body: some View {
        NavigationStack {
            List {
                // MARK: Top — egy nagy liquid glass block, eredeti layout: bal késések | jobb felül igazolt alul igazolatlan
                Section {
                    HStack(alignment: .center, spacing: 0) {
                        // Bal: késések — ring + szöveg — javított spacing, középre igazítva
                        VStack(spacing: 10) {
                            HStack {
                                Label("KÉSÉSEK", systemImage: "clock.fill")
                                    .font(.caption2.weight(.bold))
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.7)
                                Spacer(minLength: 4)
                                if hoursFromDelay > 0 {
                                    Text("+\(hoursFromDelay) óra")
                                        .font(.caption2.weight(.bold))
                                        .foregroundStyle(.white)
                                        .padding(.horizontal, 6).padding(.vertical, 3)
                                        .background(Capsule().fill(Color.red))
                                        .lineLimit(1)
                                }
                            }
                            ZStack {
                                Circle().stroke(Color.primary.opacity(scheme == .dark ? 0.08 : 0.07), lineWidth: 7)
                                Circle()
                                    .trim(from: 0, to: ringTrim)
                                    .stroke({
                                        if ringProgress >= 0.85 || hoursFromDelay > 0 { return Color.red }
                                        if ringProgress >= 0.55 { return colors.orange }
                                        return colors.accent
                                    }(), style: StrokeStyle(lineWidth: 7, lineCap: .round))
                                    .rotationEffect(.degrees(-90))
                                    .shadow(color: {
                                        if ringProgress >= 0.85 || hoursFromDelay > 0 { return Color.red }
                                        if ringProgress >= 0.55 { return colors.orange }
                                        return colors.accent
                                    }().opacity(0.32), radius: 5, y: 2)
                                    .animation(.spring(response: 0.9, dampingFraction: 0.82), value: ringTrim)
                                Circle().fill({
                                    if ringProgress >= 0.85 || hoursFromDelay > 0 { return Color.red }
                                    if ringProgress >= 0.55 { return colors.orange }
                                    return colors.accent
                                }().opacity(scheme == .dark ? 0.08 : 0.06)).padding(9)
                                Text("\(displayedDelay)")
                                    .font(.system(size: 26, weight: .bold, design: .rounded))
                                    .monospacedDigit()
                                    .foregroundStyle(isFullCycle ? Color.red : .primary)
                                    .contentTransition(.numericText())
                            }
                            .frame(width: 78, height: 78)
                            Text(isFullCycle ? "beszámítva" : totalDelay == 0 ? "nincs késés" : "\(displayedDelay) / 45 perc")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(isFullCycle ? Color.red : .secondary)
                                .lineLimit(1)
                                .minimumScaleFactor(0.8)
                        }
                        .frame(maxWidth: .infinity)

                        // Középső Apple elválasztó — a két fél között
                        Rectangle()
                            .fill(Color.primary.opacity(scheme == .dark ? 0.10 : 0.08))
                            .frame(width: 1)
                            .padding(.vertical, 8)
                            .padding(.horizontal, 12)

                        // Jobb: hiányzások — felül igazolt, alul igazolatlan — javított vertikális spacing, középre igazítva
                        VStack(alignment: .leading, spacing: 10) {
                            HStack(spacing: 6) {
                                Image(systemName: "person.fill.xmark").font(.caption2.weight(.bold)).foregroundStyle(.secondary)
                                Text("HIÁNYZÁSOK")
                                    .font(.caption2.weight(.bold))
                                    .foregroundStyle(.secondary)
                                    .tracking(0.4)
                                    .lineLimit(1)
                                Spacer(minLength: 2)
                            }
                            VStack(spacing: 0) {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text("\(absences.count - unjustifiedCount)")
                                        .font(.system(size: 30, weight: .bold, design: .rounded))
                                        .monospacedDigit()
                                        .foregroundStyle(.primary)
                                        .contentTransition(.numericText())
                                        .lineLimit(1)
                                        .minimumScaleFactor(0.5)
                                    Text("igazolt")
                                        .font(.caption2.weight(.semibold))
                                        .foregroundStyle(.secondary)
                                        .tracking(0.8)
                                        .textCase(.uppercase)
                                        .lineLimit(1)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.vertical, 4)
                                Rectangle()
                                    .fill(Color.primary.opacity(scheme == .dark ? 0.08 : 0.06))
                                    .frame(height: 1)
                                    .padding(.vertical, 8)
                                VStack(alignment: .leading, spacing: 3) {
                                    Text("\(unjustifiedCount)")
                                        .font(.system(size: 30, weight: .bold, design: .rounded))
                                        .monospacedDigit()
                                        .foregroundStyle(unjustifiedCount > 0 ? colors.red : Color.green)
                                        .contentTransition(.numericText())
                                        .lineLimit(1)
                                        .minimumScaleFactor(0.5)
                                    Text("igazolatlan")
                                        .font(.caption2.weight(.semibold))
                                        .foregroundStyle(.secondary)
                                        .tracking(0.8)
                                        .textCase(.uppercase)
                                        .lineLimit(1)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.vertical, 4)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding(16)
                    .background(
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .fill(scheme == .dark ? Color.white.opacity(0.06) : Color.white)
                            .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(Color.primary.opacity(scheme == .dark ? 0.08 : 0.06), lineWidth: 1))
                            // Light módban nincs külső shadow — a fehér kártya szürke háttéren shadow-ja szarul nézett ki
                            .shadow(color: scheme == .dark ? colors.shadow.opacity(0.30) : .clear, radius: 14, y: 6)
                    )
                    // Light módban glass nélkül — a glass saját árnyéka dobozba clipelődik a List-sorban
                    .functionalGlassWhen(scheme == .dark, cornerRadius: 20)
                    .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                }

                if isLoading {
                    ForEach(0..<3, id: \.self) { _ in
                        HStack { Text("Betöltés…").redacted(reason: .placeholder) }
                            .listRowBackground(colors.surface)
                    }
                } else if absences.isEmpty {
                    Section {
                        ContentUnavailableView("Nincs hiányzás", systemImage: "checkmark.shield.fill", description: Text("Szép munka — nincs rögzített hiányzás"))
                            .frame(maxWidth: .infinity, minHeight: 180)
                            .padding(.vertical, 12)
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                            .listRowInsets(EdgeInsets(top: 12, leading: 16, bottom: 12, trailing: 16))
                    }
                } else {
                    // MARK: Igazolatlan — mindig látszik header, legördülő top 3
                    Section {
                        if unjustifiedItems.isEmpty {
                            HStack(spacing: 10) {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundStyle(Color.green)
                                    .frame(width: 30, height: 30)
                                    .background {
                                        Circle().fill(Color.clear)
                                            .glassEffect(.clear, in: .circle)
                                    }
                                    .overlay(Circle().strokeBorder(colors.border.opacity(0.9), lineWidth: 1))
                                Text("Nincs igazolatlan hiányzás")
                                    .font(.subheadline.weight(.medium))
                                    .foregroundStyle(.secondary)
                                Spacer()
                            }
                            .listRowBackground(colors.surface)
                            .listRowInsets(EdgeInsets(top: 10, leading: 16, bottom: 10, trailing: 16))
                        } else {
                            ForEach(unjustifiedItems.prefix(unjustifiedExpanded ? 100 : 3)) { a in
                                let isDelay = a.delay != nil && (a.type.lowercased().contains("késés") || a.type.lowercased().contains("keses"))
                                AbsenceRow(item: a, colors: colors, scheme: scheme, isUnjustified: true, isDelay: isDelay)
                            }
                            if unjustifiedItems.count > 3 {
                                Button {
                                    withAnimation(SummitMotion.gentle) { unjustifiedExpanded.toggle() }
                                } label: {
                                    HStack {
                                        Text(unjustifiedExpanded ? "Kevesebb" : "További \(unjustifiedItems.count - 3)")
                                            .font(.subheadline.weight(.semibold))
                                        Spacer()
                                        Image(systemName: "chevron.down")
                                            .font(.caption.weight(.bold))
                                            .rotationEffect(.degrees(unjustifiedExpanded ? 180 : 0))
                                    }
                                    .foregroundStyle(colors.accent)
                                    .contentShape(Rectangle())
                                }
                                .listRowBackground(colors.surface)
                                .listRowInsets(EdgeInsets(top: 10, leading: 16, bottom: 10, trailing: 16))
                            }
                        }
                    } header: {
                        HStack(spacing: 6) {
                            Circle().fill(colors.red).frame(width: 6, height: 6)
                            Text(unjustifiedItems.isEmpty ? "Igazolatlan" : "Igazolatlan • \(unjustifiedItems.count)")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(colors.red)
                                .textCase(.uppercase)
                            Spacer()
                            if unjustifiedItems.count > 3 {
                                Image(systemName: unjustifiedExpanded ? "chevron.up" : "chevron.down")
                                    .font(.caption2.weight(.bold))
                                    .foregroundStyle(.secondary)
                                    .animation(SummitMotion.gentle, value: unjustifiedExpanded)
                            }
                        }
                        .contentShape(Rectangle())
                        .onTapGesture {
                            guard unjustifiedItems.count > 3 else { return }
                            withAnimation(SummitMotion.gentle) { unjustifiedExpanded.toggle() }
                        }
                    }

                    // MARK: Igazolt (+ késések) — mindig látszik, legördülő top 3
                    Section {
                        if justifiedItems.isEmpty {
                            HStack(spacing: 10) {
                                Image(systemName: "minus.circle.fill")
                                    .font(.system(size: 14))
                                    .foregroundStyle(.secondary)
                                    .frame(width: 30, height: 30)
                                    .background {
                                        Circle().fill(Color.clear)
                                            .glassEffect(.clear, in: .circle)
                                    }
                                    .overlay(Circle().strokeBorder(colors.border.opacity(0.9), lineWidth: 1))
                                Text("Nincs igazolt hiányzás")
                                    .font(.subheadline.weight(.medium))
                                    .foregroundStyle(.secondary)
                                Spacer()
                            }
                            .listRowBackground(colors.surface)
                            .listRowInsets(EdgeInsets(top: 10, leading: 16, bottom: 10, trailing: 16))
                        } else {
                            ForEach(justifiedItems.prefix(justifiedExpanded ? 100 : 3)) { a in
                                let isDelay = a.delay != nil && (a.type.lowercased().contains("késés") || a.type.lowercased().contains("keses"))
                                AbsenceRow(item: a, colors: colors, scheme: scheme, isUnjustified: false, isDelay: isDelay)
                            }
                            if justifiedItems.count > 3 {
                                Button {
                                    withAnimation(SummitMotion.gentle) { justifiedExpanded.toggle() }
                                } label: {
                                    HStack {
                                        Text(justifiedExpanded ? "Kevesebb" : "További \(justifiedItems.count - 3)")
                                            .font(.subheadline.weight(.semibold))
                                        Spacer()
                                        Image(systemName: "chevron.down")
                                            .font(.caption.weight(.bold))
                                            .rotationEffect(.degrees(justifiedExpanded ? 180 : 0))
                                    }
                                    .foregroundStyle(colors.accent)
                                    .contentShape(Rectangle())
                                }
                                .listRowBackground(colors.surface)
                                .listRowInsets(EdgeInsets(top: 10, leading: 16, bottom: 10, trailing: 16))
                            }
                        }
                    } header: {
                        HStack(spacing: 6) {
                            Circle().fill(Color.green).frame(width: 6, height: 6)
                            Text(justifiedItems.isEmpty ? "Igazolt" : "Igazolt • \(justifiedItems.count)")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                                .textCase(.uppercase)
                            Spacer()
                            if justifiedItems.count > 3 {
                                Image(systemName: justifiedExpanded ? "chevron.up" : "chevron.down")
                                    .font(.caption2.weight(.bold))
                                    .foregroundStyle(.secondary)
                                    .animation(SummitMotion.gentle, value: justifiedExpanded)
                            }
                        }
                        .contentShape(Rectangle())
                        .onTapGesture {
                            guard justifiedItems.count > 3 else { return }
                            withAnimation(SummitMotion.gentle) { justifiedExpanded.toggle() }
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .frame(maxWidth: isPad ? MacSupport.contentWidth(ipad: 1000, mac: 1150) : .infinity)
            .frame(maxWidth: .infinity)
            .scrollContentBackground(.hidden)
            .background(colors.background)
            .navigationTitle("Hiányzások")
            .navigationBarTitleDisplayMode(.large)
            .toolbarBackground(.visible, for: .navigationBar)
            .task { await load() }
            .refreshable { await load() }
            .animation(SummitMotion.gentle, value: absences.count)
            .animation(SummitMotion.gentle, value: totalDelay)
        }
        .tint(colors.accent)
    }

    func load() async {
        // Egy adatsáv: demo usert is a KretaClient szolgálja ki helyből.
        guard let user = session.selectedUser else { isLoading = false; return }
        isLoading = true
        let iss = user.instituteCode.isEmpty ? (JWT.instituteCode(from: user.accessToken) ?? "") : user.instituteCode
        let hadData = !absences.isEmpty
        let fetched = await kreta.fetchAbsences(iss: iss)
        // Totális fetch-hiba (lejárt token, offline): a legutóbbi lista marad,
        // nem ürül ki a Hiányzások tab egy sikertelen refresh-től.
        if !(fetched.isEmpty && hadData) { absences = fetched }
        isLoading = false
    }
}

// MARK: - Delay ring widget — fitness ring, jegyek átlag stílusú szöveg

private struct DelayRingWidget: View {
    let total: Int
    let remaining: Int
    let progress: Double
    let rawProgress: Double
    let hoursFromDelay: Int
    let colors: AppColors
    let scheme: ColorScheme

    // 45-ből mennyit késtél már — widget is a circular progress of missed minutes
    private var displayed: Int {
        if total == 0 { return 0 }
        return remaining == 0 ? 45 : 45 - remaining
    }
    private var ringColor: Color {
        if rawProgress >= 0.85 || hoursFromDelay > 0 { return Color.red }
        if rawProgress >= 0.55 { return colors.orange }
        return colors.accent
    }
    private var isFull: Bool { total > 0 && remaining == 0 }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Label("KÉSÉSEK", systemImage: "clock.fill")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                Spacer(minLength: 4)
                if hoursFromDelay > 0 {
                    Text("+\(hoursFromDelay) óra")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 6).padding(.vertical, 3)
                        .background(Capsule().fill(Color.red))
                        .lineLimit(1)
                }
            }
            Spacer().frame(height: 12)
            ZStack {
                Circle().stroke(Color.primary.opacity(scheme == .dark ? 0.08 : 0.07), lineWidth: 9)
                Circle()
                    .trim(from: 0, to: progress)
                    .stroke(ringColor, style: StrokeStyle(lineWidth: 9, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .shadow(color: ringColor.opacity(0.32), radius: 6, y: 2)
                    .animation(.spring(response: 0.9, dampingFraction: 0.82), value: progress)
                Circle().fill(ringColor.opacity(scheme == .dark ? 0.08 : 0.06)).padding(11)
                Text("\(displayed)")
                    .font(.system(size: 32, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(isFull ? Color.red : .primary)
                    .contentTransition(.numericText())
                    .animation(SummitMotion.gentle, value: displayed)
            }
            .frame(width: 98, height: 98)
            Spacer().frame(height: 10)
            Text(isFull ? "beszámítva" : total == 0 ? "nincs késés" : "\(displayed) / 45 perc")
                .font(.caption.weight(.semibold))
                .foregroundStyle(isFull ? Color.red : .secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
            Spacer(minLength: 0)
        }
        .padding(14)
        .frame(maxWidth: .infinity, minHeight: 210, alignment: .top)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(scheme == .dark ? Color.white.opacity(0.06) : Color.white)
                .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(Color.primary.opacity(scheme == .dark ? 0.08 : 0.06), lineWidth: 1))
                .shadow(color: scheme == .dark ? colors.shadow.opacity(0.30) : .clear, radius: 14, y: 6)
        )
        .functionalGlass(cornerRadius: 20)
    }
}

// MARK: - Hero stats — egy nagy kártya középen Apple vonallal, sokkal több hely

private struct HeroStatsCard: View {
    let total: Int
    let unjustified: Int
    let justified: Int
    let delayCount: Int
    let colors: AppColors
    let scheme: ColorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                Image(systemName: "person.fill.xmark").font(.caption2.weight(.bold)).foregroundStyle(.secondary)
                Text("HIÁNYZÁSOK")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.secondary)
                    .tracking(0.4)
                    .lineLimit(1)
                Spacer(minLength: 2)
                Text("\(justified) igazolt" + (delayCount > 0 ? " • \(delayCount) késés" : ""))
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            Spacer().frame(height: 16)
            HStack(spacing: 0) {
                // összes — bal oldal
                VStack(alignment: .center, spacing: 4) {
                    Text("\(total)")
                        .font(.system(size: 38, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(.primary)
                        .contentTransition(.numericText())
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
                    Text("óra összesen")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .tracking(0.9)
                        .textCase(.uppercase)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity)

                // Apple stílusú vékony elválasztó vonal
                Rectangle()
                    .fill(Color.primary.opacity(scheme == .dark ? 0.10 : 0.08))
                    .frame(width: 1)
                    .frame(maxHeight: 72)
                    .padding(.horizontal, 12)

                // igazolatlan — jobb oldal
                VStack(alignment: .center, spacing: 4) {
                    Text("\(unjustified)")
                        .font(.system(size: 38, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(unjustified > 0 ? colors.red : Color.green)
                        .contentTransition(.numericText())
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
                    Text("igazolatlan")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .tracking(0.9)
                        .textCase(.uppercase)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity)
            }
            .frame(maxWidth: .infinity)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 16)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(scheme == .dark ? Color.white.opacity(0.06) : Color.white)
                .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(Color.primary.opacity(scheme == .dark ? 0.08 : 0.06), lineWidth: 1))
                .shadow(color: colors.shadow.opacity(scheme == .dark ? 0.30 : 0.07), radius: 14, y: 6)
        )
        .functionalGlass(cornerRadius: 20)
    }
}

// MARK: - Row — igazodik a Timetable / Notes / Grades designhoz: glass kör + surface

private struct AbsenceRow: View {
    let item: AbsenceItem
    let colors: AppColors
    let scheme: ColorScheme
    var isUnjustified: Bool
    var isDelay: Bool = false

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: iconName)
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(dotIconColor)
                .frame(width: 32, height: 32)
                .background {
                    Circle().fill(Color.clear)
                        .glassEffect(.clear, in: .circle)
                }
                .overlay(Circle().strokeBorder(colors.border.opacity(0.9), lineWidth: 1))

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(item.subject).font(.subheadline.weight(.semibold)).lineLimit(1)
                    if let d = item.delay, d > 0 {
                        Text("\(d) perc")
                            .font(.caption2.weight(.bold).monospacedDigit())
                            .foregroundStyle(.white)
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(Capsule().fill(colors.orange))
                    }
                }
                HStack(spacing: 6) {
                    Text(item.date.formatted(date: .abbreviated, time: .omitted))
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 7).padding(.vertical, 3)
                        .background(Capsule().fill(Color.primary.opacity(scheme == .dark ? 0.08 : 0.06)))
                    if !isDelay {
                        Text(friendlyAbsenceType(item.type))
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(isUnjustified ? colors.red : Color.green)
                            .lineLimit(1)
                    }
                }
            }
            Spacer()
        }
        .listRowBackground(rowBackground)
        .alignmentGuide(.listRowSeparatorLeading) { d in d[.leading] + 16 }
        .contentShape(Rectangle())
    }

    private var iconName: String {
        if isUnjustified { return "xmark" }
        if isDelay { return "clock.fill" }
        return "checkmark"
    }
    private var dotIconColor: Color {
        if isUnjustified { return colors.red }
        if isDelay { return colors.orange }
        return Color.green
    }
    private var rowBackground: Color {
        if isUnjustified { return colors.red.opacity(scheme == .dark ? 0.10 : 0.06) }
        if isDelay { return colors.orange.opacity(scheme == .dark ? 0.08 : 0.05) }
        return colors.surface
    }
}
