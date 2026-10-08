import SwiftUI
import SwiftData
import TrainingEngine

/// Dashboard. Today's sessions are real (from the database); readiness and load
/// figures are placeholders until the load model lands in Milestone 5.
struct HomeView: View {
    @Environment(AppRouter.self) private var router
    @Query(sort: \PlannedSessionModel.date) private var sessions: [PlannedSessionModel]
    @Query private var profiles: [UserProfileModel]

    private var units: UnitSystem { profiles.first?.units ?? .metric }

    private var todaysSessions: [PlannedSessionModel] {
        let calendar = Calendar.kinetix
        return sessions
            .filter { !$0.isSoftDeleted && calendar.isDateInToday($0.date) }
            .sorted { $0.slot == .morning && $1.slot == .evening }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: KXSpacing.xl) {
                KXScreenHeader(title: "Dashboard", onNotifications: {})

                VStack(alignment: .leading, spacing: KXSpacing.xs) {
                    Text("Welcome back")
                        .font(KXFont.display)
                        .foregroundStyle(KXColor.accent)
                    Text("Here's your hybrid balance for today.")
                        .font(KXFont.callout)
                        .foregroundStyle(KXColor.inkSecondary)
                }

                readinessCard
                todaySection
            }
            .padding(KXSpacing.screenMargin)
        }
        .background(KXColor.background.ignoresSafeArea())
    }

    private var readinessCard: some View {
        VStack(alignment: .leading, spacing: KXSpacing.lg) {
            KXSectionHeader("Readiness & Training Load", subtitle: "Sample figures until Milestone 5")
            HStack(spacing: KXSpacing.xl) {
                KXRingGauge(value: 0.92, label: "92%", caption: "Optimal")
                    .frame(width: 110, height: 110)
                VStack(alignment: .leading, spacing: KXSpacing.md) {
                    loadRow(title: "Running load", value: "68%", status: .optimal, statusText: "Optimal")
                    loadRow(title: "Lifting load", value: "Low", status: .low, statusText: "Ready to lift")
                }
            }
            Divider()
            HStack {
                KXMetric(label: "Weekly", value: Units.formatDistance(meters: 28_400, units: units), unit: Units.distanceUnitLabel(units), detail: "Target 35", size: .small)
                Spacer()
                KXMetric(label: "Volume", value: "14,250", unit: Units.weightUnitLabel(units), detail: "+8% vs avg", size: .small)
                Spacer()
                KXMetric(label: "Adherence", value: "92", unit: "%", size: .small)
            }
        }
        .kxCard()
    }

    private func loadRow(title: String, value: String, status: KXStatusPill.Level, statusText: String) -> some View {
        VStack(alignment: .leading, spacing: KXSpacing.xs) {
            KXOverline(title)
            HStack(spacing: KXSpacing.sm) {
                Text(value).font(KXFont.metricSmall).foregroundStyle(KXColor.ink)
                KXStatusPill(level: status, text: statusText)
            }
        }
    }

    private func sessionLetter(_ index: Int) -> String {
        let letters = ["A", "B", "C", "D"]
        return letters[min(index, letters.count - 1)]
    }

    private var todaySection: some View {
        VStack(alignment: .leading, spacing: KXSpacing.md) {
            KXSectionHeader("Today's Schedule", subtitle: todaysSessions.isEmpty ? nil : "\(todaysSessions.count) session\(todaysSessions.count == 1 ? "" : "s") planned") {
                KXChip(text: "Active block", variant: .secondary)
            }
            if todaysSessions.isEmpty {
                VStack(alignment: .leading, spacing: KXSpacing.sm) {
                    Text("Rest day").font(KXFont.headline).foregroundStyle(KXColor.ink)
                    Text("Nothing scheduled today. Recovery is training too.")
                        .font(KXFont.callout)
                        .foregroundStyle(KXColor.inkSecondary)
                }
                .kxCard(.tinted)
            } else {
                ForEach(Array(todaysSessions.enumerated()), id: \.element.id) { index, session in
                    KXSessionCard(
                        overline: "Session \(sessionLetter(index)) · \(session.slot == .morning ? "Morning" : "Evening")",
                        title: session.title,
                        detail: "\(session.summary) · \(Int(session.plannedDurationMinutes)) min",
                        kind: session.kind,
                        status: session.status,
                        onStart: {
                            router.activeSession = ActiveSession(id: session.id, kind: session.kind, title: session.title)
                        }
                    )
                }
            }
        }
    }
}

#Preview {
    let container = try! Persistence.makeContainer(inMemory: true)
    SampleData.seed(into: container.mainContext)
    return HomeView()
        .environment(AppRouter())
        .modelContainer(container)
}
