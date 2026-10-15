import SwiftUI
import WidgetKit

// MARK: - Timeline

struct SnapshotEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot?
}

/// Reads what the app last saved. The app refreshes it (and reloads widgets) whenever it
/// opens or goes to the background; this just re-reads every half hour.
struct SnapshotProvider: TimelineProvider {
    func placeholder(in context: Context) -> SnapshotEntry {
        SnapshotEntry(date: .now, snapshot: .placeholder)
    }

    func getSnapshot(in context: Context, completion: @escaping (SnapshotEntry) -> Void) {
        completion(SnapshotEntry(date: .now, snapshot: context.isPreview ? .placeholder : WidgetSnapshot.load() ?? .placeholder))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<SnapshotEntry>) -> Void) {
        let entry = SnapshotEntry(date: .now, snapshot: WidgetSnapshot.load())
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
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Image(systemName: "bolt.circle.fill").font(.title2).foregroundStyle(KXColor.accent)
            Text("Open Kinetix to get started").font(.caption).foregroundStyle(KXColor.inkSecondary)
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

// MARK: - Training load

struct LoadWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "KinetixLoad", provider: SnapshotProvider()) { entry in
            LoadWidgetView(snapshot: entry.snapshot)
                .containerBackground(KXColor.background, for: .widget)
                .widgetURL(URL(string: "kinetix://tab/today"))
        }
        .configurationDisplayName("Training load")
        .description("Your acute:chronic load ratio and zone.")
        .supportedFamilies([.systemSmall, .accessoryCircular, .accessoryRectangular])
    }
}

struct LoadWidgetView: View {
    let snapshot: WidgetSnapshot?
    @Environment(\.widgetFamily) private var family

    private var zoneColor: Color {
        switch snapshot?.loadZone {
        case "optimal": return KXColor.success
        case "high": return KXColor.danger
        case "undertrained": return KXColor.warning
        default: return KXColor.other
        }
    }

    private var zoneSymbol: String {
        switch snapshot?.loadZone {
        case "optimal": return "checkmark.circle.fill"
        case "high": return "exclamationmark.triangle.fill"
        case "undertrained": return "arrow.down.circle.fill"
        default: return "hourglass"
        }
    }

    private var ratioText: String { snapshot?.loadRatio.map { String(format: "%.2f", $0) } ?? "–" }

    var body: some View {
        if let snapshot {
            switch family {
            case .accessoryCircular:
                Gauge(value: min(snapshot.loadRatio ?? 0, 2), in: 0...2) {
                    Text("Load")
                } currentValueLabel: {
                    Text(ratioText)
                }
                .gaugeStyle(.accessoryCircular)
            case .accessoryRectangular:
                VStack(alignment: .leading, spacing: 1) {
                    Text("TRAINING LOAD").font(.caption2.weight(.bold))
                    Text(ratioText).font(.headline.monospacedDigit())
                    Label(snapshot.loadTitle, systemImage: zoneSymbol).font(.caption)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            default:
                VStack(alignment: .leading, spacing: 6) {
                    Text("TRAINING LOAD").font(.caption2.weight(.bold)).tracking(1).foregroundStyle(KXColor.inkSecondary)
                    Text(ratioText).font(.system(size: 38, weight: .bold, design: .rounded).monospacedDigit())
                        .foregroundStyle(KXColor.ink)
                    Label {
                        Text(snapshot.loadTitle).font(.caption.weight(.semibold)).foregroundStyle(KXColor.ink)
                    } icon: {
                        Image(systemName: zoneSymbol).foregroundStyle(zoneColor)
                    }
                    Text("Optimal 0.80–1.30").font(.caption2).foregroundStyle(KXColor.inkSecondary)
                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
        } else {
            NoDataView()
        }
    }
}
