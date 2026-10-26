import SwiftUI
import Charts

// MARK: - Morph vector for premium (tantárgy detail) - fluid morph animation
private let chartSampleCount = 48
private let chartDomainMax: Double = 5.45

struct MorphVector: VectorArithmetic {
    var values: [Double]
    static var zero: MorphVector { MorphVector(values: Array(repeating: 0, count: chartSampleCount)) }
    var magnitudeSquared: Double { values.reduce(0) { $0 + $1 * $1 } }
    mutating func scale(by rhs: Double) { for i in values.indices { values[i] *= rhs } }
    static func + (lhs: MorphVector, rhs: MorphVector) -> MorphVector {
        let n = min(lhs.values.count, rhs.values.count)
        var out = lhs; for i in 0..<n { out.values[i] = lhs.values[i] + rhs.values[i] }; return out
    }
    static func - (lhs: MorphVector, rhs: MorphVector) -> MorphVector {
        let n = min(lhs.values.count, rhs.values.count)
        var out = lhs; for i in 0..<n { out.values[i] = lhs.values[i] - rhs.values[i] }; return out
    }
}

private struct MorphLineShape: Shape {
    var vector: MorphVector
    var animatableData: MorphVector { get { vector } set { vector = newValue } }
    func path(in rect: CGRect) -> Path {
        guard vector.values.count >= 2 else { return Path() }
        let n = vector.values.count
        var pts: [CGPoint] = []
        pts.reserveCapacity(n)
        for i in 0..<n {
            let x = rect.minX + CGFloat(Double(i)/Double(max(1,n-1))) * rect.width
            let norm = (vector.values[i] - 1.0)/(chartDomainMax-1.0)
            let y = rect.maxY - CGFloat(norm)*rect.height
            pts.append(CGPoint(x: x, y: y))
        }
        var p = Path(); p.move(to: pts[0])
        if pts.count == 2 { p.addLine(to: pts[1]); return p }
        for i in 0..<(pts.count-1) {
            let p0 = i>0 ? pts[i-1] : pts[0]; let p1 = pts[i]; let p2 = pts[i+1]; let p3 = i+2 < pts.count ? pts[i+2] : pts[pts.count-1]
            let cp1 = CGPoint(x: p1.x + (p2.x-p0.x)/6, y: p1.y + (p2.y-p0.y)/6)
            let cp2 = CGPoint(x: p2.x - (p3.x-p1.x)/6, y: p2.y - (p3.y-p1.y)/6)
            p.addCurve(to: p2, control1: cp1, control2: cp2)
        }
        return p
    }
}
private struct MorphAreaShape: Shape {
    var vector: MorphVector
    var animatableData: MorphVector { get { vector } set { vector = newValue } }
    func path(in rect: CGRect) -> Path {
        guard vector.values.count >= 2 else { return Path() }
        let n = vector.values.count
        var pts: [CGPoint] = []
        for i in 0..<n {
            let x = rect.minX + CGFloat(Double(i)/Double(max(1,n-1))) * rect.width
            let norm = (vector.values[i] - 1.0)/(chartDomainMax-1.0)
            let y = rect.maxY - CGFloat(norm)*rect.height
            pts.append(CGPoint(x: x, y: y))
        }
        var p = Path(); p.move(to: pts[0])
        if pts.count == 2 { p.addLine(to: pts[1]) } else {
            for i in 0..<(pts.count-1) {
                let p0 = i>0 ? pts[i-1] : pts[0]; let p1 = pts[i]; let p2 = pts[i+1]; let p3 = i+2 < pts.count ? pts[i+2] : pts[pts.count-1]
                let cp1 = CGPoint(x: p1.x + (p2.x-p0.x)/6, y: p1.y + (p2.y-p0.y)/6)
                let cp2 = CGPoint(x: p2.x - (p3.x-p1.x)/6, y: p2.y - (p3.y-p1.y)/6)
                p.addCurve(to: p2, control1: cp1, control2: cp2)
            }
        }
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY)); p.addLine(to: CGPoint(x: rect.minX, y: rect.maxY)); p.closeSubpath(); return p
    }
}

// MARK: - GradeChartView — fő képernyő (monthly+editorial) visszaállítva régi Charts-re, tantárgy detail prémium morph
struct GradeChartView: View {
    let grades: [GradeItem]
    var accent: Color
    var showTarget: Int? = nil
    var height: CGFloat = 180
    var monthly: Bool = false
    var editorial: Bool = false
    @Environment(\.colorScheme) var scheme

    var body: some View {
        // Voxel: mindkét mód ugyanaz a pixel-rácsra rajzolt grafikon
        // (a Charts-tengelyfeliratok nem kaphatnak pixelbetűt).
        // Neon: mindkét mód ugyanaz a HUD-grafikon (szögletes
        // sárga vonal, jegy-színű rombusz-pontok, célkereszt az utolsón).
        if NeonTheme.isActive {
            cpBody
        } else if VoxelTheme.isActive {
            voxelBody
        } else
        // Jegyek fő képernyő: monthly+editorial → régi jól bevált Charts, nem nyúlunk hozzá
        if monthly && editorial {
            classicBody
        } else {
            // Tantárgy detail → prémium morph, Home LiveCard stílusban (nem vág, fluid)
            premiumBody
        }
    }

