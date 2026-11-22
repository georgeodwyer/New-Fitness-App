import SwiftUI
import SwiftData
import MapKit
import TrainingEngine
import KinetixSync

/// Friends: weekly leaderboard (tap someone for head-to-head), friends' sessions, challenges,
/// and people (your code and QR, adding friends, requests, blocking, sharing on or off).
struct FriendsScreen: View {
    enum Section: String, CaseIterable, Identifiable {
        case leaderboard = "Leaderboard", feed = "Feed", challenges = "Challenges", people = "People"
        var id: String { rawValue }
    }

    @State private var section: Section = .leaderboard
    @State private var social = SocialService.shared

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: KXSpacing.lg) {
                Picker("Section", selection: $section) {
                    ForEach(Section.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                switch section {
                case .leaderboard: LeaderboardView()
                case .feed: FriendFeedView()
                case .challenges: FriendChallengesView()
                case .people: PeopleView()
                }
            }
            .padding(KXSpacing.screenMargin)
        }
        .background(KXColor.background.ignoresSafeArea())
        .navigationTitle("Friends")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { if social.pendingCode != nil { section = .people } }
    }
}

// MARK: - Leaderboard

private struct LeaderboardView: View {
    @State private var social = SocialService.shared
    @State private var weeksBack = 0
    @State private var rows: [LeaderboardRow] = []
    @State private var loading = true

    private var week: Date {
        let calendar = Calendar.kinetix
        return calendar.date(byAdding: .day, value: -7 * weeksBack, to: calendar.startOfISOWeek(for: .now)) ?? .now
    }

    var body: some View {
        VStack(alignment: .leading, spacing: KXSpacing.md) {
            HStack {
                Button { weeksBack += 1 } label: { Image(systemName: "chevron.left") }
                    .accessibilityLabel("Previous week")
                Spacer()
                Text(weeksBack == 0 ? "This week" : weeksBack == 1 ? "Last week" : "Week of \(week.formatted(.dateTime.day().month()))")
                    .font(KXFont.bodyEmphasis).foregroundStyle(KXColor.ink)
                Spacer()
                Button { weeksBack -= 1 } label: { Image(systemName: "chevron.right") }
                    .disabled(weeksBack == 0)
                    .accessibilityLabel("Next week")
            }
            if loading {
                ProgressView().frame(maxWidth: .infinity)
            } else {
                ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                    if row.isMe {
                        LeaderboardRowView(rank: index + 1, row: row)
                    } else {
                        NavigationLink {
                            HeadToHeadView(friend: SocialPerson(userId: row.userId, username: row.username, displayName: row.displayName, relation: .friend))
                        } label: { LeaderboardRowView(rank: index + 1, row: row) }
                        .buttonStyle(.plain)
                    }
                }
                Text("Points: +\(Points.plannedSession) for each planned session done, +\(Points.fullPlannedWeek) for a full week, +\(Points.streakPerWeek) for each week in a row, plus a little for training load. Tap a friend for head-to-head.")
                    .font(KXFont.caption).foregroundStyle(KXColor.inkTertiary)
            }
        }
        .kxCard()
        .task(id: weeksBack) { await load() }
        .refreshable { await load() }
    }

    private func load() async {
        loading = rows.isEmpty
        rows = (try? await social.api?.leaderboard(week: week, calendar: .kinetix)) ?? rows
        loading = false
    }
}

/// You against one friend, week by week.
struct HeadToHeadView: View {
    let friend: SocialPerson
    @State private var weeks: [HeadToHeadWeek] = []
    @State private var social = SocialService.shared

