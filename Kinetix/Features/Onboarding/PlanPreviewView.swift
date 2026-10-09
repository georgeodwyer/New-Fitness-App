import SwiftUI
import SwiftData
import TrainingEngine

/// End of onboarding: shows the generated plan and saves it on "Start training".
struct PlanPreviewView: View {
    let model: OnboardingModel
    let preview: PlanService.Preview
    let onBack: () -> Void

    @Environment(\.modelContext) private var context

    private var format: DisplayFormat { DisplayFormat(units: model.units) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: KXSpacing.xl) {
                VStack(alignment: .leading, spacing: KXSpacing.sm) {
                    KXAccentHeadline(plain: "Your plan is", accented: "ready")
                    Text(summaryLine)
                        .font(KXFont.body)
                        .foregroundStyle(KXColor.inkSecondary)
                }
                phasesCard
                zonesCard
                firstWeekCard
            }
            .padding(KXSpacing.screenMargin)
        }
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: KXSpacing.sm) {
                Button("Start training") { save() }
                    .buttonStyle(.kx(.primary, fullWidth: true))
                Button("Change my answers", action: onBack)
                    .buttonStyle(.kx(.outlined, fullWidth: true))
            }
            .padding(KXSpacing.screenMargin)
            .background(KXColor.background)
        }
        .background(KXColor.background.ignoresSafeArea())
    }

    private var summaryLine: String {
        let weeks = preview.outline.weeks.count
        let start = preview.outline.startDate.formatted(.dateTime.weekday(.wide).day().month(.wide))
        if let event = preview.outline.eventDate {
            return "\(weeks) weeks to your event on \(event.formatted(.dateTime.day().month(.wide))). Starts \(start)."
        }
        return "A \(weeks)-week block that keeps rolling. Starts \(start)."
    }

    private var phasesCard: some View {
        VStack(alignment: .leading, spacing: KXSpacing.md) {
            KXSectionHeader("Phases", subtitle: "Weekly running builds by no more than 10%")
            ForEach(preview.outline.blocks, id: \.firstWeek) { block in
                HStack(alignment: .top) {
                    KXChip(text: block.phase.displayName, variant: block.phase == .taper ? .outlined : .secondary)
                    VStack(alignment: .leading, spacing: KXSpacing.xxs) {
                        Text("\(block.weekCount) week\(block.weekCount == 1 ? "" : "s")").font(KXFont.bodyEmphasis)
                        Text(block.phase.explanation).font(KXFont.caption).foregroundStyle(KXColor.inkSecondary)
                    }
                    Spacer()
                }
            }
            if let first = preview.outline.weeks.first, let peak = preview.outline.weeks.map(\.runVolumeMeters).max() {
                Divider()
                HStack {
                    KXMetric(label: "Week 1 running", value: format.distance(first.runVolumeMeters, decimals: 0), size: .small)
                    Spacer()
                    KXMetric(label: "Peak week", value: format.distance(peak, decimals: 0), size: .small)
                }
            }
        }
        .kxCard()
    }

    private var zonesCard: some View {
        VStack(alignment: .leading, spacing: KXSpacing.md) {
            KXSectionHeader("Your pace zones", subtitle: model.profile.recentRace == nil ? "Estimated from your experience; add a race time later for accuracy" : "From your race time")
            ForEach([PaceZone.easy, .marathon, .threshold, .interval], id: \.self) { zone in
                HStack {
                    Text(zone.displayName).font(KXFont.body).foregroundStyle(KXColor.ink)
                    Spacer()
                    Text(format.paceRange(preview.zones.range(for: zone)))
                        .font(KXFont.bodyEmphasis.monospacedDigit())
                        .foregroundStyle(KXColor.ink)
                }
                .accessibilityElement(children: .combine)
            }
        }
        .kxCard()
    }

    private var firstWeekCard: some View {
        VStack(alignment: .leading, spacing: KXSpacing.md) {
            KXSectionHeader("Your first week")
            if let week = preview.firstWeek {
                ForEach(Array(week.sessions.enumerated()), id: \.offset) { _, session in
                    HStack(spacing: KXSpacing.md) {
                        Text(session.date.formatted(.dateTime.weekday(.abbreviated)))
                            .font(KXFont.captionEmphasis)
                            .foregroundStyle(KXColor.inkSecondary)
                            .frame(width: 40, alignment: .leading)
                        Image(systemName: session.kind.symbolName)
                            .foregroundStyle(session.kind.tint)
                            .frame(width: 24)
                            .accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: KXSpacing.xxs) {
                            Text(session.title).font(KXFont.bodyEmphasis).foregroundStyle(KXColor.ink)
                            Text(session.summary).font(KXFont.caption).foregroundStyle(KXColor.inkSecondary)
                        }
                        Spacer()
                        if session.isKey { KXChip(text: "Key", variant: .secondary) }
                    }
                    .accessibilityElement(children: .combine)
                }
                ForEach(week.notes, id: \.self) { note in
                    Label(note, systemImage: "info.circle")
                        .font(KXFont.caption)
                        .foregroundStyle(KXColor.inkSecondary)
                }
            } else {
                Text("Your first sessions start next week.")
                    .font(KXFont.callout)
                    .foregroundStyle(KXColor.inkSecondary)
            }
        }
        .kxCard()
    }

    private func save() {
        let profile = model.profile
        context.insert(UserProfileModel(profile: profile))
        context.insert(CoachingSettingsModel())
        PlanService.createPlan(for: profile, in: context)
    }
}

extension PaceZone {
    var displayName: String {
        switch self {
        case .easy: return "Easy & long"
        case .marathon: return "Marathon"
        case .threshold: return "Tempo"
        case .interval: return "Intervals"
        case .repetition: return "Repetition"
        }
    }
}
