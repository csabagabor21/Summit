import SwiftUI

struct RoundingDetailView: View {
    let subject: String
    @State private var threshold: Double = GradingLogic.defaultThreshold
    @State private var isExempted: Bool = false
    @EnvironmentObject var theme: ThemeStore
    @Environment(\.colorScheme) var scheme
    var colors: AppColors { theme.colors(for: scheme) }

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text(subject).font(.headline)
                        Spacer()
                        Text(String(format: "%.2f", threshold)).font(.title3.weight(.bold).monospacedDigit()).foregroundStyle(colors.accent)
                    }
                    Slider(value: $threshold, in: 0.50...0.90, step: 0.01)
                        .tint(colors.accent)
                        .onChange(of: threshold) { _, v in GradingLogic.setThreshold(v, for: subject) }
                    HStack(spacing: 12) {
                        Text("3.62 → \(GradingLogic.roundedGrade(raw: 3.62, threshold: threshold))-as").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                        Text("•").foregroundStyle(.tertiary)
                        Text("3.79 → \(GradingLogic.roundedGrade(raw: 3.79, threshold: threshold))-as").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 4)
            } header: { Text("Kerekítés").font(.caption.weight(.semibold)).foregroundStyle(.secondary).textCase(.uppercase) } footer: { Text("0.50 = 3.50-től 4-es, 0.80 = csak 3.80-tól 4-es. Súlyozott átlagra alkalmazva.").font(.caption2).foregroundStyle(.secondary) }

            Section(header: Text("Felmentés").font(.caption.weight(.semibold)).foregroundStyle(.secondary).textCase(.uppercase),
                    footer: Text("Ha fel vagy mentve, az órarendben zöld háttérrel és „Felmentett” felirattal jelenik meg — mintha elmaradna.").font(.caption2).foregroundStyle(.secondary)) {
                Toggle(isOn: $isExempted) {
                    Label(isExempted ? "Felmentve" : "Felmentett", systemImage: isExempted ? "checkmark.shield.fill" : "shield")
                        .font(.subheadline.weight(.medium))
                }
                .tint(Color.green)
                .onChange(of: isExempted) { _, v in ExemptedStore.setExempted(subject, v) }
            }

            Section {
                Button("Visszaállítás alapra (0.50)") {
                    threshold = GradingLogic.defaultThreshold
                    GradingLogic.setThreshold(threshold, for: subject)
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(colors.background)
        .navigationTitle(subject)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.visible, for: .navigationBar)
        .onAppear {
            threshold = GradingLogic.threshold(for: subject)
            isExempted = ExemptedStore.isExempted(subject)
        }
    }
}
