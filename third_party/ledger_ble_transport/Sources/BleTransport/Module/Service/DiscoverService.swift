//
//  DiscoverService.swift
//  BleTransport
//
//  Created by Dante Puglisi on 8/3/22.
//

import Foundation
import CoreBluetooth

public enum DiscoverServiceError: LocalizedError {
    case missingService

    public var errorDescription: String? {
        switch self {
        case .missingService:
            return "Missing service in the device"
        }
    }
}

class DiscoverService: TaskOperation {

    var finished: EmptyResponse?

    var peripheral: CBPeripheral

    private var serviceIdentifier: ServiceIdentifier
    private var callback: ((DiscoveryResult) -> Void)?

    deinit {
        //print("Deinited DiscoverService")
    }

    init(serviceIdentifier: ServiceIdentifier, peripheral: CBPeripheral, callback: @escaping (DiscoveryResult) -> Void) {
        self.serviceIdentifier = serviceIdentifier
        self.peripheral = peripheral
        self.callback = callback
    }

    func start() {
        if peripheral.service(with: serviceIdentifier.uuid) != nil {
            complete(withError: nil)
        } else {
            peripheral.discoverServices([serviceIdentifier.uuid])
        }
    }

    func didDiscoverServices() {
        if peripheral.service(with: serviceIdentifier.uuid) == nil {
            complete(withError: DiscoverServiceError.missingService)
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
