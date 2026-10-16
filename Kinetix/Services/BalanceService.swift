import Foundation
import SwiftData
import TrainingEngine

/// Applies the engine's rebalancing (skip, swap, load/recovery adjustments) to the
/// stored plan, and records a one-sentence explanation for every change.
@MainActor
enum BalanceService {
    static let lastAutoAdjustKey = "balance.lastAutoAdjustDay"

    private static func context(profile: AthleteProfile, now: Date) -> Rebalancer.Context {
        Rebalancer.Context(
            trainingDays: profile.trainingDays,
            zones: PaceZones(profile: profile),
            units: profile.units,
            calendar: .kinetix,
            today: now
        )
    }

    /// Planned sessions in the week containing `date`, as engine values.
    private static func week(containing date: Date, in context: ModelContext) -> [PlannedSessionModel] {
        let calendar = Calendar.kinetix
        let monday = calendar.startOfISOWeek(for: date)
        let next = calendar.date(byAdding: .day, value: 7, to: monday) ?? date
        let descriptor = FetchDescriptor<PlannedSessionModel>(predicate: #Predicate { $0.date >= monday && $0.date < next })
        return ((try? context.fetch(descriptor)) ?? []).filter { !$0.isSoftDeleted && $0.plan?.isActive != false }
    }

    static func swapOptions(for session: PlannedSessionModel, profile: AthleteProfile, now: Date = .now) -> [SwapOption] {
        Rebalancer.swapOptions(for: session.weekSession, context: context(profile: profile, now: now))
    }

    @discardableResult
    static func skip(_ session: PlannedSessionModel, profile: AthleteProfile, in modelContext: ModelContext, now: Date = .now) -> [String] {
        let models = week(containing: session.date, in: modelContext)
        let adjustments = Rebalancer.skip(session.id, week: models.map(\.weekSession), context: context(profile: profile, now: now))
        let trigger = ChangeTrigger(label: "You skipped", value: session.title,
                                    detail: session.date.formatted(.dateTime.weekday(.wide)), symbol: "forward.end")
        return apply(adjustments, to: models, profile: profile, triggers: [trigger], in: modelContext, now: now)
    }

    @discardableResult
    static func swap(_ session: PlannedSessionModel, to option: SwapOption, profile: AthleteProfile, in modelContext: ModelContext, now: Date = .now) -> [String] {
        let trigger = ChangeTrigger(label: "You chose", value: option.title, detail: "instead of \(session.title.lowercased())",
                                    symbol: "arrow.left.arrow.right")
        return apply([Adjustment(session: option.replacement, explanation: option.explanation, cause: .swapped)], to: [session],
                     profile: profile, triggers: [trigger], in: modelContext, now: now)
    }

    /// Eases the coming days if load is high or today's check-in is poor. Runs at most
    /// once a day unless `force` (e.g. right after a check-in).
    @discardableResult
    static func autoAdjust(profile: AthleteProfile, status: LoadStatus, checkIn: RecoveryCheckIn?, in modelContext: ModelContext,
                           now: Date = .now, force: Bool = false, ratio: Double? = nil,
                           restingHeartRate: RestingHeartRateSignal? = nil, hrv: HRVSignal? = nil) -> [String] {
        let calendar = Calendar.kinetix
        let dayKey = ISO8601DateFormatter().string(from: calendar.startOfDay(for: now))
        if !force, UserDefaults.standard.string(forKey: lastAutoAdjustKey) == dayKey { return [] }
        UserDefaults.standard.set(dayKey, forKey: lastAutoAdjustKey)
        let models = week(containing: now, in: modelContext)
        let adjustments = Rebalancer.adjustForLoad(week: models.map(\.weekSession), status: status, checkIn: checkIn,
                                                   context: context(profile: profile, now: now))
        let triggers = loadTriggers(status: status, ratio: ratio) + recoveryTriggers(checkIn, restingHeartRate: restingHeartRate, hrv: hrv)
        return apply(adjustments, to: models, profile: profile, triggers: triggers, in: modelContext, now: now)
    }

    private static func apply(_ adjustments: [Adjustment], to models: [PlannedSessionModel], profile: AthleteProfile,
                              triggers: [ChangeTrigger] = [], in modelContext: ModelContext, now: Date) -> [String] {
        let zones = PaceZones(profile: profile)
        var explanations: [String] = []
        for adjustment in adjustments {
            guard let model = models.first(where: { $0.id == adjustment.session.id }) else { continue }
            let before = SessionSnapshot(model.weekSession, zones: zones)
            model.update(from: adjustment.session, zones: zones)
            let change = PlanChangeModel(summary: adjustment.explanation, sessionId: model.id, now: now)
            change.causeRaw = adjustment.cause.rawValue
            change.beforeData = StoredJSON.encode(before)
            change.afterData = StoredJSON.encode(SessionSnapshot(model.weekSession, zones: zones))
            change.triggersData = StoredJSON.encode(triggers)
            modelContext.insert(change)
            explanations.append(adjustment.explanation)
        }
        try? modelContext.save()
        if !explanations.isEmpty { SyncService.shared.requestSync() }
        return explanations
    }
}

extension BalanceService {
    /// The load numbers behind a high-load change.
    static func loadTriggers(status: LoadStatus, ratio: Double?) -> [ChangeTrigger] {
        guard status == .high else { return [] }
        let range = LoadStatus.optimalRange
        return [ChangeTrigger(label: "Load ratio", value: ratio.map { String(format: "%.2f", $0) } ?? "High",
                              detail: String(format: "optimal %.2f–%.2f", range.lowerBound, range.upperBound),
                              symbol: "chart.line.uptrend.xyaxis")]
    }

