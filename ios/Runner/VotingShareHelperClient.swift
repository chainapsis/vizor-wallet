import Foundation

/// Cooperative cancellation token for the voting share lane.
///
/// Pure Swift on purpose: the voting share outbox never calls into Rust, so —
/// unlike `BackgroundMigrationCancellation` — this token carries no native
/// lightwalletd handle. Cancelling interrupts the in-flight URLSession task
/// and makes every later step of the pass bail out.
final class BackgroundVotingShareCancellation: @unchecked Sendable {
  private let lock = NSLock()
  private var cancelled = false
  private var cancelHandlers: [() -> Void] = []

  func cancel() {
    lock.lock()
    cancelled = true
    let handlers = cancelHandlers
    cancelHandlers = []
    lock.unlock()
    for handler in handlers { handler() }
  }

  var isCancelled: Bool {
    lock.lock()
    defer { lock.unlock() }
    return cancelled
  }

  /// Registers a handler run once on cancellation; runs immediately when the
  /// token is already cancelled.
  func onCancel(_ handler: @escaping () -> Void) {
    lock.lock()
    if cancelled {
      lock.unlock()
      handler()
      return
    }
    cancelHandlers.append(handler)
    lock.unlock()
  }
}

enum VotingShareHelperClientError: Error, Equatable {
  case invalidBaseUrl
  case cancelled
  case timedOut
  case transport(String)
  case invalidHTTPStatus(Int)
  case malformedResponse
}

struct VotingShareStatusResponse: Equatable {
  let status: String

  var isConfirmed: Bool { status == "confirmed" }
}

/// The only two network operations the voting share lane is allowed:
/// a share-status GET and an exact-bytes share POST against a helper server.
protocol VotingShareHelperTransport {
  func getShareStatus(
    baseUrl: String,
    roundId: String,
    shareIdHex: String,
    cancellation: BackgroundVotingShareCancellation
  ) -> Result<VotingShareStatusResponse, VotingShareHelperClientError>

  func postShare(
    baseUrl: String,
    bodyJson: Data,
    cancellation: BackgroundVotingShareCancellation
  ) -> Result<Void, VotingShareHelperClientError>
}

/// URLSession JSON transport for voting share helpers.
///
/// Deliberately direct (no Tor, no route policy), mirroring the Ironwood
/// migration outbox's pinned-direct background transport: a background pass
/// never brings Tor up, so routing this lane through the policy would only
/// convert it into failures on a Tor wallet. The session is ephemeral with
/// cookies and caching disabled so nothing about a pass persists.
final class VotingShareHelperClient: VotingShareHelperTransport {
  static let shared = VotingShareHelperClient()
  static let requestTimeout: TimeInterval = 15

  private let session: URLSession

  init(configuration: URLSessionConfiguration = VotingShareHelperClient.makeConfiguration()) {
    session = URLSession(configuration: configuration)
  }

  static func makeConfiguration() -> URLSessionConfiguration {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.timeoutIntervalForRequest = requestTimeout
    configuration.timeoutIntervalForResource = requestTimeout * 2
    configuration.httpCookieAcceptPolicy = .never
    configuration.httpShouldSetCookies = false
    configuration.httpCookieStorage = nil
    configuration.urlCache = nil
    configuration.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
    configuration.waitsForConnectivity = false
    return configuration
  }

  func getShareStatus(
    baseUrl: String,
    roundId: String,
    shareIdHex: String,
    cancellation: BackgroundVotingShareCancellation
  ) -> Result<VotingShareStatusResponse, VotingShareHelperClientError> {
    guard
      let url = Self.shareStatusURL(
        baseUrl: baseUrl,
        roundId: roundId,
        shareIdHex: shareIdHex
      )
    else {
      return .failure(.invalidBaseUrl)
    }
    var request = URLRequest(url: url)
    request.httpMethod = "GET"
    request.setValue("application/json", forHTTPHeaderField: "Accept")
    switch perform(request, cancellation: cancellation) {
    case .failure(let error):
      return .failure(error)
    case .success(let response):
      guard (200..<300).contains(response.statusCode) else {
        return .failure(.invalidHTTPStatus(response.statusCode))
      }
      return Self.parseShareStatusResponse(response.data)
    }
  }

