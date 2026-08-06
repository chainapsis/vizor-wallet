import Foundation
import Network
import UIKit

/// Where the device's power comes from, as far as a background pass can tell.
enum BackgroundPowerSupply {
  case external
  case battery
  /// The device has not reported a battery state yet. Read as "not on a
  /// charger": a pass that cannot tell has not established anything.
  case unknown
}

/// Whether the current network path charges for its bytes, as far as a
/// background pass can tell.
enum BackgroundNetworkMetering {
  case unmetered
  case metered
  /// No path has been reported yet, or there is no usable path at all. Read as
  /// "not known to be free": a pass that cannot tell has not established
  /// anything.
  case unknown
}

/// The route the user saved for wallet traffic, readable from a process that
/// never ran Dart, plus the conditions under which a background pass may carry
/// that route.
///
/// The route Rust honours is process-local and starts at direct, so a
/// background launch into a cold process would reach lightwalletd over
/// clearnet whatever the user chose. Every background pass therefore declares
/// the saved route before its first native call.
///
/// A declared Tor route is not free to run, so declaring it is not enough.
/// Measured on this stack: a cold bootstrap moves 8.45 MB down and 744 KB up
/// over 23.7 s and leaves a 46.3 MB cache; a warm one costs 0.64 s and no
/// bytes; and a bootstrapped client keeps padding its guard connection at
/// roughly 500 B/s while awake and 27 B/s while dormant. On external power over
/// an unmetered link those costs are acceptable. On battery, or over a metered
/// or constrained link, they are not — that pass does no network work and
/// defers to the foreground, which is what every pass used to do.
enum BackgroundNetworkRoute {
  /// `shared_preferences` stores Dart values in `UserDefaults.standard` behind
  /// a `flutter.` prefix; the suffix is `kTorEnabledPreferenceKey` in
  /// `lib/src/providers/network_privacy_provider.dart`.
  private static let torEnabledKey = "flutter.zcash_tor_enabled"

  /// Same directory Dart passes to the foreground toggle: the app's
  /// Application Support directory plus `tor`. Arti keeps its guard state and
  /// directory cache there, so a background bootstrap that used a different
  /// path would pick fresh guards and re-download the 46.3 MB cache instead of
  /// warming the one the foreground already paid for.
  private static let torDirectoryName = "tor"

  /// `UIDevice` answers `.unknown` for a moment after battery monitoring is
  /// switched on. Bounded so a gate never stalls on a device that simply has
  /// nothing to report.
  private static let batteryStateReadAttempts = 10
  private static let batteryStateReadRetryInterval: TimeInterval = 0.05

  /// `NWPathMonitor` reports the current path almost immediately; this only
  /// bounds the wait for a first report that never arrives.
  private static let meteringSampleTimeout: TimeInterval = 1

  private static let torStateLock = NSLock()
  private static var torIsUpForBackgroundWork = false

  /// Whether the saved route is Tor. A missing value — never chosen, or
  /// cleared by a wallet reset — reads as direct, matching the Dart default.
  static var persistedRouteIsTor: Bool {
    UserDefaults.standard.bool(forKey: torEnabledKey)
  }

  /// Whether a background pass on a Tor route can afford to run right now.
  ///
  /// Both inputs fail closed while unknown. A wake that cannot yet tell where
  /// its power or its bytes come from has not established that it may spend
  /// either, and the cost of guessing wrong is a bootstrap on cellular or on
  /// battery.
  static func torBackgroundWorkIsAffordable(
    power: BackgroundPowerSupply,
    metering: BackgroundNetworkMetering
  ) -> Bool {
    power == .external && metering == .unmetered
  }

  /// The Tor half of the gate, written once so both entry points and the tests
  /// agree on what the policy is.
  ///
  /// `bringTorUp` is evaluated only after affordability holds: a pass that
  /// cannot afford Tor must not spend 8.45 MB and 23.7 s discovering that it
  /// could not. A bring-up that does not report ready is a deferral like any
  /// other, never a reason to reach lightwalletd some other way.
  static func torBackgroundPassMayProceed(
    power: BackgroundPowerSupply,
    metering: BackgroundNetworkMetering,
    bringTorUp: () -> Bool
  ) -> Bool {
    guard torBackgroundWorkIsAffordable(power: power, metering: metering) else {
      return false
    }
    return bringTorUp()
  }

