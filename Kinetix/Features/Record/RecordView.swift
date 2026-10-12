import SwiftUI
import SwiftData
import TrainingEngine

/// The Record tab: start a run (or, soon, a gym session) without a plan, from scratch or
/// from a saved workout. Recorded sessions count towards training load like planned ones.
struct RecordView: View {
    @Query(filter: #Predicate<RunTemplateModel> { $0.deletedAt == nil }, sort: \RunTemplateModel.createdAt, order: .reverse)
    private var templates: [RunTemplateModel]
    @Query(filter: #Predicate<UserProfileModel> { $0.deletedAt == nil }) private var profiles: [UserProfileModel]
    @Environment(\.modelContext) private var context

    private var units: UnitSystem { profiles.first?.units ?? .metric }

    /// Most recently used first.
    private var sortedTemplates: [RunTemplateModel] {
        templates.sorted { ($0.lastUsedAt ?? $0.createdAt) > ($1.lastUsedAt ?? $1.createdAt) }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: KXSpacing.xl) {
                    KXScreenHeader(title: "Record")
                    Text("Track any run or gym session. It counts towards your training load, and goes to Apple Health and Strava if they're connected.")
                        .font(KXFont.callout).foregroundStyle(KXColor.inkSecondary)

                    HStack(spacing: KXSpacing.md) {
                        NavigationLink {
                            RunSetupView(initial: nil)
                        } label: {
                            choiceCard(title: "Run", detail: "Free run or your own workout with pace targets",
                                       symbol: "figure.run", tint: KXColor.run)
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("record.run")

                        choiceCard(title: "Gym", detail: "Build and track your own workouts",
                                   symbol: "dumbbell.fill", tint: KXColor.lift, badge: "Next update")
                            .opacity(0.6)
                            .accessibilityIdentifier("record.gym")
                    }

                    VStack(alignment: .leading, spacing: KXSpacing.md) {
                        KXSectionHeader("My run workouts", subtitle: templates.isEmpty ? nil : "Tap to start or edit")
                        if sortedTemplates.isEmpty {
                            KXEmptyState(symbol: "bookmark", title: "No saved workouts yet",
                                         message: "Build a run (say 2 × 10 min at threshold) and tap \u{201C}Save as template\u{201D} to reuse it.")
                        }
                        ForEach(sortedTemplates) { template in
                            NavigationLink {
                                RunSetupView(initial: template)
                            } label: {
                                templateRow(template)
                            }
                            .buttonStyle(.plain)
                            .contextMenu {
                                Button(role: .destructive) {
                                    template.softDelete()
                                    try? context.save()
                                    SyncService.shared.requestSync()
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                        }
                    }
                    .kxCard()
                }
                .padding(KXSpacing.screenMargin)
            }
            .background(KXColor.background.ignoresSafeArea())
        }
    }

    private func choiceCard(title: String, detail: String, symbol: String, tint: Color, badge: String? = nil) -> some View {
        VStack(alignment: .leading, spacing: KXSpacing.sm) {
            HStack {
                Image(systemName: symbol)
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(.white)
                    .frame(width: 52, height: 52)
                    .background(tint, in: Circle())
                Spacer()
                if let badge { KXChip(text: badge, variant: .outlined) }
            }
            Text(title).font(KXFont.title).foregroundStyle(KXColor.ink)
            Text(detail).font(KXFont.caption).foregroundStyle(KXColor.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, minHeight: 170, alignment: .topLeading)
        .kxCard()
        .accessibilityElement(children: .combine)
    }

    private func templateRow(_ template: RunTemplateModel) -> some View {
        let workout = template.workout
        return HStack(spacing: KXSpacing.md) {
            Image(systemName: "figure.run")
                .foregroundStyle(KXColor.run)
                .frame(width: 36, height: 36)
                .background(KXColor.run.opacity(0.12), in: Circle())
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(workout.name).font(KXFont.bodyEmphasis).foregroundStyle(KXColor.ink)
                Text(workout.summary(units: units)).font(KXFont.caption).foregroundStyle(KXColor.inkSecondary).lineLimit(2)
            }
            Spacer()
            Image(systemName: "chevron.right").font(.caption).foregroundStyle(KXColor.inkTertiary).accessibilityHidden(true)
        }
        .padding(.vertical, KXSpacing.xxs)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}
