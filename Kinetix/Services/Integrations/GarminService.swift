import Foundation
import Observation
import SwiftData
import TrainingEngine
#if canImport(ConnectIQ)
import ConnectIQ
#endif

/// A Garmin watch linked through Garmin Connect, for Settings.
struct GarminDeviceInfo: Identifiable, Equatable {
    let id: UUID
    let name: String
    let isConnected: Bool

    var isReady: Bool { isConnected }
    var statusText: String { isConnected ? "Connected" : "Not connected right now" }
}

/// Talks to the Kinetix app on Garmin watches through Garmin's Connect IQ link (Garmin
/// Connect must be on the phone): sends the next week's runs, and saves runs the watch
/// sends back (ticking off the plan). Message format: `GarminSync` in TrainingEngine.
@MainActor
@Observable
final class GarminService: NSObject {
    static let shared = GarminService()

    /// The scheme Garmin Connect uses to come back to Kinetix after choosing watches.
    static let urlScheme = "kinetix-ciq"
    private static let devicesKey = "garmin.devices"
    private static let sentKey = "garmin.lastSentAt"
    private static let resultKey = "garmin.lastResultAt"

    private(set) var devices: [GarminDeviceInfo] = []
    private(set) var lastSentAt: Date? = UserDefaults.standard.object(forKey: GarminService.sentKey) as? Date
    private(set) var lastResultAt: Date? = UserDefaults.standard.object(forKey: GarminService.resultKey) as? Date

    @ObservationIgnored private var container: ModelContainer?
    @ObservationIgnored private var lastSentPlan: Data?
    #if canImport(ConnectIQ)
    @ObservationIgnored private var linked: [IQDevice] = []
    #endif

    var isAvailable: Bool {
        #if canImport(ConnectIQ)
        return true
        #else
        return false
        #endif
    }

    /// Called at launch.
    func configure(container: ModelContainer) {
        self.container = container
        #if canImport(ConnectIQ)
        ConnectIQ.sharedInstance().initialize(withUrlScheme: Self.urlScheme, uiOverrideDelegate: nil)
        linked = Self.loadDevices()
        listen()
        #endif
    }

    /// Opens Garmin Connect to choose watches; it comes back through `handle(url:)`.
    func connect() {
        #if canImport(ConnectIQ)
        ConnectIQ.sharedInstance().showConnectIQDeviceSelection()
        #endif
    }

    /// The link back from Garmin Connect with the chosen watches. Returns true if it was one.
    @discardableResult
    func handle(url: URL) -> Bool {
        guard url.scheme == Self.urlScheme else { return false }
        #if canImport(ConnectIQ)
        let chosen = (ConnectIQ.sharedInstance().parseDeviceSelectionResponse(from: url) ?? []).compactMap { $0 as? IQDevice }
        guard !chosen.isEmpty else { return true }
        linked = chosen
        Self.saveDevices(chosen)
        listen()
        lastSentPlan = nil
        sendPlan(force: true)
        #endif
        return true
    }

    func forget() {
        #if canImport(ConnectIQ)
        ConnectIQ.sharedInstance().unregisterForAllDeviceEvents(self)
        ConnectIQ.sharedInstance().unregisterForAllAppMessages(self)
        linked = []
        #endif
        UserDefaults.standard.removeObject(forKey: Self.devicesKey)
        devices = []
        lastSentPlan = nil
    }

    func refreshStatus() {
        #if canImport(ConnectIQ)
        devices = linked.map { device in
            GarminDeviceInfo(id: device.uuid, name: Self.name(of: device),
                             isConnected: ConnectIQ.sharedInstance().getDeviceStatus(device) == .connected)
        }
        #endif
    }

    // MARK: Plan → watch

    /// Sends the next 7 days of runs to each linked watch (only if something changed, unless forced).
    func sendPlan(force: Bool = false, now: Date = .now) {
        #if canImport(ConnectIQ)
        guard !linked.isEmpty, let context = container?.mainContext else { return }
        var plan = WatchSyncService.makePlan(in: context, now: now)
        plan.runs = plan.runs.filter { $0.source == .planned }
        let message = GarminSync.planMessage(plan)
        let fingerprint = try? JSONSerialization.data(withJSONObject: message, options: [.sortedKeys])
        guard force || fingerprint != lastSentPlan else { return }
        lastSentPlan = fingerprint
        for device in linked {
            send(message, to: device) { [weak self] ok in
                guard ok, let self else { return }
                self.lastSentAt = .now
                UserDefaults.standard.set(self.lastSentAt, forKey: Self.sentKey)
            }
        }
        #endif
    }