    /// The check-in answers and body signals behind a poor-recovery change.
    static func recoveryTriggers(_ checkIn: RecoveryCheckIn?, restingHeartRate: RestingHeartRateSignal?,
                                 hrv: HRVSignal? = nil) -> [ChangeTrigger] {
        guard let checkIn, checkIn.isPoor else { return [] }
        let rules = BalanceRules.current.recovery
        var triggers = [
            ChangeTrigger(label: "Readiness", value: "\(Int((checkIn.readiness * 100).rounded()))%",
                          detail: "below \(Int(rules.poorReadinessBelow * 100))% counts as poor", symbol: "gauge.with.dots.needle.33percent"),
            ChangeTrigger(label: "Sleep", value: "\(checkIn.sleep)/5", symbol: "moon.zzz"),
            ChangeTrigger(label: "Soreness", value: "\(checkIn.soreness)/5", symbol: "bandage"),
            ChangeTrigger(label: "Energy", value: "\(checkIn.energy)/5", symbol: "bolt")
        ]
        if checkIn.restingHeartRateElevated, let restingHeartRate {
            triggers.append(ChangeTrigger(label: "Resting HR", value: "+\(Int(restingHeartRate.difference.rounded())) bpm",
                                          detail: "\(Int(restingHeartRate.today.rounded())) vs usual \(Int(restingHeartRate.baseline.rounded()))",
                                          symbol: "heart"))
        }
        if checkIn.hrvSuppressed, let hrv {
            triggers.append(ChangeTrigger(label: "HRV", value: "\(Int((hrv.change * 100).rounded()))%",
                                          detail: "\(Int(hrv.today.rounded())) ms vs usual \(Int(hrv.baseline.rounded()))",
                                          symbol: "waveform.path.ecg"))
        }
        return triggers
    }
}

extension PlannedSessionModel {
    /// The engine's view of this session.
    var weekSession: WeekSession {
        WeekSession(id: id, date: date, slot: slot, kind: kind, isKey: isKey, status: status, title: title, summary: summary,
                    durationMinutes: plannedDurationMinutes, effort: plannedEffort, runStructure: runStructure,
                    strength: strengthPrescription, changeReason: changeReason)
    }

    /// Writes an engine change back to the stored session.
    func update(from session: WeekSession, zones: PaceZones) {
        if session.kind != kind && originalKindData == nil {
            originalKindData = kindData
        }
        date = session.date
        slotRaw = session.slot.rawValue
        kindData = StoredJSON.encode(session.kind)
        isKey = session.isKey
        if session.status != status { status = session.status }
        title = session.title
        summary = session.summary
        plannedDurationMinutes = session.durationMinutes
        plannedEffort = session.effort
        runStructureData = session.runStructure.map { StoredJSON.encode($0) }
        strengthPrescriptionData = session.strength.map { StoredJSON.encode($0) }
        estimatedDistanceMeters = session.runStructure.map { $0.estimate(zones: zones).distanceMeters }
        changeReason = session.changeReason
        touch()
    }
}

extension TrainingPhase {
    var index: Int { TrainingPhase.allCases.firstIndex(of: self) ?? 0 }
}
