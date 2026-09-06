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
}