    var body: some View {
        let mine = weeks.reduce(0) { $0 + $1.myPoints }
        let theirs = weeks.reduce(0) { $0 + $1.theirPoints }
        let wins = weeks.filter { $0.myPoints > $0.theirPoints }.count
        let losses = weeks.filter { $0.myPoints < $0.theirPoints }.count
        let best = Double(weeks.map { max($0.myPoints, $0.theirPoints) }.max() ?? 1)
        ScrollView {
            VStack(alignment: .leading, spacing: KXSpacing.lg) {
                HStack {
                    score("You", mine, KXColor.accent)
                    Text("vs").font(KXFont.callout).foregroundStyle(KXColor.inkTertiary)
                    score(friend.name, theirs, KXColor.run)
                }
                .kxCard()
                VStack(alignment: .leading, spacing: KXSpacing.sm) {
                    KXSectionHeader("Last 8 weeks", subtitle: "You won \(wins), \(friend.name) won \(losses)")
                    ForEach(weeks.reversed()) { week in
                        VStack(alignment: .leading, spacing: 3) {
                            Text(SocialDay.date(week.weekStart, calendar: .kinetix)?.formatted(.dateTime.day().month()) ?? week.weekStart)
                                .font(KXFont.caption).foregroundStyle(KXColor.inkSecondary)
                            bar(week.myPoints, of: best, KXColor.accent)
                            bar(week.theirPoints, of: best, KXColor.run)
                        }
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel("Week of \(week.weekStart): you \(week.myPoints), \(friend.name) \(week.theirPoints)")
                    }
                }
                .kxCard()
            }
            .padding(KXSpacing.screenMargin)
        }
        .background(KXColor.background.ignoresSafeArea())
        .navigationTitle("Head-to-head")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            weeks = (try? await social.api?.headToHead(with: friend.userId, week: Calendar.kinetix.startOfISOWeek(for: .now), calendar: .kinetix)) ?? []
        }
    }

    private func score(_ name: String, _ points: Int, _ tint: Color) -> some View {
        VStack(spacing: 2) {
            Text("\(points)").font(KXFont.number(32, relativeTo: .largeTitle)).foregroundStyle(tint)
            Text(name).font(KXFont.caption).foregroundStyle(KXColor.inkSecondary).lineLimit(1)
        }
        .frame(maxWidth: .infinity)
    }

    private func bar(_ value: Int, of best: Double, _ tint: Color) -> some View {
        GeometryReader { proxy in
            HStack(spacing: 6) {
                Capsule().fill(tint).frame(width: max(4, (proxy.size.width - 44) * Double(value) / max(best, 1)), height: 8)
                Text("\(value)").font(KXFont.caption2.monospacedDigit()).foregroundStyle(KXColor.inkSecondary)
            }
        }
        .frame(height: 12)
    }
}

// MARK: - Feed

private struct FriendFeedView: View {
    @State private var social = SocialService.shared
    @State private var items: [FeedItem] = []
    @State private var loading = true
    @State private var more = true
    @State private var reporting: FeedItem?
    @AppStorage(UnitPreference.key) private var storedUnits = UnitPreference.defaultForRegion.rawValue

    private var units: UnitSystem { UnitSystem(rawValue: storedUnits) ?? UnitPreference.defaultForRegion }

    var body: some View {
        VStack(alignment: .leading, spacing: KXSpacing.md) {
            if loading {
                ProgressView().frame(maxWidth: .infinity)
            } else if items.isEmpty {
                KXEmptyState(symbol: "person.2", title: "Nothing yet", message: "Your friends' sessions appear here once they've trained.")
            }
            ForEach(items) { item in
                FeedCard(item: item, units: units) { reporting = item }
            }
            if !items.isEmpty && more {
                Button("Show more") { Task { await load(more: true) } }
                    .buttonStyle(.kx(.outlined, fullWidth: true))
            }
        }
        .task { await load(more: false) }
        .sheet(item: $reporting) { item in
            ReportSheet(userId: item.userId, name: item.name, sessionId: item.id) {
                items.removeAll { $0.userId == item.userId }
            }
        }
    }

    private func load(more loadMore: Bool) async {
        let page = (try? await social.api?.feed(before: loadMore ? items.last?.startedAt : nil, limit: 30)) ?? []
        items = loadMore ? items + page : page
        more = page.count == 30
        loading = false
    }
}

