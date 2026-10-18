import Foundation
import Observation
import WatchConnectivity
import TrainingEngine

/// The watch's copy of the plan (sent by the iPhone, kept on the watch so it works without
/// the phone) and the outbox of finished runs waiting to reach the phone.
@Observable
@MainActor
final class WatchStore: NSObject {
    static let shared = WatchStore()

    private(set) var plan: WatchPlan
    /// Finished runs not yet delivered to the phone.
    private(set) var pendingResults = 0

    @ObservationIgnored private let defaults = UserDefaults.standard
    private static let planKey = "watch.plan"

    override init() {
        plan = UserDefaults.standard.data(forKey: Self.planKey).flatMap(WatchPlan.decode) ?? .empty
        super.init()
        pendingResults = outboxFiles().count
    }

    var hasPlan: Bool { plan.generatedAt > .distantPast }

    func activate() {
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    fileprivate func receive(planData: Data) {
        guard let new = WatchPlan.decode(planData), new.generatedAt >= plan.generatedAt else { return }
        plan = new
        defaults.set(planData, forKey: Self.planKey)
    }

    // MARK: Sending results

    private var outbox: URL {
        let url = URL.documentsDirectory.appending(path: "outbox", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func outboxFiles() -> [URL] {
        (try? FileManager.default.contentsOfDirectory(at: outbox, includingPropertiesForKeys: nil))?
            .filter { $0.pathExtension == "json" } ?? []
    }

    /// Saves the run to the outbox and hands it to the system, which delivers it whenever
    /// the phone is reachable (even later, after the app has closed).
    func send(_ result: WatchRunResult) {
        let file = outbox.appending(path: "\(result.id.uuidString).json")
        try? result.encoded().write(to: file, options: .atomic)
        pendingResults = outboxFiles().count
        transfer(file)
    }

    private func transfer(_ file: URL) {
        guard WCSession.isSupported(), WCSession.default.activationState == .activated else { return }
        let alreadyQueued = WCSession.default.outstandingFileTransfers.contains { $0.file.fileURL.lastPathComponent == file.lastPathComponent }
        guard !alreadyQueued else { return }
        WCSession.default.transferFile(file, metadata: ["kind": "runResult"])
    }

    /// Re-queues anything in the outbox the system isn't already sending (e.g. after a restart).
    fileprivate func resendOutbox() {
        outboxFiles().forEach(transfer)
    }

    fileprivate func delivered(fileName: String) {
        try? FileManager.default.removeItem(at: outbox.appending(path: fileName))
        pendingResults = outboxFiles().count
    }
}

extension WatchStore: WCSessionDelegate {
    nonisolated func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        let data = session.receivedApplicationContext["plan"] as? Data
        Task { @MainActor in
            if let data { self.receive(planData: data) }
            self.resendOutbox()
        }
    }

    nonisolated func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        guard let data = applicationContext["plan"] as? Data else { return }
        Task { @MainActor in self.receive(planData: data) }
    }

    nonisolated func session(_ session: WCSession, didFinish fileTransfer: WCSessionFileTransfer, error: Error?) {
        let name = fileTransfer.file.fileURL.lastPathComponent
        Task { @MainActor in
            if error == nil {
                self.delivered(fileName: name)
            } else {
                // Tried again next time the app opens or the session reactivates.
                self.pendingResults = self.outboxFiles().count
            }
        }
    }
}
