import SwiftUI
import Charts

struct GradeChartView: View {
    let grades: [GradeItem] // sorted by date ascending
    var accent: Color
    var showTarget: Int? = nil
    var height: CGFloat = 180

    var body: some View {
        if grades.count < 2 {
            ContentUnavailableView("Nincs elég adat", systemImage: "chart.line.downtrend.xyaxis", description: Text("Adj hozzá jegyet"))
                .frame(height: height)
        } else {
            Chart {
                // area
                ForEach(Array(runningPoints.enumerated()), id: \.offset) { _, p in
                    AreaMark(x: .value("Dátum", p.date), y: .value("Átlag", p.avg))
                        .foregroundStyle(LinearGradient(colors: [accent.opacity(0.26), accent.opacity(0.02)], startPoint: .top, endPoint: .bottom))
                        .interpolationMethod(.catmullRom)
                }
                // line
                ForEach(Array(runningPoints.enumerated()), id: \.offset) { _, p in
                    LineMark(x: .value("Dátum", p.date), y: .value("Átlag", p.avg))
                        .foregroundStyle(accent)
                        .lineStyle(StrokeStyle(lineWidth: 2.8, lineCap: .round, lineJoin: .round))
                        .interpolationMethod(.catmullRom)
                }
                // points
                ForEach(grades, id: \.id) { g in
                    PointMark(x: .value("Dátum", g.date), y: .value("Jegy", Double(g.value)))
                        .foregroundStyle(g.id.hasPrefix("phantom") ? Color.orange : colorForValue(g.value).opacity(0.95))
                        .symbolSize(30)
                        .annotation(position: .overlay, alignment: .center) {
                            // subtle dot glow
                            Circle().fill(g.id.hasPrefix("phantom") ? Color.orange.opacity(0.18) : accent.opacity(0.12)).frame(width: 18, height: 18)
                        }
                }
                if let t = showTarget {
                    RuleMark(y: .value("Cél", Double(t)))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [5,5]))
                        .foregroundStyle(.secondary.opacity(0.45))
                }
            }
            .frame(height: height)
            .chartYScale(domain: 1...5)
            .chartXScale(domain: xDomain)
            .chartXAxis {
                AxisMarks(values: .stride(by: .month, count: 1)) { v in
                    AxisGridLine().foregroundStyle(Color.primary.opacity(0.06))
                    if let d = v.as(Date.self) {
                        AxisValueLabel(format: .dateTime.month(.abbreviated).year(.twoDigits)).font(.caption2)
                    }
                }
            }
            .chartYAxis {
                AxisMarks(position: .leading, values: [1,2,3,4,5]) { v in
                    AxisGridLine().foregroundStyle(Color.primary.opacity(0.06))
                    AxisTick().foregroundStyle(Color.primary.opacity(0.08))
                    AxisValueLabel().font(.caption2)
                }
            }
            .chartPlotStyle { plot in
                plot
                    .background(
                        RoundedRectangle(cornerRadius: 16).fill(Color.primary.opacity(0.03))
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                    .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Color.primary.opacity(0.06), lineWidth: 1))
            }
            .padding(.vertical, 6)
            .animation(.spring(response: 0.45, dampingFraction: 0.82), value: grades.map(\.id))
            .transition(.opacity.combined(with: .scale(scale: 0.98)))
        }
    }

    private var runningPoints: [(date: Date, avg: Double)] {
        var pts: [(Date, Double)] = []
        for idx in 0..<grades.count {
            let slice = Array(grades.prefix(idx+1))
            let avg = GradingLogic.weightedAverage(slice)
            pts.append((grades[idx].date, avg))
        }
        return pts
    }

    private var xDomain: ClosedRange<Date> {
        guard let min = grades.map(\.date).min(), let max = grades.map(\.date).max() else {
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
