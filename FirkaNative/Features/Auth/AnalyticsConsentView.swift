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
                        Text("Használati statisztika")
                            .mcDisplay(32)
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
            .background { if theme.isMinecraft { McMenuBackground() } }
            .summitSheetBackground()
            .navigationBarTitleDisplayMode(.inline)
            .summitToolbarBackground()
            .safeAreaInset(edge: .bottom) {
                VStack(spacing: 10) {
                    Button { analytics.choose(enabled: true) } label: {
                        Text("Bekapcsolom")
                            .skinFont(.headline, weight: .semibold)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 15)
                    }
                    .skinBorderedButton(prominent: true)
                    .tint(.blue)
                    Button { analytics.choose(enabled: false) } label: {
                        Text("Kikapcsolva folytatom")
                            .skinFont(.headline, weight: .semibold)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 15)
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
        // Minecraft: a menü-háttér sötét, ezért a képernyő sötét sémában fut
        // (fehér szöveg); Summitban a kapott séma marad.
        .environment(\.colorScheme, theme.isMinecraft ? .dark : scheme)
        .interactiveDismissDisabled(true)
    }

    /// Alsó gombsáv háttere: Summitban a rendszer-háttér, Minecraftban a
    /// játék menü-lábléce (föld-csempe + lábléc-elválasztó).
    @ViewBuilder
    private var consentBarBackground: some View {
        if theme.isMinecraft {
            McMenuBackground().overlay(alignment: .top) { McSeparator(footer: true) }
        } else {
            Color(.systemBackground)
        }
    }

    private var collectsCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("EZT GYŰJTI, HA BEKAPCSOLOD")
                .skinFont(.caption, weight: .bold)
                .foregroundStyle(.secondary)
            row("chart.bar.fill", "Iskolád neve", "A KRÉTA-beli intézmény neve — számlálásra elég, beazonosításra nem.")
            row("iphone", "Véletlen telepítés-azonosító", "A telefonon generált UUID — nem eszköz-ID, törléssel megújul.")
            row("app.badge.fill", "App-verzió és rendszer", "Pl. 1.0 (10), iOS 26 — hogy lássuk,min kell javítani.")
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .skinCard(fill: Color.primary.opacity(0.04))
    }

    private var notCollectsCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("EZT SOSEM GYŰJTI")
                .skinFont(.caption, weight: .bold)
                .foregroundStyle(.secondary)
            row("person.slash.fill", "Neved, jegyeid, órarended", "A KRÉTA-adataid a telefonodon maradnak.")
            row("key.slash.fill", "Jelszavad, tokened", "Belépési adatot sosem töltünk fel sehova.")
            row("location.slash.fill", "Helyzeted, eszköz-ID-d", "Nincs GPS, nincs fingerprint, nincs IP-naplózás.")
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .skinCard(fill: Color.green.opacity(0.08))
    }

    private var whyCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("MIRE HASZNÁLJUK AZ ADATOKAT?")
                .skinFont(.caption, weight: .bold)
                .foregroundStyle(.secondary)
            HStack(alignment: .top, spacing: 12) {
                SkinIcon("mountain.2.fill")
                    .skinFont(.body, weight: .semibold)
                    .foregroundStyle(.blue)
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
        .skinCard(fill: Color.blue.opacity(0.08))
    }

    private func row(_ icon: String, _ title: String, _ sub: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            SkinIcon(icon)
                .skinFont(.body, weight: .semibold)
                .foregroundStyle(.blue)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).skinFont(.subheadline, weight: .semibold)
                Text(sub).skinFont(.footnote).foregroundStyle(.secondary)
            }
        }
    }
}
