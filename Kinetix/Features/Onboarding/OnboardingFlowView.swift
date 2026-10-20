import SwiftUI
import SwiftData
import TrainingEngine

/// Onboarding: one question per screen with a progress indicator, then a plan preview.
struct OnboardingFlowView: View {
    /// Closes the flow without building a plan (shown as an × in the corner).
    var onClose: (() -> Void)? = nil
    @State private var model = OnboardingModel()
    @State private var preview: PlanService.Preview?
    @State private var showSignIn = false
    @State private var auth = AuthService.shared

    var body: some View {
        if let preview {
            PlanPreviewView(model: model, preview: preview) { self.preview = nil }
        } else {
            questions
        }
    }

    private var questions: some View {
        VStack(spacing: 0) {
            HStack(spacing: KXSpacing.sm) {
                KXStepProgress(
                    step: model.stepNumber,
                    total: model.totalSteps,
                    onBack: model.step == .units ? nil : { withAnimation { model.back() } }
                )
                if let onClose {
                    KXIconButton(systemImage: "xmark", accessibilityLabel: "Close", size: 36, action: onClose)
                        .accessibilityIdentifier("onboarding.close")
                }
            }
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
        .sheet(isPresented: $showSignIn) { AuthView(mode: .signIn) }
    }

    private var footer: some View {
        VStack(spacing: KXSpacing.sm) {
            if model.step == .finish {
                Button("Build my plan") {
                    preview = PlanService.preview(for: model.profile)
                }
                .buttonStyle(.kx(.primary, fullWidth: true))
                .disabled(!model.canContinue)
                .opacity(model.canContinue ? 1 : 0.5)
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
            if model.step == .units && auth.state == .signedOut {
                Button("Already have an account? Sign in") { showSignIn = true }
                    .font(KXFont.callout)
                    .foregroundStyle(KXColor.accent)
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

    private var stepContent: some View {
        OnboardingStepContent(step: model.step, model: model)
    }
}

/// The question screen for one onboarding step (also used to edit answers from Settings).
struct OnboardingStepContent: View {
    let step: OnboardingModel.Step
    @Bindable var model: OnboardingModel

    var body: some View {
        switch step {
        case .units: UnitsStep(model: model)
        case .runningExperience: RunningExperienceStep(model: model)
        case .raceTime: RaceTimeStep(model: model)
        case .currentRunning: CurrentRunningStep(model: model)
        case .liftingExperience: LiftingExperienceStep(model: model)
        case .liftEstimates: LiftEstimatesStep(model: model)
        case .goal: GoalStep(model: model)
        case .eventDate: EventDateStep(model: model)
        case .trainingDays: TrainingDaysStep(model: model)
        case .doubleSessions: DoubleSessionsStep(model: model)
        case .equipment: EquipmentStep(model: model)
        case .finish: FinishStep(model: model)
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
