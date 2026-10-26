import SwiftUI

/// Bejelentkezés utáni teljes képernyős választó: konkrétan megmondja,
/// mit gyűjt az app, és ott helyben ki/be kapcsolható.
///
/// GDPR-okból default: KI (előre bepipált doboz nem érvényes hozzájárulás —
/// Planet49, C-673/17). A "Folytatás" mindkét irányban ugyanannyi koppintás.
struct AnalyticsConsentView: View {
    @EnvironmentObject var analytics: AnalyticsStore
    @EnvironmentObject var theme: ThemeStore
    @Environment(\.colorScheme) var scheme

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    VStack(alignment: .leading, spacing: 8) {
                        if theme.isNeon {
                            NeonLabel("Adatvédelem // hozzájárulás", color: NeonTheme.cyan, size: 10)
                        }
                        Text("Használati statisztika")
                            .voxelDisplay(32)
                            .tracking(-0.5)
                        Text("Segít látnunk, hányan és melyik iskolákban használják a Summitot — hogy tudjuk, mire érdemes fejleszteni.")
                            .skinFont(.body)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.top, 12)

                    collectsCard
                    notCollectsCard
                    whyCard

                    Text("Bármikor kikapcsolhatod a Beállítások tetején, egy koppintással. A részletek az adatkezelési tájékoztatóban.")
                        .skinFont(.footnote)
                        .foregroundStyle(.secondary)

