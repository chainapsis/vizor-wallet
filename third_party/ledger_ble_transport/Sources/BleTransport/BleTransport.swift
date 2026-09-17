//
//  BleTransport.swift
//  BleTransport
//
//  Created by Dante Puglisi on 5/11/22.
//

import Foundation
import CoreBluetooth

/// Errors thrown when scanning/sending/receiving/connecting
public enum BleTransportError: LocalizedError {
    case pendingActionOnDevice
    case userRefusedOnDevice
    case scanningTimedOut
    case bluetoothNotAvailable
    case connectError(description: String)
    case currentConnectedError(description: String)
    case writeError(description: String)
    case readError(description: String)
    case listenError(description: String)
    case scanError(description: String)
    case pairingError(description: String)
    case lowerLevelError(description: String)

    public var errorDescription: String? {
        switch self {
        case .pendingActionOnDevice:
            return "Pending action on device"
        case .userRefusedOnDevice:
            return "User refused on device"
        case .scanningTimedOut:
            /// https://github.com/LedgerHQ/ledger-live/blob/acdd59af6dcfcda1d136ccbfc8fdf49311485a32/libs/ledgerjs/packages/hw-transport/src/Transport.ts#L261
            return "No Ledger device found (timeout)"
        case .bluetoothNotAvailable:
            return "Bluetooth is not available"
        case .connectError(let description):
            return "Connect error: \(description)"
        case .currentConnectedError(let description):
            return "Current connected error: \(description)"
        case .writeError(let description):
            return "Write error: \(description)"
        case .readError(let description):
            return "Read error: \(description)"
        case .listenError(let description):
            return "Listen error: \(description)"
        case .scanError(let description):
            return "Scan error: \(description)"
        case .pairingError(let description):
            return "Pairing error: \(description)"
        case .lowerLevelError(let description):
            return "Lower level error: \(description)"
        }
    }

    /// `id` is defined by what the JS bindings are returning and using for error handling
    public var id: String? {
        switch self {
        case .pendingActionOnDevice:
            return "TransportRaceCondition"
        case .userRefusedOnDevice:
            return nil
        case .scanningTimedOut:
            /// https://github.com/LedgerHQ/ledger-live/blob/acdd59af6dcfcda1d136ccbfc8fdf49311485a32/libs/ledgerjs/packages/hw-transport/src/Transport.ts#L261
            return "ListenTimeout"
        case .bluetoothNotAvailable:
            return nil
        case .connectError(_):
            return nil
        case .currentConnectedError(_):
            return nil
        case .writeError(_):
            return nil
        case .readError(_):
            return nil
        case .listenError(_):
            return nil
        case .scanError(_):
            return nil
        case .pairingError(_):
            return nil
        case .lowerLevelError(_):
            return nil
        }
    }
}

/// Errors received as `status` sent in a message from a device
public enum BleStatusError: LocalizedError, Hashable {
    case userRejected(status: String)
    case appNotAvailableInDevice(status: String)
    case formatNotSupported(status: String)
    case couldNotParseResponseData(status: String)
    case unknown(status: String)
    case noStatus

    public var errorDescription: String? {
        switch self {
        case .userRejected(_):
            return "User rejected action"
        case .appNotAvailableInDevice(_):
            return "App is not available in device"
        case .formatNotSupported(_):
            return "Format is not supported"
        case .couldNotParseResponseData(_):
            return "Could not parse response data"
        case .unknown(let status):
            return "Unknown error. Status received: \(status)"
        case .noStatus:
            return "No status received from device"
        }
    }

    public var status: String? {
        switch self {
        case .userRejected(let status):
            return status
        case .appNotAvailableInDevice(let status):
            return status
        case .formatNotSupported(let status):
            return status
        case .couldNotParseResponseData(let status):
            return status
        case .unknown(let status):
            return status
        case .noStatus:
            return nil
        }
    }
}

extension BleTransport: BleModuleDelegate {
    func disconnected(from peripheral: PeripheralIdentifier) {
        clearConnection()
    }

    func bluetoothAvailable(_ available: Bool) {
        bluetoothAvailabilityCompletion?(available)
        if !available {
            clearConnection()
        }
    }

    func bluetoothState(_ state: CBManagerState) {
        bluetoothStateCompletion?(state)
    }
}

