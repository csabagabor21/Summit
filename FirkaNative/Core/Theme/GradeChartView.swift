import SwiftUI
import Charts

struct GradeChartView: View {
    let grades: [GradeItem] // sorted by date ascending
    var accent: Color
    var showTarget: Int? = nil
    var height: CGFloat = 180
    var monthly: Bool = false
    var editorial: Bool = false

    var body: some View {
        if displayGrades.count < 2 {
            ContentUnavailableView("Nincs elég adat", systemImage: editorial ? "chart.line.flattrend.xyaxis" : "chart.line.downtrend.xyaxis", description: Text("Adj hozzá jegyet"))
                .frame(height: height)
        } else {
            Chart {
                if !editorial {
                    ForEach(Array(displayPoints.enumerated()), id: \.offset) { _, p in
                        AreaMark(x: .value("Dátum", p.date), y: .value("Átlag", p.avg))
                            .foregroundStyle(LinearGradient(colors: [accent.opacity(0.18), accent.opacity(0.01)], startPoint: .top, endPoint: .bottom))
                            .interpolationMethod(.catmullRom)
                    }
                }
                ForEach(Array(displayPoints.enumerated()), id: \.offset) { _, p in
                    LineMark(x: .value("Dátum", p.date), y: .value("Átlag", p.avg))
                        .foregroundStyle(editorial ? Color.primary.opacity(0.85) : accent)
                        .lineStyle(StrokeStyle(lineWidth: editorial ? 1.6 : 2.4, lineCap: .round, lineJoin: .round))
                        .interpolationMethod(.catmullRom)
                }
                if !editorial || displayGrades.count <= 12 {
                    ForEach(displayGrades, id: \.id) { g in
                        PointMark(x: .value("Dátum", g.date), y: .value("Jegy", Double(g.value)))
                            .foregroundStyle(g.id.hasPrefix("phantom") ? Color.orange : (editorial ? Color.primary.opacity(0.55) : colorForValue(g.value).opacity(0.9)))
                            .symbolSize(editorial ? 14 : 26)
                    }
                }
                if let t = showTarget, !editorial {
                    RuleMark(y: .value("Cél", Double(t)))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [5,5]))
                        .foregroundStyle(.secondary.opacity(0.35))
                }
            }
            .frame(height: height)
            .chartYScale(domain: 1...5)
            .chartXScale(domain: xDomain)
            .chartXAxis {
                AxisMarks(values: .stride(by: .month, count: 1)) { v in
                    AxisGridLine().foregroundStyle(Color.primary.opacity(editorial ? 0.04 : 0.06))
                    AxisTick().foregroundStyle(Color.primary.opacity(editorial ? 0.04 : 0.08))
                    if let d = v.as(Date.self) {
                        AxisValueLabel(format: .dateTime.month(.abbreviated)).font(.caption2).foregroundStyle(.secondary)
                    }
                }
            }
            .chartYAxis {
                AxisMarks(position: .leading, values: [1,2,3,4,5]) { v in
                    AxisGridLine().foregroundStyle(Color.primary.opacity(editorial ? 0.04 : 0.06))
                    AxisTick().foregroundStyle(Color.primary.opacity(editorial ? 0.04 : 0.08))
                    AxisValueLabel().font(.caption2).foregroundStyle(.secondary)
                }
            }
            .chartPlotStyle { plot in
                if editorial {
                    plot.background(Color.clear).padding(.vertical, 4)
                } else {
                    plot
                        .background(RoundedRectangle(cornerRadius: 16).fill(Color.primary.opacity(0.03)))
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Color.primary.opacity(0.06), lineWidth: 1))
                }
            }
            .padding(.vertical, editorial ? 2 : 6)
            .animation(.spring(response: 0.6, dampingFraction: 0.85), value: displayGrades)
            .transition(.opacity.combined(with: .scale(scale: 0.98)))
        }
    }

    // monthly: egy pont per hónap (összátlagnál)
    private var displayGrades: [GradeItem] {
        guard monthly else { return grades }
        // csoportosítás hónapra, havonta 1 pont (hónap közepe, havi átlag)
        let grouped = Dictionary(grouping: grades) { g -> String in
            let c = Calendar.current.dateComponents([.year, .month], from: g.date)
            return String(format: "%04d-%02d", c.year ?? 0, c.month ?? 0)
        }
        var monthlyItems: [GradeItem] = []
        for (_, items) in grouped {
            let sorted = items.sorted { $0.date < $1.date }
            let midDate = sorted[sorted.count/2].date
            let avg = GradingLogic.weightedAverage(sorted)
            // kerekítés nélkül, de súlyozott havi átlagból kreálunk szintetikus GradeItem-et a vonalhoz
            let value = Int(round(avg))
            let synth = GradeItem(id: "monthly-\(midDate.timeIntervalSince1970)", subject: sorted.first?.subject ?? "", value: value, valueText: "\(value)", date: midDate, teacher: "", type: "havi", weight: 100, topic: "")
            // a Chart pontjaihoz az eredeti jegyek helyett a havi átlag vonalát használjuk, de pontokat nem mutatunk havinál editorialban
            // itt a vonalhoz a havi átlagokat használjuk
            monthlyItems.append(synth)
        }
        // ha havi de kevés hónap (<2), fallback eredeti
        let sorted = monthlyItems.sorted { $0.date < $1.date }
        return sorted.count >= 2 ? sorted : grades
    }

    private var displayPoints: [(date: Date, avg: Double)] {
        let base = displayGrades
        if monthly {
            // havonta már átlagolt, nincs running
            return base.map { (date: $0.date, avg: Double($0.value)) }
        }
        var pts: [(Date, Double)] = []
        for idx in 0..<base.count {
            let slice = Array(base.prefix(idx+1))
            let avg = GradingLogic.weightedAverage(slice)
            pts.append((base[idx].date, avg))
        }
        return pts
    }

    private var xDomain: ClosedRange<Date> {
        let src = displayGrades
        guard let min = src.map(\.date).min(), let max = src.map(\.date).max() else {
            let now = Date(); return now.addingTimeInterval(-30*86400)...now
        }
        if min == max { return min.addingTimeInterval(-86400)...max.addingTimeInterval(86400) }
        let pad = max.timeIntervalSince(min) * 0.06
        return min.addingTimeInterval(-pad)...max.addingTimeInterval(pad)
    }

    private func colorForValue(_ v: Int) -> Color {
        switch v {
        case 5: return Color(hex: 0x22CCAD)
        case 4: return Color(hex: 0x92EA3B)
        case 3: return Color(hex: 0xFFD23C)
        case 2: return Color(hex: 0xFF7A45)
        case 1: return Color(hex: 0xFF4D6E)
        default: return .secondary
        }
    }
}
