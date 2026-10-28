import SwiftUI
import SwiftData
import TrainingEngine

/// What a planned session involves: run segments with target paces, or exercises
/// with sets × reps × weight.
struct SessionDetailView: View {
    let session: PlannedSessionModel
    @Query(filter: #Predicate<UserProfileModel> { $0.deletedAt == nil }) private var profiles: [UserProfileModel]
    @Environment(AppRouter.self) private var router
    @Environment(\.modelContext) private var context
    @State private var showActions = false
    @State private var lastChange: String?
    @Query(sort: \PlanChangeModel.createdAt, order: .reverse) private var allChanges: [PlanChangeModel]

    private var sessionChanges: [PlanChangeModel] {
        allChanges.filter { $0.sessionId == session.id && !$0.isSoftDeleted }
    }

    private var format: DisplayFormat { DisplayFormat(units: profiles.first?.units ?? UnitPreference.stored) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: KXSpacing.xl) {
                VStack(alignment: .leading, spacing: KXSpacing.xs) {
                    KXOverline(session.date.formatted(.dateTime.weekday(.wide).day().month()), color: session.kind.tint)
                    Text(session.title).font(KXFont.display).textCase(.uppercase).foregroundStyle(KXColor.ink)
                    Text(session.summary).font(KXFont.callout).foregroundStyle(KXColor.inkSecondary)
                }
                VStack(alignment: .leading, spacing: KXSpacing.md) {
                    HStack(alignment: .top, spacing: KXSpacing.xl) {
                        if let meters = session.estimatedDistanceMeters, meters > 0 {
                            KXMetric(label: "Distance", value: format.distance(meters), size: .small)
                        }
                        KXMetric(label: "Time", value: "\(Int(session.plannedDurationMinutes))", unit: "min", size: .small)
                        KXMetric(label: "Effort", value: "\(Int(session.plannedEffort))", unit: "/10", size: .small)
                        Spacer(minLength: 0)
                    }
                    if let structure = session.runStructure, structure.segments.count > 1 {
                        SessionStructureBar(structure: structure).frame(height: 12)
                    }
                }
                .kxCard()
                if let reason = lastChange ?? session.changeReason {
                    NavigationLink {
                        PlanChangesView(changes: sessionChanges)
                            .navigationTitle("What changed and why")
                            .navigationBarTitleDisplayMode(.inline)
                    } label: {
                        VStack(alignment: .leading, spacing: KXSpacing.xs) {
                            Label(reason, systemImage: "arrow.triangle.2.circlepath")
                                .font(KXFont.callout).foregroundStyle(KXColor.ink)
                                .multilineTextAlignment(.leading)
                            Text("Changed – see why")
                                .font(KXFont.captionEmphasis).foregroundStyle(KXColor.accent)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .kxCard(.accent)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("session.changes")
                }
                if session.status == .planned, profiles.first != nil {
                    Button {
                        showActions = true
                    } label: {
                        Label("Skip or swap this session", systemImage: "arrow.left.arrow.right")
                    }
                    .buttonStyle(.kx(.outlined, fullWidth: true))
                }
                if let structure = session.runStructure { runCard(structure) }
                if let strength = session.strengthPrescription { strengthCard(strength) }
                if session.kind == .crossTraining {
                    Text("Keep it easy and conversational: cycling, cross-trainer, swimming or a brisk walk.")
                        .font(KXFont.callout)
                        .kxCard(.tinted)
                }
            }
            .padding(KXSpacing.screenMargin)
        }
        .safeAreaInset(edge: .bottom) {
            if session.status == .planned || session.status == .swapped,
               session.kind.discipline == .run || session.kind.discipline == .strength {
                Button {
                    router.startPlanned(session, in: context)
                } label: {
                    Label(session.kind.discipline == .run ? "Start run" : "Start session", systemImage: "play.fill")
                }
                .buttonStyle(.kx(.primary, fullWidth: true))
                .padding(KXSpacing.screenMargin)
                .background(KXColor.background)
            }
        }
        .background(KXColor.background.ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showActions) {
            if let profile = profiles.first?.profile {
                SessionActionsSheet(session: session, profile: profile) { explanations in
                    showActions = false
                    lastChange = explanations.first
                }
                .presentationDetents([.medium, .large])
            }
        }
    }

    /// Every part of the run with a bar in its colour, what it's for and its pace.
    private func runCard(_ structure: RunStructure) -> some View {
        VStack(alignment: .leading, spacing: KXSpacing.sm) {
            KXOverline("Part by part")
            ForEach(Array(structure.segments.enumerated()), id: \.offset) { index, segment in
                if index > 0 { Divider().overlay(KXColor.border) }
                HStack(spacing: KXSpacing.md) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(color(segment.kind))
                        .frame(width: 4, height: 34)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: KXSpacing.xxs) {
                        Text(segment.label ?? segment.kind.displayName).font(KXFont.bodyEmphasis).foregroundStyle(KXColor.ink)
                        if let target = segment.targetPace {
                            Text((segment.paceIsGuide == true ? "About " : "") + format.paceRange(target))
                                .font(KXFont.caption.monospacedDigit())
                                .foregroundStyle(KXColor.inkSecondary)
                        }
                    }
                    Spacer()
                    Text(format.segmentLength(segment.length))
                        .font(KXFont.number(18, relativeTo: .body))
                        .foregroundStyle(KXColor.ink)
                }
                .padding(.vertical, KXSpacing.xxs)
                .accessibilityElement(children: .combine)
            }
        }
        .kxCard()
    }

    private func color(_ kind: SegmentKind) -> Color {
        switch kind {
        case .work: return KXColor.warning
        case .recovery: return KXColor.other
        case .warmUp, .coolDown, .steady: return KXColor.run
        }
    }

    private func strengthCard(_ prescription: StrengthPrescription) -> some View {
        VStack(alignment: .leading, spacing: KXSpacing.md) {
            KXOverline("Exercises")
            ForEach(Array(prescription.exercises.enumerated()), id: \.offset) { _, exercise in
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: KXSpacing.xxs) {
                        Text(exercise.name).font(KXFont.bodyEmphasis).foregroundStyle(KXColor.ink)
                        Text("Rest \(Units.formatMinutesSeconds(Double(exercise.restSeconds)))")
                            .font(KXFont.caption).foregroundStyle(KXColor.inkSecondary)
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: KXSpacing.xxs) {
                        Text("\(exercise.sets) × \(exercise.repRange.lower)–\(exercise.repRange.upper)")
                            .font(KXFont.bodyEmphasis.monospacedDigit())
                        Text(exercise.weightKg.map { format.load($0) } ?? "Bodyweight")
                            .font(KXFont.caption).foregroundStyle(KXColor.inkSecondary)
                    }
                }
                .accessibilityElement(children: .combine)
            }
        }
        .kxCard()
    }
}