@objc public class BleTransport: NSObject, BleTransportProtocol {

    public static var shared: BleTransportProtocol = BleTransport(configuration: nil, debugMode: false)

    private let bleModule: BleTransportIO
    private let handshakeTimeout: TimeInterval

    private let debugMode: Bool

    private let configuration: BleTransportConfiguration
    private var disconnectedCallback: EmptyResponse? /// Once `disconnectCallback` is set it never becomes `nil` again so we can reuse it in methods where we reconnect to the peripheral blindly like `openApp/closeApp`
    private var connectFailure: ((BleTransportError)->())?

    private var scanDuration: TimeInterval = 5.0 /// `scanDuration` will be overriden every time a value gets passed to `scan/create`

    private var peripheralsServicesTuple = [PeripheralInfoTuple]()
    private var connectedPeripheral: PeripheralIdentifier?
    private var bluetoothAvailabilityCompletion: ((Bool)->())?
    private var bluetoothStateCompletion: ((CBManagerState)->())?
    private var notifyDisconnectedCompletion: EmptyResponse?

    // One exchange owns response assembly and completion. All access is on main.
    private var pendingExchange: PendingBleExchange?
    private var abortingExchange = false
    private var isExchanging: Bool { pendingExchange != nil }
    private var waitingToDisconnectCompletion: OptionalBleErrorResponse?
    private var disconnecting = false
    private var disconnectCompletion: OptionalBleErrorResponse?
    private var connectionGeneration = 0
    private var connectionUsable = false
    private var connectSuccess: PeripheralResponse?
    private var handshakeTimer: Timer?

    private func finishExchange(_ result: Result<String, BleTransportError>) {
        let pending = pendingExchange
        pendingExchange = nil
        if case .failure = result { connectionUsable = false }
        // Capture before invoking client code: it may start a different request.
        let disconnectCompletion = waitingToDisconnectCompletion
        waitingToDisconnectCompletion = nil
        pending?.finish(result)
        if let disconnectCompletion { disconnect(completion: disconnectCompletion) }
    }

    private func failConnect(_ error: BleTransportError) {
        handshakeTimer?.invalidate()
        handshakeTimer = nil
        let failure = connectFailure
        connectFailure = nil
        connectSuccess = nil
        mtuWaitingForCallback = nil
        connectionUsable = false
        // A handshake failure can leave GATT connected with an unfinished
        // characteristic operation. Cancel through CoreBluetooth, not that queue.
        if connectedPeripheral != nil { bleModule.cancelConnection() }
        failure?(error)
    }

    /// Infer MTU
    private var mtuWaitingForCallback: PeripheralResponse?

    @objc
    public var isBluetoothAvailable: Bool {
        bleModule.isBluetoothAvailable
    }

    @objc
    public var isConnected: Bool {
        connectedPeripheral != nil
    }

    // MARK: - Initialization

    init(configuration: BleTransportConfiguration?, debugMode: Bool, module: BleTransportIO = BleModule(), handshakeTimeout: TimeInterval = 60) {
        self.bleModule = module
        self.handshakeTimeout = handshakeTimeout
        self.configuration = configuration ?? BleTransportConfiguration.defaultConfig()
        self.debugMode = debugMode

        super.init()

        self.bleModule.start(delegate: self)
    }

    // MARK: - Public Methods

    public func scan(duration: TimeInterval, callback: @escaping PeripheralsWithServicesResponse, stopped: @escaping OptionalBleErrorResponse) {
        DispatchQueue.main.async {
            self.peripheralsServicesTuple = [] /// We clean `peripheralsServicesTuple` at the start of each scan so the changes can be properly propagated and not before because it has info needed for connecting and writing to peripherals

            self.bleModule.scanLedger(duration: duration, serviceIdentifiers: self.configuration.services.map({ $0.service }), discovery: { [weak self] discovery, discoveries in
                guard let self = self else { return .continue }
                if self.updatePeripheralsServicesTuple(discoveries: discoveries) {
                    callback(self.peripheralsServicesTuple)
                }
                return .continue
            }, expired: { [weak self] discovery, discoveries in
                guard let self = self else { return .continue }
                if self.updatePeripheralsServicesTuple(discoveries: discoveries) {
                    callback(self.peripheralsServicesTuple)
                }
                return .continue
            }, stopped: { [weak self] discoveries, error, timedOut in
                guard let self = self else { return }
                self.updatePeripheralsServicesTuple(discoveries: discoveries)
                if let error = error {
                    print("Stopped scanning with error: \(error)")
                    stopped(.scanError(description: error.localizedDescription))
                } else if timedOut {
                    stopped(.scanningTimedOut)
                } else {
                    stopped(nil)
                }
            })
        }
    }

