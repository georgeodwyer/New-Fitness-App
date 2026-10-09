import SwiftUI
import TrainingEngine

/// Every design-system component on one screen, for checking against the Stitch designs
/// (try it in light and dark mode, and with large Dynamic Type sizes).
struct DesignGalleryView: View {
    @State private var weight = 105.0
    @State private var reps = 6.0
    @State private var selectedDays: Set<Weekday> = [.monday, .wednesday, .friday]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: KXSpacing.xl) {
                KXScreenHeader(title: "Design System", onNotifications: {})

                group("Colours") {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 70))], spacing: KXSpacing.sm) {
                        swatch("Accent", KXColor.accent)
                        swatch("Accent soft", KXColor.accentSoft)
                        swatch("Ink", KXColor.ink)
                        swatch("Ink 2", KXColor.inkSecondary)
                        swatch("Surface", KXColor.surface)
                        swatch("Tint", KXColor.surfaceTint)
                        swatch("Teal", KXColor.teal)
                        swatch("Slate", KXColor.slate)
                        swatch("Run", KXColor.run)
                        swatch("Lift", KXColor.lift)
                        swatch("Success", KXColor.success)
                        swatch("Warning", KXColor.warning)
                        swatch("Danger", KXColor.danger)
                        swatch("Inverted", KXColor.inverted)
                    }
                }

                group("Type") {
                    KXAccentHeadline(plain: "Calibrate your", accented: "Hybrid Engine")
                    Text("Running Trainer").font(KXFont.title)
                    Text("Barbell Back Squat").font(KXFont.headline)
                    Text("Body text for explanations and descriptions.").font(KXFont.body)
                    Text("Caption text").font(KXFont.caption).foregroundStyle(KXColor.inkSecondary)
                    KXOverline("Live telemetry HUD")
                }

                group("Buttons") {
                    HStack {
                        Button("Primary") {}.buttonStyle(.kxPrimary)
                        Button("Secondary") {}.buttonStyle(.kxSecondary)
                    }
                    HStack {
                        Button("Inverted") {}.buttonStyle(.kxInverted)
                        Button("Outlined") {}.buttonStyle(.kxOutlined)
                    }
                    Button("Start Lift") {}.buttonStyle(.kx(.primary, fullWidth: true))
                    HStack {
                        KXIconButton(systemImage: "play.fill", accessibilityLabel: "Play", variant: .accent) {}
                        KXIconButton(systemImage: "magnifyingglass", accessibilityLabel: "Search", variant: .neutral) {}
                        KXIconButton(systemImage: "headphones", accessibilityLabel: "Audio", variant: .tinted) {}
                    }
                }

                group("Chips & status") {
                    HStack {
                        KXChip(text: "Popular", variant: .primary)
                        KXChip(text: "Adaptive", systemImage: "bolt.fill")
                        KXChip(text: "Inverted", variant: .inverted)
                        KXChip(text: "Outlined", variant: .outlined)
                    }
                    HStack {
                        KXStatusPill(level: .low, text: "Undertrained")
                        KXStatusPill(level: .optimal, text: "Optimal")
                        KXStatusPill(level: .high, text: "High risk")
                    }
                    HStack(spacing: KXSpacing.xs) {
                        ForEach(Weekday.allCases, id: \.self) { day in
                            KXSelectableChip(text: day.shortName, isSelected: selectedDays.contains(day)) {
                                if selectedDays.contains(day) { selectedDays.remove(day) } else { selectedDays.insert(day) }
                            }
                        }
                    }
                }

                group("Metrics & progress") {
                    KXStepProgress(step: 2, total: 4, onBack: {})
                    HStack {
                        KXMetric(label: "Current pace", value: "4:42", unit: "/km", detail: "Target 4:45")
                        Spacer()
                        KXMetric(label: "Distance", value: "4.82", unit: "km")
                    }
                    KXProgressBar(value: 0.68)
                    HStack {
                        KXRingGauge(value: 0.92, label: "92%", caption: "Optimal").frame(width: 110, height: 110)
                        Spacer()
                        VStack {
                            KXStepper(label: "Load", value: $weight, step: 2.5, unit: "kg", format: { String(format: "%.1f", $0) })
                            KXStepper(label: "Reps", value: $reps, step: 1, format: { String(format: "%.0f", $0) })
                        }
                    }
                }

                group("Cards") {
                    KXSessionCard(overline: "Session A · Audio pacing", title: "Morning Tempo Run", detail: "6.5 km · Target 4:45/km", kind: .run(.tempo), onStart: {})
                    KXSessionCard(overline: "Session B · Hypertrophy", title: "Upper Body Strength", detail: "Chest & back · 18 working sets", kind: .strength(.upper), status: .completed)
                    Text("Tinted panel").kxCard(.tinted)
                    Text("Accent panel: \"Speed up · +5 s/km slow\"").kxCard(.accent)
                }
            }
            .padding(KXSpacing.screenMargin)
        }
        .background(KXColor.background.ignoresSafeArea())
        .navigationTitle("Design system")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func group<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: KXSpacing.md) {
            KXOverline(title, color: KXColor.accent)
            content()
        }
    }

    private func swatch(_ name: String, _ color: Color) -> some View {
        VStack(spacing: KXSpacing.xs) {
            RoundedRectangle(cornerRadius: KXRadius.sm)
                .fill(color)
                .frame(height: 44)
                .overlay(RoundedRectangle(cornerRadius: KXRadius.sm).strokeBorder(KXColor.border))
            Text(name).font(KXFont.caption).foregroundStyle(KXColor.inkSecondary)
        }
    }
}

#Preview {
    NavigationStack { DesignGalleryView() }
}
