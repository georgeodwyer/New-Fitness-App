import SwiftUI
import TrainingEngine

/// A functional workout on the phone: the station you're on, its clock, Next, and the run pace
/// against target on run stations. Then the summary with splits and "how hard was it?".
struct FunctionalWorkoutView: View {
    let model: FunctionalWorkoutModel
    let onClose: () -> Void

    @State private var confirmFinish = false
    @State private var confirmLeave = false

    var body: some View {
        Group {
            if model.isFinished {
                FunctionalSummaryView(model: model, onClose: onClose)
            } else {
                live
            }
        }
        .background(KXColor.background.ignoresSafeArea())
        .onAppear { UIApplication.shared.isIdleTimerDisabled = true }
        .onDisappear { UIApplication.shared.isIdleTimerDisabled = false }
    }

    private var format: DisplayFormat { DisplayFormat(units: model.units) }
    private var session: FunctionalSession { model.session }

    // MARK: Live

    private var live: some View {
        VStack(spacing: KXSpacing.lg) {
            header
            totalClock
            if let station = session.station {
                stationCard(station)
            }
            if let next = session.nextStation, session.phase == .work, !session.isWaitingForInterval {
                HStack {
                    Text("Then").font(KXFont.captionEmphasis).foregroundStyle(KXColor.inkTertiary)
                    Text(next.title).font(KXFont.callout).foregroundStyle(KXColor.inkSecondary).lineLimit(1)
                    Spacer()
                }
            }
            Spacer(minLength: 0)
            controls
        }
        .padding(KXSpacing.screenMargin)
        .confirmationDialog("Finish now?", isPresented: $confirmFinish, titleVisibility: .visible) {
            Button("Finish workout") { model.finish() }
        } message: {
            Text("The station you're on is saved as far as you got.")
        }
        .confirmationDialog("Leave without saving?", isPresented: $confirmLeave, titleVisibility: .visible) {
            Button("Leave and don't save", role: .destructive) { onClose() }
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: KXSpacing.sm) {
            Button { confirmLeave = true } label: {
                Image(systemName: "xmark")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(KXColor.ink)
                    .frame(width: 40, height: 40)
                    .background(KXColor.surface, in: Circle())
            }
            .accessibilityLabel("Leave workout")
            VStack(alignment: .leading, spacing: 2) {
                Text(model.workout.name).font(KXFont.headline).foregroundStyle(KXColor.ink).lineLimit(1)
                Text(model.workout.summary).font(KXFont.caption).foregroundStyle(KXColor.inkSecondary).lineLimit(1)
            }
            Spacer()
            if let bpm = model.currentHeartRate(at: model.now) {
                Label("\(Int(bpm))", systemImage: "heart.fill")
                    .font(KXFont.bodyEmphasis.monospacedDigit())
                    .foregroundStyle(KXColor.danger)
                    .accessibilityLabel("Heart rate \(Int(bpm))")
            }
        }
    }

