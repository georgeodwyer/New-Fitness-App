import SwiftUI
import SwiftData
import UserNotifications
import WatchConnectivity

/// On Today until it's done or hidden: the few things that make Kinetix work best, each one tap
/// away. Replaces the notifications card, and holds what onboarding no longer asks (reminders,
/// Apple Watch, other apps).
struct GettingStartedCard: View {
    enum Item: String, CaseIterable, Identifiable {
        case checkIn, firstSession, notifications, watch, apps
        var id: String { rawValue }
    }

    static let hiddenKey = "gettingStarted.hidden"
    static let skippedKey = "gettingStarted.skipped"

    @Environment(AppRouter.self) private var router
    @Environment(\.modelContext) private var context
    @Query(filter: #Predicate<RecoveryCheckInModel> { $0.deletedAt == nil }) private var checkIns: [RecoveryCheckInModel]
    @Query(filter: #Predicate<RunLogModel> { $0.isFinished && $0.deletedAt == nil }) private var runs: [RunLogModel]
    @Query(filter: #Predicate<StrengthLogModel> { $0.isFinished && $0.deletedAt == nil }) private var lifts: [StrengthLogModel]
    @AppStorage(GettingStartedCard.hiddenKey) private var hidden = false
    @AppStorage(GettingStartedCard.skippedKey) private var skippedRaw = ""
    @State private var notificationStatus: UNAuthorizationStatus?
    @State private var strava = StravaService.shared
    @State private var showApps = false
    @State private var showWatchHelp = false

    private var skipped: Set<String> { Set(skippedRaw.split(separator: ",").map(String.init)) }

    /// The watch item only for people with an Apple Watch paired.
    private var items: [Item] {
        Item.allCases.filter { $0 != .watch || (WCSession.isSupported() && WCSession.default.isPaired) }
    }

    private func isDone(_ item: Item) -> Bool {
        if skipped.contains(item.rawValue) { return true }
        switch item {
        case .checkIn: return !checkIns.isEmpty
        case .firstSession: return !runs.isEmpty || !lifts.isEmpty
        case .notifications: return notificationStatus.map { $0 != .notDetermined } ?? true
        case .watch: return WCSession.isSupported() && WCSession.default.isWatchAppInstalled
        case .apps: return strava.isConnected
        }
    }

    var body: some View {
        let list = items
        let done = list.filter(isDone).count
        Group {
            if !hidden && done < list.count && !TabTours.isUITesting, let step = list.first(where: { !isDone($0) }) {
                stepCard(step, list: list, done: done)
            }
        }
        .task { await refresh() }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
            Task { await refresh() }
        }
        .sheet(isPresented: $showApps) {
            NavigationStack {
                Form { IntegrationsSection(includeWatch: false) }
                    .navigationTitle("Connect your apps")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { showApps = false } } }
            }
        }
        .alert("Kinetix on Apple Watch", isPresented: $showWatchHelp) {
            Button("Open Watch app") { if let url = URL(string: "itms-watchs://") { UIApplication.shared.open(url) } }
            Button("Later", role: .cancel) {}
        } message: {
            Text("Open the Watch app on your iPhone, scroll to Kinetix under Available Apps and tap Install. Then start runs and gym sessions from your wrist.")
        }
    }

