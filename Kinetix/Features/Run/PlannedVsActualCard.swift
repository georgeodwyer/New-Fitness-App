import SwiftUI
import TrainingEngine

/// Every part of a planned run, planned against actual: what was planned (distance or time
/// and target pace), what you ran, a bar showing where your pace fell in the range, and a
/// tick or how many seconds off. Reps get a summary after the last one.
struct PlannedVsActualCard: View {
    let results: [SegmentResult]
    let format: DisplayFormat

    private var units: UnitSystem { format.units }
    private var workIndexes: [Int] { results.indices.filter { results[$0].segment.kind == .work } }

    var body: some View {
        VStack(alignment: .leading, spacing: KXSpacing.md) {
            KXSectionHeader("Part by part", subtitle: "What was planned against what you ran")
            ForEach(Array(results.enumerated()), id: \.offset) { position, result in
                PartRow(result: result, title: title(at: position), format: format)
                if workIndexes.count > 1, position == workIndexes.last {
                    repsSummary
                }
            }
        }
        .kxCard()
    }

    /// "Rep 2 of 6", else the part's name ("Warm-up", "Steady", "Tempo").
    private func title(at position: Int) -> String {
        let segment = results[position].segment
        if segment.kind == .work, workIndexes.count > 1, let number = workIndexes.firstIndex(of: position) {
            return "Rep \(number + 1) of \(workIndexes.count)"
        }
        return segment.label ?? segment.kind.displayName
    }

    /// Average, fastest and slowest rep, and how many were in range.
    @ViewBuilder private var repsSummary: some View {
        let reps = workIndexes.map { results[$0] }.filter { $0.durationSeconds >= 1 }
        let paces = reps.compactMap(\.averagePace)
        let meters = reps.reduce(0) { $0 + $1.distanceMeters }
        let seconds = reps.reduce(0) { $0 + $1.durationSeconds }
        if !paces.isEmpty {
            let average = meters > 0 ? Pace(secondsPerKm: seconds / meters * 1000) : nil
            let judged = reps.filter { $0.segment.targetPace != nil && $0.averagePace != nil }
            let inRange = judged.filter { PaceGap(result: $0, units: units)?.isInRange == true }.count
            VStack(alignment: .leading, spacing: KXSpacing.xs) {
                Text("Reps").font(KXFont.captionEmphasis).foregroundStyle(KXColor.accent)
                HStack {
                    summaryMetric("Average", average.map { format.pace($0) } ?? "--")
                    Spacer()
                    summaryMetric("Fastest", paces.min().map { format.pace($0) } ?? "--")
                    Spacer()
                    summaryMetric("Slowest", paces.max().map { format.pace($0) } ?? "--")
                }
                if !judged.isEmpty {
                    Text("\(inRange) of \(judged.count) reps in your target range")
                        .font(KXFont.caption)
                        .foregroundStyle(KXColor.inkSecondary)
                }
            }
            .padding(KXSpacing.md)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(KXColor.surfaceTint, in: RoundedRectangle(cornerRadius: KXRadius.md, style: .continuous))
            .accessibilityElement(children: .combine)
        }
    }

    private func summaryMetric(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(KXFont.caption).foregroundStyle(KXColor.inkSecondary)
            Text(value).font(KXFont.bodyEmphasis.monospacedDigit()).foregroundStyle(KXColor.ink)
        }
    }
}

/// How far a part's pace was from its target range, per km (or mile).
struct PaceGap {
    /// Positive = slower than the range, negative = faster, 0 = in range.
    let seconds: Int

    var isInRange: Bool { seconds == 0 }

    init?(result: SegmentResult, units: UnitSystem) {
        guard let target = result.segment.targetPace, let pace = result.averagePace else { return nil }
        let perUnit = units == .metric ? 1.0 : 1.609344
        let gap: Double
        if pace.secondsPerKm > target.slowest.secondsPerKm {
            gap = pace.secondsPerKm - target.slowest.secondsPerKm
        } else if pace.secondsPerKm < target.fastest.secondsPerKm {
            gap = pace.secondsPerKm - target.fastest.secondsPerKm
        } else {
            gap = 0
        }
        seconds = Int((gap * perUnit).rounded())
    }

    var text: String {
        if seconds == 0 { return "On target" }
        return seconds > 0 ? "+\(seconds) s slow" : "\(seconds) s fast".replacingOccurrences(of: "-", with: "−")
    }
}

/// One part: "Rep 1 of 6 · 800 m", "Target 3:55–4:05/km", "You 4:00/km in 3:12 ✓", and the bar.
private struct PartRow: View {
    let result: SegmentResult
    let title: String
    let format: DisplayFormat

