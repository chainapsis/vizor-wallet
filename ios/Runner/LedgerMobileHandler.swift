import BleTransport
import CoreBluetooth
import Foundation

#if os(macOS)
  import FlutterMacOS
#else
  import Flutter
#endif

final class LedgerMobileHandler: NSObject, FlutterStreamHandler {
  static let methodChannelName = "com.zcash.wallet/ledger_mobile"
  static let eventChannelName = "com.zcash.wallet/ledger_mobile/discovery"

  private var transportStorage: BleTransportProtocol?
  private var bluetoothState: CBManagerState = .unknown
  private var eventSink: FlutterEventSink?
  private var discoveryRequested = false
  private var discoveryActive = false
  private var discoveryGeneration = 0
  private var discoveredDevices: [String: PeripheralIdentifier] = [:]
  private var discoveredModels: [String: String] = [:]
  private var connectedDevice: PeripheralIdentifier?

  private var exchangeTask: Task<Void, Never>?
  private var exchangeTaskGeneration: Int?
  private var exchangeResult: FlutterResult?
  private var exchangeGeneration = 0
  private var appPreparationGeneration = 0

  init(transport: BleTransportProtocol? = nil) {
    transportStorage = transport
    super.init()
  }

  func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "requestPermissions":
      requestPermissions(result)
    case "startDiscovery":
      startDiscovery(result)
    case "stopDiscovery":
      stopDiscovery()
      result(nil)
    case "connect":
      connect(call, result: result)
    case "disconnect":
      disconnect(result)
    case "currentApp":
      currentApp(result)
    case "openZcashApp":
      openZcashApp(result)
    case "exchangeUfvk":
      exchangeUfvk(call, result: result)
    case "exchangeApdus":
      exchangeApdus(call, result: result)
    case "cancelSigning":
      cancelExchangeOperation(
        code: "cancelled",
        message: "The Ledger operation was cancelled."
      )
      result(nil)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  func onListen(
    withArguments arguments: Any?,
    eventSink events: @escaping FlutterEventSink
  ) -> FlutterError? {
    eventSink = events
    if discoveryRequested && bluetoothState == .poweredOn {
      beginDiscovery()
    }
    return nil
  }

  func onCancel(withArguments arguments: Any?) -> FlutterError? {
    eventSink = nil
    stopDiscovery()
    return nil
  }

  func close() {
    stopDiscovery()
    cancelExchangeOperation(
      code: "cancelled",
      message: "The Ledger operation was cancelled."
    )
    if let transport = transportStorage, transport.isConnected {
      transport.disconnect(completion: nil)
    }
    connectedDevice = nil
  }

  private func ensureTransport() -> BleTransportProtocol {
    if let transportStorage {
      return transportStorage
    }

    let transport = BleTransport.shared
    transportStorage = transport
    transport.bluetoothStateCallback { [weak self] state in
      DispatchQueue.main.async {
        self?.handleBluetoothState(state)
      }
    }
    return transport
  }

  private func handleBluetoothState(_ state: CBManagerState) {
    bluetoothState = state
    guard discoveryRequested else { return }

    switch state {
    case .poweredOn:
      beginDiscovery()
    case .poweredOff:
      failDiscovery(
        code: "bluetooth_off",
        message: "Turn on Bluetooth to find Ledger devices."
      )
    case .unauthorized:
      failDiscovery(
        code: "permission_denied",
        message: "Bluetooth permission is required to find Ledger devices."
      )
    case .unsupported:
      failDiscovery(
        code: "unavailable",
        message: "This device does not support Bluetooth LE."
      )
    case .unknown, .resetting:
      break
    @unknown default:
      failDiscovery(
        code: "unavailable",
        message: "Bluetooth is unavailable."
      )
    }
  }

  private func requestPermissions(_ result: @escaping FlutterResult) {
    _ = ensureTransport()
    switch CBManager.authorization {
    case .allowedAlways, .notDetermined:
      // CoreBluetooth has no standalone permission request API. The system
      // prompt is presented when discovery first starts.
      result(true)
    case .denied, .restricted:
      result(false)
    @unknown default:
      result(false)
    }
  }

