import CoreLocation
import CoreMotion
import Foundation
import Observation
import TrainingEngine

/// The numbers custom screens can show beyond the run engine's: heart-rate history (average,
/// time in zone, exertion), cadence, climb and calories. Measured on the watch, so they work
/// on watch runs and on runs mirrored from the iPhone.
@Observable
@MainActor
final class RunExtras {
    private(set) var heartRateSamples: [HeartRateSample] = []
    /// Steps per minute.
    private(set) var cadence: Double?
    private(set) var elevationGainMeters: Double?
    private(set) var calories: Double?

    @ObservationIgnored private var startedAt: Date?
    @ObservationIgnored private var lastAltitude: Double?
    @ObservationIgnored private let pedometer = CMPedometer()

    func start(at date: Date) {
        reset()
        startedAt = date
        guard CMPedometer.isCadenceAvailable() else { return }
        pedometer.startUpdates(from: date) { [weak self] data, _ in
            guard let perSecond = data?.currentCadence?.doubleValue else { return }
            Task { @MainActor in self?.cadence = perSecond * 60 }
        }
    }

    func reset() {
        pedometer.stopUpdates()
        heartRateSamples = []
        cadence = nil
        elevationGainMeters = nil
        calories = nil
        startedAt = nil
        lastAltitude = nil
    }

    func addHeartRate(_ bpm: Double, at date: Date) {
        guard let startedAt, bpm > 30, bpm < 250 else { return }
        heartRateSamples.append(HeartRateSample(elapsed: date.timeIntervalSince(startedAt), bpm: bpm))
    }

    /// Climb from GPS altitude, ignoring changes under 2 m (noise).
    func addLocations(_ locations: [CLLocation]) {
        for location in locations where location.verticalAccuracy >= 0 && location.verticalAccuracy <= 15 {
            guard let last = lastAltitude else {
                lastAltitude = location.altitude
                elevationGainMeters = elevationGainMeters ?? 0
                continue
            }
            let change = location.altitude - last
            if change >= 2 {
                elevationGainMeters = (elevationGainMeters ?? 0) + change
                lastAltitude = location.altitude
            } else if change <= -2 {
                lastAltitude = location.altitude
            }
        }
    }

    func setCalories(_ kilocalories: Double) { calories = kilocalories }
}
