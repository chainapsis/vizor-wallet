//
//  Connect.swift
//  BleTransport
//
//  Created by Dante Puglisi on 8/2/22.
//

import Foundation
import CoreBluetooth

/// Types of connection time outs. Can specify a time out in seconds, or no time out.
public enum Timeout {
    /// Specify a timeout with a duration in seconds.
    case seconds(TimeInterval)
    /// Specify there is no timeout.
    case none
}

public enum ConnectionError: LocalizedError {
    case timedOut
    case unexpectedDisconnect
    case peripheralCantBeRetrievedFromCentralManager

    public var errorDescription: String? {
        switch self {
        case .timedOut:
            return "Connection timed out."
        case .unexpectedDisconnect:
            return "Unexpected disconnect while connecting."
        case .peripheralCantBeRetrievedFromCentralManager:
            return "Central Manager can't retrieve the peripheral."
        }
    }
}

public class Connect: TaskOperation {
    var finished: EmptyResponse?
    private(set) var peripheral: CBPeripheral?
    private var callback: ((ConnectionResult) -> Void)?
    private var connectionTimer: Timer?
    private let timeout: Timeout
    private let startConnection: () throws -> Void
    private let cancelConnection: () -> Void
    private var didTimeOut = false

    convenience init(peripheralIdentifier: PeripheralIdentifier, manager: CBCentralManager, timeout: Timeout, callback: @escaping (ConnectionResult) -> Void) {
        let peripheral = manager.retrievePeripherals(withIdentifiers: [peripheralIdentifier.uuid]).first
        self.init(timeout: timeout, start: {
            guard let peripheral else { throw ConnectionError.peripheralCantBeRetrievedFromCentralManager }
            manager.connect(peripheral)
        }, cancel: {
            if let peripheral { manager.cancelPeripheralConnection(peripheral) }
        }, callback: callback)
        self.peripheral = peripheral
    }

    // Inject radio actions to exercise the real queue ownership without a radio.
    init(timeout: Timeout, start: @escaping () throws -> Void, cancel: @escaping () -> Void, callback: @escaping (ConnectionResult) -> Void) {
        self.timeout = timeout
        self.startConnection = start
        self.cancelConnection = cancel
        self.callback = callback
    }

    func start() {
        do { try startConnection() }
        catch { complete(.failure(error)); return }
        if case .seconds(let interval) = timeout {
            connectionTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: false) { [weak self] _ in
                self?.timedOut()
            }
        }
    }

    private func complete(_ result: ConnectionResult) {
        cancelTimer()
        let completion = callback
        callback = nil
        completion?(result)
        let drained = finished
        finished = nil
        drained?()
    }

    func didConnectPeripheral() {
        if didTimeOut {
            cancelConnection()
        } else if let peripheral {
            complete(.success(peripheral))
        }
    }

    func didDisconnectPeripheral(error: Error?) {
        complete(.failure(error ?? ConnectionError.unexpectedDisconnect))
    }

    private func cancelTimer() {
        connectionTimer?.invalidate()
        connectionTimer = nil
    }

    private func timedOut() {
        didTimeOut = true
        cancelTimer()
        let completion = callback
        callback = nil
        completion?(.failure(ConnectionError.timedOut))
        // Keep the queue slot until CoreBluetooth confirms teardown. A late
        // didConnect belongs to this attempt and must never complete the next.
        cancelConnection()
    }
}
