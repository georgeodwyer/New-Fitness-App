import SwiftUI

/// The privacy policy, in plain English. Keep in sync with docs/privacy-policy.md (the
/// public copy linked from the App Store listing).
struct PrivacyPolicyView: View {
    static let lastUpdated = "18 November 2026"

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: KXSpacing.lg) {
                KXAccentHeadline(plain: "Your data,", accented: "your call")
                Text("Last updated \(Self.lastUpdated)").font(KXFont.caption).foregroundStyle(KXColor.inkSecondary)
                ForEach(Self.sections) { section in
                    VStack(alignment: .leading, spacing: KXSpacing.xs) {
                        Text(section.title).font(KXFont.headline).foregroundStyle(KXColor.ink)
                        Text(section.body).font(KXFont.callout).foregroundStyle(KXColor.inkSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .kxCard()
                    .accessibilityElement(children: .combine)
                }
            }
            .padding(KXSpacing.screenMargin)
        }
        .background(KXColor.background.ignoresSafeArea())
        .navigationTitle("Privacy")
        .navigationBarTitleDisplayMode(.inline)
    }

    struct Section: Identifiable {
        let title: String
        let body: String
        var id: String { title }
    }

    static let sections: [Section] = [
        Section(title: "The short version",
                body: "Kinetix works on your iPhone and Apple Watch. Nothing leaves them unless you create an account (to back up and sync) or connect Strava or Garmin. We never sell your data, never use it for advertising, never use it to train AI models and never track you across other apps or websites."),
        Section(title: "What's stored on your iPhone",
                body: "Your answers from setup (experience, goal, training days, equipment, units), your plan, the runs and lifts you log (including routes, splits, heart rate, steps and effort), your saved workouts and routes, personal records, recovery check-ins and your settings."),
        Section(title: "If you create an account",
                body: "Your email address (or the private relay address from Sign in with Apple) and a copy of the data above are stored with our database provider, Supabase, so your training is backed up and syncs to your other devices. Only you can read your records."),
        Section(title: "Location",
                body: "Used while you're recording a run, to measure distance and pace and draw your route (the route is saved with that run), and while you plan a route, to centre the map on you. Planned routes are drawn using Apple Maps walking directions: the points you tap are sent to Apple to work out the path, and aren't linked to your account. Routes you save are stored with your other data."),
        Section(title: "Motion & Fitness",
                body: "Used during runs to count your steps, for your cadence and stride length, and on treadmill runs to measure distance without GPS. The step count is kept with that run."),
        Section(title: "Apple Health",
                body: "Only if you connect it. Kinetix reads heart rate, resting heart rate, heart rate variability, sleep, steps, active energy, VO2 max, breathing rate and workouts from other apps to show live heart rate and your body trends, judge recovery and balance your training load, and saves your runs and strength sessions to Health. These readings are read fresh from Health on this iPhone each time and are not stored in Kinetix or sent to our servers. Health data is never used for advertising or shared with anyone for marketing. Heart rate recorded during a Kinetix run is kept with that run (and backed up to your account if you have one)."),
        Section(title: "Apple Watch",
                body: "The Kinetix watch app records runs and gym sessions with the watch's heart rate, location and motion sensors. Your plan goes from your iPhone to the watch, and finished sessions come back the same way, directly between your own devices."),
        Section(title: "Bluetooth",
                body: "Used only to connect the heart rate strap you choose. The strap's identifier is stored on this iPhone so it can reconnect."),
        Section(title: "Notifications",
                body: "Reminders and summaries are made on your iPhone from your own plan and training. Nothing is sent from a server, and you choose which you get in Settings → Notifications."),
        Section(title: "Strava",
                body: "Only if you connect it. Kinetix uploads the sessions you've chosen (runs, and strength sessions if you turn that on) to your Strava account. It doesn't read or store your Strava activities. The Strava sign-in is kept in this iPhone's secure Keychain. Disconnecting revokes Kinetix's access. What happens on Strava is covered by Strava's own privacy policy."),
        Section(title: "Garmin",
                body: "Only if you connect it. With the Kinetix app on a Garmin watch, your planned runs go from your iPhone to the watch through Garmin's Connect IQ link, and runs you record on it come back the same way. With Garmin Connect linked, Kinetix puts your planned runs on your Garmin Connect calendar and receives your finished activities (summary, laps and heart rate) so it can tick off your plan. Your Garmin sign-in is held on our server (Supabase), never on your iPhone, and is used only for this. Finished activities wait there only until Kinetix on your iPhone has saved them, then they're deleted. Disconnect at any time in Settings → Garmin or in Garmin Connect, and your Garmin sign-in and calendar records are deleted straight away. What happens on Garmin Connect is covered by Garmin's own privacy policy."),
        Section(title: "Sharing",
                body: "Share cards are made on your iPhone. Nothing is posted unless you choose an app to share to; saving a card to Photos asks for permission to add images. The Instagram Stories button hands the image to the Instagram app on your phone. A workout you send to a friend is a file with the workout's steps and paces, sent through the app you choose."),
        Section(title: "Your choices",
                body: "Export everything as a file from Profile → Settings → Account. Delete your account and all your data, on this iPhone and in the cloud (including any Garmin link), from the same place. Disconnect Apple Health in the Health app, and Strava or Garmin in Settings, at any time."),
        Section(title: "Children",
                body: "Kinetix isn't intended for children under 16."),
        Section(title: "Changes and questions",
                body: "If this policy changes, the new version will appear here and on our website with a new date. For questions, use the contact details on our website or the App Store page."),
    ]
}