  private func startDiscovery(_ result: @escaping FlutterResult) {
    let transport = ensureTransport()
    switch CBManager.authorization {
    case .denied, .restricted:
      result(
        flutterError(
          code: "permission_denied",
          message: "Bluetooth permission is required to find Ledger devices."
        )
      )
      return
    case .allowedAlways, .notDetermined:
      break
    @unknown default:
      result(
        flutterError(
          code: "permission_denied",
          message: "Bluetooth permission is required to find Ledger devices."
        )
      )
      return
    }

    stopDiscovery(clearRequest: false)
    discoveredDevices.removeAll()
    discoveredModels.removeAll()
    discoveryRequested = true

    switch bluetoothState {
    case .poweredOn:
      beginDiscovery(using: transport)
      result(nil)
    case .poweredOff:
      discoveryRequested = false
      result(
        flutterError(
          code: "bluetooth_off",
          message: "Turn on Bluetooth to find Ledger devices."
        )
      )
    case .unauthorized:
      discoveryRequested = false
      result(
        flutterError(
          code: "permission_denied",
          message: "Bluetooth permission is required to find Ledger devices."
        )
      )
    case .unsupported:
      discoveryRequested = false
      result(
        flutterError(
          code: "unavailable",
          message: "This device does not support Bluetooth LE."
        )
      )
    case .unknown, .resetting:
      // The CoreBluetooth manager reports its final state asynchronously.
      // `handleBluetoothState` starts discovery once it becomes powered on.
      result(nil)
    @unknown default:
      discoveryRequested = false
      result(
        flutterError(code: "unavailable", message: "Bluetooth is unavailable.")
      )
    }
  }

  private func beginDiscovery(using existingTransport: BleTransportProtocol? = nil) {
    guard discoveryRequested, !discoveryActive, eventSink != nil else { return }
    let transport = existingTransport ?? ensureTransport()
    guard transport.isBluetoothAvailable else { return }

    discoveryActive = true
    discoveryGeneration += 1
    let generation = discoveryGeneration
    transport.scan(duration: 15) { [weak self] discoveries in
      guard let self, generation == discoveryGeneration, discoveryRequested else {
        return
      }
      discoveredDevices = Dictionary(
        uniqueKeysWithValues: discoveries.map {
          ($0.peripheral.uuid.uuidString, $0.peripheral)
        }
      )
      discoveredModels = Dictionary(
        uniqueKeysWithValues: discoveries.map {
          (
            $0.peripheral.uuid.uuidString,
            self.ledgerModelName(
              from: $0.peripheral.name,
              serviceUUID: $0.serviceUUID
            )
          )
        }
      )
      emitDevices()
    } stopped: { [weak self] error in
      guard let self, generation == discoveryGeneration else { return }
      discoveryActive = false
      discoveryRequested = false
      if let error, !isScanTimeout(error) {
        emit(errorEvent(for: error))
      } else {
        emit(["type": "ended"])
      }
    }
  }

  private func stopDiscovery(clearRequest: Bool = true) {
    discoveryGeneration += 1
    discoveryActive = false
    if clearRequest {
      discoveryRequested = false
    }
    transportStorage?.stopScanning()
  }

  private func failDiscovery(code: String, message: String) {
    discoveryGeneration += 1
    discoveryRequested = false
    discoveryActive = false
    transportStorage?.stopScanning()
    emit(["type": "error", "code": code, "message": message])
  }

  private func emitDevices() {
    let devices = discoveredDevices.values
      .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
      .map { device in
        let name = device.name == "No Name" ? "Ledger" : device.name
        return [
          "id": device.uuid.uuidString,
          "name": name,
          "model": discoveredModels[device.uuid.uuidString]
            ?? ledgerModelName(from: name),
        ]
      }
    emit(["type": "devices", "devices": devices])
  }

  private func connect(
    _ call: FlutterMethodCall,
    result: @escaping FlutterResult
  ) {
    guard
      let arguments = call.arguments as? [String: Any],
      let deviceID = arguments["deviceId"] as? String,
      let deviceUUID = UUID(uuidString: deviceID)
    else {
      result(
        flutterError(
          code: "disconnected",
          message: "The selected Ledger is no longer available."
        )
      )
      return
    }

    let device =
      discoveredDevices[deviceID]
      ?? PeripheralIdentifier(
        uuid: deviceUUID,
        name: arguments["deviceName"] as? String
      )
    discoveredDevices[deviceID] = device
    if let deviceModel = arguments["deviceModel"] as? String {
      discoveredModels[deviceID] = deviceModel
    }

    let transport = ensureTransport()
    stopDiscovery()
    transport.connect(
      toPeripheralID: device,
      disconnectedCallback: { [weak self] in
        DispatchQueue.main.async {
          self?.handleDisconnected()
        }
      },
      success: { [weak self] connected in
        self?.connectedDevice = connected
        result(nil)
      },
      failure: { [weak self] error in
        self?.completeFailure(result, error: error)
      }
    )
  }