private struct FeedCard: View {
    let item: FeedItem
    let units: UnitSystem
    let report: () -> Void

    var body: some View {
        let format = DisplayFormat(units: units)
        VStack(alignment: .leading, spacing: KXSpacing.sm) {
            HStack(spacing: KXSpacing.sm) {
                Text(String(item.name.prefix(1)).uppercased())
                    .font(KXFont.bodyEmphasis).foregroundStyle(KXColor.onAccent)
                    .frame(width: 34, height: 34).background(KXColor.accent, in: Circle())
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 1) {
                    Text(item.name).font(KXFont.bodyEmphasis).foregroundStyle(KXColor.ink)
                    Text(item.startedAt.formatted(.relative(presentation: .named))).font(KXFont.caption).foregroundStyle(KXColor.inkTertiary)
                }
                Spacer()
                Menu {
                    Button("Report or block", systemImage: "flag", action: report)
                } label: {
                    Image(systemName: "ellipsis").frame(width: 32, height: 32)
                }
                .accessibilityLabel("More")
            }
            Text(item.title).font(KXFont.headline).foregroundStyle(KXColor.ink)
            HStack(spacing: KXSpacing.lg) {
                if item.distanceMeters > 0 { stat("Distance", format.distance(item.distanceMeters)) }
                stat("Time", Units.formatMinutesSeconds(item.durationSeconds))
                if item.kind == "run", item.distanceMeters >= 500 {
                    stat("Pace", format.pace(Pace(secondsPerKm: item.durationSeconds / (item.distanceMeters / 1000))))
                }
                if item.sets > 0 { stat("Sets", "\(item.sets)") }
            }
            if let route = item.route, route.count >= 2 { FriendRouteMap(points: route) }
        }
        .kxCard()
    }

    private func stat(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            KXOverline(label)
            Text(value).font(KXFont.bodyEmphasis.monospacedDigit()).foregroundStyle(KXColor.ink)
        }
        .accessibilityElement(children: .combine)
    }
}

/// A friend's route (already trimmed 200 m at each end).
struct FriendRouteMap: View {
    let points: [[Double]]

    var body: some View {
        let coordinates = points.filter { $0.count == 2 }.map { CLLocationCoordinate2D(latitude: $0[0], longitude: $0[1]) }
        Map(initialPosition: .automatic, interactionModes: []) {
            MapPolyline(coordinates: coordinates).stroke(KXColor.run, lineWidth: 4)
        }
        .frame(height: 160)
        .clipShape(RoundedRectangle(cornerRadius: KXRadius.sm, style: .continuous))
        .accessibilityLabel("Route map")
    }
}

/// Report someone (and block them, which also unfriends).
struct ReportSheet: View {
    let userId: UUID
    let name: String
    var sessionId: UUID?
    let onBlocked: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var reason = ""
    @State private var alsoBlock = true
    @State private var error: String?
    @State private var social = SocialService.shared

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("What's wrong? (optional)", text: $reason, axis: .vertical).lineLimit(3...6)
                    Toggle("Block \(name)", isOn: $alsoBlock)
                } footer: {
                    Text("Blocking removes them as a friend and hides you from each other. Reports are reviewed by the Kinetix team.")
                }
                if let error { Section { Text(error).foregroundStyle(KXColor.danger) } }
                Section {
                    Button("Block only", role: .destructive) { Task { await send(report: false) } }
                }
            }
            .navigationTitle("Report \(name)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Report") { Task { await send(report: true) } } }
            }
        }
        .presentationDetents([.medium])
    }

    private func send(report: Bool) async {
        guard let api = social.api else { return }
        do {
            if report { try await api.report(userId, session: sessionId, reason: reason.isEmpty ? "No reason given" : reason) }
            if alsoBlock || !report {
                try await api.block(userId)
                onBlocked()
            }
            dismiss()
        } catch {
            self.error = error.localizedDescription
        }
    }
}
