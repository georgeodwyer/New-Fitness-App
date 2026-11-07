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
        Release(id: "2026-11-functional-2", title: "What's new", items: [
            Item(symbol: "figure.strengthtraining.functional", title: "Functional workouts",
                 detail: "Circuits and Hyrox in the Workout tab: rounds, intervals, EMOM and AMRAP, with run pace targets and the Apple Watch."),
            Item(symbol: "plus.circle", title: "Extra rest on the watch",
                 detail: "In a run's recovery, tap +30 S on the watch for more rest."),
            Item(symbol: "dumbbell", title: "Gym sessions carry on from last time",
                 detail: "Your own gym days now fill in the sets, reps and weights you did last time."),
            Item(symbol: "ellipsis.circle", title: "A tidier Plan tab",
                 detail: "Week review, rearrange, build my plan and pause are in the ••• menu at the top."),
            Item(symbol: "speaker.wave.2", title: "Audio fixes",
                 detail: "Music comes back to full volume after a cue, and paces are read out properly."),
            Item(symbol: "slider.horizontal.3", title: "Check-in sliders",
                 detail: "Every slider now goes from worst on the left to best on the right.")
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
