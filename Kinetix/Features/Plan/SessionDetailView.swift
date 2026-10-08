import SwiftUI
import SwiftData
import TrainingEngine

/// What a planned session involves: run segments with target paces, or exercises
/// with sets × reps × weight.
struct SessionDetailView: View {
    let session: PlannedSessionModel
    @Query private var profiles: [UserProfileModel]
    @Environment(AppRouter.self) private var router

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
                if let reason = session.changeReason {
                    Label(reason, systemImage: "arrow.triangle.2.circlepath").font(KXFont.callout).kxCard(.accent)
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
            if session.status == .planned, session.kind.discipline != .crossTraining {
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
