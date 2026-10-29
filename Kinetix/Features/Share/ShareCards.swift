import SwiftUI
import UIKit
import TrainingEngine

/// What goes on a share card.
struct ShareCardData {
    enum Kind { case run, strength }

    var kind: Kind
    var title: String
    var subtitle: String
    /// Up to three big numbers, e.g. ("Distance", "10.02 km").
    var metrics: [(label: String, value: String)]
    /// Extra lines for strength cards ("Back Squat · 100 kg × 5").
    var lines: [String] = []
    var badge: String?
    /// Route to draw (already privacy-trimmed when asked).
    var route: [RoutePoint] = []
    var units: UnitSystem = .metric
    /// Charts for runs (splits, reps, heart rate, best efforts, elevation).
    var details: RunShareDetails?
}

/// The numbers behind the run charts on share cards.
struct RunShareDetails {
    struct Rep {
        var pace: Pace
        var target: PaceRange?
        var inRange: Bool
    }
    struct Effort {
        var name: String
        var time: String
        var isNewBest: Bool
    }

    var splits: [Pace] = []
    var reps: [Rep] = []
    /// "4:28–4:34/km" when every rep had the same target.
    var repTarget: String?
    var averageHeartRate: Double?
    var maxHeartRate: Double?
    /// Zones 1–5.
    var zoneSeconds: [Double] = []
    var efforts: [Effort] = []
    var elevationGain: Double?
    var elevationProfile: [Double] = []

    var repsOnPace: Int { reps.filter(\.inRange).count }
    var hasSplits: Bool { splits.count >= 2 }
    var hasReps: Bool { reps.count >= 2 }
    var hasHeartRate: Bool { averageHeartRate != nil || zoneSeconds.contains { $0 > 0 } }
    var hasEffortsOrElevation: Bool { !efforts.isEmpty || elevationGain != nil }
}

/// Which sections the Details card shows (remembered between shares).
struct ShareDetailOptions: Equatable {
    var splits = true
    var pace = true
    var heartRate = true
    var effortsAndElevation = true
}

enum ShareCardStyle: String, CaseIterable, Identifiable {
    case map = "Map"
    case photo = "Photo"
    case sticker = "Sticker"
    case details = "Details"
    var id: String { rawValue }
}

/// A route scaled into a rectangle, keeping its shape.
struct RouteShape: Shape {
    let route: [RoutePoint]

    func path(in rect: CGRect) -> Path {
        guard route.count > 1 else { return Path() }
        // Equirectangular projection is fine at running scales.
        let midLat = route.map(\.latitude).reduce(0, +) / Double(route.count) * .pi / 180
        let xs = route.map { $0.longitude * cos(midLat) }
        let ys = route.map(\.latitude)
        guard let minX = xs.min(), let maxX = xs.max(), let minY = ys.min(), let maxY = ys.max() else { return Path() }
        let width = max(maxX - minX, 1e-9), height = max(maxY - minY, 1e-9)
        let scale = min(rect.width / width, rect.height / height)
        let offsetX = rect.minX + (rect.width - width * scale) / 2
        let offsetY = rect.minY + (rect.height - height * scale) / 2
        var path = Path()
        for (index, (x, y)) in zip(xs, ys).enumerated() {
            let point = CGPoint(x: offsetX + (x - minX) * scale, y: offsetY + (maxY - y) * scale)
            if index == 0 { path.move(to: point) } else { path.addLine(to: point) }
        }
        return path
    }
}

/// The card palette: the app's dark Volt theme, fixed so cards look the same in light mode.
enum CardColor {
    static let ground = Color(hex: 0x050506)
    static let surface = Color(hex: 0x111113)
    static let surfaceTint = Color(hex: 0x1B1B1E)
    static let track = Color(hex: 0x2A2B2F)
    static let ink = Color(hex: 0xF4F5F1)
    static let inkSecondary = Color(hex: 0xA2A59F)
    static let volt = Color(hex: 0xD6FF3D)
    static let onVolt = Color(hex: 0x0A0B05)
    static let run = Color(hex: 0x3BD3FF)
    static let lift = Color(hex: 0xFF5FA2)
    static let good = Color(hex: 0x36E27E)
    static let warn = Color(hex: 0xFFC23D)
    static let hot = Color(hex: 0xFF4F4F)
    static let slate = Color(hex: 0x8A979C)
    static let zones = [slate, run, good, warn, hot]
}

