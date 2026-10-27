import SwiftUI
import WidgetKit

// MARK: - Timeline

struct SnapshotEntry: TimelineEntry {
    let date: Date
    /// nil when there's nothing saved yet, or when what's saved is from an earlier day.
    let snapshot: WidgetSnapshot?
}

extension WidgetSnapshot {
    /// Saved today: an older snapshot would show yesterday's sessions and exertion.
    func isCurrent(at date: Date = .now) -> Bool { Calendar.current.isDate(updatedAt, inSameDayAs: date) }

    /// What the widgets show: today's snapshot only.
    static func current(at date: Date = .now) -> WidgetSnapshot? {
        load().flatMap { $0.isCurrent(at: date) ? $0 : nil }
    }
}

/// Reads what the app last saved. The app refreshes it (and reloads widgets) whenever it
/// opens or goes to the background; this just re-reads every half hour.
struct SnapshotProvider: TimelineProvider {
    func placeholder(in context: Context) -> SnapshotEntry {
        SnapshotEntry(date: .now, snapshot: .placeholder)
    }

    func getSnapshot(in context: Context, completion: @escaping (SnapshotEntry) -> Void) {
        completion(SnapshotEntry(date: .now, snapshot: context.isPreview ? .placeholder : WidgetSnapshot.current() ?? .placeholder))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<SnapshotEntry>) -> Void) {
        let entry = SnapshotEntry(date: .now, snapshot: WidgetSnapshot.current())
        // Also refresh just after midnight so "today" moves on.
        let midnight = Calendar.current.startOfDay(for: .now).addingTimeInterval(24 * 3600 + 60)
        let next = min(Date.now.addingTimeInterval(30 * 60), midnight)
        completion(Timeline(entries: [entry], policy: .after(next)))
    }
}

private func disciplineColor(_ discipline: String) -> Color {
    switch discipline {
    case "run": return KXColor.run
    case "strength": return KXColor.lift
    default: return KXColor.other
    }
}

private struct NoDataView: View {
    /// Something was saved before today (vs never).
    private var hasOlderData: Bool { WidgetSnapshot.load() != nil }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Image(systemName: "bolt.circle.fill").font(.title2).foregroundStyle(KXColor.accent)
            Text(hasOlderData ? "Open Kinetix to update today" : "Open Kinetix to get started")
                .font(.caption).foregroundStyle(KXColor.inkSecondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

// MARK: - Today

struct TodayWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "KinetixToday", provider: SnapshotProvider()) { entry in
            TodayWidgetView(snapshot: entry.snapshot)
                .containerBackground(KXColor.background, for: .widget)
                .widgetURL(URL(string: "kinetix://tab/today"))
        }
        .configurationDisplayName("Today")
        .description("Your next session.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryRectangular, .accessoryInline])
    }
}

struct TodayWidgetView: View {
    let snapshot: WidgetSnapshot?
    @Environment(\.widgetFamily) private var family

    private var next: WidgetSnapshot.Session? { snapshot?.today.first { !$0.isDone } }

    var body: some View {
        if let snapshot {
            switch family {
            case .accessoryInline:
                Text(next.map { "Today: \($0.title)" } ?? (snapshot.hasPlan ? "Rest day" : "Kinetix"))
            case .accessoryRectangular:
                VStack(alignment: .leading, spacing: 1) {
                    Text("TODAY").font(.caption2.weight(.bold))
                    Text(next?.title ?? (snapshot.hasPlan ? "Rest day" : "No plan")).font(.headline).lineLimit(1)
                    Text(next?.detail ?? (snapshot.today.isEmpty ? "Recovery is training too" : "All done today"))
                        .font(.caption).lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            default:
                full(snapshot)
            }
        } else {
            NoDataView()
        }
    }

    private func full(_ snapshot: WidgetSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("TODAY").font(.caption2.weight(.bold)).tracking(1).foregroundStyle(KXColor.inkSecondary)
            if snapshot.today.isEmpty {
                Image(systemName: snapshot.hasPlan ? "bed.double.fill" : "figure.run")
                    .font(.title2).foregroundStyle(KXColor.accent)
                Text(snapshot.hasPlan ? "Rest day" : "Record a run or workout")
                    .font(.headline).foregroundStyle(KXColor.ink)
            } else {
                ForEach(snapshot.today.prefix(family == .systemMedium ? 2 : 1)) { session in
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: session.isDone ? "checkmark.circle.fill" : session.symbol)
                            .font(.title3)
                            .foregroundStyle(session.isDone ? KXColor.success : disciplineColor(session.discipline))
                            .frame(width: 26)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(session.title).font(.headline).foregroundStyle(KXColor.ink).lineLimit(1)
                                .strikethrough(session.isDone)
                            Text(session.detail).font(.caption).foregroundStyle(KXColor.inkSecondary).lineLimit(2)
                        }
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

// MARK: - This week

struct WeekWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "KinetixWeek", provider: SnapshotProvider()) { entry in
            WeekWidgetView(snapshot: entry.snapshot)
                .containerBackground(KXColor.background, for: .widget)
                .widgetURL(URL(string: "kinetix://tab/progress"))
        }
        .configurationDisplayName("This week")
        .description("Sessions done and distance and volume against your plan.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryCircular, .accessoryRectangular])
    }
}

struct WeekWidgetView: View {
    let snapshot: WidgetSnapshot?
    @Environment(\.widgetFamily) private var family

