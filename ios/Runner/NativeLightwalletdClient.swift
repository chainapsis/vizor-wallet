import Foundation

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
  let accepted: Bool?

  init(errorCode: Int32, errorMessage: String, accepted: Bool? = nil) {
    self.errorCode = errorCode
    self.errorMessage = errorMessage
    self.accepted = accepted
  }
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
    routingTransactionId: Data,
    transactionId: Data,
    managedSubmissionRouting: Bool,
    cancellation: BackgroundMigrationCancellation
  ) -> Result<
    NativeLightwalletdTransactionObservation,
    NativeLightwalletdError
  > {
    guard routingTransactionId.count == 32,
      transactionId.count == 32,
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
      routingTransactionId.withUnsafeBytes { routingTransactionPointer in
        transactionId.withUnsafeBytes { transactionPointer in
          zcash_lightwalletd_observe_transaction(
            endpointPointer,
            routingTransactionPointer.bindMemory(to: UInt8.self).baseAddress,
            UInt(routingTransactionId.count),
            transactionPointer.bindMemory(to: UInt8.self).baseAddress,
            UInt(transactionId.count),
            &nativeObservation,
            managedSubmissionRouting,
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

  static func transactionIdByteOrders(
    storedHex: String
  ) -> (stored: Data, protocolOrder: Data)? {
    guard storedHex.count == 64 else { return nil }
    var bytes = [UInt8]()
    bytes.reserveCapacity(32)
    var index = storedHex.startIndex
    while index < storedHex.endIndex {
      let next = storedHex.index(index, offsetBy: 2)
      guard let byte = UInt8(storedHex[index..<next], radix: 16) else {
        return nil
      }
      bytes.append(byte)
      index = next
    }
    guard bytes.count == 32 else { return nil }
    let stored = Data(bytes)
    return (stored, Data(stored.reversed()))
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
    transactionId: Data,
    rawTransaction: Data,
    managedSubmissionRouting: Bool,
    cancellation: BackgroundMigrationCancellation
  ) -> Result<NativeLightwalletdSendResponse, NativeLightwalletdError> {
    guard transactionId.count == 32,
      !rawTransaction.isEmpty,
      rpcURL(endpoint: endpoint, methodPath: sendTransactionPath) != nil
    else {
      return .failure(.invalidEndpoint)
    }
    guard !cancellation.isCancelled else {
      return .failure(.cancelled)
    }
    var responseErrorCode: Int32 = 0
    var responseErrorMessage = [CChar](repeating: 0, count: 4096)
    var responseAccepted = false
    let code = endpoint.withCString { endpointPointer in
      transactionId.withUnsafeBytes { transactionIdPointer in
        rawTransaction.withUnsafeBytes { transactionPointer in
          responseErrorMessage.withUnsafeMutableBufferPointer { messagePointer in
            zcash_lightwalletd_send_transaction(
              endpointPointer,
              transactionIdPointer.bindMemory(to: UInt8.self).baseAddress,
              UInt(transactionId.count),
              transactionPointer.bindMemory(to: UInt8.self).baseAddress,
              UInt(rawTransaction.count),
              &responseErrorCode,
              messagePointer.baseAddress,
              UInt(messagePointer.count),
              &responseAccepted,
              managedSubmissionRouting,
              cancellation.lightwalletdCancellationHandle
            )
          }
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
        errorMessage: String(cString: responseErrorMessage),
        accepted: responseAccepted
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