private extension Color {
    init(hex: UInt32) {
        self.init(red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255, blue: Double(hex & 0xFF) / 255)
    }
}

/// Fixed-size card fonts (cards are images: they don't follow Dynamic Type).
enum CardFont {
    static func condensed(_ size: CGFloat, _ face: KXFont.Face = .condensedBold) -> Font { .custom(face.rawValue, fixedSize: size) }
    static func label(_ size: CGFloat = 12) -> Font { .custom(KXFont.Face.condensedSemiBold.rawValue, fixedSize: size) }
    static func text(_ size: CGFloat, _ face: KXFont.Face = .regular) -> Font { .custom(face.rawValue, fixedSize: size) }
}

/// A 9:16 card (1080 × 1920 when rendered at 3×), or a transparent sticker.
struct ShareCardView: View {
    let data: ShareCardData
    let style: ShareCardStyle
    var mapImage: UIImage?
    var photo: UIImage?
    var options = ShareDetailOptions()

    static let size = CGSize(width: 360, height: 640)

    private var format: DisplayFormat { DisplayFormat(units: data.units) }
    private var kindColor: Color { data.kind == .run ? CardColor.run : CardColor.lift }

    var body: some View {
        Group {
            switch style {
            case .sticker: sticker
            case .photo: photoCard
            case .map: mapCard
            case .details: detailsCard
            }
        }
        .environment(\.colorScheme, .dark)
    }

    // MARK: Map card

