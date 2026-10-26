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
                        Text(subject).skinFont(.headline)
                        Spacer()
                        Text(String(format: "%.2f", threshold)).font(RoundingSkinFont.readout).monospacedDigit().foregroundStyle(colors.accent)
                    }
                    SkinSlider(value: $threshold, range: 0.50...0.90, step: 0.01)
                        .tint(colors.accent)
                        .onChange(of: threshold) { _, v in GradingLogic.setThreshold(v, for: subject) }
                    HStack(spacing: 12) {
                        Text("3.62 → \(GradingLogic.roundedGrade(raw: 3.62, threshold: threshold))-as").font(RoundingSkinFont.example).foregroundStyle(.secondary)
                        Text("•").foregroundStyle(.tertiary)
                        Text("3.79 → \(GradingLogic.roundedGrade(raw: 3.79, threshold: threshold))-as").font(RoundingSkinFont.example).foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 4)
            } header: { Text("Kerekítés").voxelSectionHeader() } footer: { Text("0.50 = 3.50-től 4-es, 0.80 = csak 3.80-tól 4-es. Súlyozott átlagra alkalmazva.").skinFont(.caption2).foregroundStyle(.secondary) }
            .voxelListRowComfy(fill: colors.surface)

            Section(header: Text("Felmentés").voxelSectionHeader(),
                    footer: Text("Ha fel vagy mentve, az órarendben zöld háttérrel és „Felmentett” felirattal jelenik meg — mintha elmaradna.").skinFont(.caption2).foregroundStyle(.secondary)) {
                Toggle(isOn: $isExempted) {
                    SkinLabel(isExempted ? "Felmentve" : "Felmentett", systemImage: isExempted ? "checkmark.shield.fill" : "shield")
                        .skinFont(.subheadline, weight: .medium)
                }
                .tint(Color.green)
                .skinToggleStyle()
                .onChange(of: isExempted) { _, v in ExemptedStore.setExempted(subject, v) }
            }
            .voxelListRowComfy(fill: colors.surface)

            Section {
                Button("Visszaállítás alapra (0.50)") {
                    threshold = GradingLogic.defaultThreshold
                    GradingLogic.setThreshold(threshold, for: subject)
                }
                .voxelInlineButton()
            }
            .voxelListRowComfy(fill: colors.surface)
        }
        .listStyle(.insetGrouped)
        .summitListChrome(colors: colors)
        .navigationTitle(subject)
        .navigationBarTitleDisplayMode(.inline)
        .summitToolbarBackground()
        .onAppear {
            threshold = GradingLogic.threshold(for: subject)
            isExempted = ExemptedStore.isExempted(subject)
        }
    }
}

/// Betűk a kerekítés-nézethez. Summitban és Voxelben pontosan azt adja,
/// amit eddig a `skinFont` (title3 bold / caption semibold); Neonban a
/// küszöb nagy Rajdhani HUD-kijelző, a példasor egyenközű kód.
private enum RoundingSkinFont {
    static var readout: Font {
        VoxelTheme.isActive ? VoxelTheme.font(.title3)
            : NeonTheme.isActive ? NeonTheme.display(size: 30, weight: .bold, relativeTo: .title3)
            : Font.system(.title3, weight: .bold)
    }
    static var example: Font {
        VoxelTheme.isActive ? VoxelTheme.font(.caption)
            : NeonTheme.isActive ? NeonTheme.mono(size: 11, relativeTo: .caption)
            : Font.system(.caption, weight: .semibold)
    }
}