    // MARK: Classic — visszaállítva (GradesView jól nézett ki)
    private var classicBody: some View {
        Group {
            if displayGrades.count < 2 {
                ContentUnavailableView("Nincs elég adat", systemImage: "chart.line.flattrend.xyaxis", description: Text("Adj hozzá jegyet"))
                    .frame(height: height)
            } else {
                Chart {
                    ForEach(Array(displayPoints.enumerated()), id: \.offset) { _, p in
                        LineMark(x: .value("Dátum", p.date), y: .value("Átlag", p.avg))
                            .foregroundStyle(Color.primary.opacity(0.85))
                            .lineStyle(StrokeStyle(lineWidth: 1.6, lineCap: .round, lineJoin: .round))
                            .interpolationMethod(.catmullRom)
                    }
                    if displayGrades.count <= 12 {
                        ForEach(displayGrades, id: \.id) { g in
                            PointMark(x: .value("Dátum", g.date), y: .value("Jegy", Double(g.value)))
                                .foregroundStyle(g.id.hasPrefix("phantom") ? Color.orange : Color.primary.opacity(0.55))
                                .symbolSize(14)
                        }
                    }
                }
                .frame(height: height)
                .chartYScale(domain: 1...5)
                .chartXScale(domain: xDomain)
                .chartXAxis {
                    // Explicit tick-dátumok az adatból: a stride-os hónap-
                    // léptetés a párnázott domain miatt üres/jövő hónapot is
                    // behozott (pl. csupa szeptemberi jegynél "okt." állt a
                    // tengelyen) — ez volt a látható elcsúszás.
                    AxisMarks(values: xTickDates) { v in
                        AxisGridLine().foregroundStyle(Color.primary.opacity(0.04))
                        AxisTick().foregroundStyle(Color.primary.opacity(0.04))
                        if let d = v.as(Date.self) {
                            AxisValueLabel(xTickLabel(for: d)).font(.caption2).foregroundStyle(.secondary)
                        }
                    }
                }
                .chartYAxis {
                    AxisMarks(position: .leading, values: [1,2,3,4,5]) { v in
                        AxisGridLine().foregroundStyle(Color.primary.opacity(0.04))
                        AxisTick().foregroundStyle(Color.primary.opacity(0.04))
                        AxisValueLabel().font(.caption2).foregroundStyle(.secondary)
                    }
                }
                .chartPlotStyle { plot in plot.background(Color.clear).padding(.vertical, 4) }
                .padding(.vertical, 2)
                .animation(.spring(response: 0.6, dampingFraction: 0.85), value: displayGrades)
                .transition(.opacity.combined(with: .scale(scale: 0.98)))
            }
        }
    }

    // MARK: Premium — tantárgy detail, Home stílus
    private var premiumBody: some View {
        Group {
            if displayGrades.count < 2 {
                ContentUnavailableView("Nincs elég adat", systemImage: "chart.line.downtrend.xyaxis", description: Text("Adj hozzá jegyet"))
                    .frame(height: height)
                    .transition(.opacity)
            } else {
                premiumChart
                    .frame(height: height)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                    .transition(.opacity.combined(with: .scale(scale: 0.98)))
            }
        }
    }