    @objc
    public func stopScanning() {
        DispatchQueue.main.async {
            self.bleModule.stopScanning()
        }
    }

    public func create(scanDuration: TimeInterval, disconnectedCallback: EmptyResponse?, success: @escaping PeripheralResponse, failure: @escaping BleErrorResponse) {

        guard isBluetoothAvailable else { failure(.bluetoothNotAvailable); return }

        self.scanDuration = scanDuration

        var connecting = false

        func attemptConnecting(peripheralInfo: PeripheralInfoTuple) {
            connect(toPeripheralID: peripheralInfo.peripheral, disconnectedCallback: disconnectedCallback, success: { connectedPeripheral in
                success(connectedPeripheral)
            }, failure: failure)
        }

        self.scan(duration: scanDuration) { discoveries in
            guard let firstDiscovery = discoveries.first else { return }
            if !connecting {
                connecting = true
                attemptConnecting(peripheralInfo: firstDiscovery)
            }
        } stopped: { error in
            if let error = error {
                failure(error)
            }
        }
    }

    public func exchange(apdu apduToSend: APDU, callback: @escaping (Result<String, BleTransportError>) -> Void) {
        DispatchQueue.main.async {
            guard !self.isExchanging else {
                callback(.failure(.pendingActionOnDevice))
                return
            }

            guard self.connectionUsable else {
                callback(.failure(.currentConnectedError(description: "Reconnect the Ledger before sending another request")))
                return
            }
            self.pendingExchange = PendingBleExchange(completion: callback)
            self.writeAPDU(apduToSend)
        }
    }

    public func send(apdu: APDU, success: @escaping EmptyResponse, failure: @escaping BleErrorResponse) {
        DispatchQueue.main.async {
            self.send(value: apdu, success: success, failure: failure)
        }
    }

    /// The inner implementation of `send`
    /// - Parameters:
    ///   - value: APDU to send
    ///   - retryWithResponse: Used internally in the function if `writeWithoutResponse` fails the first time
    ///   - success: The success callback
    ///   - failure: The failue callback
    fileprivate func send<S: Sendable>(value: S, retryWithResponse: Bool = false, success: @escaping EmptyResponse, failure: @escaping BleErrorResponse) {
        let generation = connectionGeneration
        let connectedPeripheral: PeripheralIdentifier
        let connectedPeripheralTuple: PeripheralInfoTuple
        let peripheralService: BleService
        let currentConnectedTuple = currentConnectedTuple()
        switch currentConnectedTuple {
        case .success(let tuple):
            (connectedPeripheral, connectedPeripheralTuple, peripheralService) = tuple
        case .failure(let error):
            failure(error)
            return
        }
        let writeCharacteristic: CharacteristicIdentifier
        let type: CBCharacteristicWriteType
        if let canWriteWithoutCharacteristic = connectedPeripheralTuple.canWriteWithoutResponse {
            writeCharacteristic = peripheralService.writeCharacteristic(canWriteWithoutResponse: canWriteWithoutCharacteristic)
            type = canWriteWithoutCharacteristic ? .withoutResponse : .withResponse
        } else {
            writeCharacteristic = retryWithResponse ? peripheralService.writeWithResponse : peripheralService.writeWithoutResponse
            type = retryWithResponse ? .withResponse : .withoutResponse
        }
        self.bleModule.write(to: writeCharacteristic, value: value, type: type) { [weak self] result in
            guard let self = self else { failure(.writeError(description: "Self got deallocated")); return }
            guard generation == self.connectionGeneration else { return }
            switch result {
            case .success:
                if connectedPeripheralTuple.canWriteWithoutResponse == nil {
                    if let tupleIndex = self.peripheralsServicesTuple.firstIndex(where: { $0.peripheral.uuid == connectedPeripheral.uuid }) {
                        self.peripheralsServicesTuple[tupleIndex].canWriteWithoutResponse = type == .withoutResponse
                    }
                }
                success()
            case .failure(let error):
                if connectedPeripheralTuple.canWriteWithoutResponse == nil && !retryWithResponse {
                    self.send(value: value, retryWithResponse: true, success: success, failure: failure)
                } else {
                    print(error.localizedDescription)
                    failure(.writeError(description: error.localizedDescription))
                }
            }
        }
    }

