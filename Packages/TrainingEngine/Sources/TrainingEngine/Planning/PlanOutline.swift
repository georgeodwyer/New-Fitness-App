import Foundation

/// The weekly targets for one week of the plan.
public struct WeekTarget: Codable, Equatable, Sendable {
    public var index: Int
    /// Monday of the week.
    public var startDate: Date
    public var phase: TrainingPhase
    /// 0-based position within the current phase (drives workout progression).
    public var weekInPhase: Int
    /// Planned down week (~20% less volume) to absorb training.
    public var isRecoveryWeek: Bool
    public var runVolumeMeters: Double
}

public struct PlanBlock: Equatable, Sendable {
    public var phase: TrainingPhase
    public var firstWeek: Int
    public var weekCount: Int
}

/// The whole-horizon outline: phases and weekly running volume. Detailed sessions
/// are generated from it a week or two at a time.
public struct PlanOutline: Codable, Equatable, Sendable {
    public var startDate: Date
    public var eventDate: Date?
    public var weeks: [WeekTarget]

    public var blocks: [PlanBlock] {
        var result: [PlanBlock] = []
        for week in weeks {
            if let last = result.last, last.phase == week.phase {
                result[result.count - 1].weekCount += 1
            } else {
                result.append(PlanBlock(phase: week.phase, firstWeek: week.index, weekCount: 1))
            }
        }
        return result
    }

    /// The week containing `date`, if within the plan.
    public func weekIndex(containing date: Date, calendar: Calendar) -> Int? {
        let monday = calendar.startOfISOWeek(for: date)
        return weeks.firstIndex { calendar.isDate($0.startDate, inSameDayAs: monday) }
    }
}

enum OutlineBuilder {
    /// Phase for each week given total weeks, whether there's an event, and taper length.
    static func phases(totalWeeks: Int, hasEvent: Bool, taperWeeks: Int) -> [TrainingPhase] {
        guard totalWeeks > 0 else { return [] }
        guard hasEvent else {
            let base = min(4, totalWeeks)
            return Array(repeating: .base, count: base) + Array(repeating: .build, count: totalWeeks - base)
        }
        let taper = min(taperWeeks, max(totalWeeks - 1, 0))
        let remaining = totalWeeks - taper
        let peak = totalWeeks >= 8 ? 2 : (totalWeeks >= 5 ? 1 : 0)
        let beforePeak = max(remaining - peak, 0)
        let build: Int
        let base: Int
        if totalWeeks < 4 {
            build = beforePeak
            base = 0
        } else {
            build = Int((Double(beforePeak) * 0.6).rounded())
            base = beforePeak - build
        }
        return Array(repeating: .base, count: base)
            + Array(repeating: .build, count: build)
            + Array(repeating: .peak, count: min(peak, remaining))
            + Array(repeating: .taper, count: taper)
    }

    static func build(
        profile: AthleteProfile,
        startMonday: Date,
        runsPerWeek: Int,
        rules: PlanRules,
        calendar: Calendar
    ) -> PlanOutline {
        let goalRules = rules.goal(profile.goal)
        let level = profile.runningExperience.rawValue

        // Horizon: to the event week if there's a future event, else a rolling block.
        var eventDate: Date?
        var totalWeeks = rules.rollingHorizonWeeks
        if let event = profile.eventDate, event >= startMonday {
            let eventMonday = calendar.startOfISOWeek(for: event)
            let weeks = (calendar.dateComponents([.day], from: startMonday, to: eventMonday).day ?? 0) / 7 + 1
            totalWeeks = min(max(weeks, 1), 52)
            eventDate = event
        }

        let phases = phases(totalWeeks: totalWeeks, hasEvent: eventDate != nil, taperWeeks: goalRules.taperWeeks)

        // Volume targets. Peak is limited by what the number of runs can sensibly hold.
        let perRunCap = rules.maxRunMeters[level] ?? 12000
        let capacity = Double(max(runsPerWeek, 1)) * perRunCap
        let peak = min(rules.peakVolumeMeters[profile.goal.rawValue]?[level] ?? 30000, capacity)
        let start = min(rules.startVolumeMeters[level] ?? 15000, peak)
        let maxIncrease = rules.maxWeeklyIncrease
        let taperCount = phases.filter { $0 == .taper }.count
        let taperFactors = Array(rules.taperFactors.suffix(max(taperCount, 0)))

        var weeks: [WeekTarget] = []
        var lastFullVolume = start
        var peakReached = start
        var taperIndex = 0
        var weekInPhase = 0

        for (index, phase) in phases.enumerated() {
            if index > 0, phases[index - 1] == phase { weekInPhase += 1 } else { weekInPhase = 0 }
            let monday = calendar.date(byAdding: .day, value: index * 7, to: startMonday) ?? startMonday
            var isRecovery = false
            let volume: Double

            switch phase {
            case .taper:
                let factor = taperIndex < taperFactors.count ? taperFactors[taperIndex] : (rules.taperFactors.last ?? 0.5)
                volume = peakReached * factor
                taperIndex += 1
            case .base, .build, .peak:
                if index == 0 {
                    volume = start
                } else if phase != .peak, rules.recoveryWeekEvery > 0, (index + 1) % rules.recoveryWeekEvery == 0 {
                    isRecovery = true
                    volume = lastFullVolume * rules.recoveryWeekFactor
                } else {
                    let increase = phase == .peak ? 0 : min(rules.weeklyIncrease[phase.rawValue] ?? 0.05, maxIncrease)
                    volume = min(peak, lastFullVolume * (1 + increase))
                    lastFullVolume = volume
                }
                if !isRecovery { peakReached = max(peakReached, volume) }
            }

            weeks.append(WeekTarget(
                index: index,
                startDate: monday,
                phase: phase,
                weekInPhase: weekInPhase,
                isRecoveryWeek: isRecovery,
                runVolumeMeters: volume
            ))
        }
        return PlanOutline(startDate: startMonday, eventDate: eventDate, weeks: weeks)
    }
}