  private func disconnect(_ result: @escaping FlutterResult) {
    cancelExchangeOperation(
      code: "disconnected",
      message: "The Ledger disconnected. Reconnect and try again."
    )
    // BleTransport cannot disconnect until an outstanding device response drains.
    // Fail promptly so the picker shows recovery guidance instead of fake scanning.
    guard exchangeTask == nil else {
      result(pendingExchangeError())
      return
    }
    connectedDevice = nil

    guard let transport = transportStorage, transport.isConnected else {
      result(nil)
      return
    }
    transport.disconnect { [weak self] error in
      if let error {
        self?.completeFailure(result, error: error)
      } else {
        result(nil)
      }
    }
  }

  private func handleDisconnected() {
    connectedDevice = nil
    cancelExchangeOperation(
      code: "disconnected",
      message: "The Ledger disconnected. Reconnect and try again.",
      cancelPreparation: false
    )
  }

  private func currentApp(_ result: @escaping FlutterResult) {
    guard requireConnected(result) != nil else { return }
    Task { @MainActor [weak self] in
      guard let self else { return }
      do {
        result(try await readCurrentApp().asFlutterMap())
      } catch {
        completeFailure(result, error: error)
      }
    }
  }

  private func openZcashApp(_ result: @escaping FlutterResult) {
    guard let device = requireConnected(result) else { return }
    let transport = ensureTransport()
    let generation = appPreparationGeneration
    Task { @MainActor [weak self] in
      guard let self else { return }
      do {
        let app = try await LedgerMobileAppSwitchCoordinator().openZcashApp(
          openApplication: {
            let response = try await self.exchangeRaw(
              LedgerMobileProtocol.openZcashAppCommand
            )
            try LedgerMobileProtocol.requireSuccess(response)
          },
          isConnected: { transport.isConnected },
          reconnect: {
            let connected = try await transport.connect(
              toPeripheralID: device,
              disconnectedCallback: { [weak self] in
                DispatchQueue.main.async {
                  self?.handleDisconnected()
                }
              }
            )
            self.connectedDevice = connected
          },
          readCurrentApp: { try await self.readCurrentApp() },
          isCancelled: { self.appPreparationGeneration != generation }
        )
        connectedDevice = device
        result(app.asFlutterMap())
      } catch {
        completeFailure(result, error: error)
      }
    }
  }

  private func readCurrentApp() async throws -> LedgerMobileAppInfo {
    let response = try await exchangeRaw([0xb0, 0x01, 0x00, 0x00])
    return try LedgerMobileProtocol.appInfo(from: response)
  }

  private func exchangeUfvk(
    _ call: FlutterMethodCall,
    result: @escaping FlutterResult
  ) {
    guard requireConnected(result) != nil else { return }
    guard let arguments = call.arguments as? [String: Any] else {
      result(invalidApduError())
      return
    }

    let first: LedgerMobileApduCommand
    let continuation: LedgerMobileApduCommand
    do {
      first = try LedgerMobileProtocol.command(from: arguments["first"])
      continuation = try LedgerMobileProtocol.command(from: arguments["continuation"])
    } catch {
      result(invalidApduError())
      return
    }

    startExchange(result: result) { [self] in
      var responses: [[UInt8]] = []
      let firstResponse = try await exchange(first)
      responses.append(firstResponse)
      guard firstResponse.hasSuccessStatus, firstResponse.count >= 4 else {
        return responses
      }

      let expectedPayloadLength =
        2 + (Int(firstResponse[0]) << 8) + Int(firstResponse[1])
      guard expectedPayloadLength <= LedgerMobileProtocol.maxUfvkResponse else {
        return responses
      }

      var payloadLength = firstResponse.count - LedgerMobileProtocol.statusSize
      while payloadLength < expectedPayloadLength {
        let response = try await exchange(continuation)
        responses.append(response)
        guard response.hasSuccessStatus,
          response.count > LedgerMobileProtocol.statusSize
        else {
          return responses
        }
        payloadLength += response.count - LedgerMobileProtocol.statusSize
      }
      return responses
    }
  }