    public func abortExchange() {
        DispatchQueue.main.async {
            guard self.pendingExchange != nil, !self.abortingExchange else { return }
            self.abortingExchange = true
            self.connectionUsable = false
            self.connectionGeneration += 1
            if self.isConnected {
                self.bleModule.cancelConnection()
            } else {
                self.clearConnection()
            }
        }
    }

    public func disconnect(completion: OptionalBleErrorResponse?) {
        guard !disconnecting else { completion?(.pendingActionOnDevice); return }
        guard isConnected else { completion?(nil); return }
        guard !isExchanging else { self.waitingToDisconnectCompletion = completion; return }
        disconnecting = true
        disconnectCompletion = completion
        connectionUsable = false
        self.bleModule.disconnect { [weak self] result in
            guard let self else { return }
            if case .failure(let error) = result {
                let callback = self.disconnectCompletion
                self.disconnectCompletion = nil
                self.disconnecting = false
                callback?(.lowerLevelError(description: error.localizedDescription))
            }
            // Success completes in clearConnection, after the module queue and
            // notifications have drained. Never reconnect ahead of that event.
        }
    }

    public func connect(toPeripheralID peripheral: PeripheralIdentifier, disconnectedCallback: EmptyResponse?, success: @escaping PeripheralResponse, failure: @escaping BleErrorResponse) {

        guard connectSuccess == nil && !disconnecting else { failure(.pendingActionOnDevice); return }
        guard !isConnected else { failure(.connectError(description: "Already connected to a peripheral")); return }
        guard isBluetoothAvailable else { failure(.bluetoothNotAvailable); return }

        self.stopScanning()

        self.disconnectedCallback = disconnectedCallback
        connectionGeneration += 1
        let generation = connectionGeneration
        connectSuccess = success
        connectFailure = failure
        connectionUsable = false

        let connect = {
            self.bleModule.connectLedger(peripheral, timeout: .seconds(5)) { [weak self] result in
                guard let self = self else { return }
                guard generation == self.connectionGeneration, self.connectSuccess != nil else { return }
                switch result {
                case .success(let peripheral):
                    self.connectedPeripheral = peripheral
                    // Includes notification setup (which may prompt pairing).
                    self.handshakeTimer = Timer.scheduledTimer(withTimeInterval: self.handshakeTimeout, repeats: false) { [weak self] _ in
                        guard let self, generation == self.connectionGeneration else { return }
                        self.failConnect(.connectError(description: "Ledger Bluetooth initialization timed out"))
                    }
                    self.startListening {
                        guard generation == self.connectionGeneration, self.connectSuccess != nil else { return }
                        self.mtuWaitingForCallback = { [weak self] connected in
                            guard let self, generation == self.connectionGeneration else { return }
                            self.handshakeTimer?.invalidate()
                            self.handshakeTimer = nil
                            let completion = self.connectSuccess
                            self.connectSuccess = nil
                            self.connectFailure = nil
                            self.mtuWaitingForCallback = nil
                            self.connectionUsable = true
                            completion?(connected)
                        }
                        self.inferMTU()
                    }
                case .failure(let error):
                    if case ConnectionError.timedOut = error { self.disconnecting = true }
                    self.failConnect(.connectError(description: error.localizedDescription))
                }
            }
        }

        if !peripheralsServicesTuple.contains(where: { $0.peripheral == peripheral }) {
            scanAndDiscoverBeforeConnecting(lookingFor: peripheral, connectFunction: { [weak self] in
                guard let self, generation == self.connectionGeneration, self.connectSuccess != nil else { return }
                connect()
            }, failure: { [weak self] error in
                guard let self, generation == self.connectionGeneration, self.connectSuccess != nil else { return }
                self.failConnect(error)
            })
        } else {
            connect()
        }
    }

