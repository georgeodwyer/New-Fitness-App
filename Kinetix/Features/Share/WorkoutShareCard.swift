import SwiftUI
import UIKit
import TrainingEngine

/// A saved run workout as a 4:5 card for social media (1080 × 1350 at 3×), in the app's dark
/// Volt look: name, the coloured bar, each block and the total.
struct WorkoutShareCardView: View {
    let workout: CustomRunWorkout
    let units: UnitSystem
    let defaultPace: Pace

    static let size = CGSize(width: 360, height: 450)

    private var totals: String {
        let estimate = workout.estimate(defaultPace: defaultPace)
        return "≈ " + DisplayFormat(units: units).distance(estimate.distanceMeters) + " · " + Units.formatMinutesSeconds(estimate.durationSeconds)
    }

    /// "Warm-up · 2 km", "8 × 1 min @ 4:28–4:34/km + 1 min easy".
    private var blockLines: [(text: String, color: Color)] {
        workout.blocks.map { block in
            let steps = block.steps.map { CustomRunWorkout.describe($0, units: units) }.joined(separator: " + ")
            let text = block.repeats > 1 ? "\(block.repeats) × \(steps)" : steps
            let color: Color = block.steps.contains { $0.kind == .work } ? CardColor.warn : CardColor.run
            return (text, color)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text(workout.type.displayName.uppercased())
                    .font(CardFont.label(13)).tracking(1.4).foregroundStyle(CardColor.run)
                Text(workout.name.uppercased())
                    .font(CardFont.condensed(36)).foregroundStyle(CardColor.ink)
                    .lineLimit(2).minimumScaleFactor(0.6)
            }
            if let structure = workout.structure, !structure.segments.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    SessionStructureBar(structure: structure).frame(height: 16)
                    HStack(spacing: 14) {
                        legend("Easy", CardColor.run)
                        legend("Work", CardColor.warn)
                        legend("Recovery", CardColor.slate)
                    }
                }
            }
            VStack(alignment: .leading, spacing: 8) {
                ForEach(Array(blockLines.prefix(7).enumerated()), id: \.offset) { _, line in
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Circle().fill(line.color).frame(width: 7, height: 7)
                        Text(line.text).font(CardFont.text(14, .medium)).foregroundStyle(CardColor.ink)
                            .lineLimit(2).fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(CardColor.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            Spacer(minLength: 0)
            HStack(alignment: .lastTextBaseline) {
                VStack(alignment: .leading, spacing: 0) {
                    Text("TOTAL").font(CardFont.label(12)).tracking(1.2).foregroundStyle(CardColor.inkSecondary)
                    Text(totals).font(CardFont.condensed(26)).foregroundStyle(CardColor.volt)
                }
                Spacer()
                KXWordmark(height: 18, forcedWhite: true)
            }
        }
        .padding(24)
        .frame(width: Self.size.width, height: Self.size.height, alignment: .topLeading)
        .background(CardColor.ground)
        .environment(\.colorScheme, .dark)
    }

    private func legend(_ name: String, _ color: Color) -> some View {
        HStack(spacing: 5) {
            Circle().fill(color).frame(width: 8, height: 8)
            Text(name).font(CardFont.text(11)).foregroundStyle(CardColor.inkSecondary)
        }
    }
}

/// Preview a saved workout's card, then share it, save it or post it to Stories.
struct ShareWorkoutSheet: View {
    let workout: CustomRunWorkout
    let units: UnitSystem
    let defaultPace: Pace

    @Environment(\.dismiss) private var dismiss
    @State private var rendered: UIImage?
    @State private var savedMessage: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: KXSpacing.lg) {
                    if let rendered {
                        Image(uiImage: rendered).resizable().scaledToFit()
                            .clipShape(RoundedRectangle(cornerRadius: KXRadius.md))
                            .frame(maxWidth: 320)
                            .accessibilityLabel("Preview of \(workout.name)")
                    } else {
                        ProgressView().frame(height: 300)
                    }
                    if let savedMessage {
                        Label(savedMessage, systemImage: "checkmark.circle.fill").font(KXFont.callout).symbolRenderingMode(.multicolor)
                    }
                }
                .padding(KXSpacing.screenMargin)
                .frame(maxWidth: .infinity)
            }
            .background(KXColor.background.ignoresSafeArea())
            .safeAreaInset(edge: .bottom) {
                if let rendered {
                    VStack(spacing: KXSpacing.sm) {
                        ShareLink(item: ShareImage(image: rendered), preview: SharePreview(workout.name, image: Image(uiImage: rendered))) {
                            Label("Share…", systemImage: "square.and.arrow.up")
                        }
                        .buttonStyle(.kx(.primary, fullWidth: true))
                        .accessibilityIdentifier("shareWorkout.share")
                        HStack(spacing: KXSpacing.sm) {
                            Button {
                                UIImageWriteToSavedPhotosAlbum(rendered, nil, nil, nil)
                                savedMessage = "Saved to Photos"
                            } label: {
                                Label("Save", systemImage: "square.and.arrow.down")
                            }
                            .buttonStyle(.kx(.outlined, fullWidth: true))
                            if ShareService.canShareToInstagramStories {
                                Button {
                                    ShareService.shareToInstagramStories(sticker: rendered, background: nil)
                                } label: {
                                    Label("Stories", systemImage: "camera.circle")
                                }
                                .buttonStyle(.kx(.outlined, fullWidth: true))
                            }
                        }
                    }
                    .padding(KXSpacing.screenMargin)
                    .background(KXColor.background)
                }
            }
            .navigationTitle("Share workout")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } } }
        }
        .tint(KXColor.accent)
        .onAppear { rendered = ShareService.renderWorkout(workout, units: units, defaultPace: defaultPace) }
    }
}

extension ShareService {
    /// A saved workout's share card at 3× (1080 × 1350).
    static func renderWorkout(_ workout: CustomRunWorkout, units: UnitSystem, defaultPace: Pace) -> UIImage? {
        let renderer = ImageRenderer(content: WorkoutShareCardView(workout: workout, units: units, defaultPace: defaultPace))
        renderer.scale = 3
        return renderer.uiImage
    }
}