  /// `batteryState` is `.unknown` until battery monitoring is enabled, so
  /// `AppDelegate` turns it on at launch — including the launch a background
  /// task causes. Enabling here as well keeps the gate honest if it is ever
  /// reached first, and the retry covers the moment before the first report
  /// lands rather than letting a startable pass read `.unknown` and defer.
  static func currentPowerSupply() -> BackgroundPowerSupply {
    let device = UIDevice.current
    if !device.isBatteryMonitoringEnabled {
      device.isBatteryMonitoringEnabled = true
    }
    for attempt in 0..<batteryStateReadAttempts {
      switch device.batteryState {
      case .charging, .full:
        return .external
      case .unplugged:
        return .battery
      default:
        break
      }
      if attempt < batteryStateReadAttempts - 1 {
        Thread.sleep(forTimeInterval: batteryStateReadRetryInterval)
      }
    }
    return .unknown
  }

  /// `isExpensive` covers cellular and personal hotspots, `isConstrained`
  /// covers Low Data Mode. Either one means the user is paying for these bytes
  /// in money or in an allowance they asked us to respect, and a Tor bootstrap
  /// is megabytes.
  ///
  /// A path that is not satisfied reports `unknown` rather than `unmetered`:
  /// there is nothing to measure, and no pass should proceed on it.
  static func currentNetworkMetering() -> BackgroundNetworkMetering {
    let monitor = NWPathMonitor()
    let sample = BackgroundNetworkPathSample()
    let reported = DispatchSemaphore(value: 0)
    monitor.pathUpdateHandler = { path in
      sample.store(
        satisfied: path.status == .satisfied,
        metered: path.isExpensive || path.isConstrained
      )
      reported.signal()
    }
    monitor.start(
      queue: DispatchQueue(
        label: "com.keplr.vizor.background-network-metering"
      )
    )
    defer { monitor.cancel() }
    guard reported.wait(timeout: .now() + meteringSampleTimeout) == .success,
      let observation = sample.observation
    else {
      return .unknown
    }
    guard observation.satisfied else { return .unknown }
    return observation.metered ? .metered : .unmetered
  }

  /// Declares a persisted Tor route to Rust and reports whether this pass has
  /// established that it may carry that route.
  ///
  /// Call it before the first native call of a background pass. Declaring
  /// first means a path that still tries to reach lightwalletd fails closed
  /// instead of leaking; a declaration that itself fails changes nothing,
  /// because a refused pass reaches nothing either way.
  ///
  /// This never bootstraps Tor, so it is also the right question for a pass
  /// that has not decided whether it will do network work at all — scheduling
  /// a task, or inspecting local state first.
  static func allowsBackgroundNetworkPass() -> Bool {
    guard persistedRouteIsTor else { return true }
    _ = zcash_network_privacy_mark_tor_desired()
    return torBackgroundWorkIsAffordable(
      power: currentPowerSupply(),
      metering: currentNetworkMetering()
    )
  }

  /// Brings Tor up for this process and reports whether it came up ready.
  ///
  /// Blocks: a cold bootstrap is tens of seconds, so callers run it on their
  /// own queue rather than on a system callback. Success is remembered for the
  /// process because the loop-style passes ask before every round of queries;
  /// failure is not, so a later pass in the same process may try again after
  /// conditions change. A route flip only happens in the foreground, which
  /// re-decides the process route itself.
  ///
  /// A client that does not come up ready leaves the process fail-closed with
  /// no transport. The caller defers; it must never fall back to clearnet.
  @discardableResult
  static func bringUpTorForBackgroundWork() -> Bool {
    torStateLock.lock()
    let alreadyUp = torIsUpForBackgroundWork
    torStateLock.unlock()
    if alreadyUp { return true }

    guard let directory = torDataDirectoryPath() else { return false }
    let code = directory.withCString {
      zcash_network_privacy_enable_tor_for_background_work($0)
    }
    // Every non-ready code — not ready, or a panic caught at the boundary —
    // leaves the process Tor-desired and fail-closed, so a false here is a
    // deferral, not a reason to look for another way out.
    guard code == ZCASH_NETWORK_PRIVACY_TOR_READY else { return false }
    torStateLock.lock()
    torIsUpForBackgroundWork = true
    torStateLock.unlock()
    return true
  }

