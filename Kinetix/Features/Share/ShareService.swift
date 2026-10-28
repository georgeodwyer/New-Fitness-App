import SwiftUI
import UIKit
import MapKit
import CoreTransferable
import UniformTypeIdentifiers
import TrainingEngine

/// A rendered card for the share sheet (PNG keeps sticker transparency).
struct ShareImage: Transferable {
    let image: UIImage

    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(exportedContentType: .png) { item in
            guard let data = item.image.pngData() else { throw CocoaError(.fileWriteUnknown) }
            return data
        }
        .suggestedFileName("Kinetix.png")
    }
}

@MainActor
enum ShareService {
    /// Renders a card (or sticker) at 3× for crisp 1080-pixel-wide images.
    static func render(_ data: ShareCardData, style: ShareCardStyle, mapImage: UIImage?, photo: UIImage?,
                       options: ShareDetailOptions = ShareDetailOptions()) -> UIImage? {
        let renderer = ImageRenderer(content: ShareCardView(data: data, style: style, mapImage: mapImage, photo: photo, options: options))
        renderer.scale = 3
        renderer.isOpaque = style != .sticker
        return renderer.uiImage
    }

    /// A map picture of the route with the line drawn on top. nil without a route or
    /// without a connection (the card then shows the route on its own).
    static func mapImage(for route: [RoutePoint], size: CGSize = CGSize(width: 360, height: 330)) async -> UIImage? {
        guard route.count > 1 else { return nil }
        let coordinates = route.map { CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude) }
        let polyline = MKPolyline(coordinates: coordinates, count: coordinates.count)
        let rect = polyline.boundingMapRect
        let padded = rect.insetBy(dx: -rect.width * 0.25 - 200, dy: -rect.height * 0.25 - 200)
        let options = MKMapSnapshotter.Options()
        options.mapRect = padded
        options.size = size
        options.scale = 3
        options.pointOfInterestFilter = .excludingAll
        options.traitCollection = UITraitCollection(userInterfaceStyle: .dark)
        guard let snapshot = try? await MKMapSnapshotter(options: options).start() else { return nil }
        let image = UIGraphicsImageRenderer(size: size, format: { let f = UIGraphicsImageRendererFormat(); f.scale = 3; return f }())
            .image { context in
                snapshot.image.draw(at: .zero)
                let path = UIBezierPath()
                for (index, coordinate) in coordinates.enumerated() {
                    let point = snapshot.point(for: coordinate)
                    if index == 0 { path.move(to: point) } else { path.addLine(to: point) }
                }
                path.lineWidth = 5
                path.lineCapStyle = .round
                path.lineJoinStyle = .round
                UIColor.black.withAlphaComponent(0.6).setStroke()
                path.lineWidth = 9
                path.stroke()
                // Volt, as in the app's dark theme.
                UIColor(red: 0xD6 / 255, green: 1, blue: 0x3D / 255, alpha: 1).setStroke()
                path.lineWidth = 5
                path.stroke()
                _ = context
            }
        return image
    }

    // MARK: Instagram Stories

    /// The Meta (Facebook) App ID Instagram requires for direct Stories sharing, from Info.plist.
    static var instagramAppID: String? {
        guard let id = (Bundle.main.object(forInfoDictionaryKey: "InstagramAppID") as? String)?.trimmingCharacters(in: .whitespaces),
              !id.isEmpty, id.allSatisfy(\.isNumber) else { return nil }
        return id
    }

    static var canShareToInstagramStories: Bool {
        guard instagramAppID != nil, let url = URL(string: "instagram-stories://share") else { return false }
        return UIApplication.shared.canOpenURL(url)
    }

    /// Opens Instagram's story editor with the sticker placed (movable) over a background.
    static func shareToInstagramStories(sticker: UIImage, background: UIImage?) {
        guard let appID = instagramAppID,
              let url = URL(string: "instagram-stories://share?source_application=\(appID)"),
              let stickerData = sticker.pngData() else { return }
        var item: [String: Any] = ["com.instagram.sharedSticker.stickerImage": stickerData]
        if let background, let backgroundData = background.pngData() {
            item["com.instagram.sharedSticker.backgroundImage"] = backgroundData
        } else {
            item["com.instagram.sharedSticker.backgroundTopColor"] = "#111113"
            item["com.instagram.sharedSticker.backgroundBottomColor"] = "#050506"
        }
        UIPasteboard.general.setItems([item], options: [.expirationDate: Date.now.addingTimeInterval(300)])
        UIApplication.shared.open(url)
    }
}