  private func exchangeApdus(
    _ call: FlutterMethodCall,
    result: @escaping FlutterResult
  ) {
    guard requireConnected(result) != nil else { return }
    guard
      let arguments = call.arguments as? [String: Any],
      let values = arguments["commands"] as? [Any],
      !values.isEmpty
    else {
      result(
        flutterError(
          code: "unavailable",
          message: "Ledger signing APDU list is empty or invalid."
        )
      )
      return
    }

    let commands: [LedgerMobileApduCommand]
    do {
      commands = try values.map(LedgerMobileProtocol.command(from:))
    } catch {
      result(invalidApduError())
      return
    }
    startExchange(result: result) { [self] in
      var responses: [[UInt8]] = []
      for command in commands {
        let response = try await exchange(command)
        responses.append(response)
        if !response.hasSuccessStatus { break }
      }
      return responses
    }
  }

  private func startExchange(
    result: @escaping FlutterResult,
    operation: @escaping () async throws -> [[UInt8]]
  ) {
    guard exchangeTask == nil else {
      result(pendingExchangeError())
      return
    }

    exchangeGeneration += 1
    let generation = exchangeGeneration
    exchangeResult = result
    exchangeTaskGeneration = generation
    exchangeTask = Task { @MainActor [weak self] in
      guard let self else { return }
      defer {
        if exchangeTaskGeneration == generation {
          exchangeTask = nil
          exchangeTaskGeneration = nil
        }
      }

      do {
        try Task.checkCancellation()
        let responses = try await operation()
        try Task.checkCancellation()
        finishExchange(generation: generation, value: responses.asFlutterResponses())
      } catch is CancellationError {
        finishExchange(
          generation: generation,
          error: flutterError(
            code: "cancelled",
            message: "The Ledger operation was cancelled."
          )
        )
      } catch {
        finishExchange(generation: generation, error: flutterError(for: error))
      }
    }
  }

  private func pendingExchangeError() -> FlutterError {
    flutterError(
      code: "unavailable",
      message: "Finish or reject the pending request on your Ledger, then try again."
    )
  }

  private func cancelExchangeOperation(
    code: String,
    message: String,
    cancelPreparation: Bool = true
  ) {
    // App switching may disconnect BLE without cancelling the user's request.
    // Explicit Cancel, disconnect and close must invalidate preparation even
    // before the first signing APDU exists.
    if cancelPreparation { appPreparationGeneration += 1 }
    guard let pending = exchangeResult else { return }
    exchangeGeneration += 1
    exchangeResult = nil
    // BleTransport 1.0.1 cannot interrupt an exchange already waiting for a
    // device response. Keep the task occupied until that callback drains, but
    // invalidate its generation now so no late response reaches Dart.
    exchangeTask?.cancel()
    pending(flutterError(code: code, message: message))
  }

  private func finishExchange(generation: Int, value: Any) {
    guard generation == exchangeGeneration, let result = exchangeResult else {
      return
    }
    exchangeResult = nil
    result(value)
  }

  private func finishExchange(generation: Int, error: FlutterError) {
    guard generation == exchangeGeneration, let result = exchangeResult else {
      return
    }
    exchangeResult = nil
    result(error)
  }

  private func exchange(_ command: LedgerMobileApduCommand) async throws -> [UInt8] {
    try Task.checkCancellation()
    let response = try await exchangeRaw(command.encoded)
    try Task.checkCancellation()
    return response
  }

  private func exchangeRaw(_ command: [UInt8]) async throws -> [UInt8] {
    let response = try await ensureTransport().exchange(apdu: APDU(data: command))
    return try LedgerMobileProtocol.bytes(fromHex: response)
  }

  private func requireConnected(
    _ result: @escaping FlutterResult
  ) -> PeripheralIdentifier? {
    guard let connectedDevice, ensureTransport().isConnected else {
      result(
        flutterError(
          code: "disconnected",
          message: "Select and connect a Ledger first."
        )
      )
      return nil
    }
    return connectedDevice
  }

  private func completeFailure(
    _ result: @escaping FlutterResult,
    error: Error
  ) {
    result(flutterError(for: error))
  }

