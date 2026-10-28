import SwiftUI
import TrainingEngine

/// Today's sessions, stacked full width: a run shows its distance, time, target pace and
/// its parts as a coloured bar; a gym session shows a summary. Rest days and a plan that
/// hasn't started get one card.
struct TodaySessionCards: View {
    let sessions: [PlannedSessionModel]
    /// When the plan hasn't started yet.
    let planStart: Date?
    let format: DisplayFormat
    let onStart: (PlannedSessionModel) -> Void
    let onDetails: (PlannedSessionModel) -> Void
    let onActions: (PlannedSessionModel) -> Void

    var body: some View {
        VStack(spacing: KXSpacing.md) {
            if sessions.isEmpty {
                restCard
            } else {
                ForEach(sessions) { session in
                    card(session)
                }
            }
        }
    }

    // MARK: Cards

    private func card(_ session: PlannedSessionModel) -> some View {
        let tint = session.kind.tint
        let isRun = session.kind.discipline == .run
        return VStack(alignment: .leading, spacing: KXSpacing.md) {
            HStack(alignment: .center, spacing: KXSpacing.md) {
                Image(systemName: session.kind.symbolName)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(tint)
                    .frame(width: 40, height: 40)
                    .background(tint.opacity(0.14), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 1) {
                    KXOverline(overline(session), color: tint)
                    Text(session.title)
                        .font(KXFont.custom(.condensedBold, 22, relativeTo: .title3))
                        .textCase(.uppercase)
                        .foregroundStyle(KXColor.ink)
                        .lineLimit(2)
                }
                Spacer(minLength: KXSpacing.xs)
                menu(session)
            }
            if isRun {
                runDetails(session)
            } else {
                Text(summary(session))
                    .font(KXFont.callout)
                    .foregroundStyle(KXColor.inkSecondary)
            }
            footer(session)
        }
        .kxCard(padding: KXSpacing.lg)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("today.sessionTile")
    }

    @ViewBuilder
    private func runDetails(_ session: PlannedSessionModel) -> some View {
        let structure = session.runStructure
        HStack(alignment: .top, spacing: KXSpacing.lg) {
            if let meters = session.estimatedDistanceMeters, meters > 0 {
                stat("Distance", format.distance(meters))
            }
            stat("Time", "\(Int(session.plannedDurationMinutes.rounded())) min")
            if let pace = Self.targetPace(structure) {
                stat("Target", format.paceRange(pace))
            }
            Spacer(minLength: 0)
        }
        if let structure, structure.segments.count > 1 {
            SessionStructureBar(structure: structure)
                .frame(height: 12)
            Text(session.summary)
                .font(KXFont.caption)
                .foregroundStyle(KXColor.inkTertiary)
                .lineLimit(2)
        } else if !session.summary.isEmpty {
            Text(session.summary)
                .font(KXFont.callout)
                .foregroundStyle(KXColor.inkSecondary)
        }
    }

