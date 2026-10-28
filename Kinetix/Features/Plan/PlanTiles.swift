import SwiftUI
import TrainingEngine

/// Every phase of the plan, with dates and what each is for.
struct PlanPhasesView: View {
    let outline: PlanOutline
    @Environment(\.dismiss) private var dismiss

    private var currentIndex: Int? { outline.weekIndex(containing: .now, calendar: .kinetix) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: KXSpacing.lg) {
                    HStack(spacing: KXSpacing.xxs) {
                        ForEach(outline.blocks, id: \.firstWeek) { block in
                            Capsule()
                                .fill(KXColor.phase(TrainingPhase.allCases.firstIndex(of: block.phase) ?? 0))
                                .frame(height: 8)
                                .frame(maxWidth: .infinity)
                                .layoutPriority(Double(block.weekCount))
                        }
                    }
                    .accessibilityHidden(true)
                    ForEach(outline.blocks, id: \.firstWeek) { block in
                        phaseRow(block)
                    }
                    if outline.eventDate == nil {
                        Text("This is a rolling block: a new one is planned as this one finishes, starting from how your training has gone.")
                            .font(KXFont.caption)
                            .foregroundStyle(KXColor.inkSecondary)
                    }
                }
                .padding(KXSpacing.screenMargin)
            }
            .background(KXColor.background.ignoresSafeArea())
            .navigationTitle(outline.eventDate == nil ? "Your block" : "Road to race")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
        .tint(KXColor.accent)
    }

    private func phaseRow(_ block: PlanBlock) -> some View {
        let lastWeek = block.firstWeek + block.weekCount - 1
        let isNow = currentIndex.map { $0 >= block.firstWeek && $0 <= lastWeek } ?? false
        let start = outline.weeks.indices.contains(block.firstWeek) ? outline.weeks[block.firstWeek].startDate : outline.startDate
        let weeks = block.weekCount == 1 ? "Week \(block.firstWeek + 1)" : "Weeks \(block.firstWeek + 1)–\(lastWeek + 1)"
        return HStack(alignment: .top, spacing: KXSpacing.md) {
            KXChip(text: block.phase.displayName, variant: isNow ? .secondary : .outlined)
            VStack(alignment: .leading, spacing: KXSpacing.xxs) {
                Text("\(weeks) · from \(start.formatted(.dateTime.day().month(.abbreviated)))\(isNow ? " · now" : "")")
                    .font(KXFont.bodyEmphasis)
                    .foregroundStyle(KXColor.ink)
                Text(block.phase.explanation)
                    .font(KXFont.caption)
                    .foregroundStyle(KXColor.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .kxCard(isNow ? .raised : .tinted)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Paces

extension PaceZone {
    /// Short name for the paces tile.
    var tileName: String {
        switch self {
        case .easy: return "Easy & long"
        case .threshold: return "Tempo"
        case .interval: return "Intervals"
        case .halfMarathon: return "Half"
        default: return displayName
        }
    }

    /// What the pace is for, on the zones screen.
    var purpose: String {
        switch self {
        case .easy: return "Most of your running: easy runs, long runs, warm-ups and cool-downs. You can hold a conversation."
        case .steady: return "Relaxed but purposeful. The middle of progression runs and the end of some long runs."
        case .marathon: return "Your current marathon race pace."
        case .halfMarathon: return "Your current half marathon race pace."
        case .tenK: return "Your current 10K race pace."
        case .fiveK: return "Your current 5K race pace."
        case .threshold: return "Comfortably hard: tempo runs and threshold reps. A few words at a time."
        case .interval: return "Hard reps of 2–5 minutes, around 3K–5K race effort."
        case .repetition: return "Short, fast reps with full recovery, around mile race pace."
        }
    }

    /// The four on the tile: easy, the goal's race-ish pace, tempo and intervals.
    static func tileZones(for goal: TrainingGoal) -> [PaceZone] {
        let fourth: PaceZone
        switch goal {
        case .marathon: fourth = .marathon
        case .halfMarathon: fourth = .halfMarathon
        default: fourth = .steady
        }
        return [.easy, fourth, .threshold, .interval]
    }
}

/// Where the paces come from: their race time, or an estimate.
func paceSource(_ profile: AthleteProfile, format: DisplayFormat) -> String {
    guard let race = profile.recentRace, race.distanceMeters > 0, race.timeSeconds > 0 else {
        return "Estimated from your experience"
    }
    return "From your \(format.distance(race.distanceMeters)) in \(Units.formatMinutesSeconds(race.timeSeconds))"
}

/// Every pace zone, what it's for, and a way to make them more accurate.
struct PaceZonesView: View {
    let profile: AthleteProfile
    let profileModel: UserProfileModel?
    let format: DisplayFormat
    @Environment(\.dismiss) private var dismiss

    static let order: [PaceZone] = [.easy, .steady, .marathon, .halfMarathon, .tenK, .fiveK, .threshold, .interval, .repetition]

    var body: some View {
        let zones = PaceZones(profile: profile)
        NavigationStack {
            List {
                Section {
                    ForEach(Self.order, id: \.self) { zone in
                        VStack(alignment: .leading, spacing: KXSpacing.xxs) {
                            HStack {
                                Text(zone.displayName).font(KXFont.bodyEmphasis).foregroundStyle(KXColor.ink)
                                Spacer()
                                Text(format.paceRange(zones.range(for: zone)))
                                    .font(KXFont.bodyEmphasis.monospacedDigit())
                                    .foregroundStyle(KXColor.ink)
                            }
                            Text(zone.purpose).font(KXFont.caption).foregroundStyle(KXColor.inkSecondary)
                        }
                        .padding(.vertical, 2)
                        .accessibilityElement(children: .combine)
                    }
                } footer: {
                    Text(paceSource(profile, format: format) + ". Your watch shows the target pace for each part of a run.")
                }
                if let profileModel {
                    Section {
                        NavigationLink {
                            TrainingProfileView(profileModel: profileModel)
                        } label: {
                            Label(profile.recentRace == nil ? "Add a race time" : "Update your race time", systemImage: "stopwatch")
                        }
                    } footer: {
                        Text("A recent race or time trial makes these paces match your fitness. Find it under Running → Recent race time.")
                    }
                }
            }
            .navigationTitle("Your paces")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
        .tint(KXColor.accent)
    }
}