    private var premiumChart: some View {
        let vector = currentVector
        return GeometryReader { geo in
            let W = geo.size.width; let H = geo.size.height
            let top: CGFloat = 14; let bottom: CGFloat = 26; let leading: CGFloat = 28; let trailing: CGFloat = 10
            let plotX = leading; let plotY = top; let plotW = max(0, W-leading-trailing); let plotH = max(0, H-top-bottom)
            let plotRect = CGRect(x: plotX, y: plotY, width: plotW, height: plotH)
            ZStack(alignment: .topLeading) {
                Canvas { ctx, _ in
                    for v in 1...5 {
                        let norm = (Double(v)-1)/(chartDomainMax-1); let y = plotY + (1-CGFloat(norm))*plotH
                        let path = Path { p in p.move(to: CGPoint(x: plotX, y: y)); p.addLine(to: CGPoint(x: plotX+plotW, y: y)) }
                        ctx.stroke(path, with: .color(Color.primary.opacity(0.06)), lineWidth: 0.6)
                    }
                }
                ForEach(1...5, id: \.self) { v in
                    let norm = (Double(v)-1)/(chartDomainMax-1); let y = plotY + (1-CGFloat(norm))*plotH
                    Text("\(v)").font(.system(size: 10, weight: .medium, design: .rounded).monospacedDigit()).foregroundStyle(.secondary.opacity(0.9))
                        .frame(width: leading-6, alignment: .trailing).position(x: leading/2+4, y: y)
                }
                MorphAreaShape(vector: vector).fill(LinearGradient(colors: [Color.primary.opacity(0.06), Color.primary.opacity(0.0)], startPoint: .top, endPoint: .bottom))
                    .frame(width: plotW, height: plotH).offset(x: plotX, y: plotY)
                    .animation(.spring(response: 0.85, dampingFraction: 0.84), value: vector.values)
                MorphLineShape(vector: vector).stroke(Color.primary.opacity(0.85), style: StrokeStyle(lineWidth: 1.7, lineCap: .round, lineJoin: .round))
                    .frame(width: plotW, height: plotH).offset(x: plotX, y: plotY)
                    .animation(.spring(response: 0.85, dampingFraction: 0.84), value: vector.values)
                    .shadow(color: Color.primary.opacity(0.08), radius: 6, y: 2)
                ForEach(Array(dotPositions(in: plotRect).enumerated()), id: \.offset) { _, d in
                    ZStack {
                        Circle().fill(Color.white.opacity(scheme == .dark ? 0.92 : 1)).frame(width: d.diameter+4, height: d.diameter+4).shadow(color: .black.opacity(0.08), radius: 2, y: 1)
                        Circle().fill(d.isPhantom ? Color.orange : Color.primary.opacity(0.62)).frame(width: d.diameter, height: d.diameter)
                    }.position(x: d.x, y: d.y).animation(.spring(response: 0.85, dampingFraction: 0.82), value: grades)
                }
                ForEach(Array(resolvedXTicks(in: plotRect).enumerated()), id: \.offset) { _, tick in
                    Text(tick.label).font(.system(size: 10, weight: .medium)).foregroundStyle(.secondary).position(x: tick.x, y: H-10)
                }
            }
        }
        .padding(.vertical, 4)
        .background(RoundedRectangle(cornerRadius: 16).fill(scheme == .dark ? Color.white.opacity(0.04) : Color.white.opacity(0.92)).overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Color.primary.opacity(scheme == .dark ? 0.06 : 0.05), lineWidth: 1)))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    // MARK: Voxel — pixel-grafikon

    /// A grafikon adatai 0…1-re normálva (x: dátum a `xDomain`-ban, y: jegy
    /// a MC-skála szerint), hogy a rajzoló nézet ne ismerjen modellt.
    @ViewBuilder
    private var voxelBody: some View {
        if displayGrades.count < 2 {
            SkinEmptyState(title: "Nincs elég adat", systemImage: "chart.line.flattrend.xyaxis", description: Text("Adj hozzá jegyet"))
                .frame(height: height)
        } else {
            voxelChart
        }
    }

    private var voxelChart: some View {
        let dom = xDomain
        let span = max(1, dom.upperBound.timeIntervalSince(dom.lowerBound))
        func nx(_ d: Date) -> Double { min(1, max(0, d.timeIntervalSince(dom.lowerBound) / span)) }
        let dots: [VoxelPixelChart.Dot] = displayGrades.count <= 12
            ? displayGrades.map { VoxelPixelChart.Dot(x: nx($0.date), value: Double($0.value), heavy: $0.weight >= 200, phantom: $0.id.hasPrefix("phantom")) }
            : []
        return VoxelPixelChart(
            line: displayPoints.map { VoxelPixelChart.Point(x: nx($0.date), value: $0.avg) },
            dots: dots,
            ticks: xTickDates.map { VoxelPixelChart.Tick(x: nx($0), label: xTickLabel(for: $0)) },
            height: height
        )
    }

    // MARK: Neon — HUD-grafikon

    @ViewBuilder
    private var cpBody: some View {
        if displayGrades.count < 2 {
            SkinEmptyState(title: "Nincs elég adat", systemImage: "chart.line.flattrend.xyaxis", description: Text("Adj hozzá jegyet"))
                .frame(height: height)
        } else {
            cpChart
        }
    }

    private var cpChart: some View {
        let dom = xDomain
        let span = max(1, dom.upperBound.timeIntervalSince(dom.lowerBound))
        func nx(_ d: Date) -> Double { min(1, max(0, d.timeIntervalSince(dom.lowerBound) / span)) }
        let dots: [NeonHudChart.Dot] = displayGrades.count <= 12
            ? displayGrades.map { NeonHudChart.Dot(x: nx($0.date), value: $0.value, heavy: $0.weight >= 200, phantom: $0.id.hasPrefix("phantom")) }
            : []
        return NeonHudChart(
            line: displayPoints.map { NeonHudChart.Point(x: nx($0.date), value: $0.avg) },
            dots: dots,
            ticks: xTickDates.map { NeonHudChart.Tick(x: nx($0), label: xTickLabel(for: $0).uppercased()) },
            code: monthly ? "AVG.TREND // HAVI" : "AVG.TREND // FUTÓ",
            height: height
        )
    }

    // MARK: Shared helpers — 0-s jegy kizárva mindenhonnan
    /// A grafikon származtatott adatai (szűrés, havi vödrök, kijelzett pontok,
    /// futó átlag) EGYSZER bemenetenként — eddig egy body-kiértékelés több
    /// tucatszor számolta újra, a futó átlagot ráadásul négyzetesen.
    private struct Derived {
        var valid: [GradeItem]
        var buckets: [(monthStart: Date, average: Double, count: Int, subject: String)]
        var display: [GradeItem]
        var points: [(date: Date, avg: Double)]
    }
    private struct DerivedKey: Hashable {
        var grades: [GradeItem]
        var monthly: Bool
    }
    /// Kis memó (a Jegyek tab és a tárgy-részletező egyszerre több grafikont tart).
    @MainActor private static var derivedMemo: [DerivedKey: Derived] = [:]

    private var derived: Derived {
        let key = DerivedKey(grades: grades, monthly: monthly)
        if let hit = Self.derivedMemo[key] { return hit }
        let valid = grades.filter { $0.value != 0 }
        var buckets: [(monthStart: Date, average: Double, count: Int, subject: String)] = []
        if monthly {
            let b = GradingLogic.monthlyBuckets(grades: valid)
            buckets = b.count >= 2 ? b : []
        }
        let display: [GradeItem]
        if monthly, !buckets.isEmpty {
            display = buckets.map { b in
                let value = Int(round(b.average))
                return GradeItem(id: "monthly-\(b.monthStart.timeIntervalSince1970)", subject: b.subject, value: value, valueText: "\(value)", date: b.monthStart, teacher: "", type: "havi", weight: 100, topic: "")
            }
        } else {
            display = valid
        }
        var points: [(date: Date, avg: Double)] = []
        points.reserveCapacity(display.count)
        if monthly {
            points = display.map { ($0.date, Double($0.value)) }
        } else {
            // Futó súlyozott átlag lineárisan (azonos a prefixenkénti weightedAverage-dzsel).
            var sum = 0.0, weight = 0.0
            for g in display {
                if g.value != 0 {
                    sum += Double(g.value) * Double(g.weight) / 100.0
                    weight += Double(g.weight) / 100.0
                }
                points.append((g.date, weight > 0 ? sum / weight : 0))
            }
        }
        let d = Derived(valid: valid, buckets: buckets, display: display, points: points)
        if Self.derivedMemo.count >= 8 { Self.derivedMemo.removeAll() }
        Self.derivedMemo[key] = d
        return d
    }

    private var validGrades: [GradeItem] { derived.valid }
    /// Havi vödrök (csak monthly módban, min. 2 hónap esetén él).
    private var monthBuckets: [(monthStart: Date, average: Double, count: Int, subject: String)] {
        derived.buckets
    }
    /// X-tengely tickek az adatból (havi módban a vödrök hónapkezdetei,
    /// nyers módban a tartomány széle/közepe vagy hónapkezdetei).
    private var xTickDates: [Date] {
        if !monthBuckets.isEmpty { return monthBuckets.map(\.monthStart) }
        let dates = displayGrades.map(\.date)
        guard let min = dates.min(), let max = dates.max(), max > min else { return dates }
        let cal = Calendar.current
        let spanDays = max.timeIntervalSince(min) / 86400
        if spanDays > 60 {
            var out: [Date] = []
            var cur = cal.date(from: cal.dateComponents([.year, .month], from: min)) ?? min
            if cur < min, let nxt = cal.date(byAdding: .month, value: 1, to: cur) { cur = nxt }
            while cur <= max, out.count < 7 {
                out.append(cur)
                guard let nxt = cal.date(byAdding: .month, value: 1, to: cur) else { break }
                cur = nxt
            }
            return out
        }
        let mid = min.addingTimeInterval(max.timeIntervalSince(min) / 2)
        return Array(Set([min, mid, max])).sorted()
    }
    /// Statikus tengelyfelirat-formázók (eddig tick-enként új DateFormatter).
    static let monthTickFormatter: DateFormatter = {
        let f = DateFormatter(); f.locale = Locale(identifier: "hu_HU"); f.dateFormat = "MMM"; return f
    }()
    static let dayTickFormatter: DateFormatter = {
        let f = DateFormatter(); f.locale = Locale(identifier: "hu_HU"); f.dateFormat = "MM.dd"; return f
    }()
    private func xTickLabel(for d: Date) -> String {
        // Havi módban a régi kisbetűs rövid hónapnév (pl. "szept."),
        // nyers módban nap-pontos dátum.
        (monthBuckets.isEmpty ? Self.dayTickFormatter : Self.monthTickFormatter).string(from: d)
    }
    private var displayGrades: [GradeItem] { derived.display }
    private var displayPoints: [(date: Date, avg: Double)] { derived.points }
    private var xDomain: ClosedRange<Date> {
        let src = displayGrades
        guard let min = src.map(\.date).min(), let max = src.map(\.date).max() else { let now=Date(); return now.addingTimeInterval(-30*86400)...now }
        if min==max { return min.addingTimeInterval(-86400)...max.addingTimeInterval(86400) }
        let pad = max.timeIntervalSince(min)*0.06; return min.addingTimeInterval(-pad)...max.addingTimeInterval(pad)
    }
    private var currentVector: MorphVector {
        let pts = displayPoints
        guard pts.count>=2, let minD=pts.map(\.date).min(), let maxD=pts.map(\.date).max(), maxD>minD else { return MorphVector(values: Array(repeating: pts.first?.avg ?? 3, count: chartSampleCount)) }
        let span = maxD.timeIntervalSince(minD)
        var ys: [Double]=[]; ys.reserveCapacity(chartSampleCount)
        for i in 0..<chartSampleCount {
            let t=Double(i)/Double(chartSampleCount-1); let date=minD.addingTimeInterval(t*span)
            var y: Double
            if date<=pts[0].date { y=pts[0].avg } else if date>=pts.last!.date { y=pts.last!.avg } else {
                var found=pts[0].avg
                for k in 0..<(pts.count-1) { if date>=pts[k].date && date<=pts[k+1].date { let seg=pts[k+1].date.timeIntervalSince(pts[k].date); let f=seg>0 ? date.timeIntervalSince(pts[k].date)/seg : 0; found=pts[k].avg+f*(pts[k+1].avg-pts[k].avg); break } }
                y=found
            }
            ys.append(min(max(y,1),chartDomainMax))
        }
        return MorphVector(values: ys)
    }
    private struct DotPos { var x: CGFloat; var y: CGFloat; var value: Int; var diameter: CGFloat; var isPhantom: Bool }
    private func dotPositions(in plot: CGRect) -> [DotPos] {
        guard let minD=displayGrades.map(\.date).min(), let maxD=displayGrades.map(\.date).max(), maxD>minD else { return [] }
        if displayGrades.count>12 { return [] }
        let span=maxD.timeIntervalSince(minD)
        return displayGrades.map { g in
            let nx=g.date.timeIntervalSince(minD)/span; let x=plot.minX+CGFloat(nx)*plot.width
            let norm=(Double(g.value)-1)/(chartDomainMax-1); let y=plot.minY+(1-CGFloat(norm))*plot.height
            let diam: CGFloat = g.weight>=200 ? 10 : (g.weight<=75 ? 6 : 8)
            return DotPos(x: x, y: y, value: g.value, diameter: diam, isPhantom: g.id.hasPrefix("phantom"))
        }
    }
    struct XTick { var x: CGFloat; var label: String }
    private var plotSpanDays: Double { guard let minD=displayPoints.map(\.date).min(), let maxD=displayPoints.map(\.date).max() else { return 0 }; return maxD.timeIntervalSince(minD)/86400 }
    private var tickDates: [Date] {
        guard let minD=displayPoints.map(\.date).min(), let maxD=displayPoints.map(\.date).max(), maxD>minD else { return [] }
        let cal=Calendar.current; var dates:[Date]=[]; let spanDays=maxD.timeIntervalSince(minD)/86400
        if spanDays>90 { var cur=cal.date(from: cal.dateComponents([.year,.month], from: minD)) ?? minD; while cur<=maxD { dates.append(cur); guard let nxt=cal.date(byAdding: .month, value: 1, to: cur) else { break }; cur=nxt; if dates.count>7 { break } } }
        else { for i in 0...3 { let t=Double(i)/3.0; dates.append(minD.addingTimeInterval(t*maxD.timeIntervalSince(minD))) } }
        return dates
    }
    private func colorForValue(_ v: Int) -> Color { Color(hex: UInt([0xFF4D6E,0xFF7A45,0xFFD23C,0x92EA3B,0x22CCAD][max(0,min(4,v-1))])) }
}

