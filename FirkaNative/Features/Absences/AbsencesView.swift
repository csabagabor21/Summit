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
    /// A mentett hiányzások a közös gyorstárból (KretaStore) — tabra lépéskor
    /// azonnal; a váz csak akkor, ha még semmi nincs mentve.
    @State private var absences: [AbsenceItem] = KretaStore.shared.value(.absences) ?? []
    @State private var isLoading = KretaStore.shared.absences == nil
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
    private var unjustifiedCount: Int { absences.filter { !$0.isJustified }.count }
    private var justifiedCount: Int { absences.filter { $0.isJustified }.count }
    private var delayCount: Int { absences.filter { ($0.type.lowercased().contains("késés") || $0.type.lowercased().contains("keses")) && $0.delay != nil }.count }

    private var unjustifiedItems: [AbsenceItem] { absences.filter { !$0.isJustified }.sorted { $0.date > $1.date } }
    private var justifiedItems: [AbsenceItem] { absences.filter { $0.isJustified }.sorted { $0.date > $1.date } }

    /// Neon: a skin HUD-vöröse / ok-cián helyett Summitban a régi
    /// rendszer-piros / -zöld marad (az értékek ágaznak, nem a nézet).
    private var hudRed: Color { theme.isNeon ? NeonTheme.red : Color.red }
    private var okGreen: Color { theme.isNeon ? NeonTheme.cyan : Color.green }
    /// Szekció-fejléc darabszáma: Summitban „Igazolt • 3", Neonban
    /// HUD-kód „IGAZOLT // 03".
    private var countSeparator: String { theme.isNeon ? "//" : "•" }
    private func countText(_ n: Int) -> String { theme.isNeon ? String(format: "%02d", n) : "\(n)" }

    /// Neon késés-mérő: nagy sárga szám + `/45` kód, alatta 9 cellás
    /// HUD-sáv (cellánként 5 perc). 55%-tól narancs, 85%-tól / beszámított
    /// órától HUD-vörös; teljes ciklusnál statikus vörös/cián szellemkép
    /// (Reduce Transparency mellett a kit kikapcsolja).
    private var cpDelayGauge: some View {
        let hot = ringProgress >= 0.85 || hoursFromDelay > 0
        let tint = hot ? NeonTheme.red : ringProgress >= 0.55 ? NeonTheme.orange : NeonTheme.yellow
        return VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text("\(displayedDelay)")
                    .font(NeonTheme.display(size: isPad ? 44 : 34, weight: .bold, relativeTo: .title))
                    .monospacedDigit()
                    .foregroundStyle(isFullCycle ? NeonTheme.red : NeonTheme.yellow)
                    .contentTransition(.numericText())
                    .cpChromatic(isFullCycle ? 1 : 0)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                Text("/45")
                    .font(NeonTheme.mono(size: 11, relativeTo: .caption2))
                    .foregroundStyle(NeonTheme.dim)
            }
            NeonProgressBar(value: ringProgress, tint: tint, segments: 9, height: 8)
        }
        .frame(minHeight: isPad ? 96 : 78)
        .accessibilityElement(children: .combine)
    }

    /// Késés-mérő: Summitban gyűrű, Voxelben a szám + igazi XP-sáv
    /// (a 45 perces ciklus töltöttsége), Neonban HUD-sáv.
    @ViewBuilder
    private var delayGauge: some View {
        if theme.isNeon {
            cpDelayGauge
        } else if VoxelTheme.isActive {
            VStack(spacing: 8) {
                Text("\(displayedDelay)")
                    .voxelDisplay(isPad ? 34 : 26)
                    .monospacedDigit()
                    .foregroundStyle(isFullCycle ? Color.red : .primary)
                VoxelProgressBar(value: ringProgress)
            }
            .frame(minHeight: isPad ? 96 : 78)
        } else {
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
                    .voxelDisplay(isPad ? 34 : 26)
                    .monospacedDigit()
                    .foregroundStyle(isFullCycle ? Color.red : .primary)
                    .contentTransition(.numericText())
            }
            .frame(width: isPad ? 104 : 78, height: isPad ? 104 : 78)
        }
    }

    var body: some View {
        NavigationStack {
            List {
                // MARK: Top — egy nagy liquid glass block, eredeti layout: bal késések | jobb felül igazolt alul igazolatlan
                Section {
                    HStack(alignment: .center, spacing: 0) {
                        // Bal: késések — ring + szöveg — javított spacing, középre igazítva
                        VStack(spacing: 10) {
                            HStack {
                                SkinLabel("KÉSÉSEK", systemImage: "clock.fill")
                                    .skinFont(.caption2, weight: .bold)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.7)
                                Spacer(minLength: 4)
                                if hoursFromDelay > 0 {
                                    Text("+\(hoursFromDelay) óra")
                                        .cpOnly { $0.font(NeonTheme.mono(size: 10, relativeTo: .caption2)).textCase(.uppercase) }
                                        .skinFont(.caption2, weight: .bold)
                                        .foregroundStyle(theme.isNeon ? Color.black : .white)
                                        .padding(.horizontal, 6).padding(.vertical, 3)
                                        .skinPill(fill: hudRed)
                                        .lineLimit(1)
                                }
                            }
                            delayGauge
                            Text(isFullCycle ? "beszámítva" : totalDelay == 0 ? "nincs késés" : "\(displayedDelay) / 45 perc")
                                .skinFont(.caption, weight: .semibold)
                                .cpCaps()
                                .foregroundStyle(isFullCycle ? hudRed : .secondary)
                                .lineLimit(1)
                                .minimumScaleFactor(0.8)
                        }
                        .frame(maxWidth: .infinity)

                        // Középső Apple elválasztó — a két fél között
                        Rectangle()
                            .fill(theme.isNeon ? NeonTheme.yellow.opacity(0.32) : Color.primary.opacity(scheme == .dark ? 0.10 : 0.08))
                            .frame(width: 1)
                            .padding(.vertical, 8)
                            .padding(.horizontal, 12)

                        // Jobb: hiányzások — felül igazolt, alul igazolatlan — javított vertikális spacing, középre igazítva
                        VStack(alignment: .leading, spacing: 10) {
                            HStack(spacing: 6) {
                                SkinIcon("person.fill.xmark", size: 16).skinFont(.caption2, weight: .bold).foregroundStyle(.secondary)
                                Text("HIÁNYZÁSOK")
                                    .skinFont(.caption2, weight: .bold)
                                    .foregroundStyle(.secondary)
                                    .tracking(0.4)
                                    .lineLimit(1)
                                Spacer(minLength: 2)
                                if theme.isNeon {
                                    NeonLabel("ABS", bracketed: false, size: 9)
                                }
                            }
                            VStack(spacing: 0) {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text("\(absences.count - unjustifiedCount)")
                                        .voxelDisplay(isPad ? 38 : 30)
                                        .monospacedDigit()
                                        .foregroundStyle(.primary)
                                        .contentTransition(.numericText())
                                        .lineLimit(1)
                                        .minimumScaleFactor(0.5)
                                    Text("igazolt")
                                        .absStatCaption()
                                        .lineLimit(1)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.vertical, 4)
                                Rectangle()
                                    .fill(theme.isNeon ? NeonTheme.yellow.opacity(0.24) : Color.primary.opacity(scheme == .dark ? 0.08 : 0.06))
                                    .frame(height: 1)
                                    .padding(.vertical, 8)
                                VStack(alignment: .leading, spacing: 3) {
                                    Text("\(unjustifiedCount)")
                                        .voxelDisplay(isPad ? 38 : 30)
                                        .monospacedDigit()
                                        .foregroundStyle(unjustifiedCount > 0 ? colors.red : okGreen)
                                        .contentTransition(.numericText())
                                        .lineLimit(1)
                                        .minimumScaleFactor(0.5)
                                    Text("igazolatlan")
                                        .absStatCaption()
                                        .lineLimit(1)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.vertical, 4)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding(16)
                    .background {
                        if VoxelTheme.isActive {
                            VoxelBlockPanel(face: colors.surface)
                        } else if theme.isNeon {
                            NeonPanelBackground(accent: NeonTheme.red, fill: NeonTheme.panel)
                        } else {
                            RoundedRectangle(cornerRadius: 20, style: .continuous)
                                .fill(scheme == .dark ? Color.white.opacity(0.06) : Color.white)
                                .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(Color.primary.opacity(scheme == .dark ? 0.08 : 0.06), lineWidth: 1))
                                // Light módban nincs külső shadow — fehér kártya szürke háttéren rosszul mutat
                                .shadow(color: scheme == .dark ? colors.shadow.opacity(0.30) : .clear, radius: 14, y: 6)
                        }
                    }
                    // Light módban glass nélkül — a glass saját árnyéka dobozba clipelődik a List-sorban.
                    // Nem interaktív üveg: a kártyának nincs akciója, az
                    // `.interactive()` ujj alatt rugózott, mintha gomb lenne.
                    .modifier(StaticCardGlass(enabled: scheme == .dark, cornerRadius: 20))
                    .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                }

                if isLoading {
                    ForEach(0..<3, id: \.self) { _ in
                        HStack { Text("Betöltés…").redacted(reason: .placeholder) }
                            .summitRowSurface(colors: colors)
                            .voxelRowChrome()
                    }
                } else if absences.isEmpty {
                    Section {
                        SkinEmptyState(title: "Nincs hiányzás", systemImage: "checkmark.shield.fill", description: Text("Szép munka — nincs rögzített hiányzás"))
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
                                AbsenceBadge(icon: "checkmark.circle.fill", tint: AnyShapeStyle(okGreen), fontSize: 14, weight: .semibold, side: 30, colors: colors)
                                Text("Nincs igazolatlan hiányzás")
                                    .skinFont(.subheadline, weight: .medium)
                                    .foregroundStyle(.secondary)
                                Spacer()
                            }
                            .summitRowSurface(colors: colors)
                            .listRowInsets(VoxelTheme.rowInsets(EdgeInsets(top: 10, leading: 16, bottom: 10, trailing: 16)))
                        } else {
                            ForEach(unjustifiedItems.prefix(unjustifiedExpanded ? 100 : 3)) { a in
                                let isDelay = a.delay != nil && (a.type.lowercased().contains("késés") || a.type.lowercased().contains("keses"))
                                AbsenceRow(item: a, colors: colors, scheme: scheme, isUnjustified: true, isDelay: isDelay)
                            }
                            if unjustifiedItems.count > 3 {
                                Button {
                                    SummitHaptics.selection()
                                    withAnimation(SummitMotion.gentle) { unjustifiedExpanded.toggle() }
                                } label: {
                                    HStack {
                                        Text(unjustifiedExpanded ? "Kevesebb" : "További \(unjustifiedItems.count - 3)")
                                            .skinFont(.subheadline, weight: .semibold)
                                            .cpCaps()
                                        Spacer()
                                        SkinIcon("chevron.down")
                                            .skinFont(.caption, weight: .bold)
                                            .rotationEffect(.degrees(unjustifiedExpanded ? 180 : 0))
                                    }
                                    .foregroundStyle(colors.accent)
                                    .contentShape(Rectangle())
                                }
                                .summitRowSurface(colors: colors)
                                .listRowInsets(VoxelTheme.rowInsets(EdgeInsets(top: 10, leading: 16, bottom: 10, trailing: 16)))
                            }
                        }
                    } header: {
                        HStack(spacing: 6) {
                            SkinDot(color: colors.red)
                            Text(unjustifiedItems.isEmpty ? "Igazolatlan" : "Igazolatlan \(countSeparator) \(countText(unjustifiedItems.count))")
                                .skinFont(.caption, weight: .semibold)
                                .foregroundStyle(colors.red)
                                .textCase(.uppercase)
                                .cpCaps()
                            if theme.isNeon { HUDHeaderRule(color: colors.red) }
                            Spacer()
                            if unjustifiedItems.count > 3 {
                                SkinIcon(unjustifiedExpanded ? "chevron.up" : "chevron.down")
                                    .skinFont(.caption2, weight: .bold)
                                    .foregroundStyle(.secondary)
                                    .animation(SummitMotion.gentle, value: unjustifiedExpanded)
                            }
                        }
                        .contentShape(Rectangle())
                        .onTapGesture {
                            guard unjustifiedItems.count > 3 else { return }
                            SummitHaptics.selection()
                            withAnimation(SummitMotion.gentle) { unjustifiedExpanded.toggle() }
                        }
                    }

                    // MARK: Igazolt (+ késések) — mindig látszik, legördülő top 3
                    Section {
                        if justifiedItems.isEmpty {
                            HStack(spacing: 10) {
                                AbsenceBadge(icon: "minus.circle.fill", tint: AnyShapeStyle(.secondary), fontSize: 14, weight: .regular, side: 30, colors: colors)
                                Text("Nincs igazolt hiányzás")
                                    .skinFont(.subheadline, weight: .medium)
                                    .foregroundStyle(.secondary)
                                Spacer()
                            }
                            .summitRowSurface(colors: colors)
                            .listRowInsets(VoxelTheme.rowInsets(EdgeInsets(top: 10, leading: 16, bottom: 10, trailing: 16)))
                        } else {
                            ForEach(justifiedItems.prefix(justifiedExpanded ? 100 : 3)) { a in
                                let isDelay = a.delay != nil && (a.type.lowercased().contains("késés") || a.type.lowercased().contains("keses"))
                                AbsenceRow(item: a, colors: colors, scheme: scheme, isUnjustified: false, isDelay: isDelay)
                            }
                            if justifiedItems.count > 3 {
                                Button {
                                    SummitHaptics.selection()
                                    withAnimation(SummitMotion.gentle) { justifiedExpanded.toggle() }
                                } label: {
                                    HStack {
                                        Text(justifiedExpanded ? "Kevesebb" : "További \(justifiedItems.count - 3)")
                                            .skinFont(.subheadline, weight: .semibold)
                                            .cpCaps()
                                        Spacer()
                                        SkinIcon("chevron.down")
                                            .skinFont(.caption, weight: .bold)
                                            .rotationEffect(.degrees(justifiedExpanded ? 180 : 0))
                                    }
                                    .foregroundStyle(colors.accent)
                                    .contentShape(Rectangle())
                                }
                                .summitRowSurface(colors: colors)
                                .listRowInsets(VoxelTheme.rowInsets(EdgeInsets(top: 10, leading: 16, bottom: 10, trailing: 16)))
                            }
                        }
                    } header: {
                        HStack(spacing: 6) {
                            SkinDot(color: okGreen)
                            Text(justifiedItems.isEmpty ? "Igazolt" : "Igazolt \(countSeparator) \(countText(justifiedItems.count))")
                                .skinFont(.caption, weight: .semibold)
                                .foregroundStyle(theme.isNeon ? AnyShapeStyle(NeonTheme.cyan) : AnyShapeStyle(.secondary))
                                .textCase(.uppercase)
                                .cpCaps()
                            if theme.isNeon { HUDHeaderRule(color: NeonTheme.cyan) }
                            Spacer()
                            if justifiedItems.count > 3 {
                                SkinIcon(justifiedExpanded ? "chevron.up" : "chevron.down")
                                    .skinFont(.caption2, weight: .bold)
                                    .foregroundStyle(.secondary)
                                    .animation(SummitMotion.gentle, value: justifiedExpanded)
                            }
                        }
                        .contentShape(Rectangle())
                        .onTapGesture {
                            guard justifiedItems.count > 3 else { return }
                            SummitHaptics.selection()
                            withAnimation(SummitMotion.gentle) { justifiedExpanded.toggle() }
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .frame(maxWidth: isPad ? MacSupport.contentWidth(ipad: 1280, mac: 1150) : .infinity)
            .padding(.horizontal, MacSupport.sidePadding)
            .frame(maxWidth: .infinity)
            .summitListChrome(colors: colors)
            .navigationTitle("Hiányzások")
            .navigationBarTitleDisplayMode(.large)
            .summitToolbarBackground()
            .task { await load() }
            .refreshable {
                await load(force: true)
                SummitHaptics.light()
            }
            .animation(SummitMotion.gentle, value: absences.count)
            .animation(SummitMotion.gentle, value: totalDelay)
        }
        .tint(colors.accent)
    }

    /// Tabváltáskor a `.task` újra lefut — friss gyorstár-találatnál ez
    /// hálózat nélkül tér vissza. A váz csak üres listánál jön; egyébként
    /// a régi lista marad, az új adat dinamikusan beíródik.
    func load(force: Bool = false) async {
        // Egy adatsáv: demo usert is a KretaClient szolgálja ki helyből.
        guard let user = session.selectedUser else { isLoading = false; return }
        let hadData = !absences.isEmpty
        if !hadData { isLoading = true }
        let iss = user.instituteCode.isEmpty ? (JWT.instituteCode(from: user.accessToken) ?? "") : user.instituteCode
        KretaStore.shared.activate(user)
        let fetched = await kreta.fetchAbsences(iss: iss, force: force)
        // Totális fetch-hiba (lejárt token, offline): a legutóbbi lista marad,
        // nem ürül ki a Hiányzások tab egy sikertelen refresh-től.
        if !(fetched.isEmpty && hadData), absences != fetched { absences = fetched }
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
                SkinLabel("KÉSÉSEK", systemImage: "clock.fill")
                    .skinFont(.caption2, weight: .bold)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                Spacer(minLength: 4)
                if hoursFromDelay > 0 {
                    Text("+\(hoursFromDelay) óra")
                        .skinFont(.caption2, weight: .bold)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 6).padding(.vertical, 3)
                        .skinPill(fill: Color.red)
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
                    .voxelDisplay(32)
                    .monospacedDigit()
                    .foregroundStyle(isFull ? Color.red : .primary)
                    .contentTransition(.numericText())
                    .animation(SummitMotion.gentle, value: displayed)
            }
            .frame(width: 98, height: 98)
            Spacer().frame(height: 10)
            Text(isFull ? "beszámítva" : total == 0 ? "nincs késés" : "\(displayed) / 45 perc")
                .skinFont(.caption, weight: .semibold)
                .foregroundStyle(isFull ? Color.red : .secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
            Spacer(minLength: 0)
        }
        .padding(14)
        .frame(maxWidth: .infinity, minHeight: 210, alignment: .top)
        .background {
            if VoxelTheme.isActive {
                VoxelBlockPanel(face: colors.surface)
            } else if NeonTheme.isActive {
                NeonPanelBackground()
            } else {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(scheme == .dark ? Color.white.opacity(0.06) : Color.white)
                    .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(Color.primary.opacity(scheme == .dark ? 0.08 : 0.06), lineWidth: 1))
                    // Light módban nincs külső shadow — fehér kártya szürke háttéren rosszul mutat
                    .shadow(color: scheme == .dark ? colors.shadow.opacity(0.30) : .clear, radius: 14, y: 6)
            }
        }
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
                SkinIcon("person.fill.xmark", size: 16).skinFont(.caption2, weight: .bold).foregroundStyle(.secondary)
                Text("HIÁNYZÁSOK")
                    .skinFont(.caption2, weight: .bold)
                    .foregroundStyle(.secondary)
                    .tracking(0.4)
                    .lineLimit(1)
                Spacer(minLength: 2)
                Text("\(justified) igazolt" + (delayCount > 0 ? " • \(delayCount) késés" : ""))
                    .skinFont(.caption2, weight: .medium)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            Spacer().frame(height: 16)
            HStack(spacing: 0) {
                // összes — bal oldal
                VStack(alignment: .center, spacing: 4) {
                    Text("\(total)")
                        .voxelDisplay(38)
                        .monospacedDigit()
                        .foregroundStyle(.primary)
                        .contentTransition(.numericText())
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
                    Text("óra összesen")
                        .voxelSectionHeader()
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
                        .voxelDisplay(38)
                        .monospacedDigit()
                        .foregroundStyle(unjustified > 0 ? colors.red : Color.green)
                        .contentTransition(.numericText())
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
                    Text("igazolatlan")
                        .voxelSectionHeader()
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity)
            }
            .frame(maxWidth: .infinity)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 16)
        .frame(maxWidth: .infinity)
        .background {
            if VoxelTheme.isActive {
                VoxelBlockPanel(face: colors.surface)
            } else if NeonTheme.isActive {
                NeonPanelBackground()
            } else {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(scheme == .dark ? Color.white.opacity(0.06) : Color.white)
                    .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(Color.primary.opacity(scheme == .dark ? 0.08 : 0.06), lineWidth: 1))
                    .shadow(color: colors.shadow.opacity(scheme == .dark ? 0.30 : 0.07), radius: 14, y: 6)
            }
        }
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
            AbsenceBadge(icon: iconName, tint: AnyShapeStyle(dotIconColor), fontSize: 12, weight: .bold, side: 32, colors: colors)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(item.subject).skinFont(.subheadline, weight: .semibold).lineLimit(1)
                    if let d = item.delay, d > 0 {
                        Text("\(d) perc")
                            .cpOnly { $0.font(NeonTheme.mono(size: 10, relativeTo: .caption2)).textCase(.uppercase) }
                            .skinFont(.caption2, weight: .bold).monospacedDigit()
                            .foregroundStyle(cp ? Color.black : .white)
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .skinPill(fill: cp ? NeonTheme.yellow : colors.orange)
                    }
                }
                HStack(spacing: 6) {
                    Text(cp ? Self.hudDate(item.date) : item.date.formatted(date: .abbreviated, time: .omitted))
                        .cpOnly { $0.font(NeonTheme.mono(size: 10, relativeTo: .caption2)) }
                        .skinFont(.caption2, weight: .medium)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 7).padding(.vertical, 3)
                        .skinPill(fill: Color.primary.opacity(scheme == .dark ? 0.08 : 0.06))
                    if !isDelay {
                        Text(friendlyAbsenceType(item.type))
                            .skinFont(.caption2, weight: .semibold)
                            .cpCaps()
                            .foregroundStyle(isUnjustified ? colors.red : cp ? NeonTheme.cyan : Color.green)
                            .lineLimit(1)
                    }
                }
            }
            Spacer()
        }
        .listRowBackground(AbsenceRowBackground(fill: rowBackground, stripe: dotIconColor))
        .listRowInsets(VoxelTheme.rowInsets(nil))
        .listRowSeparator(VoxelTheme.isActive || cp ? .hidden : .automatic)
        .alignmentGuide(.listRowSeparatorLeading) { d in d[.leading] + 16 }
        .contentShape(Rectangle())
    }

    private var cp: Bool { NeonTheme.isActive }

    /// HUD-dátum: egyenközű „2026.10.24" (a skin adat-címkéi így írnak).
    private static let hudDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "hu_HU")
        f.dateFormat = "yyyy.MM.dd"
        return f
    }()
    private static func hudDate(_ d: Date) -> String { hudDateFormatter.string(from: d) }

    private var iconName: String {
        if isUnjustified { return "xmark" }
        if isDelay { return "clock.fill" }
        return "checkmark"
    }
    private var dotIconColor: Color {
        if isUnjustified { return colors.red }
        if isDelay { return cp ? NeonTheme.yellow : colors.orange }
        return cp ? NeonTheme.cyan : Color.green
    }
    private var rowBackground: Color {
        if isUnjustified { return colors.red.opacity(scheme == .dark ? 0.10 : 0.06) }
        if isDelay { return colors.orange.opacity(scheme == .dark ? 0.08 : 0.05) }
        return colors.surface
    }
}