  /// Declares the saved route and reports whether this pass may reach the
  /// network now — including bringing Tor up when the route is Tor.
  ///
  /// Call it immediately before network work. A pass that only wants to know
  /// whether it should exist at all wants `allowsBackgroundNetworkPass`.
  static func allowsBackgroundNetworkWork() -> Bool {
    guard persistedRouteIsTor else { return true }
    _ = zcash_network_privacy_mark_tor_desired()
    return torBackgroundPassMayProceed(
      power: currentPowerSupply(),
      metering: currentNetworkMetering(),
      bringTorUp: bringUpTorForBackgroundWork
    )
  }

  /// Whether a pass that is already running may keep reaching the network.
  ///
  /// Side-effect free and cheap on purpose: it is polled on a heartbeat, so it
  /// answers only the question that can change between gate evaluations —
  /// whether the saved route turned to Tor inside a process that never brought
  /// Tor up, which is a route this pass cannot carry. Power and metering are
  /// re-sampled by the gate itself before each round of queries.
  static var backgroundNetworkWorkRemainsAllowed: Bool {
    guard persistedRouteIsTor else { return true }
    torStateLock.lock()
    defer { torStateLock.unlock() }
    return torIsUpForBackgroundWork
  }

  private static func torDataDirectoryPath() -> String? {
    guard let supportDirectory = try? resolveWalletSupportDirectory() else {
      return nil
    }
    return supportDirectory
      .appendingPathComponent(torDirectoryName)
      .path
  }
}

private final class BackgroundNetworkPathSample: @unchecked Sendable {
  struct Observation {
    let satisfied: Bool
    let metered: Bool
  }

  private let lock = NSLock()
  private var storedObservation: Observation?

  func store(satisfied: Bool, metered: Bool) {
    lock.lock()
    storedObservation = Observation(satisfied: satisfied, metered: metered)
    lock.unlock()
  }

  var observation: Observation? {
    lock.lock()
    defer { lock.unlock() }
    return storedObservation
  }
}

final class BackgroundMigrationCancellation: @unchecked Sendable {
  private let condition = NSCondition()
  private var cancelled = false
  private let nativeHandle = zcash_lightwalletd_cancellation_create()

  func cancel() {
    condition.lock()
    cancelled = true
    condition.broadcast()
    let handle = nativeHandle
    condition.unlock()
    zcash_lightwalletd_cancellation_cancel(handle)
  }

  var isCancelled: Bool {
    condition.lock()
    defer { condition.unlock() }
    return cancelled
  }

  func waitUntilCancelled(timeout: TimeInterval) -> Bool {
    condition.lock()
    defer { condition.unlock() }
    if cancelled { return true }
    _ = condition.wait(
      until: Date().addingTimeInterval(max(0, timeout))
    )
    return cancelled
  }

  fileprivate var lightwalletdCancellationHandle: UnsafeMutableRawPointer? {
    nativeHandle
  }

  deinit {
    zcash_lightwalletd_cancellation_destroy(nativeHandle)
  }
}

enum NativeLightwalletdError: Error, Equatable {
  case invalidEndpoint
  case cancelled
  case timedOut
  case transport(String)
  case invalidHTTPStatus(Int)
  case grpcStatus(String)
  case grpcStatusUnavailable
  case malformedResponse
  case missingHeight
  case missingSendResponse
}

struct NativeLightwalletdSendResponse: Equatable {
  let errorCode: Int32
  let errorMessage: String
}

enum NativeLightwalletdTransactionObservation: Equatable {
  case notFound
  case mempool
  case mined(height: UInt64)
  case forked
}

private final class NativeLightwalletdRequestResult: @unchecked Sendable {
  private let lock = NSLock()
  private var storedResult: Result<UInt64, NativeLightwalletdError>?

  func set(_ result: Result<UInt64, NativeLightwalletdError>) {
    lock.lock()
    storedResult = result
    lock.unlock()
  }

  var result: Result<UInt64, NativeLightwalletdError>? {
    lock.lock()
    defer { lock.unlock() }
    return storedResult
  }
}