extension GradeChartView {
    func resolvedXTicks(in plot: CGRect) -> [XTick] {
        let dates=tickDates; guard let minD=displayPoints.map(\.date).min(), let maxD=displayPoints.map(\.date).max(), maxD>minD else { return [] }
        let span=maxD.timeIntervalSince(minD)
        let fmt = plotSpanDays > 90 ? Self.monthTickFormatter : Self.dayTickFormatter
        return dates.map { d in let nx=d.timeIntervalSince(minD)/span; let x=plot.minX+CGFloat(nx)*plot.width; return XTick(x: x, label: fmt.string(from: d).capitalized) }
    }
}


// MARK: - Voxel pixel-grafikon

/// Pixel-rácsra (3 pt) rajzolt vonaldiagram sötét, inventory-szerű
/// panelben: Bresenham-vonal 1 px vastagon, négyzet-pontok, szaggatott
/// pixel-rácsvonalak, Monocraft tengelyfeliratok. Se görbe, se átmenet,
/// se lágy árnyék — minden él a rácsra esik.
private struct VoxelPixelChart: View {
    struct Point { var x: Double; var value: Double }
    struct Dot { var x: Double; var value: Double; var heavy: Bool; var phantom: Bool }
    struct Tick { var x: Double; var label: String }

    var line: [Point]
    var dots: [Dot]
    var ticks: [Tick]
    var height: CGFloat

