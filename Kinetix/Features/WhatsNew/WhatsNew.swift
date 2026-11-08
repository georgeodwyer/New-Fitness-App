import SwiftUI

/// "What's new": shown once after an update with the newest notes. Add an entry at the top of
/// `releases` with each TestFlight / App Store build (a new id shows it again).
enum WhatsNew {
    struct Item: Identifiable {
        let symbol: String
        let title: String
        let detail: String
        var id: String { title }
    }

    struct Release: Identifiable {
        /// Any new value shows the screen once.
        let id: String
        let title: String
        let items: [Item]
    }

    static let releases: [Release] = [
        Release(id: "2026-11-treadmill-1", title: "What's new", items: [
            Item(symbol: "figure.run.treadmill", title: "Treadmill runs",
                 detail: "Turn on \u{201C}On a treadmill\u{201D} before a run. Kinetix tells you the speed to set for each step and counts distance from it, or from your steps."),
            Item(symbol: "ruler", title: "Match the treadmill",
                 detail: "At the end, type in the treadmill's distance and your pace and splits are corrected to it."),
            Item(symbol: "heart.text.square", title: "Saved as indoor",
                 detail: "Treadmill runs go to Apple Health as indoor runs and to Strava marked as treadmill runs.")
        ]),
        Release(id: "2026-11-feedback-1", title: "What's new", items: [
            Item(symbol: "figure.strengthtraining.functional", title: "Functional workouts",
                 detail: "Circuits and Hyrox in the Workout tab: rounds, intervals, EMOM and AMRAP, with run pace targets and the Apple Watch."),
            Item(symbol: "books.vertical", title: "Workout bank",
                 detail: "Browse every Kinetix gym session in the Workout tab and start one, or save it as your own."),
            Item(symbol: "chart.line.uptrend.xyaxis", title: "Progress for your lifts",
                 detail: "Graphs for your main lifts (or ones you choose), and every lift listed by name."),
            Item(symbol: "trophy", title: "Achievements",
                 detail: "Earn badges for check-ins, runs, distance, gym sessions, records and weeks in a row. See them in Settings."),
            Item(symbol: "arrow.triangle.2.circlepath", title: "Keep your changes",
                 detail: "Added an exercise or a set? The summary asks whether to keep it for next time."),
            Item(symbol: "bubble.left.and.text.bubble.right", title: "Weekly check-in",
                 detail: "Tell Kinetix how the week went and it can make next week lighter or a little harder."),
            Item(symbol: "plus.circle", title: "Extra rest on the watch",
                 detail: "In a run's recovery, tap +30 S on the watch for more rest."),
            Item(symbol: "dumbbell", title: "Gym sessions carry on from last time",
                 detail: "Your own gym days fill in the sets, reps and weights you did last time."),
            Item(symbol: "heart.text.square", title: "Recovery without a watch",
                 detail: "Your check-in now makes the whole score when there's no watch data, and a really bad answer always shows."),
            Item(symbol: "ellipsis.circle", title: "A tidier Plan tab",
                 detail: "Week review, rearrange, build my plan and pause are in the ••• menu at the top."),
            Item(symbol: "speaker.wave.2", title: "Fixes",
                 detail: "Music comes back to full volume after a cue, paces are read out properly, check-in sliders all run worst to best, and Rearrange week has Cancel.")
        ])
    ]

    private static let seenKey = "whatsNew.lastSeen"

    /// The notes to show now: the newest release, once. New installs don't see it (they get
    /// the walkthrough instead), they just mark it seen.
    static func pending(isNewInstall: Bool, defaults: UserDefaults = .standard) -> Release? {
        guard let latest = releases.first else { return nil }
        if defaults.string(forKey: seenKey) == latest.id { return nil }
        if isNewInstall {
            markSeen(latest, defaults: defaults)
            return nil
        }
        return latest
    }

    static func markSeen(_ release: Release, defaults: UserDefaults = .standard) {
        defaults.set(release.id, forKey: seenKey)
    }
}

struct WhatsNewView: View {
    let release: WhatsNew.Release
    let onDone: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: KXSpacing.lg) {
            ScrollView {
                VStack(alignment: .leading, spacing: KXSpacing.lg) {
                    KXWordmark(height: 18)
                    Text(release.title).font(KXFont.display).foregroundStyle(KXColor.ink)
                    ForEach(release.items) { item in
                        HStack(alignment: .top, spacing: KXSpacing.md) {
                            Image(systemName: item.symbol)
                                .font(.title3.weight(.semibold))
                                .foregroundStyle(KXColor.accent)
                                .frame(width: 32)
                                .accessibilityHidden(true)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.title).font(KXFont.bodyEmphasis).foregroundStyle(KXColor.ink)
                                Text(item.detail).font(KXFont.callout).foregroundStyle(KXColor.inkSecondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        .accessibilityElement(children: .combine)
                    }
                }
                .padding(.top, KXSpacing.xl)
            }
            Button("Continue", action: onDone)
                .buttonStyle(.kx(.primary, fullWidth: true))
                .accessibilityIdentifier("whatsNew.continue")
        }
        .padding(KXSpacing.screenMargin)
        .background(KXColor.background.ignoresSafeArea())
    }
}
