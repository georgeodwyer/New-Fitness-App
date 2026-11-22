import SwiftUI

/// Plain-English explanations of the words Kinetix uses, shown from a small "?" next to them
/// and listed on the Help page.
enum Glossary: String, CaseIterable, Identifiable {
    case readiness, recovery, exertion, weekVsUsual, legs, paces, estimatedMax, rpe, points

    var id: String { rawValue }

    var title: String {
        switch self {
        case .readiness: return "Readiness"
        case .recovery: return "Recovery score"
        case .exertion: return "Exertion"
        case .weekVsUsual: return "Week vs your usual"
        case .legs: return "Legs"
        case .paces: return "Your paces"
        case .estimatedMax: return "Estimated 1-rep max"
        case .rpe: return "Effort (RPE)"
        case .points: return "Points and levels"
        }
    }

    var text: String {
        switch self {
        case .readiness:
            return "How ready you are to train today. It combines your morning check-in with Apple Health (sleep, resting heart rate and HRV) when connected. On a low day you're offered a lighter session when you start."
        case .recovery:
            return "0 to 100: how recovered you are today, from your check-in and, with Apple Health, last night's sleep, resting heart rate and heart rate variability. Above 70 is good; below 40 means take it easy."
        case .exertion:
            return "How hard today has been, 0 to 100, from every session (heart rate when there is one, otherwise time and effort). The target range is set by your plan and how recovered you are."
        case .weekVsUsual:
            return "Your last 7 days of training compared with your average week. Big jumps above your usual are when injuries tend to happen, so Kinetix keeps an eye on it."
        case .legs:
            return "How much hard work your legs have done in the last few days (runs and leg sessions), so heavy leg days stay away from your key runs."
        case .paces:
            return "Your training paces (easy, tempo, interval and so on), worked out from a recent race or time trial. They update as you get fitter."
        case .estimatedMax:
            return "The most you could probably lift once, worked out from a set of several reps (for example 80 kg for 8 reps is about 101 kg). Used to track strength without ever testing a true max."
        case .rpe:
            return "Rate of perceived exertion: how hard a set felt, 1 to 10. 10 means you couldn't have done another rep; 8 means about two left in the tank."
        case .points:
            return "You earn points for each planned session you do (+20), for completing every planned session in a week (+50), for each week in a row you train (+5, up to 50), and a little for training load. Points add up to your level."
        }
    }
}

/// A small "?" that explains a term.
struct InfoButton: View {
    let term: Glossary
    @State private var showing = false

    init(_ term: Glossary) { self.term = term }

    var body: some View {
        Button { showing = true } label: {
            Image(systemName: "questionmark.circle")
                .font(KXFont.caption)
                .foregroundStyle(KXColor.inkTertiary)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("What is \(term.title)?")
        .popover(isPresented: $showing) {
            VStack(alignment: .leading, spacing: KXSpacing.sm) {
                Text(term.title).font(KXFont.headline).foregroundStyle(KXColor.ink)
                Text(term.text).font(KXFont.callout).foregroundStyle(KXColor.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(KXSpacing.lg)
            .frame(width: 300)
            .presentationCompactAdaptation(.popover)
        }
    }
}

/// Help & questions: common questions, what the words mean, and the tours again.
struct HelpView: View {
    private struct Question: Identifiable {
        let question: String
        let answer: String
        var id: String { question }
    }

    private let questions: [Question] = [
        Question(question: "I missed a session. What now?",
                 answer: "Nothing to do: carry on with the next one. Kinetix notices and keeps the rest of the week sensible. To fit it in elsewhere, use Plan → Adjust plan → Rearrange."),
        Question(question: "How do I move a session to another day?",
                 answer: "Plan → Adjust plan → Rearrange this week or next, then drag sessions between days. Kinetix warns you if a hard day lands next to another."),
        Question(question: "I'm ill, injured or away.",
                 answer: "Plan → Adjust plan → Pause plan. When you're back, Kinetix eases you in rather than picking up where you left off."),
        Question(question: "Why did my plan change?",
                 answer: "Tap the bell on Today to see each change and why: usually your check-in, a missed or extra session, or your fitness improving."),
        Question(question: "Do runs from my watch or other apps count?",
                 answer: "Yes. Workouts in Apple Health count towards your training load. If one lines up with a planned run, Today asks whether to count it."),
        Question(question: "How do I add more to Today?",
                 answer: "Tap ••• on Today, then Edit dashboard. Switch on cards like This week vs plan, Body or Records, and drag to reorder."),
        Question(question: "How are my paces worked out?",
                 answer: "From the race time or time trial you gave when setting up, updated from your runs as you get fitter. Change it in Settings → Training profile."),
        Question(question: "How do I add friends?",
                 answer: "Activity → Achievements → Friends. Choose a username, then search for friends, share your invite link or show your QR code."),
        Question(question: "Is my data private?",
                 answer: "Everything stays on your iPhone unless you create an account, connect an app or add friends. See Settings → Privacy policy."),
    ]

    var body: some View {
        List {
            Section("Common questions") {
                ForEach(questions) { item in
                    DisclosureGroup {
                        Text(item.answer).font(KXFont.callout).foregroundStyle(KXColor.inkSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    } label: {
                        Text(item.question).font(KXFont.body).foregroundStyle(KXColor.ink)
                    }
                }
            }
            Section("What the words mean") {
                ForEach(Glossary.allCases) { term in
                    DisclosureGroup {
                        Text(term.text).font(KXFont.callout).foregroundStyle(KXColor.inkSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    } label: {
                        Text(term.title).font(KXFont.body).foregroundStyle(KXColor.ink)
                    }
                }
            }
            Section {
                Button {
                    TabTours.resetAll()
                } label: {
                    Label("Show the tour for each tab again", systemImage: "lightbulb")
                }
            } footer: {
                Text("Each tab shows its quick tour the next time you open it, and Today shows Getting started again if anything's left.")
            }
        }
        .navigationTitle("Help & questions")
        .navigationBarTitleDisplayMode(.inline)
        .scrollContentBackground(.hidden)
        .background(KXColor.background.ignoresSafeArea())
        .tint(KXColor.accent)
    }
}
