import SwiftUI
import TrainingEngine

/// Reorder the dashboard's cards (drag the handles) and switch them on or off.
struct EditDashboardView: View {
    let onSave: (DashboardLayout) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var layout: DashboardLayout

    init(layout: DashboardLayout, onSave: @escaping (DashboardLayout) -> Void) {
        _layout = State(initialValue: layout)
        self.onSave = onSave
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(layout.cards, id: \.self) { card in
                        Toggle(isOn: Binding(get: { !layout.isHidden(card) }, set: { layout.setHidden(card, !$0) })) {
                            Label(card.displayName, systemImage: card.symbol)
                                .foregroundStyle(layout.isHidden(card) ? KXColor.inkTertiary : KXColor.ink)
                        }
                        .tint(KXColor.accent)
                        .accessibilityIdentifier("dashboard.card.\(card.rawValue)")
                    }
                    .onMove { layout.move(fromOffsets: $0, toOffset: $1) }
                } footer: {
                    Text("Drag to reorder. Switched-off cards are hidden, not deleted. Your layout syncs to your account.")
                }
                Section {
                    Button("Reset to default") { layout = .default }
                        .disabled(layout.cards == DashboardCard.defaultOrder && layout.hiddenCards.isEmpty)
                        .accessibilityIdentifier("dashboard.reset")
                }
            }
            .environment(\.editMode, .constant(.active))
            .navigationTitle("Edit dashboard")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        onSave(layout)
                        dismiss()
                    }
                    .accessibilityIdentifier("dashboard.done")
                }
            }
        }
    }
}