  private func flutterError(for error: Error) -> FlutterError {
    if error is CancellationError {
      return flutterError(code: "cancelled", message: "Ledger preparation was cancelled.")
    }
    if let protocolError = error as? LedgerMobileProtocolError {
      switch protocolError {
      case .status(0x5515):
        return flutterError(
          code: "locked",
          message: "Unlock your Ledger and reopen the Zcash app."
        )
      case .status(0x6985), .status(0x5501):
        return flutterError(
          code: "rejected",
          message: "The Ledger request was rejected on the device."
        )
      case .appSwitchTimedOut:
        return flutterError(
          code: "unavailable",
          message: "Vizor could not resume after opening the Zcash app. Try again."
        )
      case .invalidArguments, .invalidHex, .invalidAppInfo, .status:
        return flutterError(
          code: "unavailable",
          message: "Ledger returned an invalid response."
        )
      }
    }

    if let statusError = error as? BleStatusError {
      switch statusError {
      case .userRejected:
        return flutterError(
          code: "rejected",
          message: "The Ledger request was rejected on the device."
        )
      case .appNotAvailableInDevice:
        return flutterError(
          code: "unavailable",
          message: "The Zcash app is not installed on this Ledger."
        )
      case .formatNotSupported, .couldNotParseResponseData, .unknown, .noStatus:
        return flutterError(
          code: "unavailable",
          message: error.localizedDescription
        )
      }
    }

    if let transportError = error as? BleTransportError {
      switch transportError {
      case .bluetoothNotAvailable:
        if CBManager.authorization == .denied
          || CBManager.authorization == .restricted
        {
          return flutterError(
            code: "permission_denied",
            message: "Bluetooth permission is required to connect to Ledger."
          )
        }
        return flutterError(
          code: "bluetooth_off",
          message: "Turn on Bluetooth to connect to Ledger."
        )
      case .pairingError:
        return flutterError(
          code: "pairing_rejected",
          message: "Ledger Bluetooth pairing was rejected or failed."
        )
      case .userRefusedOnDevice:
        return flutterError(
          code: "rejected",
          message: "The Ledger request was rejected on the device."
        )
      case .connectError, .currentConnectedError, .writeError, .readError,
        .listenError:
        return flutterError(
          code: "disconnected",
          message: "The Ledger disconnected. Reconnect and try again."
        )
      case .pendingActionOnDevice:
        return flutterError(
          code: "unavailable",
          message: "Another Ledger operation is still active."
        )
      case .scanningTimedOut, .scanError, .lowerLevelError:
        return flutterError(code: "unavailable", message: error.localizedDescription)
      }
    }

    return flutterError(code: "unavailable", message: error.localizedDescription)
  }

  private func errorEvent(for error: Error) -> [String: Any] {
    let mapped = flutterError(for: error)
    return [
      "type": "error",
      "code": mapped.code,
      "message": mapped.message ?? "Ledger discovery failed.",
    ]
  }

  private func invalidApduError() -> FlutterError {
    flutterError(code: "unavailable", message: "Ledger APDU arguments are invalid.")
  }

  private func flutterError(code: String, message: String) -> FlutterError {
    FlutterError(code: code, message: message, details: nil)
  }

  private func emit(_ value: [String: Any]) {
    eventSink?(value)
  }

  private func isScanTimeout(_ error: Error) -> Bool {
    guard let transportError = error as? BleTransportError else { return false }
    if case .scanningTimedOut = transportError { return true }
    return false
  }

  private func ledgerModelName(
    from name: String,
    serviceUUID: CBUUID? = nil
  ) -> String {
    // BleTransport 1.0.1 identifies Nano X separately and groups Flex/Stax
    // under the FTS service. Prefer the advertised name inside that group.
    let service = serviceUUID?.uuidString.lowercased()
    if service == "13d63400-2c97-0004-0000-4c6564676572" {
      return "Ledger Nano X"
    }
    let normalized = name.lowercased()
    if service == "13d63400-2c97-6004-0000-4c6564676572" {
      if normalized.contains("flex") { return "Ledger Flex" }
      if normalized.contains("stax") { return "Ledger Stax" }
      return "Ledger Flex / Stax"
    }
    if normalized.contains("stax") { return "Ledger Stax" }
    if normalized.contains("flex") { return "Ledger Flex" }
    if normalized.contains("nano x") { return "Ledger Nano X" }
    return name
  }