  func postShare(
    baseUrl: String,
    bodyJson: Data,
    cancellation: BackgroundVotingShareCancellation
  ) -> Result<Void, VotingShareHelperClientError> {
    guard !bodyJson.isEmpty, let url = Self.sharesURL(baseUrl: baseUrl) else {
      return .failure(.invalidBaseUrl)
    }
    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    // The staged bytes are the payload; they are never re-encoded.
    request.httpBody = bodyJson
    switch perform(request, cancellation: cancellation) {
    case .failure(let error):
      return .failure(error)
    case .success(let response):
      guard (200..<300).contains(response.statusCode) else {
        return .failure(.invalidHTTPStatus(response.statusCode))
      }
      return .success(())
    }
  }

  static func shareStatusURL(
    baseUrl: String,
    roundId: String,
    shareIdHex: String
  ) -> URL? {
    guard isPathSafeHex(roundId), isPathSafeHex(shareIdHex),
      var components = normalizedBaseComponents(baseUrl)
    else {
      return nil
    }
    components.path += "/shielded-vote/v1/share-status/\(roundId)/\(shareIdHex)"
    return components.url
  }

  static func sharesURL(baseUrl: String) -> URL? {
    guard var components = normalizedBaseComponents(baseUrl) else { return nil }
    components.path += "/shielded-vote/v1/shares"
    return components.url
  }

  static func parseShareStatusResponse(
    _ data: Data
  ) -> Result<VotingShareStatusResponse, VotingShareHelperClientError> {
    guard
      let object = try? JSONSerialization.jsonObject(with: data),
      let dictionary = object as? [String: Any],
      let status = dictionary["status"] as? String
    else {
      return .failure(.malformedResponse)
    }
    return .success(VotingShareStatusResponse(status: status))
  }

  private func perform(
    _ request: URLRequest,
    cancellation: BackgroundVotingShareCancellation
  ) -> Result<(data: Data, statusCode: Int), VotingShareHelperClientError> {
    guard !cancellation.isCancelled else { return .failure(.cancelled) }
    let box = VotingShareResponseBox()
    let semaphore = DispatchSemaphore(value: 0)
    let task = session.dataTask(with: request) { data, response, error in
      if let error {
        let nsError = error as NSError
        if nsError.domain == NSURLErrorDomain && nsError.code == NSURLErrorCancelled {
          box.set(.failure(.cancelled))
        } else if nsError.domain == NSURLErrorDomain
          && nsError.code == NSURLErrorTimedOut
        {
          box.set(.failure(.timedOut))
        } else {
          box.set(.failure(.transport(nsError.localizedDescription)))
        }
      } else if let http = response as? HTTPURLResponse {
        box.set(.success((data: data ?? Data(), statusCode: http.statusCode)))
      } else {
        box.set(.failure(.malformedResponse))
      }
      semaphore.signal()
    }
    cancellation.onCancel { task.cancel() }
    task.resume()
    // The resource timeout bounds the request; the deadline below is only a
    // last-resort guard so a completion that never arrives cannot wedge the
    // background pass.
    let deadline = Date().addingTimeInterval(Self.requestTimeout * 2 + 5)
    while semaphore.wait(timeout: .now() + 0.2) == .timedOut {
      if Date() >= deadline {
        task.cancel()
        return .failure(.timedOut)
      }
    }
    guard let result = box.result else { return .failure(.malformedResponse) }
    return result
  }

  private static func normalizedBaseComponents(_ baseUrl: String) -> URLComponents? {
    guard var components = URLComponents(string: baseUrl),
      components.scheme == "https" || components.scheme == "http",
      components.host != nil
    else {
      return nil
    }
    if components.path.hasSuffix("/") {
      components.path = String(components.path.dropLast())
    }
    components.query = nil
    components.fragment = nil
    return components
  }

  private static func isPathSafeHex(_ value: String) -> Bool {
    !value.isEmpty && value.allSatisfy(\.isHexDigit)
  }
}

private final class VotingShareResponseBox: @unchecked Sendable {
  private let lock = NSLock()
  private var storedResult:
    Result<(data: Data, statusCode: Int), VotingShareHelperClientError>?

  func set(
    _ result: Result<(data: Data, statusCode: Int), VotingShareHelperClientError>
  ) {
    lock.lock()
    defer { lock.unlock() }
    // First writer wins: a late cancellation callback must not replace a
    // completed response.
    if storedResult == nil { storedResult = result }
  }

  var result: Result<(data: Data, statusCode: Int), VotingShareHelperClientError>? {
    lock.lock()
    defer { lock.unlock() }
    return storedResult
  }
}
