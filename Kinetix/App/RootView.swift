import SwiftUI
import SwiftData

/// Shows onboarding until a profile exists, then the main tab bar.
struct RootView: View {
    @Query private var profiles: [UserProfileModel]
    @State private var router = AppRouter()

    private var hasProfile: Bool {
        profiles.contains { !$0.isSoftDeleted }
    }

    var body: some View {
        Group {
            if hasProfile {
                MainTabView()
            } else {
                OnboardingWelcomeView()
            }
        }
        .environment(router)
        .tint(KXColor.accent)
    }
}

struct MainTabView: View {
    @Environment(AppRouter.self) private var router

    var body: some View {
        @Bindable var router = router
        TabView(selection: $router.selectedTab) {
            HomeView()
                .tabItem { Label("Today", systemImage: "house") }
                .tag(AppRouter.Tab.today)
            PlanView()
                .tabItem { Label("Plan", systemImage: "calendar") }
                .tag(AppRouter.Tab.plan)
            ProgressScreen()
                .tabItem { Label("Progress", systemImage: "chart.bar") }
                .tag(AppRouter.Tab.progress)
            SettingsView()
                .tabItem { Label("Settings", systemImage: "gearshape") }
                .tag(AppRouter.Tab.settings)
        }
        .fullScreenCover(item: $router.activeSession) { session in
            SessionPlaceholderView(session: session)
        }
    }
}
