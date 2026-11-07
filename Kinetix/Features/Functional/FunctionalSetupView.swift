import SwiftUI
import SwiftData
import TrainingEngine

/// Workout → Functional: a Hyrox simulation, your saved functional workouts, and the builder.
struct FunctionalSetupView: View {
    @Environment(\.modelContext) private var context
    @Environment(AppRouter.self) private var router
    @Query(filter: #Predicate<FunctionalTemplateModel> { $0.deletedAt == nil }, sort: \FunctionalTemplateModel.createdAt, order: .reverse)
    private var templates: [FunctionalTemplateModel]
    @Query(filter: #Predicate<UserProfileModel> { $0.deletedAt == nil }) private var profiles: [UserProfileModel]

    @State private var division: HyroxDivision = .openMen
    @State private var treadmill = false
    @State private var pickedDivision = false

    private var units: UnitSystem { profiles.first?.units ?? UnitPreference.stored }

    /// Most recently used first.
    private var sortedTemplates: [FunctionalTemplateModel] {
        templates.sorted { ($0.lastUsedAt ?? $0.createdAt) > ($1.lastUsedAt ?? $1.createdAt) }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: KXSpacing.xl) {
                Text("Circuits and Hyrox-style sessions: runs, SkiErg, rower, sled and any gym exercise, done in rounds, intervals, EMOM or AMRAP. Tap Next as you finish each station.")
                    .font(KXFont.callout)
                    .foregroundStyle(KXColor.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                hyroxCard

                VStack(alignment: .leading, spacing: KXSpacing.md) {
                    KXSectionHeader("My functional workouts", subtitle: templates.isEmpty ? nil : "Tap to edit · ▶ to start")
                    if sortedTemplates.isEmpty {
                        KXEmptyState(symbol: "bookmark", title: "No saved workouts yet",
                                     message: "Build one (say 4 rounds of 1 km run, 500 m row, 20 wall balls) to start it with one tap.")
                    }
                    ForEach(sortedTemplates) { template in
                        KXSwipeToDelete {
                            withAnimation {
                                template.softDelete()
                                try? context.save()
                            }
                            SyncService.shared.requestSync()
                        } content: {
                            templateRow(template)
                        }
                    }
                    NavigationLink {
                        FunctionalEditorView(template: nil)
                    } label: {
                        Label("Build a functional workout", systemImage: "plus")
                    }
                    .buttonStyle(.kx(.secondary, fullWidth: true))
                    .accessibilityIdentifier("functional.build")
                }
                .kxCard()
            }
            .padding(KXSpacing.screenMargin)
        }
        .background(KXColor.background.ignoresSafeArea())
        .navigationTitle("Functional")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            guard !pickedDivision else { return }
            pickedDivision = true
            if let saved = profiles.first?.profile.hyroxDivision { division = saved }
        }
    }

    private var hyroxCard: some View {
        let race = HyroxSimulation.workout(division: division, treadmill: treadmill)
        return VStack(alignment: .leading, spacing: KXSpacing.md) {
            HStack {
                Image(systemName: "flag.checkered")
                    .foregroundStyle(KXColor.functional)
                    .frame(width: 36, height: 36)
                    .background(KXColor.functional.opacity(0.14), in: Circle())
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Hyrox simulation").font(KXFont.bodyEmphasis).foregroundStyle(KXColor.ink)
                    Text("8 × 1 km run + station, race order").font(KXFont.caption).foregroundStyle(KXColor.inkSecondary)
                }
                Spacer()
            }
            Picker("Division", selection: $division) {
                ForEach(HyroxDivision.allCases, id: \.self) { Text($0.displayName).tag($0) }
            }
            .pickerStyle(.menu)
            .tint(KXColor.ink)
            Toggle("Runs on a treadmill", isOn: $treadmill)
                .font(KXFont.callout)
                .tint(KXColor.accent)
            Text(race.stations.filter { $0.kind != .run }.map { station in
                station.weightKg.map { "\(station.name) \(DisplayFormat(units: units).weight($0))" } ?? station.name
            }.joined(separator: " · "))
                .font(KXFont.caption)
                .foregroundStyle(KXColor.inkTertiary)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: KXSpacing.sm) {
                Button {
                    start(race, templateId: nil)
                } label: {
                    Label("Start", systemImage: "play.fill").frame(maxWidth: .infinity)
                }
                .buttonStyle(.kx(.primary, fullWidth: true))
                .accessibilityIdentifier("functional.hyrox.start")
                NavigationLink {
                    FunctionalEditorView(template: nil, initial: FunctionalWorkout(name: "My Hyrox simulation", format: race.format,
                                                                                    stations: race.stations))
                } label: {
                    Label("Edit a copy", systemImage: "square.on.square").frame(maxWidth: .infinity)
                }
                .buttonStyle(.kx(.outlined, fullWidth: true))
            }
        }
        .kxCard()
    }

    private func templateRow(_ template: FunctionalTemplateModel) -> some View {
        let workout = template.workout
        return HStack(spacing: KXSpacing.md) {
            NavigationLink {
                FunctionalEditorView(template: template)
            } label: {
                VStack(alignment: .leading, spacing: 2) {
                    Text(workout.name).font(KXFont.bodyEmphasis).foregroundStyle(KXColor.ink)
                    Text(workout.summary).font(KXFont.caption).foregroundStyle(KXColor.inkSecondary)
                    Text(workout.stations.map(\.title).joined(separator: ", "))
                        .font(KXFont.caption).foregroundStyle(KXColor.inkTertiary).lineLimit(2)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            Button {
                start(workout, templateId: template.id)
            } label: {
                Image(systemName: "play.fill")
                    .foregroundStyle(KXColor.onAccent)
                    .frame(width: 44, height: 44)
                    .background(KXColor.accent, in: Circle())
            }
            .accessibilityLabel("Start \(workout.name)")
            .disabled(workout.stations.isEmpty)
        }
        .padding(KXSpacing.md)
        .background(KXColor.surfaceTint, in: RoundedRectangle(cornerRadius: KXRadius.sm, style: .continuous))
    }

    private func start(_ workout: FunctionalWorkout, templateId: UUID?) {
        guard !workout.stations.isEmpty else { return }
        router.start(ActiveSession(id: UUID(), kind: .crossTraining, title: workout.name, functional: workout,
                                   functionalTemplateId: templateId))
    }
}