    private var totalClock: some View {
        VStack(spacing: KXSpacing.xxs) {
            if case .amrap = model.workout.format, let left = session.remaining(at: model.now) {
                Text(Units.formatMinutesSeconds(left)).font(KXFont.number(56)).foregroundStyle(KXColor.ink)
                Text("left · round \(session.round)").font(KXFont.captionEmphasis).foregroundStyle(KXColor.inkSecondary)
            } else {
                Text(Units.formatMinutesSeconds(session.elapsed(at: model.now))).font(KXFont.number(56)).foregroundStyle(KXColor.ink)
                Text(progressText).font(KXFont.captionEmphasis).foregroundStyle(KXColor.inkSecondary)
            }
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }

    private var progressText: String {
        let station = "Station \(session.stationIndex + 1) of \(model.workout.stations.count)"
        if let total = session.totalRounds, total > 1 { return "Round \(session.round) of \(total) · \(station)" }
        return station
    }

    @ViewBuilder
    private func stationCard(_ station: FunctionalStation) -> some View {
        VStack(alignment: .leading, spacing: KXSpacing.md) {
            if session.phase == .rest {
                KXOverline("Rest", color: KXColor.success)
                bigClock(session.remaining(at: model.now) ?? 0)
                if let next = session.nextStation {
                    Text("Next: \(next.title)").font(KXFont.bodyEmphasis).foregroundStyle(KXColor.ink)
                }
            } else if session.isWaitingForInterval {
                KXOverline("Done · rest until the next minute", color: KXColor.success)
                bigClock(session.remaining(at: model.now) ?? 0)
                if let next = session.nextStation {
                    Text("Next: \(next.title)").font(KXFont.bodyEmphasis).foregroundStyle(KXColor.ink)
                }
            } else {
                KXOverline(station.kind == .rest ? "Rest" : station.kind.displayName, color: KXColor.functional)
                Text(station.name)
                    .font(KXFont.custom(.condensedBold, 40, relativeTo: .largeTitle))
                    .textCase(.uppercase)
                    .foregroundStyle(KXColor.ink)
                    .lineLimit(2)
                    .minimumScaleFactor(0.6)
                HStack(spacing: KXSpacing.sm) {
                    KXChip(text: station.target.text, variant: .primary)
                    if let kg = station.weightKg, kg > 0 { KXChip(text: format.weight(kg), variant: .outlined) }
                    if station.treadmill { KXChip(text: "Treadmill", variant: .outlined) }
                }
                if let pace = model.paceText(for: station) {
                    Label(pace, systemImage: "speedometer").font(KXFont.callout).foregroundStyle(KXColor.ink)
                }
                if let speed = model.treadmillSpeed(for: station) {
                    Label("Set the treadmill to \(speed)", systemImage: "figure.run.treadmill")
                        .font(KXFont.bodyEmphasis).foregroundStyle(KXColor.ink)
                }
                if let remaining = session.remaining(at: model.now) {
                    bigClock(remaining)
                } else {
                    bigClock(session.phaseElapsed(at: model.now))
                }
                if model.isOutdoorRun { runReadout(station) }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .kxCard()
    }

    private func bigClock(_ seconds: Double) -> some View {
        Text(Units.formatMinutesSeconds(seconds))
            .font(KXFont.number(64))
            .foregroundStyle(KXColor.ink)
            .monospacedDigit()
    }

    /// Distance so far and the pace now, coloured against the target.
    private func runReadout(_ station: FunctionalStation) -> some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                KXOverline("Distance")
                Text(format.shortDistance(model.stationMeters)).font(KXFont.metricSmall).foregroundStyle(KXColor.ink)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                KXOverline(paceLabel)
                Text(model.currentPace.map { Units.formatPace($0, units: model.units) } ?? "–:––")
                    .font(KXFont.metricSmall)
                    .foregroundStyle(paceColor)
            }
        }
        .overlay(alignment: .bottomLeading) {
            if !model.hasGPSFix {
                Text("Finding GPS…").font(KXFont.caption).foregroundStyle(KXColor.warning).offset(y: 18)
            }
        }
    }

    private var paceLabel: String {
        switch model.pacePosition {
        case .tooSlow: return "Pace · speed up"
        case .tooFast: return "Pace · ease off"
        case .onTarget: return "Pace · on target"
        case nil: return "Pace"
        }
    }

    private var paceColor: Color {
        switch model.pacePosition {
        case .onTarget: return KXColor.success
        case .tooSlow, .tooFast: return KXColor.warning
        case nil: return KXColor.ink
        }
    }

    private var nextLabel: String {
        if session.phase == .rest { return "Skip rest" }
        if session.isWaitingForInterval { return "Waiting for the next minute" }
        if session.nextStation == nil { return "Finish" }
        return "Next station"
    }

    private var controls: some View {
        VStack(spacing: KXSpacing.sm) {
            Button {
                model.next()
            } label: {
                Text(nextLabel)
                    .font(KXFont.custom(.condensedBold, 24, relativeTo: .title2))
                    .textCase(.uppercase)
                    .frame(maxWidth: .infinity, minHeight: 64)
            }
            .buttonStyle(.kx(.primary, fullWidth: true))
            .disabled(session.isWaitingForInterval)
            .accessibilityIdentifier("functional.next")
            HStack(spacing: KXSpacing.sm) {
                Button {
                    model.undo()
                } label: {
                    Label("Undo", systemImage: "arrow.uturn.backward").frame(maxWidth: .infinity)
                }
                .buttonStyle(.kx(.outlined, fullWidth: true))
                .disabled(!session.canUndo)
                Button {
                    confirmFinish = true
                } label: {
                    Label("Finish", systemImage: "flag.checkered").frame(maxWidth: .infinity)
                }
                .buttonStyle(.kx(.secondary, fullWidth: true))
            }
        }
    }
}

