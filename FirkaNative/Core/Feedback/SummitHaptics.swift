import SwiftUI
#if os(iOS)
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
// Platformok:
// - iPhone: Taptic Engine, teljes skála.
// - Mac (Catalyst): ugyanez a kód fut — az imperatív hívások itt
//   direkt impact-generátorra mennek (success/warning → medium,
//   error → heavy), mert az biztosan átmegy trackpad-kattanásba.
//   Ahol nincs Force Touch trackpad (csak egér), ott fizikailag
//   néma — ez a graceful fallback, nem bug.
// - Watch: külön target, ezért az órai nézetek a beépített
//   `.sensoryFeedback`-et használják közvetlenül (watchOS 10+,
//   deployment target — nincs verziókapu). Az órán CSAK .selection
//   van (sor lenyitása, napléptetés): a csukló erősít, a success is
//   soknak hat — az óra maradjon szinte néma.
#if os(iOS)
enum SummitHaptics {
    /// Kimenet kész: új jegy megérkezett, fantom felvéve.
    /// Egyszer, az ünnepléssel / listabeszúrással együtt.
    /// Macen (Catalyst) medium impact — a notification-minta
    /// trackpad-leképezése nem garantált, az impact igen.
    static func success() {
        #if targetEnvironment(macCatalyst)
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        #else
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        #endif
    }

    /// Kimenet meghiúsult: belépési hiba, mentés elutasítva.
    /// Egyszer, a látható hibaüzenettel együtt.
    /// Macen heavy impact (erős = baj), ugyanazért, mint fent.
    static func error() {
        #if targetEnvironment(macCatalyst)
        UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
        #else
        UINotificationFeedbackGenerator().notificationOccurred(.error)
        #endif
    }

    /// Figyelmeztető kimenet (ritka: pl. felülírás megerősítése).
    static func warning() {
        #if targetEnvironment(macCatalyst)
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        #else
        UINotificationFeedbackGenerator().notificationOccurred(.warning)
        #endif
    }

    /// Választás értékek közül (szegmens, napléptető, lenyíló sor).
    /// A legfinomabb — ezt szabad a legsűrűbben.
    static func selection() {
        UISelectionFeedbackGenerator().selectionChanged()
    }

    /// Könnyű koppanás: visszavonás (pipa levétele), semleges commit.
    static func light() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    /// Határozott, feszes koppanás: készre pipálás, törlés-nyugta.
    /// A skála legerősebb rövid tagja — csak tényleges commitra.
    static func firm() {
        UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
    }

    /// Feladat-pipa egyben: készre → határozott heavy, levétel → light.
    /// A hívó a VÁLTÁS ELŐTTI állapotból számolja az újat, és csak
    /// tényleges váltáskor hívja (dupla koppintás = egy rezzenés).
    static func taskToggled(markedDone: Bool) {
        if markedDone { firm() } else { light() }
    }
}
#endif

// MARK: - Deklaratív forma nézetekbe (iPhone + Watch + Mac, rendszer intézi)
extension View {
    /// Sikeres kimenet triggerre (pl. kész-számláló nő, ünneplés megjelenik).
    func summitSuccessHaptic(trigger: some Equatable) -> some View {
        sensoryFeedback(.success, trigger: trigger)
    }

    /// Választás-visszajelzés triggerre (szegmens, lenyitott sor, nap).
    func summitSelectionHaptic(trigger: some Equatable) -> some View {
        sensoryFeedback(.selection, trigger: trigger)
    }

    /// Hibás kimenet triggerre (megjelenő hibaüzenet).
    func summitErrorHaptic(trigger: some Equatable) -> some View {
        sensoryFeedback(.error, trigger: trigger)
    }
}
