//
//  BleModule.swift
//  BleTransport
//
//  Created by Dante Puglisi on 8/2/22.
//

import Foundation
import CoreBluetooth

enum BleModuleError: LocalizedError {
    case selfIsNil
    case notConnected

    var errorDescription: String? {
        switch self {
        case .selfIsNil:
            return "Self is nil."
        case .notConnected:
            return "Attempted to perform an action when there's no device connected."
        }
    }
}

protocol BleModuleDelegate: AnyObject {
    func bluetoothAvailable(_ available: Bool)
    func bluetoothState(_ state: CBManagerState)
    func disconnected(from peripheral: PeripheralIdentifier)
}

protocol TaskOperation: AnyObject {
    var finished: EmptyResponse? { get set }

    func start()
}

public class BleModule: NSObject {
    private var cbCentralManager: CBCentralManager!

    private weak var delegate: BleModuleDelegate!

    private var operationsQueue = Queue()

    private var connectedPeripheral: Peripheral?
    private var connectionGeneration = 0

    private var listeners: [CharacteristicIdentifier: (ReadResult<Data?>) -> Void?] = [:]

    public var isBluetoothAvailable: Bool {
        if cbCentralManager == nil {
            return false
        } else {
            return cbCentralManager.state == .poweredOn
        }
    }

    public var bluetoothState: CBManagerState {
        return cbCentralManager.state
    }

    func start(delegate: BleModuleDelegate) {
        self.delegate = delegate
        self.cbCentralManager = CBCentralManager(delegate: self, queue: nil)
    }

    private func addOperation(_ operation: TaskOperation) {
        operation.finished = { [weak self] in
            if let first = self?.operationsQueue.first, first === operation {
                operation.finished = nil
                self?.operationsQueue.next()
            }
        }
        let generation = connectionGeneration
        self.operationsQueue.add(operation, isCurrent: { [weak self] in
            self?.connectionGeneration == generation
        })
    }

    private func clearAfterDisconnect(from peripheral: PeripheralIdentifier) {
        DispatchQueue.main.async {
            self.connectionGeneration += 1
            self.connectedPeripheral?.invalidate()
            self.connectedPeripheral = nil
            self.listeners.removeAll()
            self.operationsQueue.removeAllUpToScanOrConnect {
                self.delegate.disconnected(from: peripheral)
            }
        }
    }
}

// MARK: - Scan
extension BleModule {
    public func scan(duration: TimeInterval,
              throttleRSSIDelta: Int = 5,
              serviceIdentifiers: [ServiceIdentifier],
              discovery: @escaping (ScanDiscovery, [ScanDiscovery]) -> ScanAction,
              expired: ((ScanDiscovery, [ScanDiscovery]) -> ScanAction)? = nil,
              stopped: @escaping ([ScanDiscovery], Error?, Bool) -> Void) {
        let generation = connectionGeneration
        DispatchQueue.main.async {
            guard generation == self.connectionGeneration else { return }
            let scanOperation = Scan(duration: duration, throttleRSSIDelta: throttleRSSIDelta, serviceIdentifiers: serviceIdentifiers, discovery: discovery, expired: expired, stopped: stopped, manager: self.cbCentralManager)
            self.addOperation(scanOperation)
        }
    }

    func stopScanning() {
        operationsQueue.operationsOfType(Scan.self).first?.stopScanning()
    }
}

// MARK: - Connect
extension BleModule {
    public func connect(peripheralIdentifier: PeripheralIdentifier, timeout: Timeout, callback: @escaping (ConnectionResult) -> Void) {
        let generation = connectionGeneration
        DispatchQueue.main.async {
            guard generation == self.connectionGeneration else { return }
            let connectOperation = Connect(peripheralIdentifier: peripheralIdentifier, manager: self.cbCentralManager, timeout: timeout, callback: { [weak self] result in
                guard let self = self else { callback(.failure(BleModuleError.selfIsNil)); return }
                if case .success(let cbPeripheral) = result {
                    self.connectedPeripheral = Peripheral(delegate: self, cbPeripheral: cbPeripheral)
                }
                callback(result)
            })
            self.addOperation(connectOperation)
        }
    }
}

// MARK: - Write
extension BleModule {
    public func write<S: Sendable>(
        to characteristicIdentifier: CharacteristicIdentifier,
        value: S,
        type: CBCharacteristicWriteType = .withResponse,
        completion: @escaping (WriteResult) -> Void) {
            let generation = connectionGeneration
            DispatchQueue.main.async {
                guard generation == self.connectionGeneration else { return }
                guard let peripheral = self.connectedPeripheral else {
                    print("Cannot request write on \(characteristicIdentifier.description): \(BleModuleError.notConnected.localizedDescription)")
                    completion(.failure(BleModuleError.notConnected))
                    return
                }
                Task() {
                    do {
                        try await peripheral.prepareForCharacteristic(characteristicIdentifier)
                        guard generation == self.connectionGeneration else { return }
                        let writeOperation = Write(characteristicIdentifier: characteristicIdentifier, peripheral: peripheral.cbPeripheral, value: value, writeType: type, callback: completion)
                        self.addOperation(writeOperation)
                    } catch {
                        guard generation == self.connectionGeneration else { return }
                        completion(.failure(error))
                    }
                }
            }
        }
}

