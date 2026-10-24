import SwiftUI
import UIKit

enum AppTheme { static let cardRadius: CGFloat = 20 }

/// macOS-en futó iPad-app (Designed for iPad): az ablak ne tudjon
/// olvashatatlanul kicsire menni — ehhez elég a min. ablakméret.
enum MacSupport {
    /// Debug/preview: -SUMMIT_MAC_PREVIEW kapcsolóval szimulátoron is
    /// megnézhető a Mac-elrendezés (széles sáv + nagy betű).
    static var previewMac: Bool { ProcessInfo.processInfo.arguments.contains("-SUMMIT_MAC_PREVIEW") }
    static var isMac: Bool {
#if targetEnvironment(macCatalyst)
        true
#else
        ProcessInfo.processInfo.isiOSAppOnMac || previewMac
#endif
    }
    static func applyWindowSizing() {
        guard isMac else { return }
        guard let scene = UIApplication.shared.connectedScenes.first(where: { $0 is UIWindowScene }) as? UIWindowScene,
              let restrictions = scene.sizeRestrictions else { return }
        restrictions.minimumSize = CGSize(width: 1024, height: 700)
    }

    /// Tartalomsáv széles ablakban: iPaden és Macen is szélesebb a réginél,
    /// hogy ne vesszen el a hely nagy kijelzőn.
    static func contentWidth(ipad: CGFloat, mac: CGFloat) -> CGFloat {
#if targetEnvironment(macCatalyst)
        // Natív Mac app: a tartalom kitölti az ablakot, nincs középre
        // szorított sáv + fekete oldalsó rész.
        .infinity
#else
        isMac ? mac : ipad
#endif
    }
    /// Vékony oldalsó margó a teljes szélességű Mac-tartalomhoz (iOS-en 0).
    static var sidePadding: CGFloat {
#if targetEnvironment(macCatalyst)
        24
#else
        0
#endif
    }
    /// Valódi Mac-ablak (Catalyst vagy iPad-app Macen) — itt van asztal
    /// az ablak mögött, így az áttetsző rendszer-material működik. A
    /// -SUMMIT_MAC_PREVIEW szimulátoros elrendezés-előnézet NEM ilyen:
    /// ott az átlátszó ablak csak feketét mutatna, ezért az marad iOS-úton.
    static var isNativeMac: Bool {
#if targetEnvironment(macCatalyst)
        true
#else
        ProcessInfo.processInfo.isiOSAppOnMac
#endif
    }
    /// Áttetsző ablak Catalysten: az UIWindow ne fessen átlátszatlan
    /// fehér hátteret, így a natív rendszer-material (sidebar, toolbar,
    /// grouped lista-háttér) valódi vibrancy-vel látszik — ez adja a natív
    /// átlátszó Liquid Glass ablakot asztali gépen. iOS-en nem fut.
    static func applyWindowTransparency() {
        guard isNativeMac else { return }
        for scene in UIApplication.shared.connectedScenes {
            guard let ws = scene as? UIWindowScene else { continue }
            for w in ws.windows {
                w.backgroundColor = .clear
                w.isOpaque = false
            }
        }
    }
}

