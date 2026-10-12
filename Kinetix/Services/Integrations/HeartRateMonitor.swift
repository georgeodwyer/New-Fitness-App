import Foundation
import Observation
import CoreBluetooth
import TrainingEngine

/// Bluetooth heart rate straps (standard Heart Rate service 0x180D, measurement 0x2A37):
/// pairing, auto-reconnect and live readings.
@Observable
@MainActor
final class HeartRateMonitor: NSObject {
    static let shared = HeartRateMonitor()

    enum State: Equatable {
        case off
        case unauthorized
        case unsupported
        case idle
        case scanning
        case connecting(String)
        case connected(String)
    }

    struct Device: Identifiable, Equatable {
        let id: UUID
        let name: String
        var signal: Int
    }

    nonisolated static let heartRateService = CBUUID(string: "180D")
    nonisolated static let measurementCharacteristic = CBUUID(string: "2A37")

    private(set) var state: State = .idle
    private(set) var discovered: [Device] = []
    private(set) var heartRate: Int?
    private(set) var lastReadingAt: Date?

    /// Called with every usable reading (the run screen feeds these to the engine).
    @ObservationIgnored var onHeartRate: ((Double, Date) -> Void)?

    @ObservationIgnored private var central: CBCentralManager?
    @ObservationIgnored private var peripheral: CBPeripheral?
    @ObservationIgnored private var peripherals: [UUID: CBPeripheral] = [:]
    @ObservationIgnored private var wantsScan = false
    /// Reconnect automatically if the strap drops out.
    @ObservationIgnored private var keepConnected = false
    @ObservationIgnored private let settings: IntegrationSettings

    init(settings: IntegrationSettings = .shared) {
        self.settings = settings
        super.init()
    }

    var isConnected: Bool {
        if case .connected = state { return true }
        return false
    }

    /// Creating the manager is what triggers iOS's Bluetooth permission prompt, so it's
    /// done lazily, only when the user pairs a strap or a paired strap is needed.
    private func ensureCentral() -> CBCentralManager {
        if let central { return central }
        let manager = CBCentralManager(delegate: self, queue: .main,
                                       options: [CBCentralManagerOptionShowPowerAlertKey: true])
        central = manager
        return manager
    }

    // MARK: - Pairing

    func startScan() {
        wantsScan = true
        discovered = []
        let central = ensureCentral()
        if central.state == .poweredOn { beginScan() }
    }

    func stopScan() {
        wantsScan = false
        central?.stopScan()
        if state == .scanning { state = .idle }
    }

    func pair(_ device: Device) {
        stopScan()
        settings.heartRateSensorID = device.id
        settings.heartRateSensorName = device.name
        connectToSaved()
    }

    func forget() {
        keepConnected = false
        if let peripheral { central?.cancelPeripheralConnection(peripheral) }
        peripheral = nil
        settings.heartRateSensorID = nil
        settings.heartRateSensorName = nil
        heartRate = nil
        state = .idle
    }

    // MARK: - Connection

    /// Connects to the paired strap (if any) and keeps the connection until `disconnect()`.
    func connectToSaved() {
        guard settings.heartRateSensorID != nil else { return }
        keepConnected = true
        let central = ensureCentral()
        if central.state == .poweredOn { reconnect() }
    }

    func disconnect() {
        keepConnected = false
        if let peripheral { central?.cancelPeripheralConnection(peripheral) }
        heartRate = nil
        if !wantsScan { state = .idle }
    }

    private func beginScan() {
        state = .scanning
        // Straps advertise the Heart Rate service; already-connected ones (e.g. to another app)
        // don't advertise, so include those too.
        for connected in central?.retrieveConnectedPeripherals(withServices: [Self.heartRateService]) ?? [] {
            remember(connected, signal: 0)
        }
        central?.scanForPeripherals(withServices: [Self.heartRateService], options: [CBCentralManagerScanOptionAllowDuplicatesKey: false])
    }

    private func reconnect() {
        guard keepConnected, let id = settings.heartRateSensorID, let central else { return }
        guard let target = central.retrievePeripherals(withIdentifiers: [id]).first else {
            // Not known to iOS any more: scan for it.
            beginScan()
            return
        }
        peripheral = target
        target.delegate = self
        state = .connecting(settings.heartRateSensorName ?? "Heart rate strap")
        // connect() doesn't time out, so the strap reconnects whenever it comes back in range.
        central.connect(target, options: nil)
    }

    private func remember(_ peripheral: CBPeripheral, signal: Int) {
        peripherals[peripheral.identifier] = peripheral
        let name = peripheral.name ?? "Heart rate strap"
        if let index = discovered.firstIndex(where: { $0.id == peripheral.identifier }) {
            discovered[index].signal = signal
        } else {
            discovered.append(Device(id: peripheral.identifier, name: name, signal: signal))
        }
        // Found the paired strap while looking for it.
        if keepConnected, !wantsScan, peripheral.identifier == settings.heartRateSensorID, self.peripheral == nil || !isConnected {
            central?.stopScan()
            reconnect()
        }
    }

    fileprivate func handle(_ data: Data, at date: Date) {
        guard let measurement = HeartRateMeasurement.parse(data), measurement.isUsable else { return }
        heartRate = measurement.bpm
        lastReadingAt = date
        onHeartRate?(Double(measurement.bpm), date)
    }
}

extension HeartRateMonitor: CBCentralManagerDelegate {
    nonisolated func centralManagerDidUpdateState(_ central: CBCentralManager) {
        let managerState = central.state
        MainActor.assumeIsolated {
            switch managerState {
            case .poweredOn:
                state = .idle
                if wantsScan { beginScan() }
                if keepConnected { reconnect() }
            case .poweredOff: state = .off
            case .unauthorized: state = .unauthorized
            case .unsupported: state = .unsupported
            default: break
            }
        }
    }

    nonisolated func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral,
                                    advertisementData: [String: Any], rssi RSSI: NSNumber) {
        let signal = RSSI.intValue
        MainActor.assumeIsolated { remember(peripheral, signal: signal) }
    }

    nonisolated func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        MainActor.assumeIsolated {
            peripheral.delegate = self
            state = .connected(settings.heartRateSensorName ?? peripheral.name ?? "Heart rate strap")
            peripheral.discoverServices([Self.heartRateService])
        }
    }

    nonisolated func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        MainActor.assumeIsolated {
            state = .idle
            if keepConnected { reconnect() }
        }
    }

    nonisolated func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        MainActor.assumeIsolated {
            heartRate = nil
            state = .idle
            if keepConnected { reconnect() }
        }
    }
}

extension HeartRateMonitor: CBPeripheralDelegate {
    nonisolated func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        for service in peripheral.services ?? [] where service.uuid == Self.heartRateService {
            peripheral.discoverCharacteristics([Self.measurementCharacteristic], for: service)
        }
    }

    nonisolated func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        for characteristic in service.characteristics ?? [] where characteristic.uuid == Self.measurementCharacteristic {
            peripheral.setNotifyValue(true, for: characteristic)
        }
    }

    nonisolated func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        guard characteristic.uuid == Self.measurementCharacteristic, let value = characteristic.value else { return }
        let now = Date()
        MainActor.assumeIsolated { handle(value, at: now) }
    }
}