    public func bluetoothAvailabilityCallback(completion: @escaping ((Bool)->())) {
        completion(isBluetoothAvailable)
        bluetoothAvailabilityCompletion = completion
    }

    public func bluetoothStateCallback(completion: @escaping ((CBManagerState)->())) {
        completion(self.bleModule.bluetoothState)
        bluetoothStateCompletion = completion
    }

    public func notifyDisconnected(completion: @escaping EmptyResponse) {
        if !isConnected {
            completion()
        } else {
            notifyDisconnectedCompletion = completion
        }
    }

    public func getAppAndVersion(success: @escaping ((AppInfo)->()), failure: @escaping ErrorResponse) {
        let apdu = APDU(data: [0xb0, 0x01, 0x00, 0x00])
        exchange(apdu: apdu) { result in
            switch result {
            case .success(let string):
                let data = string.UInt8Array()
                var i = 0
                let format = data[i]
                if format != 1 {
                    failure(BleTransportError.lowerLevelError(description: "Format is not supported"))
                    return
                }
                i += 1
                let nameLength = Int(data[i])
                i += 1
                let nameData = data[i..<i+Int(nameLength)]
                i += nameLength
                let versionLength = Int(data[i])
                i += 1
                let versionData = data[i..<i+Int(versionLength)]
                i += versionLength
                guard let name = String(data: Data(nameData), encoding: .ascii) else { failure(BleTransportError.lowerLevelError(description: "Could not parse response data")); return }
                guard let version = String(data: Data(versionData), encoding: .ascii) else { failure(BleTransportError.lowerLevelError(description: "Could not parse response data")); return }
                success(AppInfo(name: name, version: version))
            case .failure(let error):
                failure(error)
            }
        }
    }

    public func openAppIfNeeded(_ name: String, completion: @escaping (Result<Void, Error>) -> Void) {
        Task() {
            do {
                let currentAppInfo = try await getAppAndVersion()
                if currentAppInfo.name != name {
                    if currentAppInfo.name == "BOLOS" {
                        try await openApp(name)
                        completion(.success(()))
                    } else {
                        try await closeApp()
                        try await openApp(name)
                        completion(.success(()))
                    }
                } else {
                    completion(.success(()))
                }
            } catch {
                completion(.failure(error))
            }
        }
    }


    // MARK: - Private methods

    /// Updates the current list of peripherals matching them with their service.
    ///
    /// - Parameter discoveries: All the current peripherals.
    /// - Returns: A boolean indicating whether the last changed since the last update.
    @discardableResult
    fileprivate func updatePeripheralsServicesTuple(discoveries: [ScanDiscovery]) -> Bool {
        var auxPeripherals = [PeripheralInfoTuple]()
        for discovery in discoveries {
            if let services = discovery.advertisementPacket["kCBAdvDataServiceUUIDs"] as? [CBUUID], let firstService = services.first {
                auxPeripherals.append((peripheral: discovery.peripheralIdentifier, rssi: discovery.rssi, serviceUUID: firstService, canWriteWithoutResponse: nil))
            }
        }

        let somethingChanged = auxPeripherals.map({ $0.peripheral }) != peripheralsServicesTuple.map({ $0.peripheral })

        peripheralsServicesTuple = auxPeripherals

        return somethingChanged
    }

    fileprivate func scanAndDiscoverBeforeConnecting(lookingFor: PeripheralIdentifier, connectFunction: @escaping ()->(), failure: @escaping BleErrorResponse) {
        var finished = false
        let timer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: false) { _ in
            guard !finished else { return }
            finished = true
            self.stopScanning()
            failure(.connectError(description: "Couldn't find peripheral when scanning, timed out"))
        }

