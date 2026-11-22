import SwiftUI
import TrainingEngine
import KinetixSync

/// The top of Achievements: this week's leaderboard with friends, or how to start.
struct FriendsCard: View {
    @State private var social = SocialService.shared
    @State private var auth = AuthService.shared
    @State private var board: [LeaderboardRow] = []
    @State private var choosingName = false
    @State private var showFriends = false

    var body: some View {
        VStack(alignment: .leading, spacing: KXSpacing.md) {
            KXSectionHeader("Friends", subtitle: subtitle)
            content
        }
        .kxCard()
        .navigationDestination(isPresented: $showFriends) { FriendsScreen() }
        .sheet(isPresented: $choosingName) { UsernameSheet() }
        .task(id: auth.isSignedIn) { await load() }
        .onChange(of: social.pendingCode) { _, code in if code != nil, social.profile != nil { showFriends = true } }
        .accessibilityIdentifier("achievements.friends")
    }

    private var subtitle: String {
        if !auth.isSignedIn { return "Compete with friends each week" }
        if social.profile == nil { return "Choose a username to add friends" }
        return "This week's leaderboard"
    }

    @ViewBuilder private var content: some View {
        if case .unavailable = auth.state {
            Text("Friends need an account, which isn't available in this build.")
                .font(KXFont.callout).foregroundStyle(KXColor.inkSecondary)
        } else if !auth.isSignedIn {
            Text("Sign in (Profile → Settings → Account) to add friends, share sessions and compete on a weekly leaderboard.")
                .font(KXFont.callout).foregroundStyle(KXColor.inkSecondary)
        } else if !social.loadedProfile {
            ProgressView().frame(maxWidth: .infinity)
        } else if social.profile == nil {
            Text("Points from sticking to your plan go on a weekly leaderboard with friends. Friends see your sessions and maps (the first and last 200 m are hidden).")
                .font(KXFont.callout).foregroundStyle(KXColor.inkSecondary)
            Button("Choose a username") { choosingName = true }
                .buttonStyle(.kx(.primary, fullWidth: true))
                .accessibilityIdentifier("friends.chooseUsername")
        } else {
            if board.count <= 1 {
                Text("Add friends to see who's top this week.").font(KXFont.callout).foregroundStyle(KXColor.inkSecondary)
            } else {
                ForEach(Array(board.prefix(3).enumerated()), id: \.element.id) { index, row in
                    LeaderboardRowView(rank: index + 1, row: row)
                }
                if let me = board.firstIndex(where: \.isMe), me >= 3 {
                    LeaderboardRowView(rank: me + 1, row: board[me])
                }
            }
            Button("Open friends") { showFriends = true }
                .buttonStyle(.kx(.outlined, fullWidth: true))
                .accessibilityIdentifier("friends.open")
        }
    }

    private func load() async {
        await social.loadProfile()
        guard social.profile != nil, let api = social.api else { return }
        board = (try? await api.leaderboard(week: Calendar.kinetix.startOfISOWeek(for: .now), calendar: .kinetix)) ?? []
        if social.pendingCode != nil { showFriends = true }
    }
}

struct LeaderboardRowView: View {
    let rank: Int
    let row: LeaderboardRow

    var body: some View {
        HStack(spacing: KXSpacing.md) {
            Text("\(rank)")
                .font(KXFont.number(18, relativeTo: .headline))
                .foregroundStyle(rank == 1 ? KXColor.onAccent : KXColor.ink)
                .frame(width: 32, height: 32)
                .background(rank == 1 ? KXColor.accent : KXColor.surfaceTint, in: Circle())
            VStack(alignment: .leading, spacing: 1) {
                Text(row.isMe ? "You" : row.name).font(KXFont.bodyEmphasis).foregroundStyle(KXColor.ink).lineLimit(1)
                Text("@\(row.username)").font(KXFont.caption).foregroundStyle(KXColor.inkTertiary).lineLimit(1)
            }
            Spacer()
            Text("\(row.points) pts").font(KXFont.captionEmphasis.monospacedDigit()).foregroundStyle(row.isMe ? KXColor.accent : KXColor.inkSecondary)
        }
        .accessibilityElement(children: .combine)
    }
}

/// Choose or change your username and the name friends see.
struct UsernameSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var social = SocialService.shared
    @State private var username = ""
    @State private var displayName = ""
    @State private var saving = false
    @State private var error: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Username", text: $username)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .accessibilityIdentifier("friends.username")
                    TextField("Name friends see (optional)", text: $displayName)
                } footer: {
                    Text(Username.problem(username).map { username.isEmpty ? "3 to 20 letters, numbers or underscores." : $0 }
                         ?? "Friends find you by your username. Your email is never shown.")
                }
                if let error {
                    Section { Text(error).foregroundStyle(KXColor.danger) }
                }
            }
            .navigationTitle(social.profile == nil ? "Choose a username" : "Your username")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { Task { await save() } }
                        .disabled(Username.problem(username) != nil || saving)
                }
            }
            .onAppear {
                username = social.profile?.username ?? ""
                displayName = social.profile?.displayName ?? ""
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func save() async {
        saving = true
        defer { saving = false }
        do {
            try await social.claim(username: username, displayName: displayName)
            SyncService.shared.requestSync(after: 0.5)
            dismiss()
        } catch {
            self.error = error.localizedDescription
        }
    }
}

/// In a session's toolbar once you have friends set up: Friends can see it, or Only me.
struct FriendsVisibilityButton: View {
    let id: UUID
    @State private var social = SocialService.shared
    @State private var hidden = false

    var body: some View {
        if social.profile != nil {
            Menu {
                Picker("Who can see this", selection: Binding(get: { hidden }, set: { value in
                    hidden = value
                    social.setPrivate(id, value)
                    if !value { SyncService.shared.requestSync(after: 0.5) }
                })) {
                    Label("Friends", systemImage: "person.2").tag(false)
                    Label("Only me", systemImage: "lock").tag(true)
                }
            } label: {
                Image(systemName: hidden ? "lock" : "person.2")
            }
            .accessibilityLabel(hidden ? "Only you can see this" : "Friends can see this")
            .onAppear { hidden = social.isPrivate(id) }
        }
    }
}
