import SwiftUI

// MARK: - Liquid Glass fallback legacy órákra (watchOS 26 alatt)
// A .glassEffect csak watchOS 26-tól létezik — régebbi rendszeren lapos,
// áttetsző korong a helyettesítő, ugyanazzal a tintával. 26-os rendszeren
// a render pixelre azonos a korábbival (valódi .glassEffect).
// A fallback tiszteletben tartja az accessibilityReduceTransparency-t
// (AGENTS.md üveg-szabály), magas kontrasztban pedig nem halványít.
extension View {
    /// Színezett üvegkör (az óraszám-/jegykörök mintájára).
    /// A `tint` a kész, áttetszőséggel együtt értendő tinta.
    @ViewBuilder
    func watchTintedGlassCircle(tint: Color) -> some View {
        if #available(watchOS 26, *) {
            self.glassEffect(.regular.tint(tint).interactive(), in: .circle)
        } else {
            self.background { WatchLegacyDisc(tint: tint) }
        }
    }

    /// Színezetlen üvegkör (jegykörök).
    @ViewBuilder
    func watchClearGlassCircle() -> some View {
        if #available(watchOS 26, *) {
            self.glassEffect(.clear, in: .circle)
        } else {
            self.background { WatchLegacyDisc(tint: .white.opacity(0.10)) }
        }
    }

    /// Üvegkapszula (pl. a napléptető "‹ Ma ›" pillje): a tartalomra
    /// simul, nem nyúlik — ezért a hívó tegye maxWidth-frame-be.
    @ViewBuilder
    func watchGlassPill(tint: Color = .white.opacity(0.12)) -> some View {
        if #available(watchOS 26, *) {
            self.glassEffect(.regular.tint(tint).interactive(), in: .capsule)
        } else {
            self.background { WatchLegacyPill(tint: tint) }
        }
    }

    /// Üveg-gomb stílus az elsődleges művelethez (pl. az órai
    /// Kérdezés): watchOS 26-tól a rendszer valódi Liquid Glass
    /// kapszula-gombja — saját rajzolt háttér, blur-hack nélkül,
    /// nyomott állapottal és koncentrikus sarkokkal együtt. Alatta a
    /// natív `.bordered` kapszula ugyanazzal a tintával, hogy a gomb
    /// régi rendszeren is gombnak nézzen ki.
    @ViewBuilder
    func watchGlassButtonStyle(tint: Color = .white.opacity(0.14)) -> some View {
        if #available(watchOS 26, *) {
            self.buttonStyle(.glass(.regular.tint(tint)))
        } else {
            self.buttonStyle(.bordered).tint(tint)
        }
    }

    /// Üvegkocka (pl. a teremnév kis kockája): ugyanaz az üveg, kisebb
    /// rádiusszal — a tinta jellemzően a kiemelőszín.
    @ViewBuilder
    func watchGlassCube(tint: Color = .white.opacity(0.12), cornerRadius: CGFloat = 6) -> some View {
        if #available(watchOS 26, *) {
            self.glassEffect(.regular.tint(tint).interactive(), in: .rect(cornerRadius: cornerRadius))
        } else {
            self.background { WatchLegacyCard(tint: tint, cornerRadius: cornerRadius) }
        }
    }
}

private struct WatchLegacyDisc: View {
    let tint: Color
    @Environment(\.accessibilityReduceTransparency) var reduceTransparency
    @Environment(\.colorSchemeContrast) var contrast

    var body: some View {
        Circle()
            .fill(reduceTransparency || contrast == .increased ? tint.opacity(0.9) : tint)
    }
}

private struct WatchLegacyPill: View {
    let tint: Color
    @Environment(\.accessibilityReduceTransparency) var reduceTransparency
    @Environment(\.colorSchemeContrast) var contrast

    var body: some View {
        Capsule()
            .fill(reduceTransparency || contrast == .increased ? tint.opacity(0.9) : tint)
    }
}

/// Double Tap-főgomb watchOS 10-en is: a `handGestureShortcut` csak
/// watchOS 11-től létezik, alatta a gomb sima gomb marad (a Double
/// Tap ott rendszer-szinten nem címezhető).
extension View {
    @ViewBuilder
    func watchPrimaryAction() -> some View {
        if #available(watchOS 11, *) {
            self.handGestureShortcut(.primaryAction)
        } else {
            self
        }
    }
}

private struct WatchLegacyCard: View {
    let tint: Color
    let cornerRadius: CGFloat
    @Environment(\.accessibilityReduceTransparency) var reduceTransparency
    @Environment(\.colorSchemeContrast) var contrast

    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(reduceTransparency || contrast == .increased ? tint.opacity(0.9) : tint)
    }
}
