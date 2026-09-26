import SwiftUI

// MARK: - Jegyek az órán — a telefonos lista tükre
// Összátlag-fejléc + tantárgy-sorok (GradeCircle + név + átlag • darab),
// koppintásra a tárgy jegyei új lapon. Koronával görgethető natív listák.
// Átlag- és kerekítés-számítás a telefonnal azonos (GradingLogic, az
// iPhone-ról jött küszöbökkel) — fantom-jegy és grafikon nincs az órán.
struct GradesWatchView: View {
    @EnvironmentObject var store: WatchSyncStore

    private var colors: AppColors { .darkRevamped }
    private var snapshot: WatchGradesSnapshot? { store.grades }

    /// WatchGrade → GradeItem (a GradingLogic ezen dolgozik).
    private func items(_ grades: [WatchGrade]) -> [GradeItem] {
        grades.map {
            GradeItem(
                id: $0.id, subject: $0.subject, value: $0.value,
                valueText: $0.valueText, date: $0.date, teacher: $0.teacher,
                type: $0.type, weight: $0.weight, topic: $0.topic
            )
        }
    }

    private var grouped: [String: [GradeItem]] {
        guard let snap = snapshot else { return [:] }
        return Dictionary(grouping: items(WatchGradeFilter.evkozi(snap.grades)), by: { $0.subject })
    }

    /// Csak azok a tárgyak, amikből van is évközi jegy —
    /// az üres tárgyak nem jelennek meg az órán.
    private var displaySubjects: [String] {
        grouped.keys.sorted()
    }

    private var overall: Double { GradingLogic.overallAverage(grouped: grouped) }

    var body: some View {
        NavigationStack {
            Group {
                if snapshot == nil || displaySubjects.isEmpty {
                    ContentUnavailableView(
                        "Nincs jegy",
                        systemImage: "list.number",
                        description: Text("Nyisd meg a Jegyeket iPhone-on.")
                    )
                } else {
                    List {
                        if let err = store.lastSyncError {
                            Section {
                                Text(err)
                                    .font(.caption2)
                                    .foregroundStyle(.orange)
                            }
                        }
                        Section {
                            HStack(alignment: .lastTextBaseline) {
                                VStack(alignment: .leading, spacing: 1) {
                                    Text("ÖSSZÁTLAG")
                                        .font(.caption2.weight(.semibold))
                                        .foregroundStyle(.secondary)
                                    Text(grouped.isEmpty ? "—" : String(format: "%.2f", overall))
                                        .font(.system(size: 30, weight: .bold, design: .rounded))
                                }
                                Spacer()
                                Text("\(WatchGradeFilter.evkozi(snapshot?.grades ?? []).count) jegy")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Section {
                            ForEach(displaySubjects, id: \.self) { subject in
                                NavigationLink(value: subject) {
                                    HStack(spacing: 10) {
                                        if let list = grouped[subject] {
                                            let raw = GradingLogic.weightedAverage(list)
                                            let rnd = GradingLogic.roundedGrade(
                                                raw: raw,
                                                threshold: snapshot?.thresholds[subject] ?? GradingLogic.defaultThreshold
                                            )
                                            WatchGradeCircle(value: rnd, size: 36, colors: colors)
                                            VStack(alignment: .leading, spacing: 2) {
                                                Text(subject)
                                                    .font(.subheadline.weight(.semibold))
                                                    .lineLimit(1)
                                                Text(String(format: "%.2f • %d jegy", raw, list.count))
                                                    .font(.caption2)
                                                    .foregroundStyle(.secondary)
                                                    .lineLimit(1)
                                            }
                                        }
                                    }
                                    .padding(.vertical, 2)
                                }
                            }
                        }
                    }
                    .listStyle(.plain)
                    .refreshable { await store.requestSyncNow() }
                }
            }
            .navigationTitle("Jegyek")
            .navigationDestination(for: String.self) { subject in
                WatchSubjectDetailView(
                    subject: subject,
                    grades: (grouped[subject] ?? []).sorted { $0.date > $1.date },
                    threshold: snapshot?.thresholds[subject] ?? GradingLogic.defaultThreshold,
                    colors: colors
                )
            }
        }
    }
}

// MARK: - Tárgy-részletező — SubjectDetailView sorainak tükre
private struct WatchSubjectDetailView: View {
    let subject: String
    let grades: [GradeItem]
    let threshold: Double
    let colors: AppColors

    private var avg: Double { GradingLogic.weightedAverage(grades) }

    var body: some View {
        List {
            Section {
                HStack(alignment: .lastTextBaseline) {
                    Text("ÁTLAG")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(grades.isEmpty ? "—" : String(format: "%.2f", avg))
                        .font(.system(size: 26, weight: .bold, design: .rounded))
                }
            }
            Section("Jegyek") {
                ForEach(grades) { g in
                    VStack(alignment: .leading, spacing: 5) {
                        HStack(spacing: 9) {
                            Text("\(g.value)")
                                .font(.caption.weight(.bold).monospacedDigit())
                                .foregroundStyle(colors.gradeColor(for: g.value))
                                .frame(width: 28, height: 28)
                                .background {
                                    Circle().fill(Color.clear).glassEffect(.clear, in: .circle)
                                }
                                .overlay(Circle().strokeBorder(colors.border.opacity(0.9), lineWidth: 1))
                            VStack(alignment: .leading, spacing: 1) {
                                Text(g.date.formatted(date: .abbreviated, time: .omitted) + " • \(g.weight)%")
                                    .font(.caption.weight(.medium))
                                if g.plainTopic.isEmpty {
                                    Text(g.type)
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                        if !g.plainTopic.isEmpty {
                            Text(g.plainTopic)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    .padding(.vertical, 3)
                }
            }
        }
        .listStyle(.plain)
        .navigationTitle(subject)
    }
}

// MARK: - Jegy-kör — GradeCircle (telefon) tükre
private struct WatchGradeCircle: View {
    let value: Int
    var size: CGFloat = 36
    let colors: AppColors

    var body: some View {
        Text("\(value)")
            .font(.system(size: size > 32 ? 15 : 13, weight: .bold, design: .rounded))
            .foregroundStyle(colors.gradeColor(for: value))
            .monospacedDigit()
            .frame(width: size, height: size)
            .background {
                Circle()
                    .fill(Color.clear)
                    .glassEffect(.clear, in: .circle)
            }
            .overlay(Circle().strokeBorder(colors.border.opacity(0.9), lineWidth: 1))
    }
}
