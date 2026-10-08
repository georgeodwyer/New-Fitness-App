import SwiftUI

/// The "– 105.0 +" number stepper used for logging weight and reps.
struct KXStepper: View {
    let label: String
    @Binding var value: Double
    var step: Double = 1
    var range: ClosedRange<Double> = 0...10_000
    var unit: String?
    var format: (Double) -> String = { String(format: "%g", $0) }

    var body: some View {
        VStack(spacing: KXSpacing.xs) {
            KXOverline(label)
            HStack(spacing: KXSpacing.sm) {
                KXIconButton(systemImage: "minus", accessibilityLabel: "Decrease \(label)", variant: .neutral, size: 36) {
                    value = max(range.lowerBound, value - step)
                }
                VStack(spacing: 0) {
                    Text(format(value))
                        .font(KXFont.metricSmall)
                        .foregroundStyle(KXColor.ink)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                    if let unit {
                        Text(unit).font(KXFont.caption).foregroundStyle(KXColor.inkSecondary)
                    }
                }
                .frame(minWidth: 64)
                KXIconButton(systemImage: "plus", accessibilityLabel: "Increase \(label)", variant: .neutral, size: 36) {
                    value = min(range.upperBound, value + step)
                }
            }
        }
        .padding(KXSpacing.md)
        .background(KXColor.surfaceTint, in: RoundedRectangle(cornerRadius: KXRadius.sm, style: .continuous))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
        .accessibilityValue([format(value), unit].compactMap { $0 }.joined(separator: " "))
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: value = min(range.upperBound, value + step)
            case .decrement: value = max(range.lowerBound, value - step)
            @unknown default: break
            }
        }
    }
}