// MARK: - Statikus (nem interaktív) kártya-üveg

/// Liquid Glass akció nélküli kártyára: valódi `.regular` üveg, de
/// `.interactive()` nélkül (az csak koppintható elemre való). Voxelben
/// és Neonban nincs üveg, a kártya saját panelje marad (Neonban
/// az üveg lekerekített sarka kilógott a levágott sarkú HUD-panel mögül).
private struct StaticCardGlass: ViewModifier {
    var enabled: Bool
    var cornerRadius: CGFloat

    func body(content: Content) -> some View {
        if enabled && !VoxelTheme.isActive && !NeonTheme.isActive {
            content.glassEffect(.regular, in: .rect(cornerRadius: cornerRadius))
        } else {
            content
        }
    }
}

// MARK: - Kerek ikon-jelvény (Summit) / inventory-slot (Voxel)

private struct AbsenceBadge: View {
    let icon: String
    let tint: AnyShapeStyle
    let fontSize: CGFloat
    let weight: Font.Weight
    let side: CGFloat
    let colors: AppColors

    var body: some View {
        if VoxelTheme.isActive {
            SkinIcon(icon, size: side * 0.6)
                .frame(width: side, height: side)
                .background { VoxelInventorySlot() }
        } else if NeonTheme.isActive {
            // Levágott sarkú HUD-cella: halvány állapot-arc + 1 px-es keret.
            let cell = NeonChamferShape(cut: 6, corners: .diagonal)
            SkinIcon(icon)
                .font(.system(size: fontSize, weight: weight))
                .foregroundStyle(tint)
                .frame(width: side, height: side)
                .background(cell.fill(tint.opacity(0.12)))
                .overlay(cell.strokeBorder(tint, lineWidth: 1))
        } else {
            SkinIcon(icon)
                .font(.system(size: fontSize, weight: weight))
                .foregroundStyle(tint)
                .frame(width: side, height: side)
                .background {
                    Circle().fill(Color.clear)
                        .glassEffect(.clear, in: .circle)
                }
                .overlay(Circle().strokeBorder(colors.border.opacity(0.9), lineWidth: 1))
        }
    }
}

