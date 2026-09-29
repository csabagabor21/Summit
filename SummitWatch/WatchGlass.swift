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
