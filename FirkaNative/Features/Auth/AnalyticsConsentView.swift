import SwiftUI

/// Bejelentkezés utáni teljes képernyős választó: konkrétan megmondja,
/// mit gyűjt az app, és ott helyben ki/be kapcsolható.
///
/// GDPR-okból default: KI (előre bepipált doboz nem érvényes hozzájárulás —
/// Planet49, C-673/17). A "Folytatás" mindkét irányban ugyanannyi koppintás.
struct AnalyticsConsentView: View {
    @EnvironmentObject var analytics: AnalyticsStore
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
                            .font(.body)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.top, 12)

                    collectsCard
                    notCollectsCard
                    whyCard

                    Text("Bármikor kikapcsolhatod a Beállítások tetején, egy koppintással. A részletek az adatkezelési tájékoztatóban.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)

                    Link("Adatkezelési tájékoztató", destination: URL(string: "https://gaborcsaba.com/summit/adatkezeles.html")!)
                        .font(.footnote.weight(.semibold))
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 24)
            }
            .summitSheetBackground()
            .navigationBarTitleDisplayMode(.inline)
            .summitToolbarBackground()
            .safeAreaInset(edge: .bottom) {
                VStack(spacing: 10) {
                    Button { analytics.choose(enabled: true) } label: {
                        Text("Bekapcsolom")
                            .font(.headline.weight(.semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 15)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.blue)
                    Button { analytics.choose(enabled: false) } label: {
                        Text("Kikapcsolva folytatom")
                            .font(.headline.weight(.semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 15)
                    }
                    .buttonStyle(.bordered)
                    .tint(.primary)
                }
                .padding(.horizontal, 20)
                .padding(.top, 10)
                .padding(.bottom, 16)
                .background(Color(.systemBackground))
            }
        }
        .summitSheetBackground()
        .interactiveDismissDisabled(true)
    }

    private var collectsCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("EZT GYŰJTI, HA BEKAPCSOLOD")
                .font(.caption.weight(.bold))
                .foregroundStyle(.secondary)
            row("chart.bar.fill", "Iskolád neve", "A KRÉTA-beli intézmény neve — számlálásra elég, beazonosításra nem.")
            row("iphone", "Véletlen telepítés-azonosító", "A telefonon generált UUID — nem eszköz-ID, törléssel megújul.")
            row("app.badge.fill", "App-verzió és rendszer", "Pl. 1.0 (10), iOS 26 — hogy lássuk,min kell javítani.")
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 16))
    }

    private var notCollectsCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("EZT SOSEM GYŰJTI")
                .font(.caption.weight(.bold))
                .foregroundStyle(.secondary)
            row("person.slash.fill", "Neved, jegyeid, órarended", "A KRÉTA-adataid a telefonodon maradnak.")
            row("key.slash.fill", "Jelszavad, tokened", "Belépési adatot sosem töltünk fel sehova.")
            row("location.slash.fill", "Helyzeted, eszköz-ID-d", "Nincs GPS, nincs fingerprint, nincs IP-naplózás.")
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.green.opacity(0.08), in: RoundedRectangle(cornerRadius: 16))
    }

    private var whyCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("MIRE HASZNÁLJUK AZ ADATOKAT?")
                .font(.caption.weight(.bold))
                .foregroundStyle(.secondary)
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "mountain.2.fill")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.blue)
                    .frame(width: 24)
                Text("Kíváncsiak vagyunk, mennyien vagytok a hegy tetején.")
                    .font(.subheadline.weight(.semibold))
            }
            Text("A számokból lesz a térkép a weboldalon: melyik iskolákban hányan summitolnak. Döntéstámogatásra kell — melyik suliba érdemes kimenni, mit érdemes fejleszteni. Reklámra, profilozásra sosem.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.blue.opacity(0.08), in: RoundedRectangle(cornerRadius: 16))
    }

    private func row(_ icon: String, _ title: String, _ sub: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.body.weight(.semibold))
                .foregroundStyle(.blue)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.subheadline.weight(.semibold))
                Text(sub).font(.footnote).foregroundStyle(.secondary)
            }
        }
    }
}
