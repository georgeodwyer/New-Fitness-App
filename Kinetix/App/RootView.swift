import SwiftUI
import SwiftData

/// Shows onboarding until a profile exists, then the main tab bar.
struct RootView: View {
    @Query private var profiles: [UserProfileModel]
    @State private var router = AppRouter()
    @Environment(\.modelContext) private var context
    @Environment(\.scenePhase) private var scenePhase

    private var hasProfile: Bool {
        profiles.contains { !$0.isSoftDeleted }
    }

    var body: some View {
        Group {
            if hasProfile {
                MainTabView()
            } else {
                OnboardingFlowView()
            }
        }
        .environment(router)
        .tint(KXColor.accent)
        .onChange(of: scenePhase, initial: true) { _, phase in
            // Keep detailed sessions generated about two weeks ahead.
            if phase == .active { PlanService.refresh(in: context) }
        }
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
            SessionContainerView(session: session)
        }
    }
}