extension ShareCardData {
    @MainActor
    static func run(_ log: RunLogModel, units: UnitSystem, hideEnds: Bool, zones: HeartRateZones? = nil,
                    previousBests: [BestEffortDistance: Double] = [:]) -> ShareCardData {
        let format = DisplayFormat(units: units)
        var metrics: [(label: String, value: String)] = [
            ("Distance", format.distance(log.distanceMeters, decimals: 2)),
            ("Time", Units.formatMinutesSeconds(log.durationSeconds))
        ]
        if let pace = log.averagePace { metrics.append(("Pace", format.pace(pace))) }
        let route = log.route
        return ShareCardData(
            kind: .run,
            title: log.title.isEmpty ? "Run" : log.title,
            subtitle: log.startedAt.formatted(.dateTime.weekday(.wide).day().month(.wide)),
            metrics: metrics,
            badge: log.targetedSeconds > 0 ? "\(Int((log.timeInTargetSeconds / log.targetedSeconds * 100).rounded()))% on pace" : nil,
            route: hideEnds ? RunAnalysis.privacyTrimmed(route) : route,
            units: units,
            details: RunShareDetails(log, units: units, zones: zones, previousBests: previousBests)
        )
    }

    @MainActor
    static func strength(_ log: StrengthLogModel, units: UnitSystem, records: Int) -> ShareCardData {
        let format = DisplayFormat(units: units)
        let completed = log.orderedSets.filter(\.isCompleted)
        var keys: [String] = []
        for set in completed where !keys.contains(set.progressionKey) { keys.append(set.progressionKey) }
        let lines: [String] = keys.compactMap { key in
            let sets = completed.filter { $0.progressionKey == key }
            guard let best = sets.max(by: { ($0.actualWeightKg, $0.actualReps) < ($1.actualWeightKg, $1.actualReps) }) else { return nil }
            let load = best.isBodyweight ? "\(best.actualReps) reps" : "\(format.weight(best.actualWeightKg)) × \(best.actualReps)"
            return "\(best.exerciseName.isEmpty ? best.exerciseId : best.exerciseName) · \(sets.count) sets · \(load)"
        }
        return ShareCardData(
            kind: .strength,
            title: log.title.isEmpty ? "Strength" : log.title,
            subtitle: log.startedAt.formatted(.dateTime.weekday(.wide).day().month(.wide)),
            metrics: [("Volume", format.volume(log.volumeKg)),
                      ("Time", Units.formatMinutesSeconds(log.durationSeconds)),
                      ("Sets", "\(completed.count)")],
            lines: lines,
            badge: records > 0 ? "\(records) PR\(records == 1 ? "" : "s")" : nil,
            units: units
        )
    }
}

extension RunShareDetails {
    /// The charts' numbers for a finished run. `previousBests` are the runner's best times from
    /// earlier runs (a faster time here is a new best).
    @MainActor
    init(_ log: RunLogModel, units: UnitSystem, zones: HeartRateZones?, previousBests: [BestEffortDistance: Double]) {
        self.init()
        splits = log.splits.map(\.pace)

        let results = log.segmentResults
        let work = results.filter { $0.segment.kind == .work && $0.durationSeconds >= 1 }
        if work.count >= 2 {
            reps = work.compactMap { result in
                guard let pace = result.averagePace else { return nil }
                let inRange = PaceGap(result: result, units: units)?.isInRange ?? false
                return Rep(pace: pace, target: result.segment.targetPace, inRange: inRange)
            }
            let targets = Set(work.compactMap(\.segment.targetPace))
            if targets.count == 1, let target = targets.first { repTarget = DisplayFormat(units: units).paceRange(target) }
        }

        averageHeartRate = log.averageHeartRate
        maxHeartRate = log.maxHeartRate
        if let zones { zoneSeconds = RunAnalysis.secondsInZones(log.heartRateSamples, zones: zones) }

        let route = log.route
        efforts = RunAnalysis.bestEfforts(route: route)
            .sorted { $0.key.meters > $1.key.meters }
            .map { distance, seconds in
                Effort(name: Self.shortName(distance), time: Units.formatMinutesSeconds(seconds),
                       isNewBest: previousBests[distance].map { seconds < $0 } ?? false)
            }
        elevationGain = RunAnalysis.elevationGain(route: route)
        elevationProfile = RunAnalysis.elevationProfile(route: route)
    }

    static func shortName(_ distance: BestEffortDistance) -> String {
        switch distance {
        case .oneKilometre: return "1K"
        case .oneMile: return "1 mi"
        case .fiveK: return "5K"
        case .tenK: return "10K"
        case .half: return "Half"
        case .marathon: return "Marathon"
        }
    }
}
