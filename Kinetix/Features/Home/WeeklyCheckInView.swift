import SwiftUI
import SwiftData
import TrainingEngine

/// End of the week: "How did training go?" Too much / about right / too easy, and whether the
/// gym days fitted their week. Kinetix then offers to adjust next week (they confirm first).
struct WeeklyCheckInView: View {
    let weekStart: Date
    let nextWeek: [PlannedSessionModel]
    /// Called once they've answered (Today then folds the review away to the bottom).
    var onAnswered: () -> Void = {}

    /// Whether the check-in for this week has been answered.
    static func isAnswered(weekStart: Date) -> Bool {
        UserDefaults.standard.string(forKey: key(weekStart)) != nil
    }

    static func key(_ weekStart: Date) -> String { "weeklyCheckIn.\(Int(weekStart.timeIntervalSince1970))" }

    @Environment(\.modelContext) private var context
    @State private var feel: WeekFeel?
    @State private var gymFitted: Bool?
    @State private var answered = false
    @State private var confirmAdjust = false
    @State private var showRearrange = false
    @State private var result: String?

    private var key: String { Self.key(weekStart) }
    private var hasGym: Bool { nextWeek.contains { $0.kind.discipline == .strength } }

    var body: some View {
        VStack(alignment: .leading, spacing: KXSpacing.sm) {
            KXOverline("How did the week go?")
            if answered {
                Label(result ?? "Thanks, noted.", systemImage: "checkmark.circle.fill")
                    .font(KXFont.callout).foregroundStyle(KXColor.ink).symbolRenderingMode(.multicolor)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Text("The training overall").font(KXFont.caption).foregroundStyle(KXColor.inkSecondary)
                Picker("The training overall", selection: $feel) {
                    ForEach(WeekFeel.allCases, id: \.self) { Text($0.title).tag(Optional($0)) }
                }
                .pickerStyle(.segmented)
                if hasGym {
                    Text("Did the gym days fit around your week?").font(KXFont.caption).foregroundStyle(KXColor.inkSecondary)
                    Picker("Gym days", selection: $gymFitted) {
                        Text("Yes").tag(Optional(true))
                        Text("Not really").tag(Optional(false))
                    }
                    .pickerStyle(.segmented)
                }
                Button("Send") { send() }
                    .buttonStyle(.kx(.secondary, fullWidth: true))
                    .disabled(feel == nil)
                    .accessibilityIdentifier("weekly.checkIn.send")
            }
        }
        .onAppear { answered = UserDefaults.standard.string(forKey: key) != nil }
        .confirmationDialog(adjustTitle, isPresented: $confirmAdjust, titleVisibility: .visible) {
            Button(feel == .tooMuch ? "Make next week lighter" : "Add a little more") { adjust() }
            Button("Keep next week as it is", role: .cancel) { finish(nil) }
        } message: {
            Text(feel == .tooMuch
                 ? "Steady runs about 10% shorter, interval sessions one rep fewer and one set fewer on gym accessories."
                 : "Easy, steady and long runs about 5% longer. Intervals and gym stay as planned.")
        }
        .sheet(isPresented: $showRearrange) { WeekRearrangeView() }
    }

    private var adjustTitle: String { feel == .tooMuch ? "Make next week a little lighter?" : "Make next week a little harder?" }

    private func send() {
        guard let feel else { return }
        UserDefaults.standard.set("\(feel.rawValue)|\(gymFitted.map { $0 ? "fit" : "didntFit" } ?? "-")", forKey: key)
        if feel == .aboutRight {
            finish(nil)
        } else {
            confirmAdjust = true
        }
    }

    private func adjust() {
        guard let feel else { return }
        let changed = WeeklyCheckInService.adjust(nextWeek, feel: feel, in: context)
        finish(changed > 0 ? (feel == .tooMuch ? "Next week is a little lighter (\(changed) sessions)."
                                                : "Next week has a little more running (\(changed) runs).") : nil)
    }

    private func finish(_ message: String?) {
        var text = message ?? "Thanks, noted."
        if gymFitted == false {
            text += " Move your gym days to suit you."
            showRearrange = true
        }
        withAnimation {
            result = text
            answered = true
        }
        // Give them a moment to read the reply before the card folds away.
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) { onAnswered() }
    }
}

@MainActor
enum WeeklyCheckInService {
    /// Makes next week's planned sessions lighter (too much) or a little longer (too easy).
    /// Returns how many sessions changed.
    @discardableResult
    static func adjust(_ sessions: [PlannedSessionModel], feel: WeekFeel, in context: ModelContext, now: Date = .now) -> Int {
        guard feel != .aboutRight else { return 0 }
        var changed = 0
        for session in sessions where session.status == .planned {
            switch session.kind {
            case .run(let type):
                guard let structure = session.runStructure else { continue }
                if feel == .tooEasy && (type == .tempo || type == .intervals) { continue }
                let factor = feel == .tooMuch ? 0.9 : 1.05
                let scaled = WeekAdjustment.scaled(structure, by: factor)
                guard scaled != structure else { continue }
                session.runStructureData = StoredJSON.encode(scaled)
                session.plannedDurationMinutes = max(10, (session.plannedDurationMinutes * factor).rounded())
                session.estimatedDistanceMeters = session.estimatedDistanceMeters.map { $0 * factor }
            case .strength:
                guard feel == .tooMuch, let prescription = session.strengthPrescription else { continue }
                let lighter = WeekAdjustment.lighter(prescription)
                guard lighter != prescription else { continue }
                session.strengthPrescriptionData = StoredJSON.encode(lighter)
            default:
                continue
            }
            session.changeReason = feel == .tooMuch ? "A little lighter: you said last week was too much."
                                                    : "A little more: you said last week was too easy."
            session.touch(now: now)
            changed += 1
        }
        if changed > 0 {
            context.insert(PlanChangeModel(summary: feel == .tooMuch ? "Made next week a little lighter after your weekly check-in."
                                                                     : "Added a little running to next week after your weekly check-in.",
                                           now: now))
            try? context.save()
            SyncService.shared.requestSync()
        }
        return changed
    }
}
