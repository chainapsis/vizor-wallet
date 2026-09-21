//
//  Peripheral.swift
//  BleTransport
//
//  Created by Dante Puglisi on 8/4/22.
//

import Foundation
import CoreBluetooth

public class Peripheral: NSObject {

    private(set) weak var delegate: PeripheralDelegate?
    let cbPeripheral: CBPeripheral

    private var discoveries: [UUID: (DiscoveryResult) -> Void] = [:]

    // Release suspended discovery Tasks and detach callbacks before reusing the
    // CoreBluetooth peripheral for another connection.
    func invalidate() {
        delegate = nil
        if cbPeripheral.delegate === self { cbPeripheral.delegate = nil }
        listeners.removeAll()
        let callbacks = Array(discoveries.values)
        discoveries.removeAll()
        callbacks.forEach { $0(.failure(BleModuleError.notConnected)) }
    }

    private var listeners: [CharacteristicIdentifier: (ReadResult<Data?>) -> Void?] = [:]

    init(delegate: PeripheralDelegate, cbPeripheral: CBPeripheral) {
        self.delegate = delegate
        self.cbPeripheral = cbPeripheral

        super.init()

        self.cbPeripheral.delegate = self
    }

    public var identifier: PeripheralIdentifier {
        return PeripheralIdentifier(uuid: cbPeripheral.identifier, name: cbPeripheral.name)
    }

    public func prepareForCharacteristic(_ characteristicIdentifier: CharacteristicIdentifier) async throws {
        try await discoverService(characteristicIdentifier.service)
        try await discoverCharacteristic(characteristicIdentifier)
    }

    private func discoverService(_ serviceIdentifier: ServiceIdentifier) async throws {
        return try await withCheckedThrowingContinuation { continuation in
            discoverService(serviceIdentifier) { result in
                switch result {
                case .success:
                    continuation.resume()
                case .failure(let error):
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    private func discoverCharacteristic(_ characteristicIdentifier: CharacteristicIdentifier) async throws {
        return try await withCheckedThrowingContinuation { continuation in
            discoverCharacteristic(characteristicIdentifier) { result in
                switch result {
                case .success:
                    continuation.resume()
                case .failure(let error):
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    private func discoverService(_ serviceIdentifier: ServiceIdentifier, callback: @escaping (DiscoveryResult) -> Void) {
        guard let delegate = delegate else { callback(.failure(BleModuleError.notConnected)); return }
        let id = UUID()
        discoveries[id] = callback
        let operation = DiscoverService(serviceIdentifier: serviceIdentifier, peripheral: cbPeripheral) { [weak self] result in
            self?.discoveries.removeValue(forKey: id)?(result)
        }
        delegate.requestStartOperation(operation)
    }

    private func discoverCharacteristic(_ characteristicIdentifier: CharacteristicIdentifier, callback: @escaping (DiscoveryResult) -> Void) {
        guard let delegate = delegate else { callback(.failure(BleModuleError.notConnected)); return }
        let id = UUID()
        discoveries[id] = callback
        let operation = DiscoverCharacteristic(characteristicIdentifier: characteristicIdentifier, peripheral: cbPeripheral) { [weak self] result in
            self?.discoveries.removeValue(forKey: id)?(result)
        }
        delegate.requestStartOperation(operation)
    }

    public func isListening(to characteristicIdentifier: CharacteristicIdentifier) -> Bool {
        return listeners.keys.contains(characteristicIdentifier)
    }

    public func listen<R: Receivable>(
        to characteristicIdentifier: CharacteristicIdentifier,
        completion: @escaping (ReadResult<R>) -> Void) {

            //print("Requesting listen on \(characteristicIdentifier.description)...")

            Task() {
                do {
                    try await prepareForCharacteristic(characteristicIdentifier)

                    let listenOperation = Listen(characteristicIdentifier: characteristicIdentifier, peripheral: cbPeripheral, value: true) { [weak self] result in
                        guard let self = self else { completion(.failure(BleModuleError.selfIsNil)); return }

                        switch result {
                        case .success:
                            self.listeners[characteristicIdentifier] = ({ dataResult in
                                completion(ReadResult<R>(dataResult: dataResult))
                            })
                        case .failure(let error):
                            completion(.failure(error))
                        }
                    }
                    delegate?.requestStartOperation(listenOperation)
                }
            }
        }
}

extension Peripheral: CBPeripheralDelegate {

    public func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        delegate?.didDiscoverServices()
    }

    public func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        delegate?.didDiscoverCharacteristics()
    }

    public func peripheral(_ peripheral: CBPeripheral, didUpdateNotificationStateFor characteristic: CBCharacteristic, error: Error?) {
        delegate?.didUpdateCharacteristicNotificationState(error: error)
    }

    public func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        delegate?.didUpdateValueFor(characteristic: characteristic, error: error)
    }
}