    private var mapCard: some View {
        VStack(spacing: 0) {
            ZStack(alignment: .bottom) {
                if let mapImage {
                    Image(uiImage: mapImage).resizable().scaledToFill()
                } else {
                    CardColor.surface
                    if !data.route.isEmpty {
                        RouteShape(route: data.route)
                            .stroke(CardColor.volt, style: StrokeStyle(lineWidth: 6, lineCap: .round, lineJoin: .round))
                            .padding(44)
                    } else {
                        Image(systemName: data.kind == .run ? "figure.run" : "dumbbell.fill")
                            .font(.system(size: 90, weight: .bold)).foregroundStyle(kindColor)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
                LinearGradient(colors: [CardColor.ground.opacity(0), CardColor.ground], startPoint: .top, endPoint: .bottom)
                    .frame(height: 90)
            }
            .frame(width: Self.size.width, height: 330)
            .clipped()
            VStack(alignment: .leading, spacing: 14) {
                header(titleSize: 38)
                metricRow(size: 34)
                if !data.lines.isEmpty { linesView }
                if let details = data.details {
                    if details.hasReps { repStrip(details) } else if details.hasSplits { splitStrip(details) }
                }
                Spacer(minLength: 0)
                brand
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 24)
            .frame(width: Self.size.width, height: Self.size.height - 330, alignment: .topLeading)
        }
        .frame(width: Self.size.width, height: Self.size.height)
        .background(CardColor.ground)
    }

    // MARK: Photo card

    private var photoCard: some View {
        ZStack(alignment: .bottomLeading) {
            if let photo {
                Image(uiImage: photo).resizable().scaledToFill()
                    .frame(width: Self.size.width, height: Self.size.height).clipped()
            } else {
                LinearGradient(colors: [Color(hex: 0x3A4A52), Color(hex: 0x1D2629), Color(hex: 0x0B0E10)],
                               startPoint: .topLeading, endPoint: .bottomTrailing)
            }
            LinearGradient(colors: [CardColor.ground.opacity(0), CardColor.ground.opacity(0.92)], startPoint: .center, endPoint: .bottom)
            VStack(alignment: .leading, spacing: 14) {
                if !data.route.isEmpty {
                    RouteShape(route: data.route)
                        .stroke(CardColor.volt, style: StrokeStyle(lineWidth: 3.5, lineCap: .round, lineJoin: .round))
                        .frame(width: 96, height: 80, alignment: .leading)
                        .shadow(color: .black.opacity(0.4), radius: 3)
                }
                header(titleSize: 38)
                Rectangle().fill(CardColor.ink.opacity(0.18)).frame(height: 1)
                metricRow(size: 32)
                if !data.lines.isEmpty { linesView }
                brand
            }
            .padding(24)
        }
        .frame(width: Self.size.width, height: Self.size.height)
    }

    // MARK: Sticker (transparent)

    private var sticker: some View {
        VStack(spacing: 12) {
            if !data.route.isEmpty {
                RouteShape(route: data.route)
                    .stroke(CardColor.volt, style: StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round))
                    .frame(width: 165, height: 140)
            }
            ForEach(Array(data.metrics.enumerated()), id: \.offset) { index, metric in
                VStack(spacing: 0) {
                    Text(metric.label.uppercased()).font(CardFont.label(13)).tracking(1.5)
                    Text(metric.value).font(CardFont.condensed(44)).monospacedDigit()
                        .foregroundStyle(index == data.metrics.count - 1 && data.kind == .run ? CardColor.volt : CardColor.ink)
                }
            }
            ForEach(data.lines.prefix(3), id: \.self) { line in
                Text(line).font(CardFont.text(12, .semiBold))
            }
            wordmark(height: 22).padding(.top, 4)
        }
        .foregroundStyle(CardColor.ink)
        .shadow(color: .black.opacity(0.5), radius: 4, y: 1)
        .padding(24)
        .frame(width: Self.size.width)
    }

    // MARK: Details card

    private var detailsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .bottom) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(data.subtitle.uppercased()).font(CardFont.label(12)).tracking(1.4).foregroundStyle(kindColor)
                    Text(data.title.uppercased()).font(CardFont.condensed(28)).foregroundStyle(CardColor.ink).lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
                Spacer(minLength: 8)
                VStack(alignment: .trailing, spacing: 0) {
                    ForEach(Array(data.metrics.prefix(2).enumerated()), id: \.offset) { index, metric in
                        Text(metric.value).font(CardFont.condensed(index == 0 ? 20 : 16))
                            .foregroundStyle(index == 0 ? CardColor.ink : CardColor.inkSecondary)
                    }
                }
            }
            if let details = data.details {
                if options.splits, details.hasSplits { splitsPanel(details) }
                if options.pace, details.hasReps { repsPanel(details) }
                if options.heartRate, details.hasHeartRate { heartRatePanel(details) }
                if options.effortsAndElevation, details.hasEffortsOrElevation { effortsPanel(details) }
            }
            Spacer(minLength: 0)
            brand
        }
        .padding(22)
        .frame(width: Self.size.width, height: Self.size.height, alignment: .topLeading)
        .background(CardColor.ground)
    }

    private func panel<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6, content: content)
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(CardColor.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func panelTitle(_ left: String, _ right: String? = nil, rightColor: Color = CardColor.ink) -> some View {
        HStack {
            Text(left.uppercased()).foregroundStyle(CardColor.inkSecondary)
            Spacer()
            if let right { Text(right.uppercased()).foregroundStyle(rightColor) }
        }
        .font(CardFont.label(12)).tracking(1.2)
    }

    private func splitsPanel(_ details: RunShareDetails) -> some View {
        let shown = Array(details.splits.prefix(12))
        let fastest = shown.map(\.secondsPerKm).min() ?? 0
        let slowest = shown.map(\.secondsPerKm).max() ?? 1
        return panel {
            panelTitle("Splits /" + (data.units == .metric ? "km" : "mi"))
            HStack(alignment: .bottom, spacing: 5) {
                ForEach(Array(shown.enumerated()), id: \.offset) { _, pace in
                    let share = slowest > fastest ? (slowest - pace.secondsPerKm) / (slowest - fastest) : 1
                    let isFastest = pace.secondsPerKm == fastest
                    VStack(spacing: 2) {
                        RoundedRectangle(cornerRadius: 3)
                            .fill(isFastest ? CardColor.volt : CardColor.run)
                            .frame(height: 14 + 24 * share)
                        if shown.count <= 8 {
                            Text(Units.formatPace(pace, units: data.units))
                                .font(CardFont.condensed(11, .condensedMedium))
                                .foregroundStyle(isFastest ? CardColor.ink : CardColor.inkSecondary)
                        }
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .frame(height: 54, alignment: .bottom)
        }
    }

    private func repsPanel(_ details: RunShareDetails) -> some View {
        let reps = Array(details.reps.prefix(12))
        return panel {
            panelTitle("Reps on pace" + (details.repTarget.map { " · " + $0 } ?? ""), "\(details.repsOnPace) / \(details.reps.count)",
                       rightColor: CardColor.good)
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 14), GridItem(.flexible(), spacing: 14)], spacing: 5) {
                ForEach(Array(reps.enumerated()), id: \.offset) { index, rep in
                    HStack(spacing: 6) {
                        Text("\(index + 1)").foregroundStyle(CardColor.inkSecondary).frame(width: 14, alignment: .leading)
                        if let target = rep.target {
                            CardPaceBar(target: target, pace: rep.pace, inRange: rep.inRange)
                        } else {
                            Spacer()
                        }
                        Text(Units.formatPace(rep.pace, units: data.units))
                            .foregroundStyle(CardColor.ink)
                    }
                    .font(CardFont.condensed(14, .condensedMedium))
                    .frame(height: 16)
                }
            }
        }
    }

    private func heartRatePanel(_ details: RunShareDetails) -> some View {
        let total = max(details.zoneSeconds.reduce(0, +), 1)
        let summary = [details.averageHeartRate.map { "Avg \(Int($0))" }, details.maxHeartRate.map { "Max \(Int($0))" }]
            .compactMap { $0 }.joined(separator: " · ")
        return panel {
            panelTitle("Heart rate" + (details.zoneSeconds.contains { $0 > 0 } ? " zones" : ""), summary.isEmpty ? nil : summary)
            if details.zoneSeconds.contains(where: { $0 > 0 }) {
                GeometryReader { proxy in
                    HStack(spacing: 0) {
                        ForEach(0..<5, id: \.self) { zone in
                            CardColor.zones[zone].frame(width: proxy.size.width * details.zoneSeconds[zone] / total)
                        }
                    }
                }
                .frame(height: 12)
                .clipShape(Capsule())
                HStack {
                    ForEach(0..<5, id: \.self) { zone in
                        Text("Z\(zone + 1) \(Int((details.zoneSeconds[zone] / 60).rounded()))m")
                        if zone < 4 { Spacer(minLength: 0) }
                    }
                }
                .font(CardFont.condensed(11, .condensedMedium))
                .foregroundStyle(CardColor.inkSecondary)
            }
        }
    }

    private func effortsPanel(_ details: RunShareDetails) -> some View {
        panel {
            HStack(alignment: .top, spacing: 12) {
                if let effort = details.efforts.first(where: \.isNewBest) ?? details.efforts.first {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("BEST EFFORT").font(CardFont.label(12)).tracking(1.2).foregroundStyle(CardColor.inkSecondary)
                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            Text("\(effort.name) \(effort.time)").font(CardFont.condensed(22)).foregroundStyle(CardColor.volt)
                            if effort.isNewBest {
                                Text("NEW BEST").font(CardFont.label(12)).foregroundStyle(CardColor.good)
                            }
                        }
                        .lineLimit(1).minimumScaleFactor(0.7)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                if let gain = details.elevationGain {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("ELEVATION +\(format.elevation(gain))").font(CardFont.label(12)).tracking(1.2)
                            .foregroundStyle(CardColor.inkSecondary)
                        if details.elevationProfile.count >= 2 {
                            ElevationShape(values: details.elevationProfile, closed: true).fill(CardColor.run.opacity(0.25))
                                .overlay(ElevationShape(values: details.elevationProfile, closed: false)
                                    .stroke(CardColor.run, lineWidth: 1.5))
                                .frame(height: 28)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }

    // MARK: Pieces

    private func header(titleSize: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text(data.subtitle.uppercased()).font(CardFont.label(13)).tracking(1.4).foregroundStyle(kindColor)
                if let badge = data.badge {
                    Text(badge.uppercased()).font(CardFont.condensed(12)).tracking(1)
                        .padding(.horizontal, 8).padding(.vertical, 2)
                        .background(CardColor.volt, in: Capsule()).foregroundStyle(CardColor.onVolt)
                }
            }
            Text(data.title.uppercased()).font(CardFont.condensed(titleSize)).lineLimit(2).minimumScaleFactor(0.6)
                .foregroundStyle(CardColor.ink)
        }
    }

    private func metricRow(size: CGFloat) -> some View {
        HStack(alignment: .top, spacing: 10) {
            ForEach(Array(data.metrics.prefix(3).enumerated()), id: \.offset) { index, metric in
                VStack(alignment: .leading, spacing: 0) {
                    Text(metric.label.uppercased()).font(CardFont.label(12)).tracking(1.2).foregroundStyle(CardColor.inkSecondary)
                    Text(metric.value).font(CardFont.condensed(size)).monospacedDigit()
                        .foregroundStyle(index == 2 && data.kind == .run ? CardColor.volt : CardColor.ink)
                        .lineLimit(1).minimumScaleFactor(0.5)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private var linesView: some View {
        VStack(alignment: .leading, spacing: 5) {
            ForEach(data.lines.prefix(5), id: \.self) { line in
                HStack(spacing: 8) {
                    Circle().fill(CardColor.lift).frame(width: 5, height: 5)
                    Text(line).font(CardFont.text(13, .medium)).foregroundStyle(CardColor.ink).lineLimit(1)
                }
            }
        }
    }

    /// One bar per rep, green when on pace, amber when not, taller = faster.
    private func repStrip(_ details: RunShareDetails) -> some View {
        let reps = Array(details.reps.prefix(16))
        let paces = reps.map(\.pace.secondsPerKm)
        let fastest = paces.min() ?? 0, slowest = paces.max() ?? 1
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("REPS").foregroundStyle(CardColor.inkSecondary)
                Spacer()
                Text("\(details.repsOnPace) OF \(details.reps.count) ON PACE").foregroundStyle(CardColor.good)
            }
            .font(CardFont.label(12)).tracking(1.2)
            HStack(alignment: .bottom, spacing: 5) {
                ForEach(Array(reps.enumerated()), id: \.offset) { _, rep in
                    let share = slowest > fastest ? (slowest - rep.pace.secondsPerKm) / (slowest - fastest) : 1
                    RoundedRectangle(cornerRadius: 3)
                        .fill(rep.inRange ? CardColor.good : CardColor.warn)
                        .frame(height: 20 + 14 * share)
                }
            }
            .frame(height: 34, alignment: .bottom)
        }
        .padding(.horizontal, 14).padding(.vertical, 12)
        .background(CardColor.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func splitStrip(_ details: RunShareDetails) -> some View {
        splitsPanel(details)
    }

    private var brand: some View { wordmark(height: data.kind == .run ? 22 : 18) }

    private func wordmark(height: CGFloat) -> some View {
        KXWordmark(height: height, forcedWhite: true)
    }
}

/// The target band with a dot where the rep was run (a smaller copy of Part by part's bar).
private struct CardPaceBar: View {
    let target: PaceRange
    let pace: Pace
    let inRange: Bool

    var body: some View {
        GeometryReader { proxy in
            let fast = target.fastest.secondsPerKm, slow = target.slowest.secondsPerKm
            let margin = max(slow - fast, 10)
            let low = fast - margin, high = slow + margin
            let x: (Double) -> CGFloat = { CGFloat((min(max($0, low), high) - low) / (high - low)) * proxy.size.width }
            ZStack(alignment: .leading) {
                Capsule().fill(CardColor.track).frame(height: 3)
                Capsule().fill(CardColor.good.opacity(0.45)).frame(width: max(x(slow) - x(fast), 4), height: 7).offset(x: x(fast))
                Circle().fill(inRange ? CardColor.good : CardColor.warn).frame(width: 9, height: 9).offset(x: x(pace.secondsPerKm) - 4.5)
            }
            .frame(height: proxy.size.height)
        }
        .frame(height: 10)
    }
}

/// A small elevation profile (filled when `closed`).
private struct ElevationShape: Shape {
    let values: [Double]
    let closed: Bool

    func path(in rect: CGRect) -> Path {
        guard values.count >= 2, let low = values.min(), let high = values.max() else { return Path() }
        let range = max(high - low, 5)
        let step = rect.width / CGFloat(values.count - 1)
        var path = Path()
        for (index, value) in values.enumerated() {
            let point = CGPoint(x: rect.minX + CGFloat(index) * step,
                                y: rect.maxY - CGFloat((value - low) / range) * rect.height * 0.85)
            if index == 0 { path.move(to: point) } else { path.addLine(to: point) }
        }
        if closed {
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
            path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
            path.closeSubpath()
        }
        return path
    }
}