    /// Függőleges skála: kicsit a 1 alatt és az 5 felett, hogy a szélső
    /// pontok ne a keretre üljenek.
    private let yLo = 0.6
    private let yHi = 5.4
    private let u = VoxelTheme.px
    private let left: CGFloat = 27
    private let right: CGFloat = 12
    private let top: CGFloat = 12
    private let bottom: CGFloat = 27

    private static let lineColor: Color = Color(hex: 0x55FF55)
    private static let gridColor: Color = Color(hex: 0x8B8B8B)

    var body: some View {
        GeometryReader { geo in
            let plot = plotRect(geo.size)
            ZStack(alignment: .topLeading) {
                Canvas { ctx, _ in draw(&ctx, plot: plot) }
                ForEach(1...5, id: \.self) { v in
                    Text("\(v)")
                        .font(VoxelFontLoader.font(size: 11))
                        .foregroundStyle(Color(hex: 0xE0E0E0))
                        .frame(width: left - u, alignment: .trailing)
                        .position(x: (left - u) / 2 + 3, y: snapY(Double(v), plot: plot))
                }
                ForEach(Array(ticks.enumerated()), id: \.offset) { _, t in
                    Text(t.label)
                        .font(VoxelFontLoader.font(size: 10))
                        .foregroundStyle(Color(hex: 0xA0A0A0))
                        .fixedSize()
                        .position(x: min(geo.size.width - 18, max(left + 18, plot.minX + plot.width * t.x)),
                                  y: geo.size.height - 12)
                }
            }
        }
        .frame(height: height)
        .background(VoxelBlockPanel(face: Color(hex: 0x1D1D21), outline: .black, highlight: .clear, shade: .clear, castsShadow: false))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Átlag alakulása grafikon")
        .accessibilityValue(line.last.map { String(format: "utolsó érték %.2f", $0.value) } ?? "")
    }