    /// One step at a time: the next thing to do, its button, and progress dots with Skip and Hide.
    private func stepCard(_ item: Item, list: [Item], done: Int) -> some View {
        let text = copy(item)
        return VStack(alignment: .leading, spacing: KXSpacing.sm) {
            HStack(alignment: .center, spacing: KXSpacing.md) {
                VStack(alignment: .leading, spacing: 2) {
                    KXOverline("Getting started · \(done + 1) of \(list.count)", color: KXColor.accent)
                    Text(text.title)
                        .font(KXFont.custom(.condensedBold, 22, relativeTo: .title3))
                        .textCase(.uppercase)
                        .foregroundStyle(KXColor.ink)
                    Text(text.detail)
                        .font(KXFont.caption)
                        .foregroundStyle(KXColor.inkSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: KXSpacing.xs)
                if let action = text.action {
                    Button(action) { perform(item) }
                        .buttonStyle(.kx(.primary))
                        .accessibilityIdentifier("gettingStarted.\(item.rawValue)")
                }
            }
            Divider().overlay(KXColor.border)
            HStack(spacing: KXSpacing.lg) {
                HStack(spacing: 4) {
                    ForEach(list) { other in
                        Capsule()
                            .fill(isDone(other) ? KXColor.success : (other == item ? KXColor.accent : KXColor.border))
                            .frame(width: 16, height: 4)
                    }
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(done) of \(list.count) done")
                Spacer(minLength: 0)
                if item == .notifications || item == .watch || item == .apps {
                    Button("Skip") { skip(item) }
                }
                Button("Hide all") { withAnimation { hidden = true } }
                    .accessibilityIdentifier("gettingStarted.hide")
            }
            .font(KXFont.callout)
            .foregroundStyle(KXColor.inkSecondary)
        }
        .padding(.vertical, KXSpacing.md)
        .padding(.leading, KXSpacing.lg)
        .padding(.trailing, KXSpacing.md)
        .background(KXColor.surface, in: RoundedRectangle(cornerRadius: KXRadius.md, style: .continuous))
        .accessibilityIdentifier("today.gettingStarted")
    }

    private func row(_ item: Item) -> some View {
        let done = isDone(item)
        let text = copy(item)
        return HStack(alignment: .top, spacing: KXSpacing.md) {
            Image(systemName: done ? "checkmark.circle.fill" : "circle")
                .font(.title3)
                .foregroundStyle(done ? KXColor.success : KXColor.inkTertiary)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(text.title).font(KXFont.bodyEmphasis).foregroundStyle(done ? KXColor.inkSecondary : KXColor.ink)
                    .strikethrough(done, color: KXColor.inkTertiary)
                if !done {
                    Text(text.detail).font(KXFont.caption).foregroundStyle(KXColor.inkSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: KXSpacing.sm)
            if !done {
                VStack(alignment: .trailing, spacing: KXSpacing.xs) {
                    if let action = text.action {
                        Button(action) { perform(item) }
                            .buttonStyle(.kx(.secondary))
                            .accessibilityIdentifier("gettingStarted.\(item.rawValue)")
                    }
                    if item == .notifications || item == .watch || item == .apps {
                        Button("Skip") { skip(item) }
                            .font(KXFont.caption)
                            .foregroundStyle(KXColor.inkTertiary)
                    }
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityValue(done ? "Done" : "To do")
    }

    private func copy(_ item: Item) -> (title: String, detail: String, action: String?) {
        switch item {
        case .checkIn:
            return ("Check in", "Rate sleep, energy and soreness each morning (10 seconds). Your plan adjusts to it. It's in Readiness below.", nil)
        case .firstSession:
            return ("Do your first session", "Start today's session above, or any run or gym session from the Workout tab.", "Workout")
        case .notifications:
            return ("Turn on reminders", "Your day's training each morning, results and new bests. Never more than three a day.",
                    notificationStatus == .denied ? "Settings" : "Turn on")
        case .watch:
            return ("Add Kinetix to your Apple Watch", "Record runs and gym sessions from your wrist, with heart rate.", "How")
        case .apps:
            return ("Connect Strava", "Send your sessions to Strava automatically. Garmin and other apps are in Settings → Connections.", "Connect")
        }
    }

    private func perform(_ item: Item) {
        switch item {
        case .checkIn: break
        case .firstSession: router.selectedTab = .record
        case .notifications:
            if notificationStatus == .denied {
                if let url = URL(string: UIApplication.openNotificationSettingsURLString) { UIApplication.shared.open(url) }
                return
            }
            Task {
                await NotificationService.requestPermissionIfNeeded()
                await NotificationService.scheduleMornings(in: context)
                await refresh()
            }
        case .watch: showWatchHelp = true
        case .apps: showApps = true
        }
    }

    private func skip(_ item: Item) {
        var set = skipped
        set.insert(item.rawValue)
        withAnimation { skippedRaw = set.sorted().joined(separator: ",") }
    }

    private func refresh() async {
        notificationStatus = await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
    }
}
