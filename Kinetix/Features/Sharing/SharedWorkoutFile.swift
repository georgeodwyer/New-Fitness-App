import SwiftUI
import UniformTypeIdentifiers
import TrainingEngine

extension UTType {
    /// A run workout shared with a friend (".kinetixrun").
    static let kinetixRun = UTType(exportedAs: "com.georgeodwyer.kinetix.run-workout")
}

/// A run workout as a file for the share sheet: written when it's shared, named after the workout.
struct SharedWorkoutFile: Transferable {
    let shared: SharedRunWorkout

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(exportedContentType: .kinetixRun) { file in
            let name = file.shared.name.trimmingCharacters(in: .whitespaces)
            let safe = String((name.isEmpty ? "Run" : name).map { "/:\\?%*|\"<>".contains($0) ? "-" : $0 })
            let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let url = folder.appendingPathComponent(safe).appendingPathExtension("kinetixrun")
            try (file.shared.encoded() ?? Data()).write(to: url)
            return SentTransferredFile(url)
        }
    }

    /// Reads a shared workout from a file opened in Kinetix (nil if it isn't one).
    static func read(_ url: URL) -> SharedRunWorkout? {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        guard let data = try? Data(contentsOf: url) else { return nil }
        return SharedRunWorkout.decode(data)
    }
}

/// "Share with a friend": sends the workout's structure; their paces come from their own zones.
struct ShareWorkoutButton: View {
    let workout: CustomRunWorkout
    let zones: PaceZones

    var body: some View {
        ShareLink(item: SharedWorkoutFile(shared: SharedRunWorkout(workout, zones: zones)),
                  preview: SharePreview(workout.name.isEmpty ? "Run workout" : workout.name)) {
            Image(systemName: "square.and.arrow.up")
        }
        .accessibilityLabel("Share with a friend")
        .accessibilityIdentifier("workout.share")
    }
}

/// A workout a friend sent: what it is, with the paces worked out for you, then save it.
struct ImportSharedWorkoutSheet: View {
    let shared: SharedRunWorkout
    let zones: PaceZones?
    let units: UnitSystem
    let onSave: (CustomRunWorkout) -> Void
    @Environment(\.dismiss) private var dismiss

    private var workout: CustomRunWorkout { shared.workout(for: zones) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: KXSpacing.lg) {
                    VStack(alignment: .leading, spacing: KXSpacing.xs) {
                        KXOverline("Workout from a friend", color: KXColor.accent)
                        Text(workout.name.isEmpty ? "Run" : workout.name).font(KXFont.display).foregroundStyle(KXColor.ink)
                        Text(workout.type.displayName).font(KXFont.callout).foregroundStyle(KXColor.inkSecondary)
                    }
                    VStack(alignment: .leading, spacing: KXSpacing.md) {
                        if let structure = workout.structure, structure.segments.count > 1 {
                            SessionStructureBar(structure: structure).frame(height: 12)
                        }
                        ForEach(Array(zip(shared.blocks, workout.blocks).enumerated()), id: \.offset) { _, pair in
                            blockRow(shared: pair.0, mine: pair.1)
                        }
                    }
                    .kxCard()
                    Text(zones != nil
                         ? "Paces are set from your own training zones, at the same effort your friend runs it. You can change any step after saving."
                         : "These are your friend's paces. Set up your training profile and shared workouts will use your own paces.")
                        .font(KXFont.caption).foregroundStyle(KXColor.inkTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(KXSpacing.screenMargin)
            }
            .background(KXColor.background.ignoresSafeArea())
            .safeAreaInset(edge: .bottom) {
                Button("Save to my workouts") {
                    onSave(workout)
                    dismiss()
                }
                .buttonStyle(.kx(.primary, fullWidth: true))
                .accessibilityIdentifier("import.save")
                .padding(KXSpacing.screenMargin)
                .background(KXColor.background)
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            }
        }
    }

    private func blockRow(shared: SharedRunWorkout.Block, mine: RunBlock) -> some View {
        VStack(alignment: .leading, spacing: KXSpacing.xs) {
            if mine.repeats > 1 {
                Text("\(mine.repeats) ×").font(KXFont.captionEmphasis).foregroundStyle(KXColor.inkSecondary)
            }
            ForEach(Array(zip(shared.steps, mine.steps).enumerated()), id: \.offset) { _, pair in
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(pair.1.kind.builderName) · \(lengthText(pair.1.length))")
                            .font(KXFont.bodyEmphasis).foregroundStyle(KXColor.ink)
                        if let effort = pair.0.effort {
                            Text("\(SharedRunWorkout.effortName(effort)) effort").font(KXFont.caption).foregroundStyle(KXColor.inkSecondary)
                        }
                    }
                    Spacer()
                    Text(pair.1.target?.formatted(units) ?? "No target")
                        .font(KXFont.body.monospacedDigit()).foregroundStyle(KXColor.inkSecondary)
                }
                .accessibilityElement(children: .combine)
            }
        }
    }

    private func lengthText(_ length: SegmentLength) -> String {
        switch length {
        case .distance(let meters):
            let format = DisplayFormat(units: units)
            return meters < 1000 ? format.shortDistance(meters) : format.distance(meters)
        case .duration(let seconds): return Units.formatMinutesSeconds(seconds)
        }
    }
}
