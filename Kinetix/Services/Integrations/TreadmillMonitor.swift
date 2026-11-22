import Foundation
import Observation
import CoreBluetooth
import TrainingEngine

/// A Bluetooth treadmill (standard Fitness Machine Service, FTMS): pairing, live speed,
/// distance and incline from the belt, and, if the treadmill allows it, setting the speed and
/// pausing or stopping the belt. Message format: `FTMS` in TrainingEngine.
@Observable
@MainActor
final class TreadmillMonitor: NSObject {
    static let shared = TreadmillMonitor()

    enum State: Equatable {
        case off, unauthorized, unsupported, idle, scanning
        case connecting(String)
        case connected(String)
    }

    struct Device: Identifiable, Equatable {
        let id: UUID
        let name: String
        var signal: Int
    }

    nonisolated static let service = CBUUID(string: "1826")
    nonisolated static let treadmillData = CBUUID(string: "2ACD")
    nonisolated static let controlPoint = CBUUID(string: "2AD9")
    nonisolated static let speedRange = CBUUID(string: "2AD4")

    private(set) var state: State = .idle
    private(set) var discovered: [Device] = []
    private(set) var reading: FTMS.Reading?
    private(set) var supportedSpeeds: FTMS.SpeedRange?
    /// The treadmill has a control point (it may still refuse control).
    private(set) var canControl = false
    /// The treadmill accepted Kinetix's request to control it.
    private(set) var hasControl = false
    /// Set when the treadmill refused a command, for the run screen.
    private(set) var controlProblem: String?

    /// Every reading, for the run.
    @ObservationIgnored var onReading: ((FTMS.Reading, Date) -> Void)?

    @ObservationIgnored private var central: CBCentralManager?
    @ObservationIgnored private var peripheral: CBPeripheral?
    @ObservationIgnored private var control: CBCharacteristic?
    @ObservationIgnored private var peripherals: [UUID: CBPeripheral] = [:]
    @ObservationIgnored private var wantsScan = false
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

    var pairedName: String? { settings.treadmillName }

    private func ensureCentral() -> CBCentralManager {
        if let central { return central }
        let manager = CBCentralManager(delegate: self, queue: .main, options: [CBCentralManagerOptionShowPowerAlertKey: true])
        central = manager
        return manager
    }

    // MARK: Pairing

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
        settings.treadmillID = device.id
        settings.treadmillName = device.name
        connectToSaved()
    }

    func forget() {
        disconnect()
        settings.treadmillID = nil
        settings.treadmillName = nil
    }

    // MARK: Connection

    func connectToSaved() {
        guard settings.treadmillID != nil else { return }
        keepConnected = true
        let central = ensureCentral()
        if central.state == .poweredOn { reconnect() }
    }

    func disconnect() {
        keepConnected = false
        if let peripheral { central?.cancelPeripheralConnection(peripheral) }
        peripheral = nil
        control = nil
        reading = nil
        canControl = false
        hasControl = false
        if !wantsScan { state = .idle }
    }

    private func beginScan() {
        state = .scanning
        for connected in central?.retrieveConnectedPeripherals(withServices: [Self.service]) ?? [] { remember(connected, signal: 0) }
        central?.scanForPeripherals(withServices: [Self.service], options: [CBCentralManagerScanOptionAllowDuplicatesKey: false])
    }

    private func reconnect() {
        guard keepConnected, let id = settings.treadmillID, let central else { return }
        guard let target = central.retrievePeripherals(withIdentifiers: [id]).first else {
            beginScan()
            return
        }
        peripheral = target
        target.delegate = self
        state = .connecting(settings.treadmillName ?? "Treadmill")
        central.connect(target, options: nil)
    }

    private func remember(_ peripheral: CBPeripheral, signal: Int) {
        peripherals[peripheral.identifier] = peripheral
        let name = peripheral.name ?? "Treadmill"
        if let index = discovered.firstIndex(where: { $0.id == peripheral.identifier }) {
            discovered[index].signal = signal
        } else {
            discovered.append(Device(id: peripheral.identifier, name: name, signal: signal))
        }
        if keepConnected, !wantsScan, peripheral.identifier == settings.treadmillID, self.peripheral == nil || !isConnected {
            central?.stopScan()
            reconnect()
        }
    }

    // MARK: Control

    /// Asks the treadmill to accept commands (needed once per connection).
    func requestControl() {
        guard canControl, !hasControl else { return }
        write(FTMS.requestControl)
    }

    /// Sets the belt speed (the run screen counts down first).
    func setSpeed(_ kmh: Double) {
        guard hasControl else { requestControl(); return }
        write(FTMS.setSpeed(kilometresPerHour: kmh))
    }

    func pauseBelt() { if hasControl { write(FTMS.pause) } }
    func resumeBelt() { if hasControl { write(FTMS.startOrResume) } }
    func stopBelt() { if hasControl { write(FTMS.stop) } }

    private func write(_ bytes: [UInt8]) {
        guard let peripheral, let control else { return }
        peripheral.writeValue(Data(bytes), for: control, type: .withResponse)
    }

    fileprivate func handleReading(_ data: Data, at date: Date) {
        guard let parsed = FTMS.reading([UInt8](data)) else { return }
        reading = parsed
        onReading?(parsed, date)
    }

    fileprivate func handleControlResponse(_ data: Data) {
        guard let response = FTMS.response([UInt8](data)) else { return }
        if response.opcode == FTMS.Opcode.requestControl.rawValue {
            hasControl = response.succeeded
            controlProblem = response.succeeded ? nil : "The treadmill didn't allow Kinetix to change its speed. Set it yourself."
        } else if !response.succeeded, response.opcode == FTMS.Opcode.setTargetSpeed.rawValue {
            controlProblem = "The treadmill didn't accept the new speed. Set it yourself."
        }
    }

    fileprivate func found(control characteristic: CBCharacteristic) {
        control = characteristic
        canControl = true
    }

    fileprivate func found(speeds data: Data) {
        supportedSpeeds = FTMS.speedRange([UInt8](data))
    }
}

extension TreadmillMonitor: CBCentralManagerDelegate {
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
            state = .connected(settings.treadmillName ?? peripheral.name ?? "Treadmill")
            hasControl = false
            controlProblem = nil
            peripheral.discoverServices([Self.service])
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
            reading = nil
            hasControl = false
            state = .idle
            if keepConnected { reconnect() }
        }
    }
}

extension TreadmillMonitor: CBPeripheralDelegate {
    nonisolated func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        for service in peripheral.services ?? [] where service.uuid == Self.service {
            peripheral.discoverCharacteristics([Self.treadmillData, Self.controlPoint, Self.speedRange], for: service)
        }
    }

    nonisolated func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        for characteristic in service.characteristics ?? [] {
            switch characteristic.uuid {
            case Self.treadmillData:
                peripheral.setNotifyValue(true, for: characteristic)
            case Self.controlPoint:
                // Responses to commands come back as indications.
                peripheral.setNotifyValue(true, for: characteristic)
                nonisolated(unsafe) let found = characteristic
                MainActor.assumeIsolated { self.found(control: found) }
            case Self.speedRange:
                peripheral.readValue(for: characteristic)
            default:
                break
            }
        }
    }

    nonisolated func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        guard let value = characteristic.value else { return }
        let uuid = characteristic.uuid
        let now = Date()
        MainActor.assumeIsolated {
            switch uuid {
            case Self.treadmillData: handleReading(value, at: now)
            case Self.controlPoint: handleControlResponse(value)
            case Self.speedRange: found(speeds: value)
            default: break
            }
        }
    }
}
