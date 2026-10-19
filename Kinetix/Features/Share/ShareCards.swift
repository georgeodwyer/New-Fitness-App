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
}

enum ShareCardStyle: String, CaseIterable, Identifiable {
    case map = "Map"
    case photo = "Photo"
    case sticker = "Sticker"
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

/// A 9:16 card (1080 × 1920 when rendered at 3×), or a transparent sticker.
struct ShareCardView: View {
    let data: ShareCardData
    let style: ShareCardStyle
    var mapImage: UIImage?
    var photo: UIImage?

    static let size = CGSize(width: 360, height: 640)

    var body: some View {
        switch style {
        case .sticker: sticker
        case .photo: photoCard
        case .map: mapCard
        }
    }

    // MARK: Map card

    private var mapCard: some View {
        VStack(spacing: 0) {
            ZStack {
                if let mapImage {
                    Image(uiImage: mapImage).resizable().scaledToFill()
                } else {
                    LinearGradient(colors: [Color(red: 0.09, green: 0.13, blue: 0.12), Color(red: 0.16, green: 0.22, blue: 0.2)],
                                   startPoint: .top, endPoint: .bottom)
                    if !data.route.isEmpty {
                        RouteShape(route: data.route)
                            .stroke(KXColor.accent, style: StrokeStyle(lineWidth: 5, lineCap: .round, lineJoin: .round))
                            .padding(40)
                    } else {
                        Image(systemName: data.kind == .run ? "figure.run" : "dumbbell.fill")
                            .font(.system(size: 90, weight: .bold)).foregroundStyle(KXColor.accent)
                    }
                }
            }
            .frame(width: Self.size.width, height: 380)
            .clipped()
            VStack(alignment: .leading, spacing: 14) {
                header(dark: false)
                metricRow(dark: false)
                if !data.lines.isEmpty { linesView(dark: false) }
                Spacer(minLength: 0)
                brand(dark: false, height: 32)
            }
            .padding(22)
            .frame(width: Self.size.width, height: Self.size.height - 380, alignment: .topLeading)
            .background(Color.white)
        }
        .frame(width: Self.size.width, height: Self.size.height)
        .environment(\.colorScheme, .light)
    }

    // MARK: Photo card

    private var photoCard: some View {
        ZStack(alignment: .bottomLeading) {
            if let photo {
                Image(uiImage: photo).resizable().scaledToFill()
                    .frame(width: Self.size.width, height: Self.size.height).clipped()
            } else {
                LinearGradient(colors: [KXColor.accent, Color(red: 0.55, green: 0.2, blue: 0.05)], startPoint: .topLeading, endPoint: .bottomTrailing)
            }
            LinearGradient(colors: [.clear, .black.opacity(0.75)], startPoint: .center, endPoint: .bottom)
            VStack(alignment: .leading, spacing: 14) {
                if !data.route.isEmpty {
                    RouteShape(route: data.route)
                        .stroke(.white, style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
                        .frame(width: 110, height: 110, alignment: .leading)
                        .shadow(color: .black.opacity(0.4), radius: 3)
                }
                header(dark: true)
                metricRow(dark: true)
                if !data.lines.isEmpty { linesView(dark: true) }
                brand(dark: true)
            }
            .padding(24)
        }
        .frame(width: Self.size.width, height: Self.size.height)
        .environment(\.colorScheme, .dark)
    }

    // MARK: Sticker (transparent)

    private var sticker: some View {
        VStack(spacing: 12) {
            if !data.route.isEmpty {
                RouteShape(route: data.route)
                    .stroke(.white, style: StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round))
                    .frame(width: 165, height: 165)
            }
            ForEach(Array(data.metrics.enumerated()), id: \.offset) { _, metric in
                VStack(spacing: 0) {
                    Text(metric.label.uppercased()).font(.system(size: 11, weight: .bold)).tracking(1.3)
                    Text(metric.value).font(.system(size: 29, weight: .heavy, design: .rounded)).monospacedDigit()
                }
            }
            ForEach(data.lines.prefix(3), id: \.self) { line in
                Text(line).font(.system(size: 12, weight: .semibold))
            }
            KXWordmark(height: 24, forcedWhite: true)
                .padding(.top, 4)
        }
        .foregroundStyle(.white)
        .shadow(color: .black.opacity(0.45), radius: 4, y: 1)
        .padding(24)
        .frame(width: Self.size.width)
    }

    // MARK: Pieces

    private func header(dark: Bool) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Text(data.subtitle.uppercased()).font(.system(size: 11, weight: .bold)).tracking(1.2)
                    .foregroundStyle(dark ? .white.opacity(0.8) : KXColor.inkSecondary)
                if let badge = data.badge {
                    Text(badge).font(.system(size: 10, weight: .bold))
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(KXColor.accent, in: Capsule()).foregroundStyle(.white)
                }
            }
            Text(data.title).font(.system(size: 26, weight: .heavy)).lineLimit(2)
                .foregroundStyle(dark ? .white : KXColor.ink)
        }
    }

    private func metricRow(dark: Bool) -> some View {
        HStack(alignment: .top, spacing: 18) {
            ForEach(Array(data.metrics.prefix(3).enumerated()), id: \.offset) { _, metric in
                VStack(alignment: .leading, spacing: 2) {
                    Text(metric.label.uppercased()).font(.system(size: 10, weight: .bold)).tracking(1)
                        .foregroundStyle(dark ? .white.opacity(0.75) : KXColor.inkSecondary)
                    Text(metric.value).font(.system(size: 24, weight: .heavy, design: .rounded)).monospacedDigit()
                        .foregroundStyle(dark ? .white : KXColor.ink)
                        .lineLimit(1).minimumScaleFactor(0.6)
                }
            }
        }
    }

    private func linesView(dark: Bool) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(data.lines.prefix(5), id: \.self) { line in
                Text(line).font(.system(size: 13, weight: .medium)).foregroundStyle(dark ? .white.opacity(0.9) : KXColor.ink)
                    .lineLimit(1)
            }
        }
    }

    private func brand(dark: Bool, height: CGFloat = 14) -> some View {
        KXWordmark(height: height, forcedWhite: dark ? true : nil)
    }
}