  deinit {
    close()
  }
}

struct LedgerMobileApduCommand: Equatable {
  let cla: UInt8
  let ins: UInt8
  let p1: UInt8
  let p2: UInt8
  let data: [UInt8]

  var encoded: [UInt8] {
    var value = [cla, ins, p1, p2]
    value.append(UInt8(data.count))
    value.append(contentsOf: data)
    return value
  }
}

struct LedgerMobileAppInfo: Equatable {
  let name: String
  let version: String

  func asFlutterMap() -> [String: String] {
    ["name": name, "version": version]
  }
}

struct LedgerMobileAppSwitchCoordinator {
  let recoveryTimeout: TimeInterval
  let now: () -> TimeInterval
  let waitBetweenAttempts: (TimeInterval) async throws -> Void

  init(
    recoveryTimeout: TimeInterval = 10,
    now: @escaping () -> TimeInterval = { ProcessInfo.processInfo.systemUptime },
    waitBetweenAttempts: @escaping (TimeInterval) async throws -> Void = {
      try await Task.sleep(nanoseconds: UInt64($0 * 1_000_000_000))
    }
  ) {
    self.recoveryTimeout = recoveryTimeout
    self.now = now
    self.waitBetweenAttempts = waitBetweenAttempts
  }

  func openZcashApp(
    openApplication: () async throws -> Void,
    isConnected: () -> Bool,
    reconnect: () async throws -> Void,
    readCurrentApp: () async throws -> LedgerMobileAppInfo,
    isCancelled: () -> Bool = { false }
  ) async throws -> LedgerMobileAppInfo {
    func checkCancellation() throws {
      try Task.checkCancellation()
      if isCancelled() { throw CancellationError() }
    }

    try checkCancellation()
    var lastAppName: String?
    var lastError: Error?
    do {
      // Never repeat this command: its response can be lost while the device
      // is already opening Zcash. Recover by observing that same device.
      try await openApplication()
    } catch {
      try checkCancellation()
      guard Self.isTransientTransitionError(error) else { throw error }
      lastError = error
    }

    // User approval of the open request does not consume the recovery budget.
    // The SDK's in-flight calls must drain; check elapsed time between calls
    // rather than racing an uncancellable exchange with another BLE request.
    let deadline = now() + recoveryTimeout
    while now() < deadline {
      try checkCancellation()
      if !isConnected() {
        do {
          try await reconnect()
        } catch {
          try checkCancellation()
          guard Self.isTransientTransitionError(error) else { throw error }
          lastError = error
        }
      }

      try checkCancellation()
      guard now() < deadline else { break }
      if isConnected() {
        do {
          let app = try await readCurrentApp()
          try checkCancellation()
          lastAppName = app.name
          lastError = nil
          if app.name == "Zcash" { return app }
        } catch {
          try checkCancellation()
          guard Self.isTransientTransitionError(error) else { throw error }
          lastError = error
        }
      }

      let remaining = deadline - now()
      guard remaining > 0 else { break }
      try await waitBetweenAttempts(min(0.25, remaining))
    }

    try checkCancellation()
    if lastAppName == nil, let lastError { throw lastError }
    throw LedgerMobileProtocolError.appSwitchTimedOut(lastAppName)
  }

  static func isTransientTransitionError(_ error: Error) -> Bool {
    if let error = error as? LedgerMobileProtocolError {
      // Only explicit device-busy statuses are safe to wait through. Rejection,
      // lock, missing-app and malformed responses must still fail immediately.
      return error == .status(0x6601) || error == .status(0x6901)
    }
    guard let error = error as? BleTransportError else { return false }
    switch error {
    case .connectError, .currentConnectedError, .writeError, .readError,
      .listenError, .pendingActionOnDevice, .scanningTimedOut, .scanError:
      return true
    case .bluetoothNotAvailable, .pairingError, .userRefusedOnDevice,
      .lowerLevelError:
      return false
    }
  }
}

enum LedgerMobileProtocolError: Error, Equatable {
  case invalidArguments
  case invalidHex
  case invalidAppInfo
  case appSwitchTimedOut(String?)
  case status(UInt16)
}

