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
                        if theme.isCyberpunk {
                            CPLabel("Adatvédelem // hozzájárulás", color: CyberpunkTheme.cyan, size: 10)
                        }
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
            .background {
                if theme.isCyberpunk { CPBackdrop() } else if theme.isMinecraft { McMenuBackground() }
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
                            .padding(.vertical, theme.isCyberpunk ? 2 : 15)
                    }
                    .skinBorderedButton(prominent: true)
                    .tint(.blue)
                    Button { analytics.choose(enabled: false) } label: {
                        Text("Kikapcsolva folytatom")
                            .skinFont(.headline, weight: .semibold)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, theme.isCyberpunk ? 2 : 15)
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
        // Minecraft / Cyberpunk: a háttér sötét, ezért a képernyő sötét
        // sémában fut (világos szöveg); Summitban a kapott séma marad.
        .environment(\.colorScheme, (theme.isMinecraft || theme.isCyberpunk) ? .dark : scheme)
        .interactiveDismissDisabled(true)
    }

    /// Alsó gombsáv háttere: Summitban a rendszer-háttér, Minecraftban a
    /// játék menü-lábléce (föld-csempe + lábléc-elválasztó), Cyberpunkban
    /// majdnem fekete sáv vékony sárga HUD-vonallal a tetején.
    @ViewBuilder
    private var consentBarBackground: some View {
        if theme.isCyberpunk {
            CyberpunkTheme.bgDeep
                .ignoresSafeArea(edges: .bottom)
                .overlay(alignment: .top) { CPDivider(color: CyberpunkTheme.yellow) }
        } else if theme.isMinecraft {
            McMenuBackground().overlay(alignment: .top) { McSeparator(footer: true) }
        } else {
            Color(.systemBackground)
        }
    }

    private var collectsCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            cardHeader("EZT GYŰJTI, HA BEKAPCSOLOD", code: "DATA.TX", accent: CyberpunkTheme.cyan)
            row("chart.bar.fill", "Iskolád neve", "A KRÉTA-beli intézmény neve — számlálásra elég, beazonosításra nem.", cpTint: CyberpunkTheme.cyan)
            row("iphone", "Véletlen telepítés-azonosító", "A telefonon generált UUID — nem eszköz-ID, törléssel megújul.", cpTint: CyberpunkTheme.cyan)
            row("app.badge.fill", "App-verzió és rendszer", "Pl. 1.0 (10), iOS 26 — hogy lássuk,min kell javítani.", cpTint: CyberpunkTheme.cyan)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .consentCard(fill: Color.primary.opacity(0.04), cpAccent: CyberpunkTheme.cyan)
    }

    private var notCollectsCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            cardHeader("EZT SOSEM GYŰJTI", code: "BLOCKED", accent: CyberpunkTheme.green)
            row("person.slash.fill", "Neved, jegyeid, órarended", "A KRÉTA-adataid a telefonodon maradnak.", cpTint: CyberpunkTheme.green)
            row("key.slash.fill", "Jelszavad, tokened", "Belépési adatot sosem töltünk fel sehova.", cpTint: CyberpunkTheme.green)
            row("location.slash.fill", "Helyzeted, eszköz-ID-d", "Nincs GPS, nincs fingerprint, nincs IP-naplózás.", cpTint: CyberpunkTheme.green)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .consentCard(fill: Color.green.opacity(0.08), cpAccent: CyberpunkTheme.green)
    }

    private var whyCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            cardHeader("MIRE HASZNÁLJUK AZ ADATOKAT?", code: "PURPOSE", accent: CyberpunkTheme.yellow)
            HStack(alignment: .top, spacing: 12) {
                SkinIcon("mountain.2.fill")
                    .skinFont(.body, weight: .semibold)
                    .foregroundStyle(theme.isCyberpunk ? CyberpunkTheme.yellow : .blue)
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
        .consentCard(fill: Color.blue.opacity(0.08), cpAccent: CyberpunkTheme.yellow)
    }

    /// Kártya-fejléc: Summitban/Minecraftban a szürke nagybetűs felirat,
    /// Cyberpunkban akcentszínű cím + jobbra igazított egyenközű kód.
    @ViewBuilder
    private func cardHeader(_ title: String, code: String, accent: Color) -> some View {
        if theme.isCyberpunk {
            HStack(spacing: 8) {
                Text(title)
                    .skinFont(.caption, weight: .bold)
                    .tracking(1.2)
                    .foregroundStyle(accent)
                Spacer(minLength: 6)
                CPLabel(code, color: CyberpunkTheme.dim, bracketed: false, size: 9)
                    .accessibilityHidden(true)
            }
        } else {
            Text(title)
                .skinFont(.caption, weight: .bold)
                .foregroundStyle(.secondary)
        }
    }

    private func row(_ icon: String, _ title: String, _ sub: String, cpTint: Color = CyberpunkTheme.cyan) -> some View {
        HStack(alignment: .top, spacing: 12) {
            SkinIcon(icon)
                .skinFont(.body, weight: .semibold)
                .foregroundStyle(theme.isCyberpunk ? cpTint : .blue)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).skinFont(.subheadline, weight: .semibold)
                Text(sub).skinFont(.footnote).foregroundStyle(.secondary)
            }
        }
    }
}

private extension View {
    /// Hozzájárulás-kártya felülete: Cyberpunkban kártyánként más akcentű
    /// (cián = gyűjtött, zöld = soha, sárga = cél) HUD-panel; egyébként a
    /// meglévő `skinCard`.
    @ViewBuilder
    func consentCard(fill: Color, cpAccent: Color) -> some View {
        if CyberpunkTheme.isActive {
            self.background { CPPanelBackground(accent: cpAccent) }
        } else {
            self.skinCard(fill: fill)
        }
    }
}
