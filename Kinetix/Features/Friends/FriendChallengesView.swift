import SwiftUI
import TrainingEngine
import KinetixSync

/// Challenges with friends: invites to answer, ones running (everyone's progress) and a button
/// to start a new one.
struct FriendChallengesView: View {
    @State private var social = SocialService.shared
    @State private var challenges: [FriendChallenge] = []
    @State private var loading = true
    @State private var creating = false
    @AppStorage(UnitPreference.key) private var storedUnits = UnitPreference.defaultForRegion.rawValue

    var body: some View {
        VStack(alignment: .leading, spacing: KXSpacing.md) {
            Button { creating = true } label: { Label("New challenge", systemImage: "plus") }
                .buttonStyle(.kx(.primary, fullWidth: true))
                .accessibilityIdentifier("friends.newChallenge")
            if loading {
                ProgressView().frame(maxWidth: .infinity)
            } else if challenges.isEmpty {
                KXEmptyState(symbol: "flag.checkered", title: "No challenges yet",
                             message: "Start one with friends: kilometres, gym sessions, active days or points.")
            }
            ForEach(challenges) { challenge in
                ChallengeCard(challenge: challenge, myId: social.profile?.userId) { join in
                    Task {
                        try? await social.api?.respondToChallenge(challenge.id, join: join)
                        if join { SyncService.shared.requestSync(after: 0) }
                        await load()
                    }
                }
            }
        }
        .task { await load() }
        .sheet(isPresented: $creating, onDismiss: { Task { await load() } }) { NewChallengeSheet() }
    }

    private func load() async {
        challenges = (try? await social.api?.challenges()) ?? challenges
        loading = false
    }
}

private struct ChallengeCard: View {
    let challenge: FriendChallenge
    let myId: UUID?
    let respond: (Bool) -> Void

    var body: some View {
        let calendar = Calendar.kinetix
        let end = SocialDay.date(challenge.endsOn, calendar: calendar)
        let finished = end.map { $0 < calendar.startOfDay(for: .now) } ?? false
        let joined = challenge.members.filter(\.joined)
        VStack(alignment: .leading, spacing: KXSpacing.sm) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(challenge.title).font(KXFont.headline).foregroundStyle(KXColor.ink)
                    Text("\(goal) · \(finished ? "Finished" : "ends \(end?.formatted(.dateTime.day().month()) ?? challenge.endsOn)")")
                        .font(KXFont.caption).foregroundStyle(KXColor.inkSecondary)
                }
                Spacer()
                if finished, let winner = joined.max(by: { $0.value < $1.value }), winner.value > 0 {
                    KXChip(text: winner.userId == myId ? "You won" : "\(winner.name) won", systemImage: "trophy.fill", variant: .outlined)
                }
            }
            ForEach(joined) { member in
                VStack(alignment: .leading, spacing: 3) {
                    HStack {
                        Text(member.userId == myId ? "You" : member.name).font(KXFont.callout).foregroundStyle(KXColor.ink)
                        Spacer()
                        Text(valueText(member.value)).font(KXFont.captionEmphasis.monospacedDigit()).foregroundStyle(KXColor.inkSecondary)
                    }
                    ProgressView(value: min(member.value / max(challenge.target, 1), 1))
                        .tint(member.userId == myId ? KXColor.accent : KXColor.run)
                }
                .accessibilityElement(children: .combine)
            }
            let invited = challenge.members.filter { !$0.joined }
            if !invited.isEmpty {
                Text("Invited: " + invited.map { $0.userId == myId ? "you" : $0.name }.joined(separator: ", "))
                    .font(KXFont.caption).foregroundStyle(KXColor.inkTertiary)
            }
            if !challenge.joined {
                HStack {
                    Button("Join") { respond(true) }.buttonStyle(.kx(.primary, fullWidth: true))
                    Button("No thanks") { respond(false) }.buttonStyle(.kx(.outlined, fullWidth: true))
                }
            } else if !finished {
                Button("Leave challenge", role: .destructive) { respond(false) }
                    .font(KXFont.caption)
            }
        }
        .kxCard()
    }

    private var goal: String {
        switch challenge.metric {
        case .runKilometres: return "Run \(Int(challenge.target)) km"
        case .gymSessions: return "\(Int(challenge.target)) gym sessions"
        case .activeDays: return "\(Int(challenge.target)) active days"
        case .points: return "\(Int(challenge.target)) points"
        }
    }

    private func valueText(_ value: Double) -> String {
        challenge.metric == .runKilometres ? String(format: "%.1f km", value) : "\(Int(value))"
    }
}