    private func plotRect(_ size: CGSize) -> CGRect {
        CGRect(x: left, y: top, width: max(u, size.width - left - right), height: max(u, size.height - top - bottom))
    }
    private func snapY(_ v: Double, plot: CGRect) -> CGFloat {
        let t = (v - yLo) / (yHi - yLo)
        let y = plot.maxY - CGFloat(t) * plot.height
        return (y / u).rounded() * u
    }
    private func snapX(_ x: Double, plot: CGRect) -> CGFloat {
        ((plot.minX + CGFloat(x) * plot.width) / u).rounded() * u
    }

    private func draw(_ ctx: inout GraphicsContext, plot: CGRect) {
        func cell(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat = 1, _ h: CGFloat = 1, _ c: Color) {
            ctx.fill(Path(CGRect(x: x, y: y, width: u * w, height: u * h)), with: .color(c))
        }
        // Szaggatott pixel-rácsvonalak (1 px be, 1 px ki) az 1…5 értékeknél.
        for v in 1...5 {
            let y = snapY(Double(v), plot: plot)
            var x = (plot.minX / u).rounded() * u
            var on = true
            while x < plot.maxX {
                if on { cell(x, y, 1, 1, Self.gridColor.opacity(0.35)) }
                on.toggle(); x += u
            }
        }
        // Tengelyek: tömör 1 px-es bal és alsó él.
        let axis: Color = Color(hex: 0x8B8B8B)
        let x0 = (plot.minX / u).rounded() * u - u
        let yBottom = (plot.maxY / u).rounded() * u + u
        cell(x0, plot.minY, 1, (yBottom - plot.minY) / u + 1, axis)
        cell(x0, yBottom, (plot.maxX - x0) / u + 1, 1, axis)
        // Vonal: pontok közt Bresenham, rácscellánként egy négyzet.
        let pts = line.map { CGPoint(x: snapX($0.x, plot: plot), y: snapY(min(yHi, max(yLo, $0.value)), plot: plot)) }
        for i in 0..<max(0, pts.count - 1) { bresenham(pts[i], pts[i + 1], cell: { cell($0, $1, 1, 1, Self.lineColor) }) }
        if pts.count == 1, let p = pts.first { cell(p.x, p.y, 1, 1, Self.lineColor) }
        // Pontok: fekete kerettel körbevett fehér (fantom: narancs) négyzet.
        for d in dots {
            let side: CGFloat = d.heavy ? 9 : 6
            let c = CGPoint(x: snapX(d.x, plot: plot), y: snapY(min(yHi, max(yLo, d.value)), plot: plot))
            let o = ((side / 2) / u).rounded() * u
            ctx.fill(Path(CGRect(x: c.x - o - u, y: c.y - o - u, width: side + 2 * u, height: side + 2 * u)), with: .color(.black))
            ctx.fill(Path(CGRect(x: c.x - o, y: c.y - o, width: side, height: side)),
                     with: .color(d.phantom ? Color(hex: 0xFFAA00) : .white))
        }
    }