    var body: some View {
        if let snapshot {
            let fraction = snapshot.sessionsPlanned > 0 ? Double(snapshot.sessionsDone) / Double(snapshot.sessionsPlanned) : 0
            switch family {
            case .accessoryCircular:
                Gauge(value: min(fraction, 1)) {
                    Image(systemName: "figure.run")
                } currentValueLabel: {
                    Text("\(snapshot.sessionsDone)/\(snapshot.sessionsPlanned)")
                }
                .gaugeStyle(.accessoryCircularCapacity)
            case .accessoryRectangular:
                VStack(alignment: .leading, spacing: 1) {
                    Text("THIS WEEK").font(.caption2.weight(.bold))
                    Text("\(snapshot.sessionsDone) of \(snapshot.sessionsPlanned) sessions").font(.headline)
                    Text("\(snapshot.runDone) run · \(snapshot.liftDone)").font(.caption).lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            default:
                VStack(alignment: .leading, spacing: 8) {
                    Text("THIS WEEK").font(.caption2.weight(.bold)).tracking(1).foregroundStyle(KXColor.inkSecondary)
                    HStack(spacing: 12) {
                        ZStack {
                            Circle().stroke(KXColor.border, lineWidth: 7)
                            Circle().trim(from: 0, to: min(fraction, 1))
                                .stroke(KXColor.accent, style: StrokeStyle(lineWidth: 7, lineCap: .round))
                                .rotationEffect(.degrees(-90))
                            VStack(spacing: 0) {
                                Text("\(snapshot.sessionsDone)/\(snapshot.sessionsPlanned)").font(.headline.monospacedDigit())
                                Text("sessions").font(.system(size: 9)).foregroundStyle(KXColor.inkSecondary)
                            }
                        }
                        .frame(width: 70, height: 70)
                        if family == .systemMedium {
                            VStack(alignment: .leading, spacing: 8) {
                                bar("Running", done: snapshot.runDone, planned: snapshot.runPlanned, fraction: snapshot.runFraction, color: KXColor.run)
                                bar("Lifting", done: snapshot.liftDone, planned: snapshot.liftPlanned, fraction: snapshot.liftFraction, color: KXColor.lift)
                            }
                        }
                    }
                    if family == .systemSmall {
                        Text("\(snapshot.runDone) run").font(.caption).foregroundStyle(KXColor.inkSecondary)
                    }
                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
        } else {
            NoDataView()
        }
    }

    private func bar(_ label: String, done: String, planned: String, fraction: Double, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text(label).font(.caption.weight(.semibold)).foregroundStyle(KXColor.ink)
                Spacer()
                Text(planned.isEmpty ? done : "\(done) / \(planned)").font(.caption2.monospacedDigit()).foregroundStyle(KXColor.inkSecondary)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(KXColor.border)
                    Capsule().fill(color).frame(width: geo.size.width * min(max(fraction, 0), 1))
                }
            }
            .frame(height: 6)
        }
    }
}

// MARK: - Strain

struct LoadWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "KinetixLoad", provider: SnapshotProvider()) { entry in
            LoadWidgetView(snapshot: entry.snapshot)
                .containerBackground(KXColor.background, for: .widget)
                .widgetURL(URL(string: "kinetix://tab/today"))
        }
        .configurationDisplayName("Exertion")
        .description("Today's exertion against your target, and your recovery.")
        .supportedFamilies([.systemSmall, .accessoryCircular, .accessoryRectangular])
    }
}

struct LoadWidgetView: View {
    let snapshot: WidgetSnapshot?
    @Environment(\.widgetFamily) private var family

    private var strain: Double { snapshot?.strain ?? 0 }
    private var strainText: String { snapshot?.strain.map { "\(Int($0.rounded()))" } ?? "–" }
    private var targetText: String? {
        guard let low = snapshot?.strainLow, let high = snapshot?.strainHigh else { return nil }
        return String(format: "Target %.1f–%.1f", low, high)
    }
    private var recoveryText: String? { snapshot?.recovery.map { "Recovery \(Int($0))" } }

    var body: some View {
        if let snapshot {
            switch family {
            case .accessoryCircular:
                Gauge(value: min(strain, 100), in: 0...100) {
                    Text("Exertion")
                } currentValueLabel: {
                    Text(strainText)
                }
                .gaugeStyle(.accessoryCircular)
            case .accessoryRectangular:
                VStack(alignment: .leading, spacing: 1) {
                    Text("EXERTION").font(.caption2.weight(.bold))
                    Text(strainText + " / 100").font(.headline.monospacedDigit())
                    if let targetText { Text(targetText).font(.caption) }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            default:
                VStack(alignment: .leading, spacing: 6) {
                    Text("EXERTION").font(.caption2.weight(.bold)).tracking(1).foregroundStyle(KXColor.inkSecondary)
                    HStack(alignment: .firstTextBaseline, spacing: 2) {
                        Text(strainText).font(.system(size: 38, weight: .bold, design: .rounded).monospacedDigit())
                            .foregroundStyle(KXColor.ink)
                        Text("/100").font(.caption).foregroundStyle(KXColor.inkSecondary)
                    }
                    if let targetText {
                        Text(targetText).font(.caption.weight(.semibold)).foregroundStyle(KXColor.ink)
                    }
                    if let recoveryText {
                        Text(recoveryText).font(.caption2).foregroundStyle(KXColor.inkSecondary)
                    }
                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .widgetAccentable()
                .opacity(snapshot.strain == nil ? 0.6 : 1)
            }
        } else {
            NoDataView()
        }
    }
}
