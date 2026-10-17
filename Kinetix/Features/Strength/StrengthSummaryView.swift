import SwiftUI
import SwiftData
import TrainingEngine

/// After a workout: totals, new records and what changes next time (and why).
struct StrengthSummaryView: View {
    let summary: StrengthService.Summary
    let units: UnitSystem
    /// The saved workout (for "Upload to Strava").
    var log: StrengthLogModel? = nil
    let onDone: () -> Void

    @Environment(\.modelContext) private var context
    @State private var strava = StravaService.shared
    @State private var settings = IntegrationSettings.shared
    @State private var uploading = false
    @State private var uploadError: String?

    private var format: DisplayFormat { DisplayFormat(units: units) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: KXSpacing.xl) {
                VStack(alignment: .leading, spacing: KXSpacing.xs) {
                    KXOverline("Workout complete", color: KXColor.success)
                    Text(summary.title).font(KXFont.display).foregroundStyle(KXColor.ink)
                }
                HStack {
                    KXMetric(label: "Time", value: Units.formatMinutesSeconds(summary.durationSeconds), size: .small)
                    Spacer()
                    KXMetric(label: "Volume", value: Units.formatWeight(kg: summary.volumeKg, units: units),
                             unit: Units.weightUnitLabel(units), size: .small)
                    Spacer()
                    KXMetric(label: "Sets", value: "\(summary.completedSets)", size: .small)
                    Spacer()
                    KXMetric(label: "Load", value: "\(Int(summary.load))", unit: "AU", size: .small)
                }
                .kxCard()

                if !summary.records.isEmpty {
                    VStack(alignment: .leading, spacing: KXSpacing.md) {
                        KXSectionHeader("New personal records")
                        ForEach(summary.records) { item in
                            HStack {
                                Image(systemName: "trophy.fill").foregroundStyle(KXColor.accent).accessibilityHidden(true)
                                VStack(alignment: .leading, spacing: KXSpacing.xxs) {
                                    Text(item.exerciseName).font(KXFont.bodyEmphasis)
                                    Text(item.record.kind.displayName).font(KXFont.caption).foregroundStyle(KXColor.inkSecondary)
                                }
                                Spacer()
                                Text(format.weight(item.record.value)).font(KXFont.bodyEmphasis.monospacedDigit())
                            }
                            .accessibilityElement(children: .combine)
                        }
                    }
                    .kxCard(.accent)
                }

                if let log, strava.isConnected, !settings.stravaUploadLifts {
                    stravaCard(log)
                }

                if !summary.changes.isEmpty {
                VStack(alignment: .leading, spacing: KXSpacing.md) {
                    KXSectionHeader("Next time", subtitle: "How your weights progress")
                    ForEach(summary.changes) { change in
                        HStack(alignment: .top, spacing: KXSpacing.md) {
                            Image(systemName: symbol(for: change.change))
                                .foregroundStyle(color(for: change.change))
                                .frame(width: 24)
                                .accessibilityHidden(true)
                            Text(change.reason).font(KXFont.callout).foregroundStyle(KXColor.ink)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                .kxCard()
                }
            }
            .padding(KXSpacing.screenMargin)
        }
        .safeAreaInset(edge: .bottom) {
            Button("Done", action: onDone)
                .buttonStyle(.kx(.primary, fullWidth: true))
                .padding(KXSpacing.screenMargin)
                .background(KXColor.background)
        }
        .background(KXColor.background.ignoresSafeArea())
    }

    private func stravaCard(_ log: StrengthLogModel) -> some View {
        VStack(alignment: .leading, spacing: KXSpacing.sm) {
            if let id = log.stravaActivityId {
                Label("On Strava", systemImage: "checkmark.circle.fill")
                    .font(KXFont.bodyEmphasis).foregroundStyle(KXColor.ink)
                    .symbolRenderingMode(.multicolor)
                if let url = URL(string: "https://www.strava.com/activities/\(id)") {
                    Link("View on Strava", destination: url)
                        .font(KXFont.captionEmphasis)
                        .foregroundStyle(StravaView.brand)
                }
            } else {
                Button {
                    Task {
                        uploading = true
                        uploadError = nil
                        do {
                            try await ActivityExportService.uploadStrengthToStrava(log, units: units, in: context)
                        } catch {
                            uploadError = error.localizedDescription
                        }
                        uploading = false
                    }
                } label: {
                    Label(uploading ? "Uploading…" : "Upload to Strava", systemImage: "arrow.up.forward.app")
                        .font(KXFont.bodyEmphasis)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity, minHeight: 48)
                        .background(StravaView.brand, in: RoundedRectangle(cornerRadius: KXRadius.sm, style: .continuous))
                }
                .buttonStyle(.plain)
                .disabled(uploading)
                .accessibilityIdentifier("strength.uploadStrava")
                if let uploadError {
                    Text(uploadError).font(KXFont.caption).foregroundStyle(KXColor.ink)
                }
            }
        }
        .kxCard()
    }

    private func symbol(for change: ProgressionDecision.Change) -> String {
        switch change {
        case .increase: return "arrow.up.circle.fill"
        case .deload: return "arrow.down.circle.fill"
        case .hold, .none: return "equal.circle.fill"
        }
    }

    private func color(for change: ProgressionDecision.Change) -> Color {
        switch change {
        case .increase: return KXColor.success
        case .deload: return KXColor.warning
        case .hold, .none: return KXColor.slate
        }
    }
}
