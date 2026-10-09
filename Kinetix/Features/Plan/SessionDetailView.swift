import SwiftUI
import SwiftData
import TrainingEngine

/// What a planned session involves: run segments with target paces, or exercises
/// with sets × reps × weight.
struct SessionDetailView: View {
    let session: PlannedSessionModel
    @Query private var profiles: [UserProfileModel]
    @Environment(AppRouter.self) private var router
    @State private var showActions = false
    @State private var lastChange: String?

    private var format: DisplayFormat { DisplayFormat(units: profiles.first?.units ?? .metric) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: KXSpacing.xl) {
                VStack(alignment: .leading, spacing: KXSpacing.xs) {
                    KXOverline(session.date.formatted(.dateTime.weekday(.wide).day().month()), color: KXColor.accent)
                    Text(session.title).font(KXFont.display).foregroundStyle(KXColor.ink)
                    Text(session.summary).font(KXFont.callout).foregroundStyle(KXColor.inkSecondary)
                }
                HStack(spacing: KXSpacing.xl) {
                    KXMetric(label: "Duration", value: "\(Int(session.plannedDurationMinutes))", unit: "min", size: .small)
                    KXMetric(label: "Effort", value: "\(Int(session.plannedEffort))", unit: "/10", size: .small)
                    if session.isKey { KXChip(text: "Key session", systemImage: "star.fill", variant: .secondary) }
                }
                if let reason = lastChange ?? session.changeReason {
                    Label(reason, systemImage: "arrow.triangle.2.circlepath").font(KXFont.callout).kxCard(.accent)
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
                Button("Start session") {
                    router.activeSession = ActiveSession(id: session.id, kind: session.kind, title: session.title)
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

    private func runCard(_ structure: RunStructure) -> some View {
        VStack(alignment: .leading, spacing: KXSpacing.md) {
            KXSectionHeader("Structure", subtitle: "\(structure.segments.count) segment\(structure.segments.count == 1 ? "" : "s")")
            ForEach(Array(structure.segments.enumerated()), id: \.offset) { _, segment in
                HStack(alignment: .firstTextBaseline) {
                    Circle()
                        .fill(segment.kind == .work ? KXColor.accent : KXColor.teal)
                        .frame(width: 8, height: 8)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: KXSpacing.xxs) {
                        Text(segment.label ?? segment.kind.displayName).font(KXFont.bodyEmphasis).foregroundStyle(KXColor.ink)
                        Text(format.segmentLength(segment.length)).font(KXFont.caption).foregroundStyle(KXColor.inkSecondary)
                    }
                    Spacer()
                    if let target = segment.targetPace {
                        Text(format.paceRange(target))
                            .font(KXFont.callout.monospacedDigit())
                            .foregroundStyle(segment.kind == .work ? KXColor.accent : KXColor.inkSecondary)
                    }
                }
                .accessibilityElement(children: .combine)
            }
        }
        .kxCard()
    }

    private func strengthCard(_ prescription: StrengthPrescription) -> some View {
        VStack(alignment: .leading, spacing: KXSpacing.md) {
            KXSectionHeader("Exercises")
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
                        Text(exercise.weightKg.map { format.weight($0) } ?? "Bodyweight")
                            .font(KXFont.caption).foregroundStyle(KXColor.inkSecondary)
                    }
                }
                .accessibilityElement(children: .combine)
            }
        }
        .kxCard()
    }
}
