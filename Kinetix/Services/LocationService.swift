import Foundation
import CoreLocation
import TrainingEngine

/// Something that delivers GPS samples during a run: the real GPS, or a simulation.
@MainActor
protocol RunLocationSource: AnyObject {
    var onSample: ((LocationSample) -> Void)? { get set }
    func start()
    func stop()
}

/// Real GPS. Keeps running with the screen locked and the app in the background
/// (background location mode + a background activity session; iOS shows the blue
/// location indicator so the runner knows tracking is on).
@MainActor
final class GPSLocationSource: NSObject, RunLocationSource, CLLocationManagerDelegate {
    var onSample: ((LocationSample) -> Void)?
    var onAuthorizationChange: ((CLAuthorizationStatus) -> Void)?

    private let manager = CLLocationManager()
    private var backgroundSession: CLBackgroundActivitySession?

    override init() {
        super.init()
        manager.delegate = self
        manager.activityType = .fitness
        manager.desiredAccuracy = kCLLocationAccuracyBest
        manager.distanceFilter = kCLDistanceFilterNone
        manager.pausesLocationUpdatesAutomatically = false
    }

    var authorizationStatus: CLAuthorizationStatus { manager.authorizationStatus }

    func requestPermission() {
        if manager.authorizationStatus == .notDetermined {
            manager.requestWhenInUseAuthorization()
        }
    }

    /// Starts updates early (before the run) so a GPS lock is ready.
    func warmUp() {
        guard isAuthorized else { return }
        manager.startUpdatingLocation()
    }

    var isAuthorized: Bool {
        manager.authorizationStatus == .authorizedWhenInUse || manager.authorizationStatus == .authorizedAlways
    }

    func start() {
        guard isAuthorized else { return }
        backgroundSession = CLBackgroundActivitySession()
        manager.allowsBackgroundLocationUpdates = true
        manager.showsBackgroundLocationIndicator = true
        manager.startUpdatingLocation()
    }

    func stop() {
        manager.stopUpdatingLocation()
        manager.allowsBackgroundLocationUpdates = false
        backgroundSession?.invalidate()
        backgroundSession = nil
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        let samples = locations.map {
            LocationSample(timestamp: $0.timestamp, latitude: $0.coordinate.latitude, longitude: $0.coordinate.longitude,
                           horizontalAccuracy: $0.horizontalAccuracy, speed: $0.speed)
        }
        MainActor.assumeIsolated {
            for sample in samples { onSample?(sample) }
        }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        MainActor.assumeIsolated {
            onAuthorizationChange?(status)
            if isAuthorized { manager.startUpdatingLocation() }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        // Temporary failures (e.g. no fix yet) are expected; the run screen shows GPS status.
    }
}

/// Plays back a simulated runner, optionally faster than real time.
/// The run model drives it with its clock (see `RunWorkoutModel`).
@MainActor
final class SimulatedLocationSource: RunLocationSource {
    var onSample: ((LocationSample) -> Void)?
    private var generator: SimulatedRunner.Generator
    private var simulatedTime: Double = 0
    private var running = false

    init(structure: RunStructure?) {
        generator = SimulatedRunner.Generator(runner: SimulatedRunner.demo(structure: structure))
    }

    func start() { running = true }
    func stop() { running = false }

    /// Emits samples up to `seconds` of simulated running, stamped with clock times.
    func advance(by seconds: Double, clockNow: Date) {
        guard running, seconds > 0 else { return }
        let target = simulatedTime + seconds
        while simulatedTime + 1 <= target {
            simulatedTime += 1
            var sample = generator.sample(at: simulatedTime, start: .distantPast)
            sample.timestamp = clockNow.addingTimeInterval(simulatedTime - target)
            onSample?(sample)
        }
    }
}