// MARK: - Summary

/// Time, rounds and every station's split (runs with their pace against target), then
/// "how hard was it?" and save.
struct FunctionalSummaryView: View {
    let model: FunctionalWorkoutModel
    let onClose: () -> Void

    @State private var effort: Double = 7
    @State private var title = ""
    @State private var confirmDiscard = false

    private var format: DisplayFormat { DisplayFormat(units: model.units) }
    private var record: FunctionalRecord { model.record ?? FunctionalRecord(session: model.session) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: KXSpacing.xl) {
                VStack(alignment: .leading, spacing: KXSpacing.xs) {
                    KXOverline("Workout complete", color: KXColor.success)
                    Text(model.workout.name).font(KXFont.display).foregroundStyle(KXColor.ink)
                }
                HStack {
                    KXMetric(label: "Time", value: Units.formatMinutesSeconds(model.totalSeconds), size: .small)
                    Spacer()
                    if case .amrap = model.workout.format {
                        KXMetric(label: "Rounds", value: "\(record.roundsDone)", size: .small)
                        Spacer()
                    }
                    KXMetric(label: "Stations", value: "\(record.splits.filter { $0.kind != .rest }.count)", size: .small)
                    if record.runMeters > 0 {
                        Spacer()
                        KXMetric(label: "Run", value: format.distance(record.runMeters, decimals: 2), size: .small)
                    }
                    if let max = model.maxHeartRate {
                        Spacer()
                        KXMetric(label: "Max HR", value: "\(Int(max))", size: .small)
                    }
                }
                .kxCard()

                if !record.timeByKind.isEmpty {
                    VStack(alignment: .leading, spacing: KXSpacing.sm) {
                        KXSectionHeader("Where the time went")
                        let longest = record.timeByKind.first?.seconds ?? 1
                        ForEach(record.timeByKind, id: \.kind) { item in
                            HStack(spacing: KXSpacing.sm) {
                                Text(item.kind.displayName).font(KXFont.callout).foregroundStyle(KXColor.ink)
                                    .frame(width: 120, alignment: .leading)
                                GeometryReader { geo in
                                    Capsule().fill(KXColor.functional)
                                        .frame(width: max(6, geo.size.width * item.seconds / max(longest, 1)))
                                }
                                .frame(height: 10)
                                Text(Units.formatMinutesSeconds(item.seconds)).font(KXFont.captionEmphasis.monospacedDigit())
                                    .foregroundStyle(KXColor.inkSecondary)
                                    .frame(width: 52, alignment: .trailing)
                            }
                            .accessibilityElement(children: .combine)
                        }
                    }
                    .kxCard()
                }

                VStack(alignment: .leading, spacing: KXSpacing.sm) {
                    KXSectionHeader("Splits")
                    ForEach(Array(record.splits.enumerated()), id: \.offset) { _, split in
                        splitRow(split)
                        Divider().overlay(KXColor.border)
                    }
                }
                .kxCard()

                effortCard
                if model.savedLog == nil {
                    Button("Save workout") {
                        model.save(effort: effort, title: title)
                        onClose()
                    }
                    .buttonStyle(.kx(.primary, fullWidth: true))
                    .accessibilityIdentifier("functional.save")
                    Button("Discard", role: .destructive) { confirmDiscard = true }
                        .buttonStyle(.kx(.outlined, fullWidth: true))
                }
            }
            .padding(KXSpacing.screenMargin)
        }
        .onAppear { if title.isEmpty { title = model.workout.name } }
        .confirmationDialog("Discard this workout?", isPresented: $confirmDiscard, titleVisibility: .visible) {
            Button("Discard", role: .destructive) { onClose() }
        } message: {
            Text("It won't be saved or count towards your training load.")
        }
    }

    private func splitRow(_ split: FunctionalSplit) -> some View {
        let station = model.workout.stations[safeIndex: split.stationIndex]
        let runPace = pace(of: split, station: station)
        let range = station.flatMap { model.paceRange(for: $0) }
        let position = runPace.flatMap { pace in range.map { $0.position(of: pace, toleranceSecondsPerKm: 5) } }
        return HStack(alignment: .firstTextBaseline, spacing: KXSpacing.sm) {
            if (model.session.totalRounds ?? 2) > 1 {
                Text("R\(split.round)").font(KXFont.captionEmphasis).foregroundStyle(KXColor.inkTertiary).frame(width: 26, alignment: .leading)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text("\(split.name) \(split.target.text)").font(KXFont.callout).foregroundStyle(split.kind == .rest ? KXColor.inkTertiary : KXColor.ink)
                if let runPace {
                    HStack(spacing: KXSpacing.xxs) {
                        Text(format.pace(runPace)).font(KXFont.caption.monospacedDigit())
                        if let range {
                            Text("· target \(range.fastest == range.slowest ? format.pace(range.fastest) : format.paceRange(range))")
                                .font(KXFont.caption)
                        }
                        if let position {
                            Image(systemName: position == .onTarget ? "checkmark.circle.fill" : "exclamationmark.circle")
                                .font(KXFont.caption)
                                .foregroundStyle(position == .onTarget ? KXColor.success : KXColor.warning)
                        }
                    }
                    .foregroundStyle(KXColor.inkSecondary)
                }
            }
            Spacer()
            Text(Units.formatMinutesSeconds(split.seconds)).font(KXFont.bodyEmphasis.monospacedDigit()).foregroundStyle(KXColor.ink)
        }
        .accessibilityElement(children: .combine)
    }

    /// A run split's pace: GPS distance outside, or the set distance on a treadmill.
    private func pace(of split: FunctionalSplit, station: FunctionalStation?) -> Pace? {
        guard split.kind == .run, split.seconds > 0 else { return nil }
        var meters = split.meters
        if meters == nil || meters == 0, station?.treadmill == true, case .meters(let target) = split.target { meters = target }
        guard let meters, meters > 20 else { return nil }
        return Pace(secondsPerKm: split.seconds / meters * 1000)
    }

    private var effortCard: some View {
        VStack(alignment: .leading, spacing: KXSpacing.md) {
            Text("How hard was that overall?").font(KXFont.headline).foregroundStyle(KXColor.ink)
            HStack {
                Text("\(Int(effort))").font(KXFont.metric).foregroundStyle(KXColor.accent)
                Text("/ 10").font(KXFont.bodyEmphasis).foregroundStyle(KXColor.ink)
                Spacer()
            }
            Slider(value: $effort, in: 1...10, step: 1)
                .tint(KXColor.accent)
                .accessibilityLabel("Session effort")
            TextField("Name", text: $title)
                .font(KXFont.body)
                .padding(KXSpacing.sm)
                .background(KXColor.surfaceTint, in: RoundedRectangle(cornerRadius: KXRadius.sm, style: .continuous))
            Text("Counts towards your training load like a gym session, and goes to Apple Health and Strava if they're on.")
                .font(KXFont.caption).foregroundStyle(KXColor.inkSecondary)
        }
        .kxCard()
    }
}

