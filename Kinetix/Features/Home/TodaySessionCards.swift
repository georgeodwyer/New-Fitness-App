import SwiftUI
import TrainingEngine

/// Today's sessions, stacked full width, each a compact row: the session and its essentials,
/// a round Start button and small links. Rest days and a plan that
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

    /// A compact row: what it is and the essentials on one line, a big round Start button, the
    /// Apple Health "Count it" offer when a run there matches, and small links underneath.
    private func card(_ session: PlannedSessionModel) -> some View {
        let tint = session.kind.tint
        let isRun = session.kind.discipline == .run
        let open = session.status == .planned || session.status == .swapped
        return VStack(alignment: .leading, spacing: KXSpacing.sm) {
            HStack(alignment: .center, spacing: KXSpacing.md) {
                VStack(alignment: .leading, spacing: 2) {
                    KXOverline(overline(session), color: tint)
                    Text(session.title)
                        .font(KXFont.custom(.condensedBold, 24, relativeTo: .title3))
                        .textCase(.uppercase)
                        .foregroundStyle(KXColor.ink)
                        .lineLimit(2)
                    Text(isRun ? runLine(session) : summary(session))
                        .font(KXFont.callout)
                        .foregroundStyle(KXColor.inkSecondary)
                        .lineLimit(2)
                }
                Spacer(minLength: KXSpacing.xs)
                trailing(session, open: open)
            }
            if isRun, open, Calendar.kinetix.isDateInToday(session.date) {
                HealthMatchStrip(session: session, format: format)
            }
            Divider().overlay(KXColor.border)
            HStack(spacing: KXSpacing.lg) {
                Button(session.status == .completed ? "View" : "Details") { onDetails(session) }
                    .accessibilityIdentifier("today.details")
                if session.status == .planned {
                    Button("Swap, move or skip") { onActions(session) }
                        .accessibilityIdentifier("today.actions")
                }
                Spacer(minLength: 0)
            }
            .font(KXFont.callout)
            .foregroundStyle(KXColor.inkSecondary)
        }
        .padding(.vertical, KXSpacing.md)
        .padding(.leading, KXSpacing.lg)
        .padding(.trailing, KXSpacing.md)
        .background(KXColor.surface, in: RoundedRectangle(cornerRadius: KXRadius.md, style: .continuous))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("today.sessionTile")
    }

    /// The round button on the right: Start, a tick once done, or a word when skipped.
    @ViewBuilder
    private func trailing(_ session: PlannedSessionModel, open: Bool) -> some View {
        if session.status == .completed {
            Image(systemName: "checkmark")
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(KXColor.onAccent)
                .frame(width: 56, height: 56)
                .background(KXColor.success, in: Circle())
                .accessibilityLabel("Done")
        } else if session.status == .skipped {
            Text("Skipped").font(KXFont.captionEmphasis).foregroundStyle(KXColor.inkSecondary)
        } else if open, canStart(session) {
            Button { onStart(session) } label: {
                Image(systemName: "play.fill")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(KXColor.onAccent)
                    .frame(width: 60, height: 60)
                    .background(KXColor.accent, in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(session.kind.discipline == .run ? "Start run" : "Start \(session.title)")
            .accessibilityIdentifier("today.start")
        }
    }

    /// "5.0 km · 30 min · 5:10–5:57/km".
    private func runLine(_ session: PlannedSessionModel) -> String {
        var parts: [String] = []
        if let meters = session.estimatedDistanceMeters, meters > 0 { parts.append(format.distance(meters)) }
        parts.append("\(Int(session.plannedDurationMinutes.rounded())) min")
        if let pace = Self.targetPace(session.runStructure) { parts.append(format.paceRange(pace)) }
        return parts.joined(separator: " · ")
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
        switch session.kind.discipline {
        case .run: text += " · Run"
        case .strength: text += " · Gym"
        default: break
        }
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
