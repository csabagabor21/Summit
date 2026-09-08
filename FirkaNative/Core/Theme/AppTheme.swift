import SwiftUI
import UIKit

enum AppTheme { static let cardRadius: CGFloat = 20 }

/// macOS-en futó iPad-app (Designed for iPad): az ablak ne tudjon
/// olvashatatlanul kicsire menni — ehhez elég a min. ablakméret.
enum MacSupport {
    /// Debug/preview: -SUMMIT_MAC_PREVIEW kapcsolóval szimulátoron is
    /// megnézhető a Mac-elrendezés (széles sáv + nagy betű).
    static var previewMac: Bool { ProcessInfo.processInfo.arguments.contains("-SUMMIT_MAC_PREVIEW") }
    static var isMac: Bool { ProcessInfo.processInfo.isiOSAppOnMac || previewMac }
    static func applyWindowSizing() {
        guard isMac else { return }
        guard let scene = UIApplication.shared.connectedScenes.first(where: { $0 is UIWindowScene }) as? UIWindowScene,
              let restrictions = scene.sizeRestrictions else { return }
        restrictions.minimumSize = CGSize(width: 1024, height: 700)
    }
    /// Tartalomsáv széles ablakban: iPaden és Macen is szélesebb a réginél,
    /// hogy ne vesszen el a hely nagy kijelzőn.
    static func contentWidth(ipad: CGFloat, mac: CGFloat) -> CGFloat {
        isMac ? mac : ipad
    }
}

// Only functional layer may use glass — system provides it for Tab/Toolbar.
// No custom content cards. Content uses plain List/Section (system material).
extension View {
    // Keep only for primary floating CTA if needed — otherwise use .buttonStyle(.glass) native
    @ViewBuilder
    func functionalGlass(cornerRadius: CGFloat = 20, tint: Color? = nil) -> some View {
        if #available(iOS 26.0, *) {
            if let t = tint { self.glassEffect(.regular.tint(t).interactive(), in: .rect(cornerRadius: cornerRadius)) }
            else { self.glassEffect(.regular.interactive(), in: .rect(cornerRadius: cornerRadius)) }
        } else {
            self.background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: cornerRadius))
        }
    }

    // Feltételes glass: light módban a List-sorokban a glass saját árnyéka
    // dobozosan clipelődik — ott sima kártya marad, glass csak sötétben.
    @ViewBuilder
    func functionalGlassWhen(_ cond: Bool, cornerRadius: CGFloat = 20, tint: Color? = nil) -> some View {
        if cond { functionalGlass(cornerRadius: cornerRadius, tint: tint) } else { self }
    }

    @ViewBuilder
    func glassEffectIfAvailable(in circle: Circle = Circle(), tint: Color? = nil) -> some View {
        if #available(iOS 26.0, *) {
            if let t = tint { self.glassEffect(.regular.tint(t).interactive(), in: circle) }
            else { self.glassEffect(.regular.interactive(), in: circle) }
        } else {
            self.background(.ultraThinMaterial, in: circle)
        }
    }

    @ViewBuilder
    func glassEffectIfAvailable(in rect: RoundedRectangle, tint: Color? = nil) -> some View {
        if #available(iOS 26.0, *) {
            if let t = tint { self.glassEffect(.regular.tint(t).interactive(), in: rect) }
            else { self.glassEffect(.regular.interactive(), in: rect) }
        } else {
            self.background(.ultraThinMaterial, in: rect)
        }
    }

    func appBackground(colors: AppColors) -> some View {
        colors.background.ignoresSafeArea()
    }

    /// Lista-sor liquid glass háttérrel a SummitBackdrop fölé: a sor mögött
    /// átlátszik a háttérkép (valós idejű mintavétel + blur), nem tömör kártya.
    /// Használat: a Section kap `.listRowBackground(Color.clear)`-t (különben
    /// a rendszer szürke sor-háttere takarná a hátteret), a sor tartalma meg ezt.
    /// A `.regular` stílus az iOS 27 rendszer-csúszkát (ultra clear ↔ fully
    /// tinted) magától követi — NE tegyél rá kézi opacity-réteget, az harcolna vele.
    @ViewBuilder
    func summitGlassRow(cornerRadius: CGFloat = 16) -> some View {
        if #available(iOS 26.0, *) {
            self.glassEffect(.regular.interactive(), in: .rect(cornerRadius: cornerRadius))
        } else {
            self.background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: cornerRadius))
        }
    }
}

/// Summit háttérkép (Glacier asset) séma-függő fátyollal — a lista
/// szövegei olvashatók maradnak világos módban is. Beállítások + később
/// bármelyik lista-képernyő mögé betehető (.scrollContentBackground(.hidden) mellé).
///
/// scrollOffset <= 0 görgetéskor: a kép a tartalomnál lassabban (≈25%)
/// kúszik felfelé a teljes scroll-range-en — parallax, nem fix háttér.
struct SummitBackdrop: View {
    /// Melyik asset a háttérkép (pl. "Glacier", "DevPeak").
    var imageName: String = "Glacier"
    @Environment(\.colorScheme) var scheme
    // iOS 27 Liquid Glass-csúszka (ultra clear ↔ fully tinted) a VALÓDI
    // .glassEffect-rétegeket magától követi — de a saját háttér/fátyol
    // rétegeinknek kézzel kell igazodniuk, különben a panel "nem reagál":
    // Reduce Transparency-nél tömör háttér (fotó nélkül), emelt
    // kontrasztnál erősebb fátyol, hogy a teljes csúszka-tartományban olvasható maradjon.
    @Environment(\.accessibilityReduceTransparency) var reduceTransparency
    @Environment(\.colorSchemeContrast) var contrast
    var scrollOffset: CGFloat = 0
    var body: some View {
        if reduceTransparency {
            (scheme == .dark ? Color.black : Color.white).ignoresSafeArea()
        } else {
            GeometryReader { proxy in
                let h = proxy.size.height
                let extra = h * 0.4 // ennyi tartalék kép lóg túl — eddig tart a lassú kúszás
                let shift = min(0, max(-extra, scrollOffset * 0.25))
                ZStack {
                    Image(imageName)
                        .resizable()
                        .scaledToFill()
                        .frame(width: proxy.size.width, height: h + extra, alignment: .top)
                        .offset(y: shift)
                        .ignoresSafeArea()
                    LinearGradient(colors: veil, startPoint: .top, endPoint: .bottom)
                        .ignoresSafeArea()
                }
            }
            .ignoresSafeArea()
        }
    }
    private var veil: [Color] {
        // Emelt kontrasztnál +0.08 fátyol — az ultra-clear glass alatt is olvasható szöveg.
        let boost: Double = contrast == .increased ? 0.08 : 0
        if scheme == .dark {
            return [.black.opacity(0.76 + boost), .black.opacity(0.60 + boost), .black.opacity(0.84 + boost)]
        }
        return [.white.opacity(0.88 + boost), .white.opacity(0.76 + boost), .white.opacity(0.92 + boost)]
    }
}
