import SwiftUI

enum AppTheme { static let cardRadius: CGFloat = 20 }

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

    func appBackground(colors: AppColors) -> some View {
        colors.background.ignoresSafeArea()
    }
}