    /// Egész rács-cellákon lépkedő vonalrajzolás (a végpontok már a rácson ülnek).
    private func bresenham(_ a: CGPoint, _ b: CGPoint, cell: (CGFloat, CGFloat) -> Void) {
        var x = Int((a.x / u).rounded()), y = Int((a.y / u).rounded())
        let x1 = Int((b.x / u).rounded()), y1 = Int((b.y / u).rounded())
        let dx = abs(x1 - x), dy = -abs(y1 - y)
        let sx = x < x1 ? 1 : -1, sy = y < y1 ? 1 : -1
        var err = dx + dy
        while true {
            cell(CGFloat(x) * u, CGFloat(y) * u)
            if x == x1 && y == y1 { break }
            let e2 = 2 * err
            if e2 >= dy { err += dy; x += sx }
            if e2 <= dx { err += dx; y += sy }
        }
    }
}


// MARK: - Neon HUD-grafikon

/// Neon-HUD vonaldiagram levágott sarkú panelben: szaggatott cián
/// rácsvonalak, a jegy színére festett 1…5 tengelyfeliratok, szögletes
/// (nem simított) sárga átlag-vonal halvány sárga területtel, a jegyek
/// rombusz-pontként a saját színükben (fantom: üres körvonal), az utolsó
/// ponton célkereszt-sarkok + érték. A rács egyetlen statikus Canvas; csak
/// megjelenéskor fut egy rövid kirajzolódás (Reduce Motion mellett az sem).
private struct NeonHudChart: View {
    struct Point { var x: Double; var value: Double }
    struct Dot { var x: Double; var value: Int; var heavy: Bool; var phantom: Bool }
    struct Tick { var x: Double; var label: String }

    var line: [Point]
    var dots: [Dot]
    var ticks: [Tick]
    var code: String
    var height: CGFloat

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Kirajzolódás (0…1) — példányonként egyszer.
    @State private var progress: CGFloat = 0

    private let yLo = 0.6
    private let yHi = 5.4
    private let left: CGFloat = 26
    private let right: CGFloat = 14
    private let top: CGFloat = 26
    private let bottom: CGFloat = 24

    var body: some View {
        GeometryReader { geo in
            let plot = plotRect(geo.size)
            let pts = line.map { CGPoint(x: px($0.x, plot), y: py($0.value, plot)) }
            ZStack(alignment: .topLeading) {
                Canvas { ctx, _ in drawGrid(&ctx, plot: plot) }
                // Terület az átlag-vonal alatt (halvány sárga → semmi).
                NeonPolyArea(points: pts, baseline: plot.maxY)
                    .fill(LinearGradient(colors: [NeonTheme.yellow.opacity(0.16), NeonTheme.yellow.opacity(0)],
                                         startPoint: .top, endPoint: .bottom))
                    .opacity(Double(progress))
                NeonPolyline(points: pts)
                    .trim(from: 0, to: progress)
                    .stroke(NeonTheme.yellow, style: StrokeStyle(lineWidth: 1.5, lineCap: .square, lineJoin: .miter))
                ForEach(Array(dots.enumerated()), id: \.offset) { _, d in
                    dotView(d).position(x: px(d.x, plot), y: py(Double(d.value), plot))
                }
                .opacity(Double(progress))
                if let last = pts.last, let lastValue = line.last?.value {
                    reticle(at: last, value: lastValue, in: plot)
                        .opacity(progress >= 1 ? 1 : 0)
                }
                // Tengelyfeliratok: 1…5 a jegy színében.
                ForEach(1...5, id: \.self) { v in
                    Text("\(v)")
                        .font(NeonTheme.mono(size: 10, relativeTo: .caption2))
                        .foregroundStyle(NeonTheme.gradeColor(for: v).opacity(0.85))
                        .frame(width: left - 8, alignment: .trailing)
                        .position(x: (left - 8) / 2 + 2, y: py(Double(v), plot))
                }
                ForEach(Array(ticks.enumerated()), id: \.offset) { _, t in
                    Text(t.label)
                        .font(NeonTheme.mono(size: 9, relativeTo: .caption2))
                        .tracking(0.6)
                        .foregroundStyle(NeonTheme.dim)
                        .fixedSize()
                        .position(x: min(geo.size.width - 20, max(left + 18, px(t.x, plot))), y: geo.size.height - 11)
                }
                NeonLabel(code, color: NeonTheme.dim, size: 9)
                    .padding(.leading, 16)
                    .padding(.top, 8)
            }
            .dynamicTypeSize(...DynamicTypeSize.xLarge)
        }
        .frame(height: height)
        .background(NeonPanelBackground(accent: NeonTheme.yellow, fill: NeonTheme.panel, cut: 12))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Átlag alakulása grafikon")
        .accessibilityValue(line.last.map { String(format: "utolsó érték %.2f", $0.value) } ?? "")
        .onAppear {
            guard progress < 1 else { return }
            if reduceMotion { progress = 1 } else { withAnimation(.easeOut(duration: 0.55)) { progress = 1 } }
        }
    }

    private func plotRect(_ size: CGSize) -> CGRect {
        CGRect(x: left, y: top, width: max(1, size.width - left - right), height: max(1, size.height - top - bottom))
    }
    private func px(_ x: Double, _ plot: CGRect) -> CGFloat { plot.minX + CGFloat(x) * plot.width }
    private func py(_ v: Double, _ plot: CGRect) -> CGFloat {
        let t = (min(yHi, max(yLo, v)) - yLo) / (yHi - yLo)
        return plot.maxY - CGFloat(t) * plot.height
    }

