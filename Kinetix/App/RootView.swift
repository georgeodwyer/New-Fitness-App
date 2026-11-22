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
    /// "What's new" after an update (once per release).
    @State private var whatsNew: WhatsNew.Release?
    /// A workout a friend shared, opened from Messages, AirDrop or Files.
    @State private var sharedWorkout: SharedRunWorkout?
    @State private var sharedWorkoutUnreadable = false

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
            if !LaunchOptions().isUITesting {
                whatsNew = WhatsNew.pending(isNewInstall: profiles.isEmpty)
            }
        }
        .sheet(item: $whatsNew) { release in
            WhatsNewView(release: release) {
                WhatsNew.markSeen(release)
                whatsNew = nil
            }
            .interactiveDismissDisabled()
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
            // A workout a friend shared (.kinetixrun).
            if url.isFileURL {
                if let shared = SharedWorkoutFile.read(url) { sharedWorkout = shared } else { sharedWorkoutUnreadable = true }
                return
            }
            // Back from Garmin Connect after choosing watches.
            if GarminService.shared.handle(url: url) { return }
            guard url.scheme == "kinetix", url.host != "localhost" else { return }
            if url.host == "tab" {
                switch url.lastPathComponent {
                case "plan": router.selectedTab = .plan
                case "record": router.selectedTab = .record
                case "progress", "activity": router.selectedTab = .progress
                case "settings", "profile": router.selectedTab = .settings
                default: router.selectedTab = .today
                }
            }
        }
        .sheet(isPresented: Binding(get: { sharedWorkout != nil }, set: { if !$0 { sharedWorkout = nil } })) {
            if let sharedWorkout {
                let profile = profiles.first?.profile
                ImportSharedWorkoutSheet(shared: sharedWorkout, zones: profile.map(PaceZones.init(profile:)),
                                         units: profile?.units ?? UnitPreference.stored) { workout in
                    context.insert(RunTemplateModel(workout: workout))
                    try? context.save()
                    SyncService.shared.requestSync()
                    router.selectedTab = .record
                }
            }
        }
        .alert("Can't open this workout", isPresented: $sharedWorkoutUnreadable) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("It may be from a newer version of Kinetix. Update the app from TestFlight or the App Store and try again.")
        }
        .onChange(of: scenePhase, initial: true) { _, phase in
            // Keep detailed sessions generated about two weeks ahead.
            if phase == .active {
                // For "a week away" notifications.
                UserDefaults.standard.set(Date(), forKey: TrainingNotifications.Keys.lastOpened)
                // Back in the app mid-workout: bring the watch up to date.
                WatchMirrorService.shared.resendLast()
                if router.activeSession == nil, interruptedRun == nil {
                    interruptedRun = RunService.interrupted(in: context, excluding: router.runModel?.log?.id)
                }
                PlanService.refresh(in: context)
                SyncService.shared.requestSync(after: 0.5)
                let units = profiles.first?.units ?? UnitPreference.stored
                Task {
                    await HealthService.shared.refresh()
                    if let profile = profiles.first?.profile { FormService.check(profile: profile, in: context) }
                    await ActivityExportService.retryPending(in: context, units: units)
                    StravaService.shared.removeImportedActivities(in: context)
                    WatchSyncService.shared.sendPlan()
                    WidgetSnapshotService.update(in: context)
                }
            } else if phase == .background {
                WidgetSnapshotService.update(in: context)
                WatchSyncService.shared.sendPlan()
                Task { await NotificationService.scheduleMornings(in: context) }
                BackgroundRefresh.submit()
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
    @Environment(\.modelContext) private var context

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
                .tabItem { Label("Workout", systemImage: "figure.mixed.cardio") }
                .tag(AppRouter.Tab.record)
            ActivityScreen()
                .safeAreaInset(edge: .bottom) { MiniWorkoutBar() }
                .tabItem { Label("Activity", systemImage: "chart.bar") }
                .tag(AppRouter.Tab.progress)
            ProfileView()
                .safeAreaInset(edge: .bottom) { MiniWorkoutBar() }
                .tabItem { Label("Profile", systemImage: "person.crop.circle") }
                .tag(AppRouter.Tab.settings)
        }
        // Below-par recovery or a sore area: change today's session, or keep it as planned?
        .confirmationDialog(router.pendingReduction?.offer.title ?? "Today's session", isPresented: Binding(
            get: { router.pendingReduction != nil },
            set: { if !$0 { router.pendingReduction = nil } }
        ), titleVisibility: .visible, presenting: router.pendingReduction) { pending in
            if let other = pending.offer.swapWith {
                Button("Swap with \(other.title) and start it") { router.answerReduction(.swap, in: context) }
            }
            if let option = pending.offer.option {
                Button("\(option.title) and start") { router.answerReduction(.takeChange, in: context) }
            }
            if let day = pending.offer.moveTo {
                Button("Move it to \(day.formatted(.dateTime.weekday(.wide)))") { router.answerReduction(.move, in: context) }
            }
            Button("Keep as planned") { router.answerReduction(.keep, in: context) }
            Button("Cancel", role: .cancel) { router.pendingReduction = nil }
        } message: { pending in
            Text(pending.offer.message)
        }
        .fullScreenCover(item: $router.presentedSession) { session in
            SessionContainerView(session: session)
                .environment(router)
        }
    }
}