        scan(duration: scanDuration) { [weak self] discoveries in
            if !finished, discoveries.contains(where: { $0.peripheral == lookingFor }) {
                finished = true
                timer.invalidate()
                connectFunction()
                self?.stopScanning()
            }
        } stopped: { error in
            if let error = error, !finished {
                finished = true
                timer.invalidate()
                failure(.connectError(description: "Couldn't find peripheral when scanning because of error: \(error.localizedDescription)"))
            }
        }

    }

    fileprivate func currentConnectedTuple() -> Result<(PeripheralIdentifier, PeripheralInfoTuple, BleService), BleTransportError> {
        guard let connectedPeripheral = connectedPeripheral else { return .failure(.currentConnectedError(description: "Not connected")) }
        guard let connectedPeripheralTuple = peripheralsServicesTuple.first(where: { $0.peripheral.uuid == connectedPeripheral.uuid }) else { return .failure(.currentConnectedError(description: "peripheralsServiceTuple doesn't contain connected peripheral UUID")) }
        guard let peripheralService = configuration.serviceMatching(serviceUUID: connectedPeripheralTuple.serviceUUID) else { return .failure(.currentConnectedError(description: "No matching peripheralService")) }

        return .success((connectedPeripheral, connectedPeripheralTuple, peripheralService))
    }

    /**
     * Write the next ble frame to the peripheral, only triggered from the exchange/send methods.
     **/
    fileprivate func writeAPDU(_ apdu: APDU, withResponse: Bool = false) {
        guard let pending = pendingExchange else { return }
        guard !apdu.isEmpty else {
            finishExchange(.failure(.writeError(description: "APDU is empty")))
            return
        }
        send(apdu: apdu) { [weak self, weak pending] in
            guard let self, let pending, !self.abortingExchange, self.pendingExchange === pending else { return }
            apdu.next()
            if !apdu.isEmpty { self.writeAPDU(apdu) }
        } failure: { [weak self, weak pending] error in
            guard let self, let pending, !self.abortingExchange, self.pendingExchange === pending else { return }
            self.finishExchange(.failure(error))
        }
    }

    fileprivate func startListening(setupFinished: EmptyResponse?) {
        let generation = connectionGeneration
        self.listen { [weak self] apduReceived in
            guard let self, generation == self.connectionGeneration else { return }
            if self.mtuWaitingForCallback != nil {
                self.parseMTUresponse(apduReceived: apduReceived)
                return
            }
            guard let pending = self.pendingExchange else { return }
            if let result = pending.receive(apduReceived.data) { self.finishExchange(result) }
        } setupFinished: { [weak self] in
            guard let self, generation == self.connectionGeneration else { return }
            setupFinished?()
        } failure: { [weak self] error in
            guard let self, generation == self.connectionGeneration else { return }
            if self.connectSuccess != nil { self.failConnect(error) }
            else { self.finishExchange(.failure(error)) }
        }
    }

    fileprivate func listen(apduReceived: @escaping APDUResponse, setupFinished: EmptyResponse?, failure: @escaping BleErrorResponse) {
        let peripheralService: BleService
        let currentConnectedTuple = currentConnectedTuple()
        switch currentConnectedTuple {
        case .success(let tuple):
            (_, _, peripheralService) = tuple
        case .failure(let error):
            failure(error)
            return
        }
        self.bleModule.listen(to: peripheralService.notify) { (result: ReadResult<APDU>) in
            switch result {
            case .success(let apdu):
                apduReceived(apdu)
            case .failure(let error):
                if (error as NSError).code == CBATTError.insufficientEncryption.rawValue {
                    failure(.pairingError(description: error.localizedDescription))
                } else {
                    failure(.listenError(description: error.localizedDescription))
                }
            }
        } setupFinished: {
            setupFinished?()
        }
    }

    fileprivate func inferMTU() {
        send(value: APDU.inferMTU) {} failure: { [weak self] error in
            self?.failConnect(error)
        }
    }

    fileprivate func parseMTUresponse(apduReceived: APDU) {
        guard apduReceived.data.count >= 6, apduReceived.data.first == 0x08,
              apduReceived.data[5] > 5 else {
            failConnect(.connectError(description: "Invalid Ledger MTU response"))
            return
        }
        APDU.mtuSize = Int(apduReceived.data[5])
        let completion = mtuWaitingForCallback
        mtuWaitingForCallback = nil
        if let connectedPeripheral { completion?(connectedPeripheral) }
    }

    fileprivate func clearConnection() {
        abortingExchange = false
        connectionGeneration += 1
        connectedPeripheral = nil
        connectionUsable = false
        handshakeTimer?.invalidate()
        handshakeTimer = nil
        let connectError = connectFailure
        connectFailure = nil
        connectSuccess = nil
        mtuWaitingForCallback = nil
        let notify = notifyDisconnectedCompletion
        notifyDisconnectedCompletion = nil
        let disconnected = disconnectedCallback
        let disconnectedResult = disconnectCompletion
        disconnectCompletion = nil
        disconnecting = false
        // Release SDK ownership and buffers before any reentrant client callback.
        finishExchange(.failure(.currentConnectedError(description: "Ledger disconnected")))
        connectError?(.connectError(description: "Ledger disconnected during initialization"))
        notify?()
        disconnected?()
        disconnectedResult?(nil)
    }

    fileprivate func openApp(_ name: String, success: @escaping EmptyResponse, failure: @escaping ErrorResponse) {
        let errorCodes: [BleStatusError: [String]] = [.userRejected(status: ""): ["6985", "5501"], .appNotAvailableInDevice(status: ""): ["6984", "6807"]]
        let nameData = Data(name.utf8)
        var data: [UInt8] = [0xe0, 0xd8, 0x00, 0x00]
        data.append(UInt8(nameData.count))
        data.append(contentsOf: nameData)
        let apdu = APDU(data: data)
        BleTransport.shared.exchange(apdu: apdu) { [weak self] result in
            guard let self = self else { failure(BleTransportError.lowerLevelError(description: "closeApp -> self is nil")); return }
            guard let disconnectedCallback = self.disconnectedCallback else { failure(BleTransportError.lowerLevelError(description: "closeApp -> disconnectedCallback is nil")); return }

            switch result {
            case .success(let response):
                if let error = self.parseStatus(response: response, errorCodes: errorCodes) {
                    failure(error)
                } else {
                    self.notifyDisconnected {
                        self.create(scanDuration: self.scanDuration, disconnectedCallback: disconnectedCallback) { _ in
                            success()
                        } failure: { error in
                            failure(error)
                        }
                    }
                }
            case .failure(let error):
                failure(error)
            }
        }
    }

    /// Never call this method directly since some apps (like Bitcoin) will hang the execution if `getAppAndVersion` is not called right before
    fileprivate func closeApp(success: @escaping EmptyResponse, failure: @escaping ErrorResponse) {
        let apdu = APDU(data: [0xb0, 0xa7, 0x00, 0x00])
        BleTransport.shared.exchange(apdu: apdu) { [weak self] result in
            guard let self = self else { failure(BleTransportError.lowerLevelError(description: "closeApp -> self is nil")); return }
            guard let disconnectedCallback = self.disconnectedCallback else { failure(BleTransportError.lowerLevelError(description: "closeApp -> disconnectedCallback is nil")); return }

            switch result {
            case .success(_):
                self.notifyDisconnected {
                    self.create(scanDuration: self.scanDuration, disconnectedCallback: disconnectedCallback) { _ in
                        success()
                    } failure: { error in
                        failure(error)
                    }
                }
            case .failure(let error):
                failure(error)
            }
        }
    }

    fileprivate func parseStatus(response: String, errorCodes: [BleStatusError: [String]]) -> BleStatusError? {
        let status = String(response.suffix(4))
        if status.count == 4 {
            if status == "9000" {
                return nil
            } else {
                if let error = errorCodes.first(where: { $0.value.contains(status) })?.key {
                    /// `error` here is a BleStatusError which we used to group the status codes that match the associated value `status` it has is empty because we didn't know the appropriate status then so we re-generate it here
                    switch error {
                    case .userRejected(_):
                        return .userRejected(status: status)
                    case .appNotAvailableInDevice(_):
                        return .appNotAvailableInDevice(status: status)
                    case .formatNotSupported(_):
                        return .formatNotSupported(status: status)
                    case .couldNotParseResponseData(_):
                        return .couldNotParseResponseData(status: status)
                    case .unknown(_):
                        return .unknown(status: status)
                    case .noStatus:
                        return .noStatus
                    }
                } else {
                    return .unknown(status: status)
                }
            }
        } else {
            return .noStatus
        }
    }
}