enum LedgerMobileProtocol {
  static let statusSize = 2
  static let maxUfvkResponse = 8 * 1024
  static let openZcashAppCommand = LedgerMobileApduCommand(
    cla: 0xe0,
    ins: 0xd8,
    p1: 0,
    p2: 0,
    data: Array("Zcash".utf8)
  ).encoded

  static func command(from value: Any?) throws -> LedgerMobileApduCommand {
    guard let map = value as? [String: Any],
      let cla = byte(map["cla"]),
      let ins = byte(map["ins"]),
      let p1 = byte(map["p1"]),
      let p2 = byte(map["p2"]),
      let data = dataBytes(map["data"]),
      data.count <= Int(UInt8.max)
    else {
      throw LedgerMobileProtocolError.invalidArguments
    }
    return LedgerMobileApduCommand(cla: cla, ins: ins, p1: p1, p2: p2, data: data)
  }

  static func bytes(fromHex hex: String) throws -> [UInt8] {
    guard hex.count.isMultiple(of: 2) else {
      throw LedgerMobileProtocolError.invalidHex
    }
    var bytes: [UInt8] = []
    bytes.reserveCapacity(hex.count / 2)
    var index = hex.startIndex
    while index < hex.endIndex {
      let next = hex.index(index, offsetBy: 2)
      guard let byte = UInt8(hex[index..<next], radix: 16) else {
        throw LedgerMobileProtocolError.invalidHex
      }
      bytes.append(byte)
      index = next
    }
    return bytes
  }

  static func appInfo(from response: [UInt8]) throws -> LedgerMobileAppInfo {
    guard response.count >= 2 else {
      throw LedgerMobileProtocolError.invalidAppInfo
    }
    let status =
      (UInt16(response[response.count - 2]) << 8)
      | UInt16(response[response.count - 1])
    guard status == 0x9000 else {
      throw LedgerMobileProtocolError.status(status)
    }

    let payload = response.dropLast(statusSize)
    var index = payload.startIndex
    guard index < payload.endIndex, payload[index] == 1 else {
      throw LedgerMobileProtocolError.invalidAppInfo
    }
    index = payload.index(after: index)

    let name = try readString(from: payload, index: &index)
    let version = try readString(from: payload, index: &index)
    return LedgerMobileAppInfo(name: name, version: version)
  }

  static func requireSuccess(_ response: [UInt8]) throws {
    guard response.count >= statusSize else {
      throw LedgerMobileProtocolError.invalidHex
    }
    let status =
      (UInt16(response[response.count - 2]) << 8)
      | UInt16(response[response.count - 1])
    guard status == 0x9000 else {
      throw LedgerMobileProtocolError.status(status)
    }
  }

  private static func readString(
    from payload: ArraySlice<UInt8>,
    index: inout ArraySlice<UInt8>.Index
  ) throws -> String {
    guard index < payload.endIndex else {
      throw LedgerMobileProtocolError.invalidAppInfo
    }
    let length = Int(payload[index])
    index = payload.index(after: index)
    guard let end = payload.index(index, offsetBy: length, limitedBy: payload.endIndex),
      end <= payload.endIndex,
      let value = String(bytes: payload[index..<end], encoding: .ascii)
    else {
      throw LedgerMobileProtocolError.invalidAppInfo
    }
    index = end
    return value
  }

  private static func byte(_ value: Any?) -> UInt8? {
    guard let number = value as? NSNumber else { return nil }
    let integer = number.intValue
    guard (0...Int(UInt8.max)).contains(integer) else { return nil }
    return UInt8(integer)
  }

  private static func dataBytes(_ value: Any?) -> [UInt8]? {
    if let typedData = value as? FlutterStandardTypedData {
      return [UInt8](typedData.data)
    }
    if let data = value as? Data {
      return [UInt8](data)
    }
    if let values = value as? [Any] {
      var bytes: [UInt8] = []
      bytes.reserveCapacity(values.count)
      for value in values {
        guard let byte = byte(value) else { return nil }
        bytes.append(byte)
      }
      return bytes
    }
    return nil
  }
}

extension Array where Element == UInt8 {
  fileprivate var hasSuccessStatus: Bool {
    count >= LedgerMobileProtocol.statusSize
      && self[count - 2] == 0x90
      && self[count - 1] == 0x00
  }
}

extension Array where Element == [UInt8] {
  fileprivate func asFlutterResponses() -> [[Int]] {
    map { response in response.map(Int.init) }
  }
}