// MARK: - Listen
extension BleModule {
    public func listen<R: Receivable>(
        to characteristicIdentifier: CharacteristicIdentifier,
        completion: @escaping (ReadResult<R>) -> Void,
        setupFinished: EmptyResponse?) {
            let generation = connectionGeneration
            DispatchQueue.main.async {
                guard generation == self.connectionGeneration else { return }
                guard let peripheral = self.connectedPeripheral else {
                    print("Cannot request listen on \(characteristicIdentifier.description): \(BleModuleError.notConnected.localizedDescription)")
                    completion(.failure(BleModuleError.notConnected))
                    return
                }

                Task() {
                    do {
                        try await peripheral.prepareForCharacteristic(characteristicIdentifier)
                        guard generation == self.connectionGeneration else { return }

                        let listenOperation = Listen(characteristicIdentifier: characteristicIdentifier, peripheral: peripheral.cbPeripheral, value: true) { [weak self] result in
                            guard let self = self else { completion(.failure(BleModuleError.selfIsNil)); return }

                            switch result {
                            case .success:
                                self.listeners[characteristicIdentifier] = ({ dataResult in
                                    completion(ReadResult<R>(dataResult: dataResult))
                                })
                                setupFinished?()
                            case .failure(let error):
                                completion(.failure(error))
                            }
                        }
                        self.addOperation(listenOperation)
                    }
                }
            }
        }
}

// MARK: - Disconnect
extension BleModule {
    // Abort a failed handshake even when its characteristic operation is stuck.
    func cancelConnection() {
        guard let peripheral = connectedPeripheral else { return }
        cbCentralManager.cancelPeripheralConnection(peripheral.cbPeripheral)
    }

    public func disconnect(completion: ((DisconnectionResult) -> Void)? = nil) {
        DispatchQueue.main.async {
            guard let connectedPeripheral = self.connectedPeripheral else { completion?(.failure(BleModuleError.notConnected)); return }
            let disconnectOperation = Disconnect(peripheral: connectedPeripheral.cbPeripheral, manager: self.cbCentralManager, callback: completion)
            self.addOperation(disconnectOperation)
        }
    }
}

extension BleModule: CBCentralManagerDelegate {
    public func centralManagerDidUpdateState(_ central: CBCentralManager) {
        if central.state != .poweredOn {
            // Radio loss need not take the ordinary peripheral-disconnect path.
            // Invalidate queued Tasks before SDK callbacks can initiate recovery.
            connectionGeneration += 1
            connectedPeripheral?.invalidate()
            connectedPeripheral = nil
            listeners.removeAll()
            operationsQueue.discardAll()
        }
        delegate.bluetoothAvailable(central.state == .poweredOn)
        delegate.bluetoothState(central.state)
    }

    public func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String: Any], rssi RSSI: NSNumber) {
        operationsQueue.operationsOfType(Scan.self).first?.discoveredPeripheral(cbPeripheral: peripheral, advertisementData: advertisementData, rssi: RSSI)
    }

    public func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        guard let attempt = operationsQueue.operationsOfType(Connect.self).first,
              attempt.peripheral === peripheral else { return }
        attempt.didConnectPeripheral()
    }

    public func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        /// We ignore `error` because an error thrown here wouldn't mean that `disconnect` failed but rather that we got disconnected unexpectedly (which happens for example every time the device disconnect because of opening/quitting an app on it)
        let peripheralIdentifier = PeripheralIdentifier(uuid: peripheral.identifier, name: peripheral.name)
        operationsQueue.operationsOfType(Connect.self).first?.didDisconnectPeripheral(error: nil)
        operationsQueue.operationsOfType(Disconnect.self).first?.didDisconnectPeripheral(peripheral: peripheralIdentifier)
        clearAfterDisconnect(from: peripheralIdentifier)
    }

    /**
     This mostly happens when either the Bluetooth device or the Core Bluetooth stack somehow only partially completes the negotiation of a connection. For simplicity we treat this as a disconnection event, so we can perform all the same clean up logic.
     */
    public func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        operationsQueue.operationsOfType(Connect.self).first?.didDisconnectPeripheral(error: error)
        clearAfterDisconnect(from: PeripheralIdentifier(uuid: peripheral.identifier, name: peripheral.name))
    }
}

extension BleModule: PeripheralDelegate {
    func requestStartOperation(_ operation: TaskOperation) {
        addOperation(operation)
    }

    func didDiscoverServices() {
        operationsQueue.operationsOfType(DiscoverService.self).first?.didDiscoverServices()
    }

    func didDiscoverCharacteristics() {
        operationsQueue.operationsOfType(DiscoverCharacteristic.self).first?.didDiscoverCharacteristics()
    }

    func didUpdateCharacteristicNotificationState(error: Error?) {
        operationsQueue.operationsOfType(Listen.self).forEach({
            $0.didUpdateCharacteristicNotificationState(error: error)
        })
    }

    func didUpdateValueFor(characteristic: CBCharacteristic, error: Error?) {
        guard let characteristicIdentifier = CharacteristicIdentifier(characteristic) else {
            print("Received value update for characteristic (\(characteristic.uuid.uuidString) without a valid service. Update will be ignored")
            return
        }

        guard let listenCallback = listeners[characteristicIdentifier] else { return }
        if let error = error {
            listenCallback(.failure(error))
        } else {
            listenCallback(.success(characteristic.value))
        }
    }
}

extension CBPeripheral {
    public func service(with uuid: CBUUID) -> CBService? {
        return services?.first { $0.uuid == uuid }
    }
}

extension CBService {
    public func characteristic(with uuid: CBUUID) -> CBCharacteristic? {
        return characteristics?.first { $0.uuid == uuid }
    }
}