/// Async implementations
extension BleTransport {
    public func bluetoothStateCallback() async -> CBManagerState {
        return await withCheckedContinuation { continuation in
            bluetoothStateCallback { state in
                continuation.resume(returning: state)
            }
        }
    }
    @discardableResult
    public func create(scanDuration: TimeInterval, disconnectedCallback: EmptyResponse?) async throws -> PeripheralIdentifier {
        let lock = NSLock()
        return try await withCheckedThrowingContinuation { continuation in

            // https://forums.swift.org/t/how-to-prevent-swift-task-continuation-misuse/57581
            var nillableContinuation: CheckedContinuation<PeripheralIdentifier, Error>? = continuation

            create(scanDuration: scanDuration, disconnectedCallback: disconnectedCallback) { response in
                lock.lock()
                defer { lock.unlock() }
                nillableContinuation?.resume(returning: response)
                nillableContinuation = nil
            } failure: { error in
                lock.lock()
                defer { lock.unlock() }

                nillableContinuation?.resume(throwing: error)
                nillableContinuation = nil
            }

        }
    }
    @discardableResult
    public func connect(toPeripheralID: PeripheralIdentifier, disconnectedCallback: EmptyResponse?) async throws -> PeripheralIdentifier {
        let lock = NSLock()
        return try await withCheckedThrowingContinuation { continuation in

            // https://forums.swift.org/t/how-to-prevent-swift-task-continuation-misuse/57581
            var nillableContinuation: CheckedContinuation<PeripheralIdentifier, Error>? = continuation

            connect(toPeripheralID: toPeripheralID, disconnectedCallback: disconnectedCallback) { response in
                lock.lock()
                defer { lock.unlock() }
                nillableContinuation?.resume(returning: response)
                nillableContinuation = nil
            } failure: { error in
                lock.lock()
                defer { lock.unlock() }
                nillableContinuation?.resume(throwing: error)
                nillableContinuation = nil
            }

        }
    }
    public func exchange(apdu apduToSend: APDU) async throws -> String {
        return try await withCheckedThrowingContinuation { continuation in
            exchange(apdu: apduToSend) { result in
                switch result {
                case .success(let response):
                    continuation.resume(returning: response)
                case .failure(let error):
                    continuation.resume(throwing: error)
                }
            }
        }
    }
    public func send(apdu: APDU) async throws {
        return try await withCheckedThrowingContinuation { continuation in
            send(apdu: apdu) {
                continuation.resume()
            } failure: { error in
                continuation.resume(throwing: error)
            }

        }
    }
    public func disconnect() async throws {
        let lock = NSLock()
        return try await withCheckedThrowingContinuation { continuation in

            // https://forums.swift.org/t/how-to-prevent-swift-task-continuation-misuse/57581
            var nillableContinuation: CheckedContinuation<Void, Error>? = continuation

            disconnect() { error in
                if let error = error {
                    lock.lock()
                    defer { lock.unlock() }
                    nillableContinuation?.resume(throwing: error)
                    nillableContinuation = nil
                } else {
                    lock.lock()
                    defer { lock.unlock() }
                    nillableContinuation?.resume()
                    nillableContinuation = nil
                }
            }
        }
    }
    public func getAppAndVersion() async throws -> AppInfo {
        return try await withCheckedThrowingContinuation { continuation in
            self.getAppAndVersion { response in
                continuation.resume(returning: response)
            } failure: { error in
                continuation.resume(throwing: error)
            }
        }
    }
    public func openAppIfNeeded(_ name: String) async throws {
        return try await withCheckedThrowingContinuation { continuation in
            openAppIfNeeded(name) { result in
                switch result {
                case .success(_):
                    continuation.resume()
                case .failure(let error):
                    continuation.resume(throwing: error)
                }
            }
        }
    }
    fileprivate func openApp(_ name: String) async throws {
        return try await withCheckedThrowingContinuation { continuation in
            openApp(name) {
                continuation.resume()
            } failure: { error in
                continuation.resume(throwing: error)
            }
        }
    }
    fileprivate func closeApp() async throws {
        return try await withCheckedThrowingContinuation { continuation in
            closeApp() {
                continuation.resume()
            } failure: { error in
                continuation.resume(throwing: error)
            }
        }
    }
}

func print(_ object: Any) {
    #if DEBUG
    Swift.print("BleTransport", object)
    #endif
}