private final class NativeLightwalletdSendRequestResult: @unchecked Sendable {
  private let lock = NSLock()
  private var storedResult: Result<NativeLightwalletdSendResponse, NativeLightwalletdError>?

  func set(
    _ result: Result<NativeLightwalletdSendResponse, NativeLightwalletdError>
  ) {
    lock.lock()
    storedResult = result
    lock.unlock()
  }

  var result: Result<NativeLightwalletdSendResponse, NativeLightwalletdError>? {
    lock.lock()
    defer { lock.unlock() }
    return storedResult
  }
}

private final class NativeLightwalletdTransactionRequestResult:
  @unchecked Sendable
{
  private let lock = NSLock()
  private var storedResult:
    Result<NativeLightwalletdTransactionObservation, NativeLightwalletdError>?

  func set(
    _ result:
      Result<NativeLightwalletdTransactionObservation, NativeLightwalletdError>
  ) {
    lock.lock()
    storedResult = result
    lock.unlock()
  }

  var result:
    Result<NativeLightwalletdTransactionObservation, NativeLightwalletdError>?
  {
    lock.lock()
    defer { lock.unlock() }
    return storedResult
  }
}

enum NativeLightwalletdClient {
  private static let latestBlockPath =
    "/cash.z.wallet.sdk.rpc.CompactTxStreamer/GetLatestBlock"
  private static let getTransactionPath =
    "/cash.z.wallet.sdk.rpc.CompactTxStreamer/GetTransaction"
  private static let sendTransactionPath =
    "/cash.z.wallet.sdk.rpc.CompactTxStreamer/SendTransaction"

  static func latestBlockHeight(
    endpoint: String,
    cancellation: BackgroundMigrationCancellation
  ) -> Result<UInt64, NativeLightwalletdError> {
    guard rpcURL(endpoint: endpoint, methodPath: latestBlockPath) != nil else {
      return .failure(.invalidEndpoint)
    }
    guard !cancellation.isCancelled else {
      return .failure(.cancelled)
    }
    var height: UInt64 = 0
    let code = endpoint.withCString {
      zcash_lightwalletd_latest_block_height(
        $0,
        &height,
        cancellation.lightwalletdCancellationHandle
      )
    }
    guard code != ZCASH_LIGHTWALLETD_RESULT_CANCELLED,
      !cancellation.isCancelled
    else {
      return .failure(.cancelled)
    }
    guard code == 0 else {
      return .failure(.transport("Rust lightwalletd latest block failed (code \(code))"))
    }
    return .success(height)
  }

  static func parseLatestBlockResponse(_ data: Data) throws -> UInt64 {
    guard data.count >= 5, data[data.startIndex] == 0 else {
      throw NativeLightwalletdError.malformedResponse
    }
    let length = data[data.startIndex + 1...data.startIndex + 4]
      .reduce(0) { ($0 << 8) | Int($1) }
    let payloadStart = data.startIndex + 5
    let payloadEnd = payloadStart + length
    guard length > 0, payloadEnd <= data.endIndex else {
      throw NativeLightwalletdError.malformedResponse
    }
    let payload = data[payloadStart..<payloadEnd]
    var index = payload.startIndex
    while index < payload.endIndex {
      let key = try readVarint(payload, index: &index)
      let fieldNumber = key >> 3
      let wireType = key & 0x07
      if fieldNumber == 1, wireType == 0 {
        return try readVarint(payload, index: &index)
      }
      try skipField(payload, wireType: wireType, index: &index)
    }
    throw NativeLightwalletdError.missingHeight
  }

