import Foundation
import SwiftData
import TrainingEngine

/// Units for people who haven't built a plan yet (the profile holds them once it exists).
enum UnitPreference {
    static let key = "units.preferred"

    static var stored: UnitSystem {
        get { UserDefaults.standard.string(forKey: key).flatMap(UnitSystem.init(rawValue:)) ?? defaultForRegion }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: key) }
    }

    /// Miles and pounds in the US, Liberia and Myanmar; metric elsewhere.
    static var defaultForRegion: UnitSystem {
        Locale.current.measurementSystem == .us ? .imperial : .metric
    }
}

/// The health & safety notice, acknowledged once (in plan set-up or before the first recording).
enum HealthNotice {
    static let key = "health.noticeAccepted"
    static var accepted: Bool {
        get { UserDefaults.standard.bool(forKey: key) }
        set { UserDefaults.standard.set(newValue, forKey: key) }
    }
}

/// Things every install needs whether or not a plan exists.
@MainActor
enum AppBootstrap {
    static func ensureDefaults(in context: ModelContext) {
        let settings = (try? context.fetch(FetchDescriptor<CoachingSettingsModel>())) ?? []
        if !settings.contains(where: { $0.deletedAt == nil }) {
            context.insert(CoachingSettingsModel())
            try? context.save()
        }
    }
}
