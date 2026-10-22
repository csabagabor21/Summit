import SwiftUI

struct ContentView: View {
    @EnvironmentObject var session: SessionStore
    @EnvironmentObject var theme: ThemeStore
    @EnvironmentObject var analytics: AnalyticsStore

    var body: some View {
        Group {
            if let cat = theme.sizeCategoryOverride {
                content.environment(\.sizeCategory, cat)
            } else {
                content
            }
        }
        .animation(SummitMotion.gentle, value: session.isLoggedIn)
        // Skin-váltáskor a nav/tab-sávok betűje is átvált (UIKit-appearance).
        .onChange(of: theme.skin) { _, s in
            MinecraftTheme.applyChromeAppearance(minecraft: s == .minecraft)
        }
        // Continuity (Handoff): a másik eszközön álló Summit átveszi
        // az aktuális tabot + pozíciót (lásd HandoffCenter.handle).
        .onContinueUserActivity(SummitHandoff.activityType) { activity in
            HandoffCenter.handle(activity)
        }
    }

    private var content: some View {
        Group {
            if session.isLoggedIn {
                MainTabView()
                    .transition(.opacity.combined(with: .scale(scale: 0.98)))
                    // Bejelentkezés utáni teljes képernyős választó: amíg nincs
                    // döntés, ez jön fel — konkrét listával, azonnali ki/bekapcsolással.
                    .fullScreenCover(isPresented: Binding(
                        get: { !analytics.hasChosen },
                        set: { if !$0 { analytics.choose(enabled: analytics.isEnabled) } }
                    )) {
                        AnalyticsConsentView()
                            .environmentObject(analytics)
                    }
            } else {
                LoginView()
                    .transition(.opacity)
            }
        }
    }
}
