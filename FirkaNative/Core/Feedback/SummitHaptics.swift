import SwiftUI
#if os(iOS)
import Observation
import UIKit
#endif

// MARK: - SummitHaptics — az app egyetlen haptikus belépője (iPhone + Mac Catalyst)
//
// Dizájn-szabályok (Apple HIG + WWDC-ajánlások alapján — a lényeg, hogy
// menő legyen, de sose "földrengés"):
// - Egy esemény = egy rezzenés. Soha nem lövünk kettőt ugyanarra.
// - Csak VALÓDI állapotváltozásra: készre pipa, szegmens-váltás,
//   lenyíló sor, sikeres/hibás kimenet. Puszta koppintásra, görgetésre,
//   tabváltásra, toggle-re NEM — azt a rendszer adja (duplázva fárasztó).
// - Mindig vizuális kísérővel (animáció, pipa, hibaüzenet) — a haptika
//   sosem az egyetlen visszajelzés.
// - Erősség-skála: .selection (választás) < light (visszavonás) <
//   .success/.error (kimenet) < heavy (készre pipa — ez az egyetlen
//   heavy-pont, direkt kérésre határozott).
// - Nézetekben inkább a deklaratív `.sensoryFeedback(_, trigger:)`
//   való ( lent `successHaptic(trigger:)` stb. ) — az imperatív
//   `SummitHaptics.*()` csak oda kell, ahol nincs trigger-állapot
//   (pl. onAppear-ünneplés, ViewModel-hiba).
//
// Platformok (méricskélve, nem feltételezve):
// - iPhone: Taptic Engine, teljes skála (UIKit-generátorok).
// - Mac (Catalyst): az UIKit-generátorok (impact/selection/
//   notification) NÉMÁK — az Apple csak a trackpad-natív
//   alignment/levelChange mintákat játssza le. Ezért az imperatív
//   hívások Macen a HapticRelay számlálóit pörgetik, és a gyökér-
//   nézeten lévő `.sensoryFeedback(.alignment/.levelChange)`
//   váltja őket kattanássá. Ahol nincs Force Touch trackpad
//   (csak egér), ott fizikailag néma — ez nem bug.
// - Watch: külön target, ezért az órai nézetek a beépített
//   `.sensoryFeedback`-et használják közvetlenül (watchOS 10+,
//   deployment target — nincs verziókapu). Az órán CSAK .selection
//   van (sor lenyitása, napléptetés): a csukló erősít, a success is
//   soknak hat — az óra maradjon szinte néma.
#if os(iOS)
/// Mac-relé: Catalysten az UIKit-generátorok némák, így az imperatív
/// hívások ezeket a számlálókat pörgetik; a SummitApp gyökerén lévő
/// `.sensoryFeedback(.alignment/.levelChange)` játssza le őket
/// trackpad-kattanásként. iPhone-on nem használjuk (ott a Taptic Engine
/// közvetlenül szólal meg, a triggerek sosem változnak).
@Observable
final class HapticRelay {
    static let shared = HapticRelay()
    /// Választás-tick (→ .alignment).
    var selectionTick = 0
    /// Commit-tick: light/firm/success/warning/error (→ .levelChange).
    /// A trackpad szókincse durva — egy csatorna elég mindnek.
    var commitTick = 0
    private init() {}
}

enum SummitHaptics {
    /// Kimenet kész: új jegy megérkezett, fantom felvéve.
    /// Egyszer, az ünnepléssel / listabeszúrással együtt.
    static func success() {
        #if targetEnvironment(macCatalyst)
        HapticRelay.shared.commitTick += 1
        #else
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        #endif
    }

    /// Kimenet meghiúsult: belépési hiba, mentés elutasítva.
    /// Egyszer, a látható hibaüzenettel együtt.
    static func error() {
        #if targetEnvironment(macCatalyst)
        HapticRelay.shared.commitTick += 1
        #else
        UINotificationFeedbackGenerator().notificationOccurred(.error)
        #endif
    }

    /// Figyelmeztető kimenet (ritka: pl. felülírás megerősítése).
    static func warning() {
        #if targetEnvironment(macCatalyst)
        HapticRelay.shared.commitTick += 1
        #else
        UINotificationFeedbackGenerator().notificationOccurred(.warning)
        #endif
    }

    /// Választás értékek közül (szegmens, napléptető, lenyíló sor).
    /// A legfinomabb — ezt szabad a legsűrűbben.
    static func selection() {
        #if targetEnvironment(macCatalyst)
        HapticRelay.shared.selectionTick += 1
        #else
        UISelectionFeedbackGenerator().selectionChanged()
        #endif
    }

    /// Könnyű koppanás: visszavonás (pipa levétele), semleges commit.
    static func light() {
        #if targetEnvironment(macCatalyst)
        HapticRelay.shared.commitTick += 1
        #else
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        #endif
    }

    /// Határozott, feszes koppanás: készre pipálás, törlés-nyugta.
    /// A skála legerősebb rövid tagja — csak tényleges commitra.
    /// (Macen a trackpad nem tud heavy-t, ott levelChange-tick.)
    static func firm() {
        #if targetEnvironment(macCatalyst)
        HapticRelay.shared.commitTick += 1
        #else
        UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
        #endif
    }

    /// Feladat-pipa egyben: készre → határozott heavy, levétel → light.
    /// A hívó a VÁLTÁS ELŐTTI állapotból számolja az újat, és csak
    /// tényleges váltáskor hívja (dupla koppintás = egy rezzenés).
    static func taskToggled(markedDone: Bool) {
        if markedDone { firm() } else { light() }
    }
}
#endif

// MARK: - Deklaratív forma nézetekbe
// iPhone-on a Taptic Engine-skálát, Macen (Catalyst) a trackpad-natív
// alignment/levelChange-et játssza (.selection/.success/.error Macen néma).
extension View {
    /// Sikeres kimenet triggerre (pl. kész-számláló nő, ünneplés megjelenik).
    func summitSuccessHaptic(trigger: some Equatable) -> some View {
        #if targetEnvironment(macCatalyst)
        sensoryFeedback(.levelChange, trigger: trigger)
        #else
        sensoryFeedback(.success, trigger: trigger)
        #endif
    }

    /// Választás-visszajelzés triggerre (szegmens, lenyitott sor, nap).
    func summitSelectionHaptic(trigger: some Equatable) -> some View {
        #if targetEnvironment(macCatalyst)
        sensoryFeedback(.alignment, trigger: trigger)
        #else
        sensoryFeedback(.selection, trigger: trigger)
        #endif
    }

    /// Hibás kimenet triggerre (megjelenő hibaüzenet).
    func summitErrorHaptic(trigger: some Equatable) -> some View {
        #if targetEnvironment(macCatalyst)
        sensoryFeedback(.levelChange, trigger: trigger)
        #else
        sensoryFeedback(.error, trigger: trigger)
        #endif
    }
}
