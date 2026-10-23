import SwiftUI

// Not used after HIG fix — Home now uses native segmented Picker.
// Kept for reference, no glass.
struct FilterBarView: View {
    let tabs = ["Mind", "Jegyek", "Dolgozatok", "Üzenetek", "Hiányzások"]
    @Binding var selected: Int
    var body: some View {
        SkinSegmentedPicker(selection: $selected,
                            options: tabs.indices.map { (value: $0, title: tabs[$0]) },
                            accessibilityTitle: "Filter")
            .padding(.horizontal, 16)
    }
}
