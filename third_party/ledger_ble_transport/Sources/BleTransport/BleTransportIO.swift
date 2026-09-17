import CoreBluetooth
import Foundation

/// Radio boundary used by the real transport and deterministic lifecycle tests.
protocol BleTransportIO: AnyObject {
    var isBluetoothAvailable: Bool { get }
    var bluetoothState: CBManagerState { get }
    func start(delegate: BleModuleDelegate)
    func stopScanning()
    func scanLedger(duration: TimeInterval, serviceIdentifiers: [ServiceIdentifier],
                    discovery: @escaping (ScanDiscovery, [ScanDiscovery]) -> ScanAction,
                    expired: ((ScanDiscovery, [ScanDiscovery]) -> ScanAction)?,
                    stopped: @escaping ([ScanDiscovery], Error?, Bool) -> Void)
    func connectLedger(_ id: PeripheralIdentifier, timeout: Timeout,
                       callback: @escaping (Result<PeripheralIdentifier, Error>) -> Void)
    func write<S: Sendable>(to: CharacteristicIdentifier, value: S,
                           type: CBCharacteristicWriteType, completion: @escaping (WriteResult) -> Void)
    func listen<R: Receivable>(to: CharacteristicIdentifier, completion: @escaping (ReadResult<R>) -> Void,
                              setupFinished: EmptyResponse?)
    func disconnect(completion: ((DisconnectionResult) -> Void)?)
    func cancelConnection()
}

extension BleModule: BleTransportIO {
    func scanLedger(duration: TimeInterval, serviceIdentifiers: [ServiceIdentifier],
                    discovery: @escaping (ScanDiscovery, [ScanDiscovery]) -> ScanAction,
                    expired: ((ScanDiscovery, [ScanDiscovery]) -> ScanAction)?,
                    stopped: @escaping ([ScanDiscovery], Error?, Bool) -> Void) {
        scan(duration: duration, serviceIdentifiers: serviceIdentifiers,
             discovery: discovery, expired: expired, stopped: stopped)
    }

    func connectLedger(_ id: PeripheralIdentifier, timeout: Timeout,
                       callback: @escaping (Result<PeripheralIdentifier, Error>) -> Void) {
        connect(peripheralIdentifier: id, timeout: timeout) { result in
            switch result {
            case .success(let peripheral):
                callback(.success(PeripheralIdentifier(uuid: peripheral.identifier, name: peripheral.name)))
            case .failure(let error): callback(.failure(error))
            }
        }
    }
}
