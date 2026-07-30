import Foundation
import Network

private func isNativeLocalHost(_ host: String) -> Bool {
  let host = host.lowercased()
  if host == "localhost" || host == "::1" || host == "10.0.2.2" {
    return true
  }
  return IPv4Address(host)?.rawValue.first == 127
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

private final class NativeRequestResult<Value>: @unchecked Sendable {
  private let lock = NSLock()
  private var storedResult: Result<Value, NativeLightwalletdError>?

  func set(_ result: Result<Value, NativeLightwalletdError>) {
    lock.lock()
    storedResult = result
    lock.unlock()
  }

  var result: Result<Value, NativeLightwalletdError>? {
    lock.lock()
    defer { lock.unlock() }
    return storedResult
  }
}

struct NativeBoundedResponseBuffer {
  private(set) var data = Data()
  let maximumBytes: Int?

  mutating func append(_ chunk: Data) -> Bool {
    if let maximumBytes {
      guard data.count <= maximumBytes,
        chunk.count <= maximumBytes - data.count
      else {
        return false
      }
    }
    data.append(chunk)
    return true
  }
}

private final class NativeRequestSessionDelegate: NSObject,
  URLSessionDataDelegate
{
  private let result: NativeRequestResult<(HTTPURLResponse, Data)>
  private let semaphore: DispatchSemaphore
  private let maximumResponseBytes: Int?
  private let rejectRedirects: Bool
  private var response: HTTPURLResponse?
  private var responseData: NativeBoundedResponseBuffer
  private var didFinish = false

  init(
    result: NativeRequestResult<(HTTPURLResponse, Data)>,
    semaphore: DispatchSemaphore,
    maximumResponseBytes: Int?,
    rejectRedirects: Bool
  ) {
    self.result = result
    self.semaphore = semaphore
    self.maximumResponseBytes = maximumResponseBytes
    self.rejectRedirects = rejectRedirects
    responseData = NativeBoundedResponseBuffer(
      maximumBytes: maximumResponseBytes
    )
  }

  func urlSession(
    _ session: URLSession,
    task: URLSessionTask,
    willPerformHTTPRedirection response: HTTPURLResponse,
    newRequest request: URLRequest,
    completionHandler: @escaping (URLRequest?) -> Void
  ) {
    completionHandler(rejectRedirects ? nil : request)
  }

  func urlSession(
    _ session: URLSession,
    dataTask: URLSessionDataTask,
    didReceive response: URLResponse,
    completionHandler: @escaping (URLSession.ResponseDisposition) -> Void
  ) {
    guard let http = response as? HTTPURLResponse else {
      completionHandler(.cancel)
      finish(.failure(.malformedResponse))
      return
    }
    if let maximumResponseBytes,
      response.expectedContentLength > Int64(maximumResponseBytes)
    {
      completionHandler(.cancel)
      finish(.failure(.malformedResponse))
      return
    }
    self.response = http
    completionHandler(.allow)
  }

  func urlSession(
    _ session: URLSession,
    dataTask: URLSessionDataTask,
    didReceive data: Data
  ) {
    guard responseData.append(data) else {
      dataTask.cancel()
      finish(.failure(.malformedResponse))
      return
    }
  }

  func urlSession(
    _ session: URLSession,
    task: URLSessionTask,
    didCompleteWithError error: Error?
  ) {
    guard !didFinish else { return }
    if let error {
      finish(.failure(.transport(String(describing: error))))
      return
    }
    guard let response else {
      finish(.failure(.malformedResponse))
      return
    }
    finish(.success((response, responseData.data)))
  }

  private func finish(
    _ requestResult: Result<
      (HTTPURLResponse, Data),
      NativeLightwalletdError
    >
  ) {
    guard !didFinish else { return }
    didFinish = true
    result.set(requestResult)
    semaphore.signal()
  }
}

private func performNativeRequest<Value>(
  _ request: URLRequest,
  cancellation: BackgroundMigrationCancellation,
  maximumResponseBytes: Int? = nil,
  rejectRedirects: Bool = false,
  parseResponse: @escaping (HTTPURLResponse, Data) throws -> Value
) -> Result<Value, NativeLightwalletdError> {
  let semaphore = DispatchSemaphore(value: 0)
  let result = NativeRequestResult<(HTTPURLResponse, Data)>()
  let delegate = NativeRequestSessionDelegate(
    result: result,
    semaphore: semaphore,
    maximumResponseBytes: maximumResponseBytes,
    rejectRedirects: rejectRedirects
  )
  let configuration = URLSessionConfiguration.ephemeral
  configuration.timeoutIntervalForRequest = 15
  configuration.timeoutIntervalForResource = 16
  let session = URLSession(
    configuration: configuration,
    delegate: delegate,
    delegateQueue: nil
  )
  let task = session.dataTask(with: request)
  task.resume()

  let deadline = Date(timeIntervalSinceNow: 16)
  while semaphore.wait(timeout: .now() + 0.25) == .timedOut {
    if cancellation.isCancelled {
      task.cancel()
      session.invalidateAndCancel()
      return .failure(.cancelled)
    }
    if Date() >= deadline {
      task.cancel()
      session.invalidateAndCancel()
      return .failure(.timedOut)
    }
  }
  session.finishTasksAndInvalidate()
  switch result.result {
  case .success(let (http, data)):
    do {
      return .success(try parseResponse(http, data))
    } catch let error as NativeLightwalletdError {
      return .failure(error)
    } catch {
      return .failure(.malformedResponse)
    }
  case .failure(let error):
    return .failure(error)
  case nil:
    return .failure(.malformedResponse)
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

  static func transactionSubmissionURL(
    endpoint: String,
    syncEndpoint: String
  ) -> URL? {
    guard let components = URLComponents(string: endpoint),
      components.user == nil,
      components.password == nil,
      let submissionHost = components.host,
      components.query == nil,
      components.fragment == nil,
      components.path.isEmpty || components.path == "/",
      components.scheme == "https"
        || (components.scheme == "http" && isNativeLocalHost(submissionHost)),
      let syncHost = URLComponents(string: syncEndpoint)?.host,
      submissionHost.caseInsensitiveCompare(syncHost) != .orderedSame
    else {
      return nil
    }
    return components.url
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

private struct NativeTransactionRelayRequest: Encodable {
  let jsonrpc = "2.0"
  let id = 1
  let method = "sendrawtransaction"
  let params: [String]
}

private struct NativeTransactionRelayResponse: Decodable {
  struct ErrorBody: Decodable {
    let code: Int64
    let message: String
  }

  let jsonrpc: String?
  let id: Int?
  let result: String?
  let error: ErrorBody?
}

enum NativeTransactionRelayClient {
  private static let maximumResponseBytes = 64 * 1024

  static func sendTransaction(
    endpoint: String,
    expectedTxidHex: String,
    rawTransaction: Data,
    cancellation: BackgroundMigrationCancellation
  ) -> Result<NativeLightwalletdSendResponse, NativeLightwalletdError> {
    guard let url = relayURL(endpoint), isTxidHex(expectedTxidHex) else {
      return .failure(.invalidEndpoint)
    }
    let payload: Data
    do {
      payload = try JSONEncoder().encode(
        NativeTransactionRelayRequest(
          params: [rawTransaction.map { String(format: "%02x", $0) }.joined()]
        )
      )
    } catch {
      return .failure(.malformedResponse)
    }

    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    request.timeoutInterval = 15
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.httpBody = payload

    return performNativeRequest(
      request,
      cancellation: cancellation,
      maximumResponseBytes: maximumResponseBytes,
      rejectRedirects: true,
      parseResponse: { http, data in
        guard (200...299).contains(http.statusCode) else {
          throw NativeLightwalletdError.invalidHTTPStatus(http.statusCode)
        }
        return try parseSendTransactionResponse(
          data,
          expectedTxidHex: expectedTxidHex
        )
      }
    )
  }

  static func parseSendTransactionResponse(
    _ data: Data,
    expectedTxidHex: String
  ) throws -> NativeLightwalletdSendResponse {
    guard isTxidHex(expectedTxidHex) else {
      throw NativeLightwalletdError.malformedResponse
    }
    let response = try JSONDecoder().decode(
      NativeTransactionRelayResponse.self,
      from: data
    )
    guard response.jsonrpc == "2.0", response.id == 1 else {
      throw NativeLightwalletdError.malformedResponse
    }
    switch (response.result, response.error) {
    case (.some(let returnedTxid), .none):
      guard isTxidHex(returnedTxid),
        returnedTxid.caseInsensitiveCompare(expectedTxidHex) == .orderedSame
      else {
        throw NativeLightwalletdError.malformedResponse
      }
      return NativeLightwalletdSendResponse(errorCode: 0, errorMessage: "")
    case (.none, .some(let error)):
      guard let code = Int32(exactly: error.code) else {
        throw NativeLightwalletdError.malformedResponse
      }
      return NativeLightwalletdSendResponse(
        errorCode: code,
        errorMessage: error.message
      )
    default:
      throw NativeLightwalletdError.malformedResponse
    }
  }

  static func relayURL(_ endpoint: String) -> URL? {
    guard let components = URLComponents(string: endpoint),
      components.user == nil,
      components.password == nil,
      let host = components.host,
      components.query == nil,
      components.fragment == nil,
      components.scheme == "https" || (components.scheme == "http" && isNativeLocalHost(host))
    else {
      return nil
    }
    return components.url
  }

  private static func isTxidHex(_ value: String) -> Bool {
    value.utf8.count == 64
      && value.utf8.allSatisfy {
        (48...57).contains($0) || (65...70).contains($0) || (97...102).contains($0)
      }
  }
}