  static func transaction(
    endpoint: String,
    transactionId: Data,
    cancellation: BackgroundMigrationCancellation
  ) -> Result<
    NativeLightwalletdTransactionObservation,
    NativeLightwalletdError
  > {
    guard transactionId.count == 32,
      rpcURL(endpoint: endpoint, methodPath: getTransactionPath) != nil
    else {
      return .failure(.invalidEndpoint)
    }
    guard !cancellation.isCancelled else {
      return .failure(.cancelled)
    }
    var nativeObservation = CLightwalletdTransactionObservation(
      state: 0,
      mined_height: 0
    )
    let code = endpoint.withCString { endpointPointer in
      transactionId.withUnsafeBytes { transactionPointer in
        zcash_lightwalletd_observe_transaction(
          endpointPointer,
          transactionPointer.bindMemory(to: UInt8.self).baseAddress,
          UInt(transactionId.count),
          &nativeObservation,
          cancellation.lightwalletdCancellationHandle
        )
      }
    }
    guard code != ZCASH_LIGHTWALLETD_RESULT_CANCELLED,
      !cancellation.isCancelled
    else {
      return .failure(.cancelled)
    }
    guard code == 0 else {
      return .failure(.transport("Rust lightwalletd transaction lookup failed (code \(code))"))
    }
    switch nativeObservation.state {
    case 0:
      return .success(.notFound)
    case 1:
      return .success(.mempool)
    case 2:
      return .success(.mined(height: nativeObservation.mined_height))
    case 3:
      return .success(.forked)
    default:
      return .failure(.malformedResponse)
    }
  }

  static func parseTransactionResponse(
    _ data: Data
  ) throws -> NativeLightwalletdTransactionObservation {
    let payload = try grpcPayload(data)
    var index = payload.startIndex
    var height: UInt64 = 0
    while index < payload.endIndex {
      let key = try readVarint(payload, index: &index)
      let fieldNumber = key >> 3
      let wireType = key & 0x07
      if fieldNumber == 2, wireType == 0 {
        height = try readVarint(payload, index: &index)
      } else {
        try skipField(payload, wireType: wireType, index: &index)
      }
    }
    if height == 0 { return .mempool }
    if height == UInt64.max { return .forked }
    return .mined(height: height)
  }

  static func sendTransaction(
    endpoint: String,
    rawTransaction: Data,
    cancellation: BackgroundMigrationCancellation
  ) -> Result<NativeLightwalletdSendResponse, NativeLightwalletdError> {
    guard !rawTransaction.isEmpty,
      rpcURL(endpoint: endpoint, methodPath: sendTransactionPath) != nil
    else {
      return .failure(.invalidEndpoint)
    }
    guard !cancellation.isCancelled else {
      return .failure(.cancelled)
    }
    var responseErrorCode: Int32 = 0
    var responseErrorMessage = [CChar](repeating: 0, count: 4096)
    let code = endpoint.withCString { endpointPointer in
      rawTransaction.withUnsafeBytes { transactionPointer in
        responseErrorMessage.withUnsafeMutableBufferPointer { messagePointer in
          zcash_lightwalletd_send_transaction(
            endpointPointer,
            transactionPointer.bindMemory(to: UInt8.self).baseAddress,
            UInt(rawTransaction.count),
            &responseErrorCode,
            messagePointer.baseAddress,
            UInt(messagePointer.count),
            cancellation.lightwalletdCancellationHandle
          )
        }
      }
    }
    guard code != ZCASH_LIGHTWALLETD_RESULT_CANCELLED,
      !cancellation.isCancelled
    else {
      return .failure(.cancelled)
    }
    guard code == 0 else {
      return .failure(.transport("Rust lightwalletd send failed (code \(code))"))
    }
    return .success(
      NativeLightwalletdSendResponse(
        errorCode: responseErrorCode,
        errorMessage: String(cString: responseErrorMessage)
      )
    )
  }

  static func parseSendTransactionResponse(
    _ data: Data
  ) throws -> NativeLightwalletdSendResponse {
    let payload = try grpcPayload(data)
    var index = payload.startIndex
    var errorCode: Int32?
    var errorMessage = ""
    while index < payload.endIndex {
      let key = try readVarint(payload, index: &index)
      let fieldNumber = key >> 3
      let wireType = key & 0x07
      if fieldNumber == 1, wireType == 0 {
        errorCode = Int32(
          bitPattern: UInt32(
            truncatingIfNeeded: try readVarint(payload, index: &index)
          )
        )
      } else if fieldNumber == 2, wireType == 2 {
        let length = try readVarint(payload, index: &index)
        guard length <= UInt64(Int.max),
          payload.distance(from: index, to: payload.endIndex) >= Int(length)
        else {
          throw NativeLightwalletdError.malformedResponse
        }
        let end = payload.index(index, offsetBy: Int(length))
        guard
          let decoded = String(
            data: payload[index..<end],
            encoding: .utf8
          )
        else {
          throw NativeLightwalletdError.malformedResponse
        }
        errorMessage = decoded
        index = end
      } else {
        try skipField(payload, wireType: wireType, index: &index)
      }
    }
    return NativeLightwalletdSendResponse(
      // SendResponse.errorCode is a proto3 scalar. A successful zero value is
      // omitted from the wire, so an absent field is the canonical success
      // response rather than a malformed payload.
      errorCode: errorCode ?? 0,
      errorMessage: errorMessage
    )
  }

