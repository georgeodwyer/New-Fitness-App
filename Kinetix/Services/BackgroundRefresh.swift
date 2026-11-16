import Foundation
import BackgroundTasks
import SwiftData

/// Background app refresh: iOS wakes Kinetix a few times a day (when and how often is up to
/// iOS, and Apple Health can only be read while the phone is unlocked). Each time it reads the
/// latest Health data, notes runs from other apps, checks the day's live nudges (recovery,
/// steps, exertion) and rebuilds the week's notifications so they're up to date.
enum BackgroundRefresh {
    static let identifier = "com.georgeodwyer.kinetix.refresh"

    /// Asks for the next refresh, no sooner than an hour away.
    static func submit() {
        let request = BGAppRefreshTaskRequest(identifier: identifier)
        request.earliestBeginDate = Date(timeIntervalSinceNow: 60 * 60)
        try? BGTaskScheduler.shared.submit(request)
    }

    @MainActor
    static func run(container: ModelContainer) async {
        submit()
        let context = container.mainContext
        await HealthService.shared.refresh()
        PlanService.refresh(in: context)
        await ActivityNotifications.importedRuns(in: context)
        await ActivityNotifications.checkLive(in: context)
        await TrainingNotifications.schedule(in: context)
    }
}
