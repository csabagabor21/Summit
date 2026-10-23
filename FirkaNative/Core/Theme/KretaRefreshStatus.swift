import SwiftUI

// MARK: - Frissítés-állapot sor („Frissítés…" / „Mentve: tegnap 18:42")
// A mentett adat azonnal látszik, a háttér-frissítés pedig ezzel a kis,
// egyértelmű sorral jelzi magát — hogy senki ne higgye a mentett órarendet
// véglegesnek (pl. hogy nincs helyettesítés), amíg a friss még úton van.
// Sikertelen frissítés után a mentett adat ideje látszik. Magyarázó mondat
// szándékosan nincs: csak az állapot, röviden. Tartalom-réteg (nem üveg):
// a szöveg a hordozó felület (lista / hét-sáv üvege) vibrancyjét kapja.

/// Rövid, magyar „mikor" felirat a mentett adathoz: „ma 18:42",
/// „tegnap 18:42", „hétfő 18:42" (egy héten belül), különben „okt. 12. 18:42".
enum KretaSavedTimeFormat {
    private static let huLocale = Locale(identifier: "hu_HU")
    private static let time: DateFormatter = {
        let f = DateFormatter()
        f.locale = huLocale
        f.dateFormat = "H:mm"
        return f
    }()
    private static let weekday: DateFormatter = {
        let f = DateFormatter()
        f.locale = huLocale
        f.dateFormat = "EEEE"
        return f
    }()
    private static let dayMonth: DateFormatter = {
        let f = DateFormatter()
        f.locale = huLocale
        f.setLocalizedDateFormatFromTemplate("MMMd")
        return f
    }()

    static func text(_ date: Date, now: Date = Date(), calendar: Calendar = .current) -> String {
        let t = time.string(from: date)
        if calendar.isDate(date, inSameDayAs: now) { return "ma \(t)" }
        if let y = calendar.date(byAdding: .day, value: -1, to: now), calendar.isDate(date, inSameDayAs: y) {
            return "tegnap \(t)"
        }
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: date), to: calendar.startOfDay(for: now)).day ?? 99
        if days >= 0 && days < 7 { return "\(weekday.string(from: date)) \(t)" }
        return "\(dayMonth.string(from: date)) \(t)"
    }
}

/// Az állapot tartalma (szülőtől független) — a hét-sáv és a Főoldal is
/// ezt rajzolja. Üresjáratban (friss adat) semmit nem mutat.
struct KretaRefreshStatusLabel: View {
    let status: KretaStore.ScreenStatus

    var body: some View {
        switch status {
        case .idle:
            EmptyView()
        case .refreshing:
            HStack(spacing: 5) {
                SkinProgress()
                    .controlSize(.mini)
                Text("Frissítés…")
                    .lineLimit(1)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Frissítés folyamatban")
        case .saved(let date):
            SkinLabel("Mentve: \(KretaSavedTimeFormat.text(date))", systemImage: "clock.arrow.circlepath")
                .lineLimit(1)
                .accessibilityLabel("Mentett adat: \(KretaSavedTimeFormat.text(date))")
        }
    }
}

/// Önálló állapotsor: a megadott adattípusok közös állapotát olvassa a
/// store-ból. Saját nézet, hogy a store-változás csak ezt rajzolja újra,
/// ne a szülő képernyőt.
struct KretaRefreshStatusLine: View {
    let kinds: [KretaDataKind]

    var body: some View {
        KretaRefreshStatusLabel(status: KretaStore.shared.status(for: kinds))
            .animation(SummitMotion.gentle, value: KretaStore.shared.status(for: kinds))
    }
}

/// Láthatatlan figyelő: a store megadott típusainak mentési idejét (és a
/// fiók / betöltés állapotát) figyeli, és változáskor hív. A szülő nézet
/// body-ja így nem függ a store-tól — egy távoli hét lehúzása nem
/// rajzolja újra a teljes képernyőt, csak az érintett adat frissül.
struct KretaStoreWatcher: View {
    let kinds: [KretaDataKind]
    let action: () -> Void

    private struct Signature: Equatable {
        var account: String?
        var bootstrapping: Bool
        var stamps: [Date?]
    }

    var body: some View {
        let store = KretaStore.shared
        let sig = Signature(account: store.accountHash, bootstrapping: store.isBootstrapping,
                            stamps: kinds.map { store.savedAt($0) })
        Color.clear
            .frame(width: 0, height: 0)
            .accessibilityHidden(true)
            .onChange(of: sig) { _, _ in action() }
    }
}