    private func drawGrid(_ ctx: inout GraphicsContext, plot: CGRect) {
        for v in 1...5 {
            let y = py(Double(v), plot).rounded() + 0.5
            var p = Path(); p.move(to: CGPoint(x: plot.minX, y: y)); p.addLine(to: CGPoint(x: plot.maxX, y: y))
            ctx.stroke(p, with: .color(NeonTheme.cyan.opacity(v == 3 ? 0.22 : 0.12)), style: StrokeStyle(lineWidth: 1, dash: [2, 4]))
        }
        // Bal tengely: vékony vörös vonal, alul rövid fényes szakasszal.
        let x0 = plot.minX.rounded() - 3.5
        var axis = Path(); axis.move(to: CGPoint(x: x0, y: plot.minY - 4)); axis.addLine(to: CGPoint(x: x0, y: plot.maxY + 4))
        ctx.stroke(axis, with: .color(NeonTheme.red.opacity(0.35)), lineWidth: 1)
        ctx.fill(Path(CGRect(x: x0 - 0.5, y: plot.maxY - 10, width: 2, height: 14)), with: .color(NeonTheme.red))
    }

    /// Rombusz-pont a jegy színében; nehéz (≥200%) nagyobb, fantom üres.
    @ViewBuilder
    private func dotView(_ d: Dot) -> some View {
        let side: CGFloat = d.heavy ? 10 : 7
        let color = NeonTheme.gradeColor(for: d.value)
        NeonDiamond()
            .fill(d.phantom ? NeonTheme.panel : color)
            .overlay(NeonDiamond().stroke(d.phantom ? color : NeonTheme.bg, lineWidth: d.phantom ? 1 : 1.5))
            .frame(width: side, height: side)
    }

    /// Célkereszt-sarkok az utolsó ponton + az érték (mono, sárga).
    private func reticle(at p: CGPoint, value: Double, in plot: CGRect) -> some View {
        let r: CGFloat = 8
        let labelLeft = p.x > plot.midX
        return ZStack {
            NeonReticle(arm: 3.5)
                .stroke(NeonTheme.yellow, lineWidth: 1)
                .frame(width: r * 2, height: r * 2)
                .position(p)
            Text(String(format: "%.2f", value))
                .font(NeonTheme.mono(size: 10, relativeTo: .caption2))
                .foregroundStyle(NeonTheme.bg)
                .padding(.horizontal, 4)
                .padding(.vertical, 1)
                .background(NeonTheme.yellow)
                .fixedSize()
                .position(x: labelLeft ? p.x - r - 22 : p.x + r + 22,
                          y: p.y < plot.minY + 12 ? p.y + 12 : p.y - 12)
        }
    }
}

/// Szögletes (töréspontos) vonal a megadott pontokon — trim-elhető.
private struct NeonPolyline: Shape {
    var points: [CGPoint]
    func path(in rect: CGRect) -> Path {
        var p = Path()
        guard let first = points.first else { return p }
        p.move(to: first)
        for pt in points.dropFirst() { p.addLine(to: pt) }
        return p
    }
}

/// A vonal alatti terület az alapvonalig.
private struct NeonPolyArea: Shape {
    var points: [CGPoint]
    var baseline: CGFloat
    func path(in rect: CGRect) -> Path {
        var p = Path()
        guard let first = points.first, let last = points.last else { return p }
        p.move(to: CGPoint(x: first.x, y: baseline))
        for pt in points { p.addLine(to: pt) }
        p.addLine(to: CGPoint(x: last.x, y: baseline))
        p.closeSubpath()
        return p
    }
}

private struct NeonDiamond: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: rect.midX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
        p.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.minX, y: rect.midY))
        p.closeSubpath()
        return p
    }
}

/// Négy sarok-szögletből álló célkereszt (a játék lock-on jele).
private struct NeonReticle: Shape {
    var arm: CGFloat
    func path(in rect: CGRect) -> Path {
        var p = Path()
        let r = rect
        p.move(to: CGPoint(x: r.minX, y: r.minY + arm)); p.addLine(to: CGPoint(x: r.minX, y: r.minY)); p.addLine(to: CGPoint(x: r.minX + arm, y: r.minY))
        p.move(to: CGPoint(x: r.maxX - arm, y: r.minY)); p.addLine(to: CGPoint(x: r.maxX, y: r.minY)); p.addLine(to: CGPoint(x: r.maxX, y: r.minY + arm))
        p.move(to: CGPoint(x: r.maxX, y: r.maxY - arm)); p.addLine(to: CGPoint(x: r.maxX, y: r.maxY)); p.addLine(to: CGPoint(x: r.maxX - arm, y: r.maxY))
        p.move(to: CGPoint(x: r.minX + arm, y: r.maxY)); p.addLine(to: CGPoint(x: r.minX, y: r.maxY)); p.addLine(to: CGPoint(x: r.minX, y: r.maxY - arm))
        return p
    }
}
