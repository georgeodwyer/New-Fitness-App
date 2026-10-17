import SwiftUI
import SwiftData

/// The main tab bar, straight away: a plan is optional (it's built from the Plan tab), so
/// Record, Progress and Settings work from the first launch. A short animated splash covers
/// start-up.
struct RootView: View {
    @Query(filter: #Predicate<UserProfileModel> { $0.deletedAt == nil }) private var profiles: [UserProfileModel]
    @State private var router = AppRouter()
    @State private var showSplash = true
    @Environment(\.modelContext) private var context
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        ZStack {
            MainTabView()
            if showSplash {
                LaunchSplashView()
                    .transition(.opacity)
                    .zIndex(1)
            }
        }
        .task {
            AppBootstrap.ensureDefaults(in: context)
            // Someone who built a plan before this version already read the health notice.
            if !profiles.isEmpty { HealthNotice.accepted = true }
            let seconds = LaunchOptions().isUITesting ? 0.2 : 1.4
            try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            withAnimation(.easeOut(duration: 0.35)) { showSplash = false }
        }
        .environment(router)
        .tint(KXColor.accent)
        // Links from widgets and the lock screen: kinetix://tab/<today|plan|record|progress|settings>.
        .onOpenURL { url in
            guard url.scheme == "kinetix", url.host != "localhost" else { return }
            if url.host == "tab" {
                switch url.lastPathComponent {
                case "plan": router.selectedTab = .plan
                case "record": router.selectedTab = .record
                case "progress": router.selectedTab = .progress
                case "settings": router.selectedTab = .settings
                default: router.selectedTab = .today
                }
            }
        }
        .onChange(of: scenePhase, initial: true) { _, phase in
            // Keep detailed sessions generated about two weeks ahead.
            if phase == .active {
                PlanService.refresh(in: context)
                SyncService.shared.requestSync(after: 0.5)
                let units = profiles.first?.units ?? UnitPreference.stored
                Task {
                    await HealthService.shared.refresh()
                    await ActivityExportService.retryPending(in: context, units: units)
                    await StravaService.shared.importRecent(in: context)
                    WidgetSnapshotService.update(in: context)
                }
            } else if phase == .background {
                WidgetSnapshotService.update(in: context)
            }
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
            RecordView()
                .tabItem { Label("Record", systemImage: "record.circle") }
                .tag(AppRouter.Tab.record)
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
