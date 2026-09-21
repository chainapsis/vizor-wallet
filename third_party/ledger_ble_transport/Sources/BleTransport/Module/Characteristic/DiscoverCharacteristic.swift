//
//  DiscoverCharacteristic.swift
//  BleTransport
//
//  Created by Dante Puglisi on 8/3/22.
//

import Foundation
import CoreBluetooth

public enum DiscoverCharacteristicError: LocalizedError {
    case missingService(ServiceIdentifier)
    case missingCharacteristic(CharacteristicIdentifier)
    case missingCharacteristicProperty(CBCharacteristicProperties)

    public var errorDescription: String? {
        switch self {
        case .missingService(let service):
            return "Missing service: \(service)"
        case .missingCharacteristic(let characteristic):
            return "Missing characteristic: \(characteristic)"
        case .missingCharacteristicProperty(let properties):
            return "Missing characteristic properties: \(properties)"
        }
    }
}

class DiscoverCharacteristic: TaskOperation {

    var finished: EmptyResponse?

    let peripheral: CBPeripheral

    private var characteristicIdentifier: CharacteristicIdentifier
    private var callback: ((DiscoveryResult) -> Void)?

    init(characteristicIdentifier: CharacteristicIdentifier, peripheral: CBPeripheral, callback: @escaping (DiscoveryResult) -> Void) {
        self.characteristicIdentifier = characteristicIdentifier
        self.peripheral = peripheral
        self.callback = callback
    }

    func start() {
        guard let service = peripheral.service(with: characteristicIdentifier.service.uuid) else {
            complete(withError: DiscoverCharacteristicError.missingService(characteristicIdentifier.service))
            return
        }

        if service.characteristic(with: characteristicIdentifier.uuid) != nil {
            complete(withError: nil)
        } else {
            peripheral.discoverCharacteristics([characteristicIdentifier.uuid], for: service)
        }
    }

    func didDiscoverCharacteristics() {
        guard let service = peripheral.service(with: characteristicIdentifier.service.uuid) else {
            complete(withError: DiscoverCharacteristicError.missingService(characteristicIdentifier.service))
            return
        }

        if service.characteristic(with: characteristicIdentifier.uuid) == nil {
            complete(withError: DiscoverCharacteristicError.missingCharacteristic(characteristicIdentifier))
        } else {
            complete(withError: nil)
        }
    }

    func complete(withError error: Error?) {
        if let error = error {
            callback?(.failure(error))
        } else {
            callback?(.success)
        }
        callback = nil
        finished?()
    }
}