// MARK: - Neon-segédek (csak ebben a fájlban)

/// Hiányzás-sor háttere: Neonban HUD-sor panel (levágott sarok,
/// 1 px-es keret az állapot színében) + 2 pt-os állapot-csík a bal élen;
/// Summitban / Voxelben változatlanul a `skinRowBackground`.
private struct AbsenceRowBackground: View {
    var fill: Color
    var stripe: Color

    var body: some View {
        if NeonTheme.isActive {
            NeonRowBackground(accent: stripe, fill: fill)
                .overlay(alignment: .leading) {
                    // A bal felső levágás (10 pt) alatt indul, a panel
                    // behúzásán belül ül.
                    Rectangle()
                        .fill(stripe)
                        .frame(width: 2)
                        .padding(.top, NeonTheme.rowVerticalInset + 14)
                        .padding(.bottom, NeonTheme.rowVerticalInset + 4)
                        .padding(.leading, NeonTheme.rowHorizontalInset + 3)
                }
        } else {
            VoxelTheme.skinRowBackground(fill)
        }
    }
}

/// Szekció-fejléc kitöltő vonala (Neon): 1 pt-os halvány HUD-vonal.
private struct HUDHeaderRule: View {
    var color: Color
    var body: some View {
        Rectangle().fill(color.opacity(0.35)).frame(height: 1).accessibilityHidden(true)
    }
}

private extension View {
    /// Csak Neon-skinben alkalmazott módosítás; Summitban és
    /// Voxelben a nézet érintetlen marad.
    @ViewBuilder
    func cpOnly<V: View>(_ transform: (Self) -> V) -> some View {
        if NeonTheme.isActive { transform(self) } else { self }
    }

    /// HUD-felirat: nagybetűs, ritkított (csak Neonban).
    func cpCaps() -> some View {
        cpOnly { $0.textCase(.uppercase).tracking(1.2) }
    }

    /// Hero-számok alatti felirat: Neonban apró egyenközű halvány
    /// kód-címke (a skin vörös szekció-fejléce itt félrevezető lenne az
    /// „igazolt" alatt), máshol a megszokott `voxelSectionHeader`.
    @ViewBuilder
    func absStatCaption() -> some View {
        if NeonTheme.isActive {
            self.font(NeonTheme.mono(size: 10, relativeTo: .caption2))
                .textCase(.uppercase)
                .tracking(1)
                .foregroundStyle(NeonTheme.dim)
        } else {
            self.voxelSectionHeader()
        }
    }
}