/// A saved functional workout's splits (session history).
struct FunctionalSplitsCard: View {
    let record: FunctionalRecord
    let units: UnitSystem

    var body: some View {
        VStack(alignment: .leading, spacing: KXSpacing.sm) {
            KXSectionHeader("Splits", subtitle: record.workout.summary)
            ForEach(Array(record.splits.enumerated()), id: \.offset) { _, split in
                HStack(alignment: .firstTextBaseline, spacing: KXSpacing.sm) {
                    if record.splits.contains(where: { $0.round > 1 }) {
                        Text("R\(split.round)").font(KXFont.captionEmphasis).foregroundStyle(KXColor.inkTertiary)
                            .frame(width: 26, alignment: .leading)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(split.name) \(split.target.text)").font(KXFont.callout)
                            .foregroundStyle(split.kind == .rest ? KXColor.inkTertiary : KXColor.ink)
                        if split.kind == .run, let meters = split.meters, meters > 20, split.seconds > 0 {
                            Text(DisplayFormat(units: units).pace(Pace(secondsPerKm: split.seconds / meters * 1000)))
                                .font(KXFont.caption.monospacedDigit()).foregroundStyle(KXColor.inkSecondary)
                        }
                    }
                    Spacer()
                    Text(Units.formatMinutesSeconds(split.seconds)).font(KXFont.bodyEmphasis.monospacedDigit()).foregroundStyle(KXColor.ink)
                }
                .accessibilityElement(children: .combine)
            }
        }
        .kxCard()
    }
}

private extension Array {
    subscript(safeIndex index: Int) -> Element? { indices.contains(index) ? self[index] : nil }
}
