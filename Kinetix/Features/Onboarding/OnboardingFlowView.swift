import SwiftUI
import SwiftData
import TrainingEngine

/// Onboarding: one question per screen with a progress indicator, then a plan preview.
struct OnboardingFlowView: View {
    @State private var model = OnboardingModel()
    @State private var preview: PlanService.Preview?

    var body: some View {
        if let preview {
            PlanPreviewView(model: model, preview: preview) { self.preview = nil }
        } else {
            questions
        }
    }

    private var questions: some View {
        VStack(spacing: 0) {
            KXStepProgress(
                step: model.stepNumber,
                total: model.totalSteps,
                onBack: model.step == .units ? nil : { withAnimation { model.back() } }
            )
            .padding(.horizontal, KXSpacing.screenMargin)
            .padding(.vertical, KXSpacing.md)

            ScrollView {
                VStack(alignment: .leading, spacing: KXSpacing.xl) {
                    stepContent
                }
                .padding(KXSpacing.screenMargin)
                .frame(maxWidth: .infinity, alignment: .leading)
                .id(model.step)
                .transition(.asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity), removal: .opacity))
            }
            .scrollDismissesKeyboard(.interactively)

            footer
        }
        .background(KXColor.background.ignoresSafeArea())
    }

    private var footer: some View {
        VStack(spacing: KXSpacing.sm) {
            if model.step == .finish {
                Button("Build my plan") {
                    preview = PlanService.preview(for: model.profile)
                }
                .buttonStyle(.kx(.primary, fullWidth: true))
            } else {
                Button("Continue") { withAnimation { model.next() } }
                    .buttonStyle(.kx(.primary, fullWidth: true))
                    .disabled(!model.canContinue)
                    .opacity(model.canContinue ? 1 : 0.5)
                if model.isOptional {
                    Button("Skip") { withAnimation { model.skip() } }
                        .buttonStyle(.kx(.outlined, fullWidth: true))
                }
            }
            #if DEBUG
            if model.step == .units {
                Button("Use sample answers (developer)") { model.fillSampleAnswers() }
                    .font(KXFont.caption)
                    .foregroundStyle(KXColor.inkTertiary)
            }
            #endif
        }
        .padding(KXSpacing.screenMargin)
        .background(KXColor.background)
    }

    @ViewBuilder
    private var stepContent: some View {
        switch model.step {
        case .units: UnitsStep(model: model)
        case .runningExperience: RunningExperienceStep(model: model)
        case .raceTime: RaceTimeStep(model: model)
        case .liftingExperience: LiftingExperienceStep(model: model)
        case .liftEstimates: LiftEstimatesStep(model: model)
        case .goal: GoalStep(model: model)
        case .eventDate: EventDateStep(model: model)
        case .trainingDays: TrainingDaysStep(model: model)
        case .doubleSessions: DoubleSessionsStep(model: model)
        case .equipment: EquipmentStep(model: model)
        case .finish: FinishStep()
        }
    }
}

/// Shared heading for each question.
struct OnboardingQuestion: View {
    let plain: String
    let accented: String
    let detail: String

    var body: some View {
        VStack(alignment: .leading, spacing: KXSpacing.sm) {
            KXAccentHeadline(plain: plain, accented: accented)
                .accessibilityAddTraits(.isHeader)
            Text(detail)
                .font(KXFont.body)
                .foregroundStyle(KXColor.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

#Preview {
    OnboardingFlowView()
        .modelContainer(try! Persistence.makeContainer(inMemory: true))
}
