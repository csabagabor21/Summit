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

    /// Üvegkártya (pl. az órarend-sorok háttere a telefon mintájára):
    /// lekerekített téglalap-üveg, státusz-tinttel színezve.
    @ViewBuilder
    func watchGlassCard(tint: Color = .white.opacity(0.10), cornerRadius: CGFloat = 14) -> some View {
        if #available(watchOS 26, *) {
            self.glassEffect(.regular.tint(tint).interactive(), in: .rect(cornerRadius: cornerRadius))
        } else {
            self.background { WatchLegacyCard(tint: tint, cornerRadius: cornerRadius) }
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
