import SwiftUI

// Not used after HIG fix — Home now uses native segmented Picker.
// Kept for reference, no glass.
struct FilterBarView: View {
    let tabs = ["Mind", "Jegyek", "Dolgozatok", "Üzenetek", "Hiányzások"]
    @Binding var selected: Int
    var body: some View {
        Picker("Filter", selection: $selected) {
            ForEach(0..<tabs.count, id: \.self) { i in Text(tabs[i]).tag(i) }
        }
        .pickerStyle(.segmented)
        .padding(.horizontal, 16)
    }
}
