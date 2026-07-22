import Foundation

final class BackgroundMigrationCancellation: @unchecked Sendable {
  private let lock = NSLock()
  private var cancelled = false

  func cancel() {
    lock.lock()
    cancelled = true
    lock.unlock()
  }

  var isCancelled: Bool {
    lock.lock()
    defer { lock.unlock() }
    return cancelled
  }
}

enum NativeLightwalletdError: Error, Equatable {
  case invalidEndpoint
  case cancelled
  case timedOut
  case transport(String)
  case invalidHTTPStatus(Int)
  case grpcStatus(String)
  case malformedResponse
  case missingHeight
  case missingSendResponse
}

struct NativeLightwalletdSendResponse: Equatable {
  let errorCode: Int32
  let errorMessage: String
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

enum NativeLightwalletdClient {
  private static let latestBlockPath =
    "/cash.z.wallet.sdk.rpc.CompactTxStreamer/GetLatestBlock"
  private static let sendTransactionPath =
    "/cash.z.wallet.sdk.rpc.CompactTxStreamer/SendTransaction"

  static func latestBlockHeight(
    endpoint: String,
    cancellation: BackgroundMigrationCancellation
  ) -> Result<UInt64, NativeLightwalletdError> {
    guard let url = rpcURL(endpoint: endpoint, methodPath: latestBlockPath) else {
      return .failure(.invalidEndpoint)
    }
    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    request.timeoutInterval = 15
    request.setValue("application/grpc", forHTTPHeaderField: "Content-Type")
    request.setValue("trailers", forHTTPHeaderField: "TE")
    request.httpBody = Data(repeating: 0, count: 5)

    let semaphore = DispatchSemaphore(value: 0)
    let result = NativeLightwalletdRequestResult()
    let configuration = URLSessionConfiguration.ephemeral
    configuration.timeoutIntervalForRequest = 15
    configuration.timeoutIntervalForResource = 16
    let session = URLSession(configuration: configuration)
    let task = session.dataTask(with: request) { data, response, error in
      defer { semaphore.signal() }
      if let error {
        result.set(.failure(.transport(String(describing: error))))
        return
      }
      guard let http = response as? HTTPURLResponse else {
        result.set(.failure(.malformedResponse))
        return
      }
      guard http.statusCode == 200 else {
        result.set(.failure(.invalidHTTPStatus(http.statusCode)))
        return
      }
      if let grpcStatus = http.value(forHTTPHeaderField: "grpc-status"),
        grpcStatus != "0"
      {
        result.set(.failure(.grpcStatus(grpcStatus)))
        return
      }
      guard let data else {
        result.set(.failure(.malformedResponse))
        return
      }
      do {
        result.set(.success(try parseLatestBlockResponse(data)))
      } catch let error as NativeLightwalletdError {
        result.set(.failure(error))
      } catch {
        result.set(.failure(.malformedResponse))
      }
    }
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
    return result.result ?? .failure(.malformedResponse)
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

  static func sendTransaction(
    endpoint: String,
    rawTransaction: Data,
    cancellation: BackgroundMigrationCancellation
  ) -> Result<NativeLightwalletdSendResponse, NativeLightwalletdError> {
    guard let url = rpcURL(endpoint: endpoint, methodPath: sendTransactionPath) else {
      return .failure(.invalidEndpoint)
    }
    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    request.timeoutInterval = 15
    request.setValue("application/grpc", forHTTPHeaderField: "Content-Type")
    request.setValue("trailers", forHTTPHeaderField: "TE")
    request.httpBody = grpcFrame(payload: rawTransactionMessage(rawTransaction))

    let semaphore = DispatchSemaphore(value: 0)
    let result = NativeLightwalletdSendRequestResult()
    let configuration = URLSessionConfiguration.ephemeral
    configuration.timeoutIntervalForRequest = 15
    configuration.timeoutIntervalForResource = 16
    let session = URLSession(configuration: configuration)
    let task = session.dataTask(with: request) { data, response, error in
      defer { semaphore.signal() }
      if let error {
        result.set(.failure(.transport(String(describing: error))))
        return
      }
      guard let http = response as? HTTPURLResponse else {
        result.set(.failure(.malformedResponse))
        return
      }
      guard http.statusCode == 200 else {
        result.set(.failure(.invalidHTTPStatus(http.statusCode)))
        return
      }
      if let grpcStatus = http.value(forHTTPHeaderField: "grpc-status"),
        grpcStatus != "0"
      {
        result.set(.failure(.grpcStatus(grpcStatus)))
        return
      }
      guard let data else {
        result.set(.failure(.malformedResponse))
        return
      }
      do {
        result.set(.success(try parseSendTransactionResponse(data)))
      } catch let error as NativeLightwalletdError {
        result.set(.failure(error))
      } catch {
        result.set(.failure(.malformedResponse))
      }
    }
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
    return result.result ?? .failure(.malformedResponse)
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
    guard let errorCode else {
      throw NativeLightwalletdError.missingSendResponse
    }
    return NativeLightwalletdSendResponse(
      errorCode: errorCode,
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
