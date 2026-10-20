import SwiftUI
import TrainingEngine

/// Edits onboarding answers on the onboarding screens: one question, or several in a row
/// with a progress bar. The last screen saves; × cancels.
struct ProfileQuestionsView: View {
    @Bindable var model: OnboardingModel
    let steps: [OnboardingModel.Step]
    let onCancel: () -> Void
    let onSave: () -> Void

    @State private var index = 0

    private var step: OnboardingModel.Step { steps[min(index, steps.count - 1)] }
    private var isLast: Bool { index >= steps.count - 1 }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: KXSpacing.sm) {
                if steps.count > 1 {
                    KXStepProgress(step: index + 1, total: steps.count,
                                   onBack: index == 0 ? nil : { withAnimation { index -= 1 } })
                } else {
                    Text("Training profile")
                        .font(KXFont.captionEmphasis)
                        .foregroundStyle(KXColor.inkSecondary)
                    Spacer()
                }
                KXIconButton(systemImage: "xmark", accessibilityLabel: "Cancel", size: 36, action: onCancel)
                    .accessibilityIdentifier("profileEdit.cancel")
            }
            .padding(.horizontal, KXSpacing.screenMargin)
            .padding(.vertical, KXSpacing.md)

            ScrollView {
                VStack(alignment: .leading, spacing: KXSpacing.xl) {
                    OnboardingStepContent(step: step, model: model)
                }
                .padding(KXSpacing.screenMargin)
                .frame(maxWidth: .infinity, alignment: .leading)
                .id(step)
                .transition(.asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity), removal: .opacity))
            }
            .scrollDismissesKeyboard(.interactively)

            VStack(spacing: KXSpacing.sm) {
                Button(isLast ? "Save" : "Continue") {
                    if isLast { onSave() } else { withAnimation { index += 1 } }
                }
                .buttonStyle(.kx(.primary, fullWidth: true))
                .disabled(!model.canContinue)
                .opacity(model.canContinue ? 1 : 0.5)
                .accessibilityIdentifier("profileEdit.primary")
                if model.isOptional {
                    Button("Clear this answer") {
                        model.clear(step)
                        if isLast { onSave() } else { withAnimation { index += 1 } }
                    }
                    .buttonStyle(.kx(.outlined, fullWidth: true))
                }
            }
            .padding(KXSpacing.screenMargin)
            .background(KXColor.background)
        }
        .background(KXColor.background.ignoresSafeArea())
        .tint(KXColor.accent)
        // The model's own step drives "can continue" and "optional" for this screen.
        .onAppear { model.step = step }
        .onChange(of: index) { model.step = step }
    }
}
