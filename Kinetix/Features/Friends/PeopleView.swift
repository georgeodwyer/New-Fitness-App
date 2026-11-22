import SwiftUI
import CoreImage.CIFilterBuiltins
import TrainingEngine
import KinetixSync

/// Your username, friend code, QR code and invite link; finding people by username or code;
/// requests; friends; blocked people; and whether friends see your sessions.
struct PeopleView: View {
    @State private var social = SocialService.shared
    @State private var people: [SocialPerson] = []
    @State private var blocked: [SocialPerson] = []
    @State private var query = ""
    @State private var results: [SocialPerson] = []
    @State private var code = ""
    @State private var codeResult: SocialPerson?
    @State private var codeMessage: String?
    @State private var showQR = false
    @State private var editingName = false
    @State private var reporting: SocialPerson?
    @State private var headToHead: SocialPerson?
    @State private var error: String?

    var body: some View {
        VStack(alignment: .leading, spacing: KXSpacing.xl) {
            if let profile = social.profile { meCard(profile) }
            addCard
            let incoming = people.filter { $0.relation == .incoming }
            if !incoming.isEmpty {
                listCard("Requests", incoming) { person in
                    HStack {
                        Button("Accept") { act { try await $0.respond(to: person.userId, accept: true) } }.buttonStyle(.kx(.primary))
                        Button("Decline") { act { try await $0.respond(to: person.userId, accept: false) } }.buttonStyle(.kx(.outlined))
                    }
                }
            }
            let friends = people.filter { $0.relation == .friend }
            listCard("Friends (\(friends.count))", friends) { person in
                Menu {
                    Button("Head-to-head") { headToHead = person }
                    Button("Remove friend", role: .destructive) { act { try await $0.remove(person.userId) } }
                    Button("Report or block", role: .destructive) { reporting = person }
                } label: { Image(systemName: "ellipsis").frame(width: 32, height: 32) }
                .accessibilityLabel("Options for \(person.name)")
            }
            let outgoing = people.filter { $0.relation == .outgoing }
            if !outgoing.isEmpty {
                listCard("Sent", outgoing) { person in
                    Button("Cancel") { act { try await $0.remove(person.userId) } }.buttonStyle(.kx(.outlined))
                }
            }
            if !blocked.isEmpty {
                listCard("Blocked", blocked) { person in
                    Button("Unblock") { act { try await $0.unblock(person.userId) } }.buttonStyle(.kx(.outlined))
                }
            }
            if let error { Text(error).font(KXFont.caption).foregroundStyle(KXColor.danger) }
        }
        .task { await load() }
        .onAppear { if let pending = social.pendingCode { code = pending; social.pendingCode = nil; Task { await lookUpCode() } } }
        .sheet(isPresented: $showQR) { if let profile = social.profile { QRSheet(profile: profile) } }
        .sheet(isPresented: $editingName) { UsernameSheet() }
        .navigationDestination(item: $headToHead) { HeadToHeadView(friend: $0) }
        .sheet(item: $reporting) { person in
            ReportSheet(userId: person.userId, name: person.name) { Task { await load() } }
        }
    }

    // MARK: You

