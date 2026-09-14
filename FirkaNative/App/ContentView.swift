import SwiftUI

struct ContentView: View {
    @EnvironmentObject var session: SessionStore
    @EnvironmentObject var theme: ThemeStore

    var body: some View {
        Group {
            if let cat = theme.sizeCategoryOverride {
                content.environment(\.sizeCategory, cat)
            } else {
                content
            }
        }
        .animation(SummitMotion.gentle, value: session.isLoggedIn)
    }

    private var content: some View {
        Group {
            if session.isLoggedIn {
                MainTabView()
                    .transition(.opacity.combined(with: .scale(scale: 0.98)))
            } else {
                LoginView()
                    .transition(.opacity)
            }
        }
    }
}