    #if canImport(ConnectIQ)
    private func app(on device: IQDevice) -> IQApp? {
        guard let id = UUID(uuidString: GarminSync.watchAppId) else { return nil }
        return IQApp(uuid: id, storeUuid: id, device: device)
    }

    private func send(_ message: [String: Any], to device: IQDevice, done: @escaping @MainActor (Bool) -> Void) {
        guard let app = app(on: device) else { return }
        ConnectIQ.sharedInstance().sendMessage(message as NSDictionary, to: app, progress: { _, _ in }, completion: { result in
            // 0 is "success" in Garmin's result codes.
            let ok = result.rawValue == 0
            Task { @MainActor in done(ok) }
        })
    }

    private func listen() {
        let iq = ConnectIQ.sharedInstance()
        iq.unregisterForAllDeviceEvents(self)
        iq.unregisterForAllAppMessages(self)
        for device in linked {
            iq.register(forDeviceEvents: device, delegate: self)
            if let app = app(on: device) { iq.register(forAppMessages: app, delegate: self) }
        }
        refreshStatus()
    }

    // MARK: Watch → phone

    fileprivate func received(_ message: [String: Any], from device: IQDevice) {
        switch GarminSync.type(of: message) {
        case "hello":
            sendPlan(force: true)
        case "result":
            saveResult(message, from: device)
        default:
            break
        }
    }

    private func saveResult(_ message: [String: Any], from device: IQDevice) {
        guard let context = container?.mainContext, let rid = message["rid"] as? String else { return }
        let profile = ((try? context.fetch(FetchDescriptor<UserProfileModel>())) ?? []).first { !$0.isSoftDeleted }
        let units = profile?.units ?? UnitPreference.stored
        var option: WatchRunOption?
        if let sessionId = GarminSync.sessionId(in: message),
           let session = try? context.fetch(FetchDescriptor<PlannedSessionModel>(predicate: #Predicate { $0.id == sessionId })).first {
            option = WatchRunOption(id: session.id, source: .planned, title: session.title, date: session.date,
                                    structure: session.runStructure, typicalEffort: session.plannedEffort)
        }
        if let result = GarminSync.result(from: message, option: option, units: units) {
            if WatchSyncService.save(result, importSource: "garmin", in: context) != nil {
                lastResultAt = .now
                UserDefaults.standard.set(lastResultAt, forKey: Self.resultKey)
                WidgetSnapshotService.update(in: context)
                WatchSyncService.shared.sendPlan()
            }
        }
        // Saved (now or before): the watch can forget it.
        send(GarminSync.ackMessage(resultId: rid), to: device) { _ in }
        sendPlan()
    }

    // MARK: Saved watches

    private static func name(of device: IQDevice) -> String {
        if let name = device.friendlyName, !name.isEmpty { return name }
        return device.modelName ?? "Garmin watch"
    }

    private static func loadDevices() -> [IQDevice] {
        guard let data = UserDefaults.standard.data(forKey: devicesKey) else { return [] }
        return (try? NSKeyedUnarchiver.unarchivedArrayOfObjects(ofClass: IQDevice.self, from: data)) ?? []
    }

    private static func saveDevices(_ devices: [IQDevice]) {
        if let data = try? NSKeyedArchiver.archivedData(withRootObject: devices, requiringSecureCoding: true) {
            UserDefaults.standard.set(data, forKey: devicesKey)
        }
    }
    #endif
}

#if canImport(ConnectIQ)
extension GarminService: IQDeviceEventDelegate, IQAppMessageDelegate {
    nonisolated func deviceStatusChanged(_ device: IQDevice!, status: IQDeviceStatus) {
        Task { @MainActor in
            self.refreshStatus()
            if status == .connected { self.sendPlan() }
        }
    }

    nonisolated func receivedMessage(_ message: Any!, from app: IQApp!) {
        guard let dictionary = message as? [String: Any], let device = app?.device else { return }
        Task { @MainActor in self.received(dictionary, from: device) }
    }
}
#endif
