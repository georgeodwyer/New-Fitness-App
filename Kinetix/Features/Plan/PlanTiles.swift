import SwiftUI
import TrainingEngine

/// About square on an iPhone with two tiles side by side (matches the Today tiles).
private let planTileMinHeight: CGFloat = 172

/// Top of the Plan tab: where you are in the block, and your paces. Two squares side by
/// side, stacked at the largest text sizes.
struct PlanTopTiles: View {
    let outline: PlanOutline
    let profile: AthleteProfile?
    let profileModel: UserProfileModel?
    let format: DisplayFormat

    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var showBlock = false
    @State private var showPaces = false

    var body: some View {
        let layout = typeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: KXSpacing.md))
            : AnyLayout(HStackLayout(alignment: .top, spacing: KXSpacing.md))
        layout {
            Button { showBlock = true } label: { BlockTile(outline: outline) }
                .buttonStyle(.plain)
                .frame(maxHeight: .infinity)
                .accessibilityHint("Shows every phase of your plan")
            if let profile {
                Button { showPaces = true } label: { PacesTile(profile: profile, format: format) }
                    .buttonStyle(.plain)
                    .frame(maxHeight: .infinity)
                    .accessibilityHint("Shows all your pace zones")
            }
        }
        .fixedSize(horizontal: false, vertical: true)
        .sheet(isPresented: $showBlock) { PlanPhasesView(outline: outline) }
        .sheet(isPresented: $showPaces) {
            if let profile { PaceZonesView(profile: profile, profileModel: profileModel, format: format) }
        }
    }
}

// MARK: - Block

/// "Week 3 of 12 · Build", what the phase is for, and what's next.
private struct BlockTile: View {
    let outline: PlanOutline

    private var calendar: Calendar { .kinetix }
    private var currentIndex: Int? { outline.weekIndex(containing: .now, calendar: calendar) }

    var body: some View {
        VStack(alignment: .leading, spacing: KXSpacing.sm) {
            KXOverline(outline.eventDate == nil ? "Your block" : "Road to race", color: KXColor.accent)
            if let index = currentIndex {
                let week = outline.weeks[index]
                HStack(alignment: .center, spacing: KXSpacing.sm) {
                    progressRing(done: index + 1, of: outline.weeks.count, phase: week.phase)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Week \(index + 1) of \(outline.weeks.count)")
                            .font(KXFont.headline)
                            .foregroundStyle(KXColor.ink)
                            .minimumScaleFactor(0.8)
                        Text(week.isRecoveryWeek ? "\(week.phase.displayName) · easier week" : week.phase.displayName)
                            .font(KXFont.captionEmphasis)
                            .foregroundStyle(KXColor.phase(TrainingPhase.allCases.firstIndex(of: week.phase) ?? 0))
                    }
                }
                Text(week.phase.explanation)
                    .font(KXFont.caption)
                    .foregroundStyle(KXColor.inkSecondary)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Text("Starts \(outline.startDate.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated)))")
                    .font(KXFont.headline)
                    .foregroundStyle(KXColor.ink)
                if let first = outline.weeks.first {
                    Text(first.phase.explanation)
                        .font(KXFont.caption)
                        .foregroundStyle(KXColor.inkSecondary)
                        .lineLimit(3)
                }
            }
            Spacer(minLength: 0)
            if let next = nextText {
                Label(next, systemImage: "arrow.right.circle")
                    .font(KXFont.caption)
                    .foregroundStyle(KXColor.inkSecondary)
                    .lineLimit(2)
            }
        }
        .frame(maxWidth: .infinity, minHeight: planTileMinHeight, alignment: .topLeading)
        .kxCard(padding: KXSpacing.md)
        .accessibilityElement(children: .combine)
    }

    /// "Peak from 9 Nov", "Race on 7 Dec", or when a rolling block renews.
    private var nextText: String? {
        let day: (Date) -> String = { $0.formatted(.dateTime.day().month(.abbreviated)) }
        let current = currentIndex ?? -1
        if let next = outline.blocks.first(where: { $0.firstWeek > current }), outline.weeks.indices.contains(next.firstWeek) {
            return "\(next.phase.displayName) from \(day(outline.weeks[next.firstWeek].startDate))"
        }
        if let event = outline.eventDate { return "Race on \(day(event))" }
        guard let last = outline.weeks.last,
              let renews = calendar.date(byAdding: .day, value: 7, to: last.startDate) else { return nil }
        return "New block from \(day(renews))"
    }

    private func progressRing(done: Int, of total: Int, phase: TrainingPhase) -> some View {
        let color = KXColor.phase(TrainingPhase.allCases.firstIndex(of: phase) ?? 0)
        return ZStack {
            Circle().stroke(KXColor.surfaceTint, lineWidth: 5)
            Circle()
                .trim(from: 0, to: total > 0 ? CGFloat(done) / CGFloat(total) : 0)
                .stroke(color, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
        .frame(width: 34, height: 34)
        .accessibilityHidden(true)
    }
}

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
private func paceSource(_ profile: AthleteProfile, format: DisplayFormat) -> String {
    guard let race = profile.recentRace, race.distanceMeters > 0, race.timeSeconds > 0 else {
        return "Estimated from your experience"
    }
    return "From your \(format.distance(race.distanceMeters)) in \(Units.formatMinutesSeconds(race.timeSeconds))"
}

/// Easy, a goal pace, tempo and intervals, per km (or mile).
private struct PacesTile: View {
    let profile: AthleteProfile
    let format: DisplayFormat

    private var zones: PaceZones { PaceZones(profile: profile) }

    var body: some View {
        VStack(alignment: .leading, spacing: KXSpacing.sm) {
            HStack {
                KXOverline("Your paces", color: KXColor.accent)
                Spacer(minLength: 0)
                Text("per \(Units.distanceUnitLabel(format.units))")
                    .font(KXFont.caption)
                    .foregroundStyle(KXColor.inkTertiary)
            }
            VStack(alignment: .leading, spacing: KXSpacing.xs) {
                ForEach(PaceZone.tileZones(for: profile.goal), id: \.self) { zone in
                    let range = zones.range(for: zone)
                    HStack(alignment: .firstTextBaseline, spacing: KXSpacing.xs) {
                        Text(zone.tileName)
                            .font(KXFont.caption)
                            .foregroundStyle(KXColor.inkSecondary)
                            .lineLimit(1)
                        Spacer(minLength: KXSpacing.xxs)
                        Text("\(Units.formatPace(range.fastest, units: format.units))–\(Units.formatPace(range.slowest, units: format.units))")
                            .font(KXFont.captionEmphasis.monospacedDigit())
                            .foregroundStyle(KXColor.ink)
                            .lineLimit(1)
                    }
                    .minimumScaleFactor(0.75)
                    .accessibilityElement(children: .combine)
                }
            }
            Spacer(minLength: 0)
            Text(paceSource(profile, format: format))
                .font(KXFont.caption)
                .foregroundStyle(KXColor.inkTertiary)
                .lineLimit(2)
        }
        .frame(maxWidth: .infinity, minHeight: planTileMinHeight, alignment: .topLeading)
        .kxCard(padding: KXSpacing.md)
    }
}

/// Every pace zone, what it's for, and a way to make them more accurate.
private struct PaceZonesView: View {
    let profile: AthleteProfile
    let profileModel: UserProfileModel?
    let format: DisplayFormat
    @Environment(\.dismiss) private var dismiss

    private static let order: [PaceZone] = [.easy, .steady, .marathon, .halfMarathon, .tenK, .fiveK, .threshold, .interval, .repetition]

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
