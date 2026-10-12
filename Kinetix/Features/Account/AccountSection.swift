import SwiftUI
import SwiftData

/// Settings rows for the account: sign in, sync status, sign out, delete.
struct AccountSection: View {
    @Environment(\.modelContext) private var context
    @State private var auth = AuthService.shared
    @State private var sync = SyncService.shared
    @State private var showAuth = false
    @State private var confirmSignOut = false

    var body: some View {
        switch auth.state {
        case .unavailable:
            Label {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Account").foregroundStyle(KXColor.ink)
                    Text("Not available in this build").font(KXFont.caption).foregroundStyle(KXColor.inkSecondary)
                }
            } icon: {
                Image(systemName: "person.crop.circle").foregroundStyle(KXColor.inkSecondary)
            }
        case .signedOut:
            Button {
                showAuth = true
            } label: {
                Label("Sign in or create account", systemImage: "person.crop.circle.badge.plus")
            }
            .sheet(isPresented: $showAuth) { AuthView(mode: .create) }
        case .signedIn(let email, _):
            Label {
                VStack(alignment: .leading, spacing: 2) {
                    Text(email ?? "Signed in with Apple").foregroundStyle(KXColor.ink)
                    Text(syncText).font(KXFont.caption).foregroundStyle(KXColor.inkSecondary)
                }
            } icon: {
                Image(systemName: "person.crop.circle.fill").foregroundStyle(KXColor.accent)
            }
            Button {
                Task { await sync.sync(context: context) }
            } label: {
                Label(sync.status == .syncing ? "Syncing…" : "Sync now", systemImage: "arrow.triangle.2.circlepath")
            }
            .disabled(sync.status == .syncing)
            Button {
                confirmSignOut = true
            } label: {
                Label("Sign out", systemImage: "rectangle.portrait.and.arrow.right")
            }
            .confirmationDialog("Sign out?", isPresented: $confirmSignOut, titleVisibility: .visible) {
                Button("Sign out") { Task { await auth.signOut() } }
            } message: {
                Text("Your data stays on this iPhone and is still backed up in your account. Sign in again any time to resume syncing.")
            }
        }
    }

    private var syncText: String {
        switch sync.status {
        case .syncing: return "Syncing…"
        case .failed(let message): return "Not synced: \(message)"
        case .idle:
            guard let last = sync.lastSyncedAt else { return "Not synced yet" }
            return "Synced \(last.formatted(.relative(presentation: .named)))"
        }
    }
}
