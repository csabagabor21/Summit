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
                    AxisMarks(values: .stride(by: .month, count: 1)) { v in
                        AxisGridLine().foregroundStyle(Color.primary.opacity(0.04))
                        AxisTick().foregroundStyle(Color.primary.opacity(0.04))
                        if let _ = v.as(Date.self) {
                            AxisValueLabel(format: .dateTime.month(.abbreviated)).font(.caption2).foregroundStyle(.secondary)
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

    // MARK: Shared helpers — 0-s jegy kizárva mindenhonnan
    private var validGrades: [GradeItem] { grades.filter { $0.value != 0 } }
    private var displayGrades: [GradeItem] {
        let src = validGrades
        guard monthly else { return src }
        let grouped = Dictionary(grouping: src) { g -> String in
            let c = Calendar.current.dateComponents([.year, .month], from: g.date)
            return String(format: "%04d-%02d", c.year ?? 0, c.month ?? 0)
        }
        var monthlyItems: [GradeItem] = []
        for (_, items) in grouped {
            let sorted = items.sorted { $0.date < $1.date }
            let midDate = sorted[sorted.count/2].date
            let avg = GradingLogic.weightedAverage(sorted)
            let value = Int(round(avg))
            let synth = GradeItem(id: "monthly-\(midDate.timeIntervalSince1970)", subject: sorted.first?.subject ?? "", value: value, valueText: "\(value)", date: midDate, teacher: "", type: "havi", weight: 100, topic: "")
            monthlyItems.append(synth)
        }
        let sorted = monthlyItems.sorted { $0.date < $1.date }
        return sorted.count >= 2 ? sorted : src
    }
    private var displayPoints: [(date: Date, avg: Double)] {
        let base = displayGrades
        if monthly { return base.map { ($0.date, Double($0.value)) } }
        var pts: [(Date,Double)] = []
        for idx in 0..<base.count { pts.append((base[idx].date, GradingLogic.weightedAverage(Array(base.prefix(idx+1))))) }
        return pts
    }
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
        let fmt: DateFormatter = { let f=DateFormatter(); f.locale=Locale(identifier:"hu_HU"); f.dateFormat=plotSpanDays>90 ? "MMM" : "MM.dd"; return f }()
        return dates.map { d in let nx=d.timeIntervalSince(minD)/span; let x=plot.minX+CGFloat(nx)*plot.width; return XTick(x: x, label: fmt.string(from: d).capitalized) }
    }
}
