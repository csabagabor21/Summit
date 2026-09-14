import SwiftUI

// MARK: - SummitMotion — egységes, visszafogott mozgásrendszer
//
// Apple-szerű elv: kevés, lassú, fizikás mozgás. Egy helyen definiált
// görbék, hogy a tabok ne "más nyelven" mozogjanak egymáshoz képest.
// Új animációt ide vegyél fel, ne szórj magic-number springeket a view-kba.
//
// Szabályok:
// • Navigációra (TabView, NavigationStack push/pop) SOHA nem teszünk
//   custom animációt — azt a rendszer rajzolja (Liquid Glass morph).
// • Hosszú listák soraira nincs per-sor kaszkád — scroll közben olcsón hat.
// • Minden belépés tiszteletben tartja a Reduce Motiont.

enum SummitMotion {
    /// Elsődleges görbe: kártyák, szekciók, tab-váltás jellegű mozgások.
    static var gentle: Animation {
        .spring(response: 0.42, dampingFraction: 0.86)
    }
    /// Kis kontrollok: toggle, pipa, picker, "Ma" gomb.
    static var snappy: Animation {
        .spring(response: 0.32, dampingFraction: 0.86)
    }
    /// Belépő fade: címsorok, hero-elemek első megjelenése.
    static func entrance(delay: Double = 0) -> Animation {
        .easeOut(duration: 0.5).delay(delay)
    }
    /// Élő progress (MOST-kártya, órarend): a 15 mp-es Timeline-lépések
    /// közötti ugrást simítja, nem pattog.
    static var progress: Animation {
        .linear(duration: 0.6)
    }
    /// Nap/hét lapozás az órarendben: irányt tartó, gyors csúszás.
    static var page: Animation {
        .spring(response: 0.36, dampingFraction: 0.84)
    }
}

// MARK: - summitEntrance — finom fade + 8pt emelkedés első megjelenéskor
//
// Használat: címsorra, hero-kártyára, üres-állapot ikonra — max 2-3 elem
// képernyőnként, növekvő delay-jel. Listasorokra ne.

private struct SummitAppearModifier: ViewModifier {
    var delay: Double
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var appeared = false

    func body(content: Content) -> some View {
        content
            .opacity(appeared ? 1 : 0)
            .offset(y: (appeared || reduceMotion) ? 0 : 8)
            .onAppear {
                if reduceMotion {
                    appeared = true
                } else {
                    withAnimation(SummitMotion.entrance(delay: delay)) {
                        appeared = true
                    }
                }
            }
    }
}

extension View {
    /// Finom belépés első megjelenéskor. Reduce Motion mellett csak fade.
    func summitEntrance(delay: Double = 0) -> some View {
        modifier(SummitAppearModifier(delay: delay))
    }
}

// MARK: - SummitPress — visszafogott nyomás-visszajelzés
//
// A rendszer-gombokra nem kell, de a custom kártya-sorok tap-jére igen:
// 0.97-es skála, árnyék nélkül. Apple-szerű, nem "gumis".

struct SummitPressStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.97 : 1.0)
            .opacity(configuration.isPressed ? 0.92 : 1.0)
            .animation(SummitMotion.snappy, value: configuration.isPressed)
    }
}