                    Link("Adatkezelési tájékoztató", destination: URL(string: "https://gaborcsaba.com/summit/adatkezeles.html")!)
                        .skinFont(.footnote, weight: .semibold)
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 24)
            }
            .background {
                if theme.isNeon { NeonBackdrop() } else if theme.isVoxel { VoxelMenuBackground() }
            }
            .summitSheetBackground()
            .navigationBarTitleDisplayMode(.inline)
            .summitToolbarBackground()
            .safeAreaInset(edge: .bottom) {
                VStack(spacing: 10) {
                    Button { analytics.choose(enabled: true) } label: {
                        Text("Bekapcsolom")
                            .skinFont(.headline, weight: .semibold)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, theme.isNeon ? 2 : 15)
                    }
                    .skinBorderedButton(prominent: true)
                    .tint(.blue)
                    Button { analytics.choose(enabled: false) } label: {
                        Text("Kikapcsolva folytatom")
                            .skinFont(.headline, weight: .semibold)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, theme.isNeon ? 2 : 15)
                    }
                    .skinBorderedButton()
                    .tint(.primary)
                }
                .padding(.horizontal, 20)
                .padding(.top, 10)
                .padding(.bottom, 16)
                .background { consentBarBackground }
            }
        }
        .summitSheetBackground()
        // Voxel / Neon: a háttér sötét, ezért a képernyő sötét
        // sémában fut (világos szöveg); Summitban a kapott séma marad.
        .environment(\.colorScheme, (theme.isVoxel || theme.isNeon) ? .dark : scheme)
        .interactiveDismissDisabled(true)
    }

    /// Alsó gombsáv háttere: Summitban a rendszer-háttér, Voxelben a
    /// játék menü-lábléce (föld-csempe + lábléc-elválasztó), Neonban
    /// majdnem fekete sáv vékony sárga HUD-vonallal a tetején.
    @ViewBuilder
    private var consentBarBackground: some View {
        if theme.isNeon {
            NeonTheme.bgDeep
                .ignoresSafeArea(edges: .bottom)
                .overlay(alignment: .top) { NeonDivider(color: NeonTheme.yellow) }
        } else if theme.isVoxel {
            VoxelMenuBackground().overlay(alignment: .top) { VoxelSeparator(footer: true) }
        } else {
            Color(.systemBackground)
        }
    }

    private var collectsCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            cardHeader("EZT GYŰJTI, HA BEKAPCSOLOD", code: "DATA.TX", accent: NeonTheme.cyan)
            row("chart.bar.fill", "Iskolád neve", "A KRÉTA-beli intézmény neve — számlálásra elég, beazonosításra nem.", cpTint: NeonTheme.cyan)
            row("iphone", "Véletlen telepítés-azonosító", "A telefonon generált UUID — nem eszköz-ID, törléssel megújul.", cpTint: NeonTheme.cyan)
            row("app.badge.fill", "App-verzió és rendszer", "Pl. 1.0 (10), iOS 26 — hogy lássuk,min kell javítani.", cpTint: NeonTheme.cyan)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .consentCard(fill: Color.primary.opacity(0.04), cpAccent: NeonTheme.cyan)
    }

    private var notCollectsCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            cardHeader("EZT SOSEM GYŰJTI", code: "BLOCKED", accent: NeonTheme.green)
            row("person.slash.fill", "Neved, jegyeid, órarended", "A KRÉTA-adataid a telefonodon maradnak.", cpTint: NeonTheme.green)
            row("key.slash.fill", "Jelszavad, tokened", "Belépési adatot sosem töltünk fel sehova.", cpTint: NeonTheme.green)
            row("location.slash.fill", "Helyzeted, eszköz-ID-d", "Nincs GPS, nincs fingerprint, nincs IP-naplózás.", cpTint: NeonTheme.green)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .consentCard(fill: Color.green.opacity(0.08), cpAccent: NeonTheme.green)
    }

    private var whyCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            cardHeader("MIRE HASZNÁLJUK AZ ADATOKAT?", code: "PURPOSE", accent: NeonTheme.yellow)
            HStack(alignment: .top, spacing: 12) {
                SkinIcon("mountain.2.fill")
                    .skinFont(.body, weight: .semibold)
                    .foregroundStyle(theme.isNeon ? NeonTheme.yellow : .blue)
                    .frame(width: 24)
                Text("Kíváncsiak vagyunk, mennyien vagytok a hegy tetején.")
                    .skinFont(.subheadline, weight: .semibold)
            }
            Text("A számokból lesz a térkép a weboldalon: melyik iskolákban hányan summitolnak. Döntéstámogatásra kell — melyik suliba érdemes kimenni, mit érdemes fejleszteni. Reklámra, profilozásra sosem.")
                .skinFont(.footnote)
                .foregroundStyle(.secondary)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .consentCard(fill: Color.blue.opacity(0.08), cpAccent: NeonTheme.yellow)
    }

    /// Kártya-fejléc: Summitban/Voxelben a szürke nagybetűs felirat,
    /// Neonban akcentszínű cím + jobbra igazított egyenközű kód.
    @ViewBuilder
    private func cardHeader(_ title: String, code: String, accent: Color) -> some View {
        if theme.isNeon {
            HStack(spacing: 8) {
                Text(title)
                    .skinFont(.caption, weight: .bold)
                    .tracking(1.2)
                    .foregroundStyle(accent)
                Spacer(minLength: 6)
                NeonLabel(code, color: NeonTheme.dim, bracketed: false, size: 9)
                    .accessibilityHidden(true)
            }
        } else {
            Text(title)
                .skinFont(.caption, weight: .bold)
                .foregroundStyle(.secondary)
        }
    }

    private func row(_ icon: String, _ title: String, _ sub: String, cpTint: Color = NeonTheme.cyan) -> some View {
        HStack(alignment: .top, spacing: 12) {
            SkinIcon(icon)
                .skinFont(.body, weight: .semibold)
                .foregroundStyle(theme.isNeon ? cpTint : .blue)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).skinFont(.subheadline, weight: .semibold)
                Text(sub).skinFont(.footnote).foregroundStyle(.secondary)
            }
        }
    }
}

private extension View {
    /// Hozzájárulás-kártya felülete: Neonban kártyánként más akcentű
    /// (cián = gyűjtött, zöld = soha, sárga = cél) HUD-panel; egyébként a
    /// meglévő `skinCard`.
    @ViewBuilder
    func consentCard(fill: Color, cpAccent: Color) -> some View {
        if NeonTheme.isActive {
            self.background { NeonPanelBackground(accent: cpAccent) }
        } else {
            self.skinCard(fill: fill)
        }
    }
}