    private var segment: RunSegment { result.segment }
    private var done: Bool { result.durationSeconds >= 1 }
    private var gap: PaceGap? { PaceGap(result: result, units: format.units) }
    /// Easy jogs between reps and the like: shown smaller.
    private var isMinor: Bool { segment.kind == .recovery }

    var body: some View {
        VStack(alignment: .leading, spacing: KXSpacing.xs) {
            HStack(alignment: .firstTextBaseline) {
                Text(title)
                    .font(isMinor ? KXFont.captionEmphasis : KXFont.bodyEmphasis)
                    .foregroundStyle(isMinor ? KXColor.inkSecondary : KXColor.ink)
                Text("· \(format.segmentLength(segment.length))")
                    .font(isMinor ? KXFont.caption : KXFont.callout)
                    .foregroundStyle(KXColor.inkSecondary)
                Spacer(minLength: 0)
                verdict
            }
            if let target = segment.targetPace {
                line(segment.paceIsGuide == true ? "Guide" : "Target", format.paceRange(target), emphasis: false)
            }
            if done {
                line("You", actualText, emphasis: true)
                if let target = segment.targetPace, let pace = result.averagePace, !isMinor {
                    PaceRangeBar(target: target, pace: pace, inRange: gap?.isInRange ?? false)
                        .frame(height: 14)
                        .accessibilityHidden(true)
                }
            } else {
                line("You", "Not reached", emphasis: false)
            }
        }
        .padding(isMinor ? KXSpacing.sm : KXSpacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(isMinor ? Color.clear : KXColor.surfaceTint, in: RoundedRectangle(cornerRadius: KXRadius.md, style: .continuous))
        .overlay {
            if isMinor {
                RoundedRectangle(cornerRadius: KXRadius.md, style: .continuous).strokeBorder(KXColor.surfaceTint, lineWidth: 1)
            }
        }
        .accessibilityElement(children: .combine)
    }

    /// "4:00/km in 3:12" (planned by distance) or "4:00/km over 1.25 km" (planned by time).
    private var actualText: String {
        let pace = result.averagePace.map { format.pace($0) } ?? "--"
        switch segment.length {
        case .distance: return "\(pace) in \(Units.formatMinutesSeconds(result.durationSeconds))"
        case .duration: return "\(pace) over \(format.distance(result.distanceMeters, decimals: 2))"
        }
    }

    @ViewBuilder private var verdict: some View {
        if done, let gap {
            if gap.isInRange {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(KXColor.success)
                    .accessibilityLabel("On target")
            } else {
                Text(gap.text)
                    .font(KXFont.captionEmphasis.monospacedDigit())
                    .foregroundStyle(segment.paceIsGuide == true ? KXColor.inkSecondary : KXColor.warning)
            }
        }
    }

    private func line(_ label: String, _ value: String, emphasis: Bool) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: KXSpacing.sm) {
            Text(label)
                .font(KXFont.caption)
                .foregroundStyle(KXColor.inkSecondary)
                .frame(width: 44, alignment: .leading)
            Text(value)
                .font((emphasis ? KXFont.bodyEmphasis : KXFont.callout).monospacedDigit())
                .foregroundStyle(emphasis ? KXColor.ink : KXColor.inkSecondary)
        }
    }
}

/// The target range as a band on a faster → slower scale, with a dot where you ran.
private struct PaceRangeBar: View {
    let target: PaceRange
    let pace: Pace
    let inRange: Bool

    var body: some View {
        GeometryReader { proxy in
            let fast = target.fastest.secondsPerKm, slow = target.slowest.secondsPerKm
            let margin = max(slow - fast, 10)
            let low = fast - margin, high = slow + margin
            let x: (Double) -> CGFloat = { value in
                CGFloat((min(max(value, low), high) - low) / (high - low)) * proxy.size.width
            }
            let mid = proxy.size.height / 2
            ZStack(alignment: .leading) {
                Capsule().fill(KXColor.inkTertiary.opacity(0.25)).frame(height: 4)
                Capsule()
                    .fill(KXColor.success.opacity(0.45))
                    .frame(width: max(x(slow) - x(fast), 4), height: 8)
                    .offset(x: x(fast))
                Circle()
                    .fill(inRange ? KXColor.success : KXColor.warning)
                    .overlay(Circle().stroke(KXColor.background, lineWidth: 2))
                    .frame(width: 14, height: 14)
                    .offset(x: x(pace.secondsPerKm) - 7)
            }
            .frame(height: proxy.size.height)
            .position(x: proxy.size.width / 2, y: mid)
        }
    }
}