    private func stat(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            KXOverline(label)
            Text(value)
                .font(KXFont.number(22, relativeTo: .title3))
                .foregroundStyle(KXColor.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private func footer(_ session: PlannedSessionModel) -> some View {
        HStack(spacing: KXSpacing.sm) {
            switch session.status {
            case .completed:
                Label("Done", systemImage: "checkmark.circle.fill")
                    .font(KXFont.bodyEmphasis)
                    .foregroundStyle(KXColor.success)
                Spacer()
                Button("View") { onDetails(session) }
                    .buttonStyle(.kx(.outlined))
            case .skipped:
                Label("Skipped", systemImage: "xmark.circle")
                    .font(KXFont.bodyEmphasis)
                    .foregroundStyle(KXColor.inkSecondary)
                Spacer()
            default:
                if canStart(session) {
                    Button {
                        onStart(session)
                    } label: {
                        Label(session.kind.discipline == .run ? "Start run" : "Start", systemImage: "play.fill")
                    }
                    .buttonStyle(.kx(.primary, fullWidth: true))
                    .accessibilityLabel("Start \(session.title)")
                }
                Button("Details") { onDetails(session) }
                    .buttonStyle(.kx(.outlined, fullWidth: !canStart(session)))
            }
        }
    }

    private func menu(_ session: PlannedSessionModel) -> some View {
        Menu {
            Button { onDetails(session) } label: { Label("Details", systemImage: "info.circle") }
            if session.status == .planned {
                Button { onActions(session) } label: { Label("Skip, swap or move", systemImage: "arrow.left.arrow.right") }
            }
        } label: {
            Image(systemName: "ellipsis")
                .font(.body.weight(.semibold))
                .foregroundStyle(KXColor.inkSecondary)
                .frame(width: 36, height: 32)
                .background(KXColor.surfaceTint, in: Capsule())
        }
        .accessibilityLabel("More for \(session.title)")
    }

    private var restCard: some View {
        HStack(spacing: KXSpacing.md) {
            Image(systemName: planStart == nil ? "bed.double.fill" : "calendar")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(KXColor.teal)
                .frame(width: 40, height: 40)
                .background(KXColor.teal.opacity(0.14), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                if let planStart {
                    Text("Plan starts \(planStart.formatted(.dateTime.weekday(.wide).day().month(.abbreviated)))")
                        .font(KXFont.headline).foregroundStyle(KXColor.ink)
                    Text("An easy run, a walk or rest until then.")
                        .font(KXFont.caption).foregroundStyle(KXColor.inkSecondary)
                } else {
                    Text("Rest day").font(KXFont.headline).textCase(.uppercase).foregroundStyle(KXColor.ink)
                    Text("Recovery is when the training sinks in.")
                        .font(KXFont.caption).foregroundStyle(KXColor.inkSecondary)
                }
            }
            Spacer(minLength: 0)
        }
        .kxCard()
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("today.sessionTile")
    }

    // MARK: Text

    private func overline(_ session: PlannedSessionModel) -> String {
        var text = sessions.count > 1 ? (session.slot == .morning ? "Morning" : "Evening") : "Today"
        if session.status == .swapped { text += " · Swapped" }
        return text
    }

    /// "6 exercises · 55 min" for a gym session; the summary for anything else.
    private func summary(_ session: PlannedSessionModel) -> String {
        let minutes = "\(Int(session.plannedDurationMinutes.rounded())) min"
        if let count = session.strengthPrescription?.exercises.count, count > 0 {
            return "\(count) exercise\(count == 1 ? "" : "s") · \(minutes)"
        }
        return session.summary.isEmpty ? minutes : "\(session.summary) · \(minutes)"
    }

    private func canStart(_ session: PlannedSessionModel) -> Bool {
        session.kind.discipline == .run || session.kind.discipline == .strength
    }

    /// The pace of the main efforts: the first work part, else a steady part.
    static func targetPace(_ structure: RunStructure?) -> PaceRange? {
        guard let segments = structure?.segments else { return nil }
        return segments.first { $0.kind == .work && $0.targetPace != nil }?.targetPace
            ?? segments.first { $0.kind == .steady && $0.targetPace != nil }?.targetPace
    }
}

/// A run's parts side by side, as wide as they are long: easy parts in the run colour, efforts
/// in amber, recoveries faint.
struct SessionStructureBar: View {
    let structure: RunStructure

    private func seconds(_ segment: RunSegment) -> Double {
        switch segment.length {
        case .duration(let seconds): return seconds
        case .distance(let meters):
            let secondsPerKm = segment.targetPace.map { ($0.fastest.secondsPerKm + $0.slowest.secondsPerKm) / 2 } ?? 330
            return meters / 1000 * secondsPerKm
        }
    }

    private func color(_ kind: SegmentKind) -> Color {
        switch kind {
        case .work: return KXColor.warning
        case .recovery: return KXColor.other
        case .warmUp, .coolDown, .steady: return KXColor.run
        }
    }

    var body: some View {
        GeometryReader { geo in
            let parts = structure.segments.map { (kind: $0.kind, seconds: max(seconds($0), 1)) }
            let total = parts.reduce(0) { $0 + $1.seconds }
            let gap: CGFloat = 2
            let usable = geo.size.width - gap * CGFloat(max(parts.count - 1, 0))
            HStack(spacing: gap) {
                ForEach(Array(parts.enumerated()), id: \.offset) { _, part in
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(color(part.kind))
                        .opacity(part.kind == .recovery ? 0.7 : 1)
                        .frame(width: max(3, usable * part.seconds / total))
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(structure.segments.count) parts")
    }
}