/// Start a challenge: what, how much, how long and which friends.
private struct NewChallengeSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var social = SocialService.shared
    @State private var metric: FriendChallenge.Metric = .runKilometres
    @State private var target = 50.0
    @State private var weeks = 2
    @State private var title = ""
    @State private var friends: [SocialPerson] = []
    @State private var chosen: Set<UUID> = []
    @State private var error: String?
    @State private var saving = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Challenge") {
                    Picker("Goal", selection: $metric) {
                        Text("Kilometres run").tag(FriendChallenge.Metric.runKilometres)
                        Text("Gym sessions").tag(FriendChallenge.Metric.gymSessions)
                        Text("Active days").tag(FriendChallenge.Metric.activeDays)
                        Text("Points").tag(FriendChallenge.Metric.points)
                    }
                    Stepper(targetText, value: $target, in: range, step: step)
                    Picker("Length", selection: $weeks) {
                        Text("1 week").tag(1)
                        Text("2 weeks").tag(2)
                        Text("4 weeks").tag(4)
                    }
                    TextField(defaultTitle, text: $title)
                }
                Section {
                    if friends.isEmpty {
                        Text("Add friends first (People).").foregroundStyle(KXColor.inkSecondary)
                    }
                    ForEach(friends) { friend in
                        Button {
                            if chosen.contains(friend.userId) { chosen.remove(friend.userId) } else { chosen.insert(friend.userId) }
                        } label: {
                            HStack {
                                Text(friend.name).foregroundStyle(KXColor.ink)
                                Spacer()
                                if chosen.contains(friend.userId) { Image(systemName: "checkmark").foregroundStyle(KXColor.accent) }
                            }
                        }
                    }
                } header: { Text("Invite") } footer: { Text("It starts today. Everything you do counts, including sessions logged by hand or from Apple Health.") }
                if let error { Section { Text(error).foregroundStyle(KXColor.danger) } }
            }
            .navigationTitle("New challenge")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Start") { Task { await start() } }.disabled(chosen.isEmpty || saving)
                }
            }
            .onChange(of: metric) { _, value in target = Self.defaultTarget(value, weeks: weeks) }
            .onChange(of: weeks) { _, value in target = Self.defaultTarget(metric, weeks: value) }
            .task { friends = ((try? await social.api?.friends()) ?? []).filter { $0.relation == .friend } }
        }
    }

    private var range: ClosedRange<Double> {
        switch metric {
        case .runKilometres: return 5...1000
        case .gymSessions: return 1...60
        case .activeDays: return 1...Double(weeks * 7)
        case .points: return 50...5000
        }
    }

    private var step: Double {
        switch metric {
        case .runKilometres: return 5
        case .points: return 50
        default: return 1
        }
    }

    private var targetText: String {
        switch metric {
        case .runKilometres: return "\(Int(target)) km"
        case .gymSessions: return "\(Int(target)) sessions"
        case .activeDays: return "\(Int(target)) days"
        case .points: return "\(Int(target)) points"
        }
    }

    private var defaultTitle: String { "\(targetText) in \(weeks) week\(weeks == 1 ? "" : "s")" }

    static func defaultTarget(_ metric: FriendChallenge.Metric, weeks: Int) -> Double {
        switch metric {
        case .runKilometres: return Double(weeks * 25)
        case .gymSessions: return Double(weeks * 3)
        case .activeDays: return Double(weeks * 5)
        case .points: return Double(weeks * 150)
        }
    }

    private func start() async {
        guard let api = social.api else { return }
        saving = true
        defer { saving = false }
        let calendar = Calendar.kinetix
        let today = calendar.startOfDay(for: .now)
        let end = calendar.date(byAdding: .day, value: weeks * 7 - 1, to: today) ?? today
        do {
            let name = title.trimmingCharacters(in: .whitespaces)
            try await api.createChallenge(title: name.isEmpty ? defaultTitle : name, metric: metric, target: min(max(target, range.lowerBound), range.upperBound),
                                          starts: today, ends: end, friends: Array(chosen), calendar: calendar)
            SyncService.shared.requestSync(after: 0)
            dismiss()
        } catch {
            self.error = error.localizedDescription
        }
    }
}
