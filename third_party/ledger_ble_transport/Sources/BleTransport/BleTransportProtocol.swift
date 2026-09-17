//
//  BleTransportProtocol.swift
//  BleTransport
//
//  Created by Dante Puglisi on 5/12/22.
//

import Foundation
import CoreBluetooth

public typealias PeripheralInfoTuple = (peripheral: PeripheralIdentifier, rssi: Int, serviceUUID: CBUUID, canWriteWithoutResponse: Bool?)
public typealias PeripheralResponse = ((PeripheralIdentifier)->())
public typealias PeripheralsWithServicesResponse = (([PeripheralInfoTuple])->())
public typealias APDUResponse = ((APDU)->())
public typealias EmptyResponse = (()->())
public typealias BleErrorResponse = ((BleTransportError)->())
public typealias OptionalBleErrorResponse = ((BleTransportError?)->())
public typealias ErrorResponse = ((Error)->())

public protocol BleTransportProtocol {

    static var shared: BleTransportProtocol { get }

    var isBluetoothAvailable: Bool { get }
    var isConnected: Bool { get }

    // MARK: - Scan

    /// Scan for reachable peripherals with the services provided.
    ///
    /// - Parameter callback: Called each time the peripheral list of discovered peripherals changes.
    func scan(duration: TimeInterval, callback: @escaping PeripheralsWithServicesResponse, stopped: @escaping OptionalBleErrorResponse)

    /// Stop scanning for reachable peripherals.
    ///
    func stopScanning()


    // MARK: - Connect

    /// Attempt to connect to a given peripheral.
    ///
    /// - Parameter peripheral: The peripheral to connect to.
    func connect(toPeripheralID peripheral: PeripheralIdentifier, disconnectedCallback: EmptyResponse?, success: @escaping PeripheralResponse, failure: @escaping BleErrorResponse)
    @discardableResult func connect(toPeripheralID peripheral: PeripheralIdentifier, disconnectedCallback: EmptyResponse?) async throws -> PeripheralIdentifier

    /// Convenience method to `scan` for peripherals and connecting to the first discovered one.
    /// - Parameters:
    ///   - success: Callback called when the connection is successful.
    ///   - failure: Callback called when the connection failed.
    func create(scanDuration: TimeInterval, disconnectedCallback: EmptyResponse?, success: @escaping PeripheralResponse, failure: @escaping BleErrorResponse)
    @discardableResult func create(scanDuration: TimeInterval, disconnectedCallback: EmptyResponse?) async throws -> PeripheralIdentifier


    // MARK: - Messaging

    /// Send an `APDU` and wait for the response from the peripheral.
    /// - Parameters:
    ///   - apduToSend: `APDU` to send.
    ///   - callback: Callback that contains the result of the exchange.
    func exchange(apdu apduToSend: APDU, callback: @escaping (Result<String, BleTransportError>) -> Void)
    func exchange(apdu apduToSend: APDU) async throws -> String

    /// Send an `APDU` message.
    /// - Parameters:
    ///   - apdu: `APDU` to send.
    ///   - success: Callback called when the connection is successful.
    ///   - failure: Callback called when the connection failed.
    func send(apdu: APDU, success: @escaping EmptyResponse, failure: @escaping BleErrorResponse)
    func send(apdu: APDU) async throws


    // MARK: - Disconnect

    /// Abort a pending exchange by closing the radio link. Completion waits for disconnect.
    func abortExchange()

    /// Disconnect from the passed peripheral.
    /// - Parameters:
    ///   - immediate: Whether the disconnection should be queued or executed immediately. Passing `false` will wait until the current tasks have been completed.
    ///   - completion: Callback called when the peripheral disconnection has failed with an error or disconnected successfully (`error == nil`).
    func disconnect(completion: OptionalBleErrorResponse?)
    func disconnect() async throws


    // MARK: - Notifications

    /// Get notified when bluetooth changes availability
    /// - Parameter completion: Callback called when bluetooth becomes available (or immediately if was already available)
    func bluetoothAvailabilityCallback(completion: @escaping ((_ availability: Bool)->()))

    /// Get notified when bluetooth changes its state
    /// - Parameter completion: Callback called whenever bluetooth state changes (and immediately with the current state)
    func bluetoothStateCallback(completion: @escaping ((_ state: CBManagerState)->()))
    func bluetoothStateCallback() async -> CBManagerState

    /// Get notified once when the peripheral disconnects
    /// - Parameter completion: Callback called when the peripheral disconnects. This will be called only once.
    func notifyDisconnected(completion: @escaping EmptyResponse)


    // MARK: - Convenience methods

    func getAppAndVersion(success: @escaping ((AppInfo)->()), failure: @escaping ErrorResponse)
    func getAppAndVersion() async throws -> AppInfo

    func openAppIfNeeded(_ name: String, completion: @escaping (Result<Void, Error>) -> Void)
    func openAppIfNeeded(_ name: String) async throws
}

public struct AppInfo {
    let name: String
    let version: String
}
