import SwiftUI

/// A number that can be typed as well as stepped: tap it to type a value (number keypad,
/// with a Done button), and it's checked and applied when you finish.
struct KXEditableNumber: View {
    /// The value as shown, e.g. "105" or "102.5".
    let display: String
    var font: Font = KXFont.bodyEmphasis
    /// Allow a decimal point (weights, distances); whole numbers otherwise (reps, sets).
    var allowsDecimal = true
    let accessibilityLabel: String
    /// Called with the typed number; the caller keeps it within range.
    let onCommit: (Double) -> Void

    @State private var isEditing = false
    @State private var text = ""
    @FocusState private var focused: Bool

    var body: some View {
        if isEditing {
            TextField(display, text: $text)
                .keyboardType(allowsDecimal ? .decimalPad : .numberPad)
                .multilineTextAlignment(.center)
                .font(font.monospacedDigit())
                .foregroundStyle(KXColor.ink)
                .focused($focused)
                .frame(minWidth: 48)
                .padding(.vertical, 2)
                .background(KXColor.surface, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).stroke(KXColor.accent, lineWidth: 1.5))
                .accessibilityLabel(accessibilityLabel)
                .onAppear {
                    // Start from the number alone (without its unit).
                    text = String(display.filter { $0.isNumber || $0 == "." || $0 == "," })
                    focused = true
                }
                .onChange(of: focused) { _, isFocused in
                    if !isFocused { commit() }
                }
                .onSubmit(commit)
                .toolbar {
                    ToolbarItemGroup(placement: .keyboard) {
                        Spacer()
                        Button("Done") { focused = false }
                            .font(KXFont.bodyEmphasis)
                    }
                }
        } else {
            Button {
                isEditing = true
            } label: {
                Text(display)
                    .font(font.monospacedDigit())
                    .foregroundStyle(KXColor.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .padding(.horizontal, 4)
                    .background(alignment: .bottom) {
                        // A faint underline says "tap to type".
                        Rectangle().fill(KXColor.border).frame(height: 1)
                    }
            }
            .buttonStyle(.plain)
            .accessibilityLabel(accessibilityLabel)
            .accessibilityValue(display)
            .accessibilityHint("Double-tap to type a number")
        }
    }

    private func commit() {
        guard isEditing else { return }
        isEditing = false
        let cleaned = text.replacingOccurrences(of: ",", with: ".").trimmingCharacters(in: .whitespaces)
        guard let number = Double(cleaned), number.isFinite else { return }
        onCommit(allowsDecimal ? number : number.rounded())
    }
}
