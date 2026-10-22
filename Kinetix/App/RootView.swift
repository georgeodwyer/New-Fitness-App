import SwiftUI
import SwiftData
import TrainingEngine

/// The main tab bar, straight away: a plan is optional (it's built from the Plan tab), so
/// Record, Progress and Settings work from the first launch. A short animated splash covers
/// start-up.
struct RootView: View {
    @Query(filter: #Predicate<UserProfileModel> { $0.deletedAt == nil }) private var profiles: [UserProfileModel]
    @State private var router = AppRouter()
    @State private var showSplash = true
    @Environment(\.modelContext) private var context
    @Environment(\.scenePhase) private var scenePhase
    /// A run that was recording when Kinetix stopped, offered to save or discard.
    @State private var interruptedRun: RunLogModel?
    @State private var showStoreRecovered = Persistence.recoveredFromBrokenStore

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
        .alert("Kinetix started fresh", isPresented: $showStoreRecovered) {
            Button("OK") { Persistence.recoveredFromBrokenStore = false }
        } message: {
            Text("This update couldn't read the data saved on this iPhone, so it was kept aside and Kinetix started fresh. If you have an account, sign in to bring your training back.")
        }
        .alert("Save your unfinished run?", isPresented: Binding(get: { interruptedRun != nil }, set: { if !$0 { interruptedRun = nil } }),
               presenting: interruptedRun) { log in
            Button("Save run") {
                RunService.saveInterrupted(log, in: context)
                interruptedRun = nil
            }
            Button("Discard", role: .destructive) {
                RunService.discard(log, in: context)
                interruptedRun = nil
            }
        } message: { log in
            Text(interruptedText(log))
        }
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
                if router.activeSession == nil, interruptedRun == nil {
                    interruptedRun = RunService.interrupted(in: context, excluding: router.runModel?.log?.id)
                }
                PlanService.refresh(in: context)
                SyncService.shared.requestSync(after: 0.5)
                let units = profiles.first?.units ?? UnitPreference.stored
                Task {
                    await HealthService.shared.refresh()
                    await ActivityExportService.retryPending(in: context, units: units)
                    await StravaService.shared.importRecent(in: context)
                    WatchSyncService.shared.sendPlan()
                    WidgetSnapshotService.update(in: context)
                }
            } else if phase == .background {
                WidgetSnapshotService.update(in: context)
                WatchSyncService.shared.sendPlan()
            }
        }
    }
}

extension RootView {
    /// "Your run from 07:12 (5.20 km, 31:04) stopped before it was saved. Save it as it was?"
    func interruptedText(_ log: RunLogModel) -> String {
        let units = profiles.first?.units ?? UnitPreference.stored
        let when = log.startedAt.formatted(.dateTime.weekday(.wide).hour().minute())
        let distance = DisplayFormat(units: units).distance(log.distanceMeters, decimals: 2)
        return "Your run from \(when) (\(distance), \(Units.formatMinutesSeconds(log.durationSeconds))) stopped before it was saved. Save it as it was at that point?"
    }
}

struct MainTabView: View {
    @Environment(AppRouter.self) private var router

    var body: some View {
        @Bindable var router = router
        TabView(selection: $router.selectedTab) {
            HomeView()
                .safeAreaInset(edge: .bottom) { MiniWorkoutBar() }
                .tabItem { Label("Today", systemImage: "house") }
                .tag(AppRouter.Tab.today)
            PlanView()
                .safeAreaInset(edge: .bottom) { MiniWorkoutBar() }
                .tabItem { Label("Plan", systemImage: "calendar") }
                .tag(AppRouter.Tab.plan)
            RecordView()
                .safeAreaInset(edge: .bottom) { MiniWorkoutBar() }
                .tabItem { Label("Record", systemImage: "record.circle") }
                .tag(AppRouter.Tab.record)
            ProgressScreen()
                .safeAreaInset(edge: .bottom) { MiniWorkoutBar() }
                .tabItem { Label("Progress", systemImage: "chart.bar") }
                .tag(AppRouter.Tab.progress)
            SettingsView()
                .safeAreaInset(edge: .bottom) { MiniWorkoutBar() }
                .tabItem { Label("Settings", systemImage: "gearshape") }
                .tag(AppRouter.Tab.settings)
        }
        .fullScreenCover(item: $router.presentedSession) { session in
            SessionContainerView(session: session)
                .environment(router)
        }
    }
}