    private func meCard(_ profile: SocialProfile) -> some View {
        VStack(alignment: .leading, spacing: KXSpacing.md) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(profile.displayName.isEmpty ? "@\(profile.username)" : profile.displayName).font(KXFont.headline).foregroundStyle(KXColor.ink)
                    if !profile.displayName.isEmpty { Text("@\(profile.username)").font(KXFont.caption).foregroundStyle(KXColor.inkSecondary) }
                }
                Spacer()
                Button("Edit") { editingName = true }
            }
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    KXOverline("Your friend code")
                    Text(profile.friendCode).font(KXFont.number(24, relativeTo: .title2)).foregroundStyle(KXColor.ink).textSelection(.enabled)
                }
                Spacer()
                Button { showQR = true } label: { Image(systemName: "qrcode").font(.title2) }
                    .accessibilityLabel("Show QR code")
            }
            if let link = FriendLink.url(code: profile.friendCode) {
                ShareLink(item: link, subject: Text("Add me on Kinetix"),
                          message: Text("Add me as a friend on Kinetix: tap the link, or enter my code \(profile.friendCode).")) {
                    Label("Invite a friend", systemImage: "square.and.arrow.up").frame(maxWidth: .infinity)
                }
                .buttonStyle(.kx(.outlined, fullWidth: true))
            }
            Toggle("Friends see my sessions", isOn: Binding(get: { profile.sharing }, set: { on in
                Task { do { try await social.setSharing(on) } catch { self.error = error.localizedDescription } }
            }))
            .font(KXFont.callout)
            Text("Friends see your sessions, maps (without the first and last 200 m) and points. To hide one session, open it and choose Only me.")
                .font(KXFont.caption).foregroundStyle(KXColor.inkTertiary)
        }
        .kxCard()
    }

    // MARK: Adding

    private var addCard: some View {
        VStack(alignment: .leading, spacing: KXSpacing.md) {
            KXSectionHeader("Add friends")
            TextField("Search usernames", text: $query)
                .textInputAutocapitalization(.never).autocorrectionDisabled()
                .textFieldStyle(.roundedBorder)
                .accessibilityIdentifier("friends.search")
                .task(id: query) {
                    try? await Task.sleep(for: .milliseconds(300))
                    guard !Task.isCancelled else { return }
                    results = query.trimmingCharacters(in: .whitespaces).count >= 2 ? ((try? await social.api?.search(query)) ?? []) : []
                }
            ForEach(results) { person in personRow(person) { addButton(person) } }
            HStack {
                TextField("Friend code or link", text: $code)
                    .textInputAutocapitalization(.characters).autocorrectionDisabled()
                    .textFieldStyle(.roundedBorder)
                Button("Find") { Task { await lookUpCode() } }
                    .disabled(FriendLink.code(fromText: code) == nil)
            }
            if let codeResult { personRow(codeResult) { addButton(codeResult) } }
            if let codeMessage { Text(codeMessage).font(KXFont.caption).foregroundStyle(KXColor.inkSecondary) }
        }
        .kxCard()
    }

    @ViewBuilder private func addButton(_ person: SocialPerson) -> some View {
        switch person.relation ?? SocialPerson.Relation.none {
        case .friend: Text("Friends").font(KXFont.caption).foregroundStyle(KXColor.success)
        case .outgoing: Text("Sent").font(KXFont.caption).foregroundStyle(KXColor.inkSecondary)
        case .incoming: Button("Accept") { add(person) }.buttonStyle(.kx(.primary))
        case .none: Button("Add") { add(person) }.buttonStyle(.kx(.primary))
        }
    }

    private func add(_ person: SocialPerson) {
        act { api in
            let relation = try await api.sendRequest(to: person.userId)
            if let index = results.firstIndex(where: { $0.userId == person.userId }) { results[index].relation = relation }
            if codeResult?.userId == person.userId { codeResult?.relation = relation }
        }
    }

    private func lookUpCode() async {
        codeResult = nil
        codeMessage = nil
        guard let value = FriendLink.code(fromText: code) else { return }
        if value == social.profile?.friendCode { codeMessage = "That's your code."; return }
        do {
            codeResult = try await social.api?.find(code: value)
            if codeResult == nil { codeMessage = "No one has that code." }
        } catch {
            codeMessage = error.localizedDescription
        }
    }

    // MARK: Lists

    private func listCard<Trailing: View>(_ title: String, _ list: [SocialPerson], @ViewBuilder trailing: @escaping (SocialPerson) -> Trailing) -> some View {
        VStack(alignment: .leading, spacing: KXSpacing.sm) {
            KXSectionHeader(title)
            if list.isEmpty {
                Text("No one yet. Search for a username, enter a code or send an invite.")
                    .font(KXFont.callout).foregroundStyle(KXColor.inkSecondary)
            }
            ForEach(list) { person in personRow(person) { trailing(person) } }
        }
        .kxCard()
    }

    private func personRow<Trailing: View>(_ person: SocialPerson, @ViewBuilder trailing: () -> Trailing) -> some View {
        HStack(spacing: KXSpacing.sm) {
            Text(String(person.name.prefix(1)).uppercased())
                .font(KXFont.bodyEmphasis).foregroundStyle(KXColor.onAccent)
                .frame(width: 34, height: 34).background(KXColor.accent, in: Circle())
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 1) {
                Text(person.name).font(KXFont.bodyEmphasis).foregroundStyle(KXColor.ink).lineLimit(1)
                Text("@\(person.username)").font(KXFont.caption).foregroundStyle(KXColor.inkTertiary).lineLimit(1)
            }
            Spacer()
            trailing()
        }
    }

    private func act(_ work: @escaping (SocialAPI) async throws -> Void) {
        guard let api = social.api else { return }
        Task {
            do {
                try await work(api)
                error = nil
                await load()
            } catch {
                self.error = error.localizedDescription
            }
        }
    }

    private func load() async {
        guard let api = social.api else { return }
        people = (try? await api.friends()) ?? people
        blocked = (try? await api.blocked()) ?? blocked
    }
}

/// Your QR code: a friend scans it with their camera to open Kinetix and add you.
private struct QRSheet: View {
    let profile: SocialProfile
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: KXSpacing.lg) {
                if let image = Self.qr(FriendLink.url(code: profile.friendCode)?.absoluteString ?? profile.friendCode) {
                    Image(uiImage: image)
                        .interpolation(.none)
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: 260)
                        .padding(KXSpacing.lg)
                        .background(Color.white, in: RoundedRectangle(cornerRadius: KXRadius.md, style: .continuous))
                        .accessibilityLabel("QR code for adding \(profile.username)")
                }
                Text("@\(profile.username)").font(KXFont.headline).foregroundStyle(KXColor.ink)
                Text("Code \(profile.friendCode)").font(KXFont.callout).foregroundStyle(KXColor.inkSecondary)
                Text("Your friend points their iPhone camera at this, then taps the link to open Kinetix.")
                    .font(KXFont.caption).foregroundStyle(KXColor.inkTertiary).multilineTextAlignment(.center)
            }
            .padding(KXSpacing.screenMargin)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(KXColor.background.ignoresSafeArea())
            .navigationTitle("Your QR code")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
    }

    static func qr(_ text: String) -> UIImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(text.utf8)
        filter.correctionLevel = "M"
        guard let output = filter.outputImage?.transformed(by: CGAffineTransform(scaleX: 10, y: 10)),
              let cgImage = CIContext().createCGImage(output, from: output.extent) else { return nil }
        return UIImage(cgImage: cgImage)
    }
}