  private static func grpcFrame(payload: Data) -> Data {
    var frame = Data([0x00])
    let length = UInt32(payload.count).bigEndian
    withUnsafeBytes(of: length) { frame.append(contentsOf: $0) }
    frame.append(payload)
    return frame
  }

  private static func rawTransactionMessage(_ rawTransaction: Data) -> Data {
    var message = Data([0x0A])
    message.append(contentsOf: encodeVarint(UInt64(rawTransaction.count)))
    message.append(rawTransaction)
    return message
  }

  private static func transactionFilterMessage(
    _ transactionId: Data
  ) -> Data {
    // TxFilter.hash is protobuf field 3.
    var message = Data([0x1A])
    message.append(contentsOf: encodeVarint(UInt64(transactionId.count)))
    message.append(transactionId)
    return message
  }

  private static func encodeVarint(_ value: UInt64) -> [UInt8] {
    var value = value
    var encoded: [UInt8] = []
    repeat {
      var byte = UInt8(value & 0x7f)
      value >>= 7
      if value != 0 { byte |= 0x80 }
      encoded.append(byte)
    } while value != 0
    return encoded
  }

  private static func grpcPayload(_ data: Data) throws -> Data.SubSequence {
    guard data.count >= 5, data[data.startIndex] == 0 else {
      throw NativeLightwalletdError.malformedResponse
    }
    let length = data[data.startIndex + 1...data.startIndex + 4]
      .reduce(0) { ($0 << 8) | Int($1) }
    let payloadStart = data.startIndex + 5
    let payloadEnd = payloadStart + length
    guard payloadEnd <= data.endIndex else {
      throw NativeLightwalletdError.malformedResponse
    }
    return data[payloadStart..<payloadEnd]
  }

  private static func rpcURL(endpoint: String, methodPath: String) -> URL? {
    guard var components = URLComponents(string: endpoint),
      components.scheme == "https" || components.scheme == "http",
      components.host != nil
    else {
      return nil
    }
    let prefix =
      components.path.hasSuffix("/")
      ? String(components.path.dropLast())
      : components.path
    components.path = prefix + methodPath
    components.query = nil
    components.fragment = nil
    return components.url
  }

  private static func readVarint(
    _ data: Data.SubSequence,
    index: inout Data.Index
  ) throws -> UInt64 {
    var value: UInt64 = 0
    var shift: UInt64 = 0
    while index < data.endIndex, shift < 64 {
      let byte = data[index]
      index = data.index(after: index)
      value |= UInt64(byte & 0x7f) << shift
      if byte & 0x80 == 0 { return value }
      shift += 7
    }
    throw NativeLightwalletdError.malformedResponse
  }

  private static func skipField(
    _ data: Data.SubSequence,
    wireType: UInt64,
    index: inout Data.Index
  ) throws {
    switch wireType {
    case 0:
      _ = try readVarint(data, index: &index)
    case 1:
      guard data.distance(from: index, to: data.endIndex) >= 8 else {
        throw NativeLightwalletdError.malformedResponse
      }
      index = data.index(index, offsetBy: 8)
    case 2:
      let length = try readVarint(data, index: &index)
      guard length <= UInt64(Int.max),
        data.distance(from: index, to: data.endIndex) >= Int(length)
      else {
        throw NativeLightwalletdError.malformedResponse
      }
      index = data.index(index, offsetBy: Int(length))
    case 5:
      guard data.distance(from: index, to: data.endIndex) >= 4 else {
        throw NativeLightwalletdError.malformedResponse
      }
      index = data.index(index, offsetBy: 4)
    default:
      throw NativeLightwalletdError.malformedResponse
    }
  }
}