// Only functional layer may use glass — system provides it for Tab/Toolbar.
// No custom content cards. Content uses plain List/Section (system material).
extension View {
    // Keep only for primary floating CTA if needed — otherwise use .buttonStyle(.glass) native
    @ViewBuilder
    func functionalGlass(cornerRadius: CGFloat = 20, tint: Color? = nil) -> some View {
        // Minecraft-skinben a kártya pixel-blokk, nem üveg.
        if MinecraftTheme.isActive {
            self
        } else if #available(iOS 26.0, *) {
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
        // Minecraftban nincs üveg: a hívó saját pixel-háttere marad.
        if MinecraftTheme.isActive {
            self
        } else if #available(iOS 26.0, *) {
            if let t = tint { self.glassEffect(.regular.tint(t).interactive(), in: circle) }
            else { self.glassEffect(.regular.interactive(), in: circle) }
        } else {
            self.background(.ultraThinMaterial, in: circle)
        }
    }

    @ViewBuilder
    func glassEffectIfAvailable(in rect: RoundedRectangle, tint: Color? = nil) -> some View {
        if MinecraftTheme.isActive {
            self
        } else if #available(iOS 26.0, *) {
            if let t = tint { self.glassEffect(.regular.tint(t).interactive(), in: rect) }
            else { self.glassEffect(.regular.interactive(), in: rect) }
        } else {
            self.background(.ultraThinMaterial, in: rect)
        }
    }

    func appBackground(colors: AppColors) -> some View {
        colors.background.ignoresSafeArea()
    }

    /// Beviteli mező látható dobozzal: a csupasz TextField nem jelzi,
    /// hogy oda szöveget kell írni — ez ad neki hátteret + keretet.
    /// Világos és sötét módban is olvasható, kontrasztot nem tör meg.
    @ViewBuilder
    func summitInput() -> some View {
        if MinecraftTheme.isActive {
            self.modifier(McTextFieldFrame())
        } else {
            summitInputBox()
        }
    }

    private func summitInputBox() -> some View {
        self
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color.primary.opacity(0.22)))
    }

    /// Lista-sor liquid glass háttérrel a SummitBackdrop fölé: a sor mögött
    /// átlátszik a háttérkép (valós idejű mintavétel + blur), nem tömör kártya.
    /// Használat: a Section kap `.listRowBackground(Color.clear)`-t (különben
    /// a rendszer szürke sor-háttere takarná a hátteret), a sor tartalma meg ezt.
    /// A `.regular` stílus az iOS 27 rendszer-csúszkát (ultra clear ↔ fully
    /// tinted) magától követi — NE tegyél rá kézi opacity-réteget, az harcolna vele.
    @ViewBuilder
    func summitGlassRow(cornerRadius: CGFloat = 16) -> some View {
        // Minecraft-skin: üveg helyett blokk — ez az EGY pont az összes
        // lista-szigetet (Beállítások, Főoldal, Jegyek, órarend-sorok)
        // blokk-stílusúra váltja, a Summit-ág változatlan marad.
        // (UserDefaults-olvasás: nincs Environment-függés, preview-ban
        // az alapértelmezett Summit-ág fut.)
        if UserDefaults.standard.string(forKey: "ui.skin") == VisualSkin.minecraft.rawValue {
            self.minecraftCard(cornerRadius: 6)
        } else if #available(iOS 26.0, *) {
            // NEM `.interactive()`: ez egy sziget-háttér (több sor
            // tárolója), nem gomb — az interaktív üveg az egész szigetet
            // megrugóztatta az ujj alatt, a halott felületeken is („reagált,
            // de nem történt semmi"). A sorok saját gombjai adják a választ.
            self.glassEffect(.regular, in: .rect(cornerRadius: cornerRadius))
        } else {
            self.background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: cornerRadius))
        }
    }

    /// Lista-képernyő chrome: iOS-en a saját Summit-háttér (opaque
    /// colors.background + rejtett scroll-háttér), natív Mac-ablakban a
    /// rendszer anyaga — áttetsző grouped háttér vibrancy-vel, Liquid Glass
    /// sidebar + toolbar. Semmi kézi blur/opacity: a rendszer rajzol.
    @ViewBuilder
    func summitListChrome(colors: AppColors) -> some View {
        if MinecraftTheme.isActive {
            // Minecraft: élő égbolt minden lista mögött (napos dolog a
            // Főoldalon is) — a sorok blokk-háttere takar, a közökben
            // átlátszik az ég.
            self
                .scrollContentBackground(.hidden)
                .background { MinecraftBackdrop(ground: false) }
        } else if MacSupport.isNativeMac {
            self
                .scrollContentBackground(.visible)
                .background(Color.clear)
        } else {
            self
                .scrollContentBackground(.hidden)
                .background(colors.background)
        }
    }

    /// Toolbar-háttér: iOS-en kényszerített látható sáv, natív Mac-ablakban
    /// nincs felülírás — a rendszer rajzolja az átlátszó Liquid Glass bart.
    @ViewBuilder
    func summitToolbarBackground() -> some View {
        // Minecraft: a nav-sáv a játék menü-fejléce (földcsempe), a tetején
        // átlátszó — a kényszerített rendszer-sáv helyett az appearance dönt.
        if MinecraftTheme.isActive || MacSupport.isNativeMac {
            self
        } else {
            self.toolbarBackground(.visible, for: .navigationBar)
        }
    }

    /// Sor-háttér: iOS-en a Summit surface-kártya, natív Mac-ablakban a
    /// rendszer sora — különben világos módban tömör fehér dobozok ülnének
    /// az áttetsző ablakon.
    @ViewBuilder
    func summitRowSurface(colors: AppColors) -> some View {
        if MinecraftTheme.isActive {
            self.listRowBackground(McRowPanel(face: colors.surface))
        } else if MacSupport.isNativeMac {
            self.listRowBackground(Color.clear)
        } else {
            self.listRowBackground(colors.surface)
        }
    }

    /// Teljes képernyős lap (pl. consent): iOS-en tömör rendszer-háttér,
    /// natív Mac-ablakban átlátszó — a mögöttes tartalom áttűnik.
    @ViewBuilder
    func summitSheetBackground() -> some View {
        if MinecraftTheme.isActive {
            self.background { McMenuBackground() }
        } else if MacSupport.isNativeMac {
            self.background(Color.clear)
        } else {
            self.background(Color(.systemBackground).ignoresSafeArea())
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
