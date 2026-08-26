import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import '../../rust/api/network_privacy.dart' as rust_network_privacy;

class NetworkHttpResponse {
  const NetworkHttpResponse({
    required this.statusCode,
    required this.bodyBytes,
    this.headers = const {},
  });

  final int statusCode;
  final Uint8List bodyBytes;
  final Map<String, List<String>> headers;

  String? header(String name) {
    final values = headers[name.toLowerCase()];
    return values == null || values.isEmpty ? null : values.first;
  }
}

class TorUnsupportedHttpMethodException implements Exception {
  const TorUnsupportedHttpMethodException(this.method);

  final String method;

  @override
  String toString() =>
      'The $method request was blocked because the embedded Tor transport '
      'does not support this method.';
}

class DirectNetworkRequestsBlockedException implements Exception {
  const DirectNetworkRequestsBlockedException();

  @override
  String toString() =>
      'Direct network requests are blocked while the app switches to Tor.';
}

class NetworkHttpRequestCancelledException implements Exception {
  const NetworkHttpRequestCancelledException();

  @override
  String toString() => 'Network HTTP request cancelled';
}

class _DirectRequestOperation<T> {
  _DirectRequestOperation({required this.result, required Future<T> source})
    : drained = source.then<void>((_) {}, onError: (_, _) {});

  factory _DirectRequestOperation.fromFuture(Future<T> source) =>
      _DirectRequestOperation(result: source, source: source);

  final Future<T> result;
  final Future<void> drained;
}

/// Tor transport boundary used after the process-wide route selects Tor.
///
/// Implementations must apply each timeout to the underlying transport
/// operation, not only to the Future returned to Dart.
abstract interface class TorHttpBridge {
  Future<NetworkHttpResponse> get(
    Uri uri, {
    required Map<String, String> headers,
    required Duration? timeout,
    Future<void>? cancelSignal,
  });

  Future<NetworkHttpResponse> post(
    Uri uri, {
    required Map<String, String> headers,
    required List<int> bodyBytes,
    required Duration? timeout,
    Future<void>? cancelSignal,
  });

  Future<NetworkHttpResponse> download(
    Uri uri, {
    required Map<String, String> headers,
    required String destinationPath,
  });
}

class RustTorHttpBridge implements TorHttpBridge {
  const RustTorHttpBridge();

  static const _requestTimeoutError = 'Tor HTTP request timed out';

  @override
  Future<NetworkHttpResponse> get(
    Uri uri, {
    required Map<String, String> headers,
    required Duration? timeout,
    Future<void>? cancelSignal,
  }) {
    return _request(
      timeout,
      cancelSignal,
      (requestId) => rust_network_privacy.torHttpGet(
        url: uri.toString(),
        headers: _rustHeaders(headers),
        timeoutMilliseconds: _timeoutMilliseconds(timeout),
        requestId: requestId,
      ),
    );
  }

  @override
  Future<NetworkHttpResponse> post(
    Uri uri, {
    required Map<String, String> headers,
    required List<int> bodyBytes,
    required Duration? timeout,
    Future<void>? cancelSignal,
  }) {
    return _request(
      timeout,
      cancelSignal,
      (requestId) => rust_network_privacy.torHttpPost(
        url: uri.toString(),
        headers: _rustHeaders(headers),
        body: bodyBytes,
        timeoutMilliseconds: _timeoutMilliseconds(timeout),
        requestId: requestId,
      ),
    );
  }

  @override
  Future<NetworkHttpResponse> download(
    Uri uri, {
    required Map<String, String> headers,
    required String destinationPath,
  }) async {
    final response = await rust_network_privacy.torHttpDownload(
      url: uri.toString(),
      headers: _rustHeaders(headers),
      destinationPath: destinationPath,
    );
    return networkHttpResponseFromRust(response);
  }

  static BigInt? _timeoutMilliseconds(Duration? timeout) {
    if (timeout == null) return null;
    if (timeout <= Duration.zero) {
      throw ArgumentError.value(timeout, 'timeout', 'must be positive');
    }
    return BigInt.from(timeout.inMilliseconds < 1 ? 1 : timeout.inMilliseconds);
  }

  Future<NetworkHttpResponse> _request(
    Duration? timeout,
    Future<void>? cancelSignal,
    Future<rust_network_privacy.NetworkHttpResponse> Function(BigInt? requestId)
    send,
  ) async {
    final signal = cancelSignal;
    final requestId = signal == null
        ? null
        : rust_network_privacy.torHttpBeginRequest();
    var completed = false;
    if (requestId != null) {
      unawaited(
        signal!.then((_) {
          if (!completed) {
            rust_network_privacy.torHttpCancelRequest(requestId: requestId);
          }
        }, onError: (_, _) {}),
      );
    }
    try {
      return networkHttpResponseFromRust(await send(requestId));
    } catch (error, stackTrace) {
      if (timeout != null && error.toString().contains(_requestTimeoutError)) {
        throw TimeoutException(_requestTimeoutError, timeout);
      }
      Error.throwWithStackTrace(error, stackTrace);
    } finally {
      completed = true;
    }
  }

  static List<rust_network_privacy.NetworkHttpHeader> _rustHeaders(
    Map<String, String> headers,
  ) => [
    for (final entry in headers.entries)
      rust_network_privacy.NetworkHttpHeader(
        name: entry.key,
        value: entry.value,
      ),
  ];
}

/// Converts the generated Rust response while preserving the concrete nested
/// generic types. Leaving either collection inferred through `unmodifiable`
/// produces `Map<dynamic, dynamic>` / `List<dynamic>` at runtime and breaks
/// every successful Tor HTTP response when it is read as typed headers.
NetworkHttpResponse networkHttpResponseFromRust(
  rust_network_privacy.NetworkHttpResponse response,
) {
  final headers = <String, List<String>>{};
  for (final header in response.headers) {
    (headers[header.name.toLowerCase()] ??= <String>[]).add(header.value);
  }
  final immutableHeaders = <String, List<String>>{
    for (final entry in headers.entries)
      entry.key: List<String>.unmodifiable(entry.value),
  };
  return NetworkHttpResponse(
    statusCode: response.statusCode,
    bodyBytes: response.body,
    headers: Map<String, List<String>>.unmodifiable(immutableHeaders),
  );
}

/// Routes app-owned HTTP traffic through the process-wide network privacy
/// policy. Tor mode never falls back to [HttpClient] when Tor is unavailable.
class NetworkHttpClient {
  NetworkHttpClient({
    HttpClient? directClient,
    bool Function()? torDesired,
    TorHttpBridge? torBridge,
  }) : _directClient = directClient ?? HttpClient(),
       _torDesired = torDesired ?? rust_network_privacy.isTorEnabled,
       _torBridge = torBridge ?? const RustTorHttpBridge() {
    _instances.add(this);
  }

  static final Set<NetworkHttpClient> _instances = {};
  static bool _directRequestsBlocked = false;

  HttpClient _directClient;
  final bool Function() _torDesired;
  final TorHttpBridge _torBridge;
  var _activeDirectRequests = 0;
  var _directClientNeedsReset = false;
  var _closed = false;
  Completer<void>? _directRequestsDrained;

  /// Prevents new direct HTTP work, force-closes every app-owned direct
  /// client, and waits until the interrupted operations have unwound.
  static Future<void> quiesceDirectRequests() async {
    _directRequestsBlocked = true;
    await Future.wait([
      for (final client in List<NetworkHttpClient>.of(_instances))
        client._quiesceDirectRequests(),
    ]);
  }

  /// Reopens direct HTTP routing only after Rust has confirmed the route
  /// switch away from Tor.
  static void allowDirectRequests() {
    for (final client in List<NetworkHttpClient>.of(_instances)) {
      client._resetDirectClientAfterQuiesce();
    }
    _directRequestsBlocked = false;
  }

  Future<NetworkHttpResponse> request(
    String method,
    Uri uri, {
    Map<String, String> headers = const {},
    List<int> bodyBytes = const [],
    Duration? timeout,
    Future<void>? cancelSignal,
  }) {
    _requirePositiveTimeout(timeout);
    return _torDesired()
        ? _requestViaTorWithRedirects(
            method.toUpperCase(),
            uri,
            headers: headers,
            bodyBytes: bodyBytes,
            timeout: timeout,
            cancelSignal: cancelSignal,
          )
        : _runDirectRequest(
            () => _requestDirect(
              method.toUpperCase(),
              uri,
              headers: headers,
              bodyBytes: bodyBytes,
              timeout: timeout,
              cancelSignal: cancelSignal,
            ),
          );
  }

  /// Streams a GET response to [destination] without retaining the response
  /// body in Dart memory. Tor mode performs the file write inside Rust so large
  /// downloads do not cross the FFI boundary as a whole-body byte array.
  Future<NetworkHttpResponse> downloadToFile(
    Uri uri,
    File destination, {
    Map<String, String> headers = const {},
    Duration? timeout,
  }) {
    final future = _torDesired()
        ? _requestViaTorWithRedirects(
            'GET',
            uri,
            headers: headers,
            bodyBytes: const [],
            destinationPath: destination.path,
            timeout: null,
            cancelSignal: null,
          )
        : _runDirectRequest(
            () => _DirectRequestOperation.fromFuture(
              _downloadDirect(uri, destination, headers: headers),
            ),
          );
    return timeout == null ? future : future.timeout(timeout);
  }

  void close({bool force = false}) {
    if (_closed) return;
    _closed = true;
    _directClient.close(force: force);
    if (_activeDirectRequests == 0) _instances.remove(this);
  }

  Future<T> _runDirectRequest<T>(
    _DirectRequestOperation<T> Function() request,
  ) {
    if (_directRequestsBlocked || _closed) {
      return Future.error(const DirectNetworkRequestsBlockedException());
    }
    _activeDirectRequests++;
    final _DirectRequestOperation<T> operation;
    try {
      operation = request();
    } catch (error, stackTrace) {
      _finishDirectRequest();
      return Future.error(error, stackTrace);
    }
    unawaited(operation.drained.whenComplete(_finishDirectRequest));
    return operation.result;
  }

  void _finishDirectRequest() {
    _activeDirectRequests--;
    if (_activeDirectRequests == 0) {
      _directRequestsDrained?.complete();
      _directRequestsDrained = null;
      if (_closed) _instances.remove(this);
    }
  }

  Future<void> _quiesceDirectRequests() {
    _directClient.close(force: true);
    if (!_closed) _directClientNeedsReset = true;
    if (_activeDirectRequests == 0) return Future.value();
    return (_directRequestsDrained ??= Completer<void>()).future;
  }

  void _resetDirectClientAfterQuiesce() {
    if (_closed || !_directClientNeedsReset) return;
    _directClient = HttpClient();
    _directClientNeedsReset = false;
  }

  Future<NetworkHttpResponse> _requestViaTorWithRedirects(
    String method,
    Uri initialUri, {
    required Map<String, String> headers,
    required List<int> bodyBytes,
    String? destinationPath,
    required Duration? timeout,
    required Future<void>? cancelSignal,
  }) async {
    if (method != 'GET' && method != 'POST') {
      throw TorUnsupportedHttpMethodException(method);
    }

    var currentMethod = method;
    var currentUri = initialUri;
    var currentHeaders = Map<String, String>.of(headers);
    var currentBody = bodyBytes;
    final stopwatch = Stopwatch()..start();
    for (var redirectCount = 0; redirectCount <= 5; redirectCount++) {
      final remainingTimeout = _remainingTimeout(timeout, stopwatch);
      final response = destinationPath != null
          ? await _torBridge.download(
              currentUri,
              headers: currentHeaders,
              destinationPath: destinationPath,
            )
          : currentMethod == 'GET'
          ? await _torBridge.get(
              currentUri,
              headers: currentHeaders,
              timeout: remainingTimeout,
              cancelSignal: cancelSignal,
            )
          : await _torBridge.post(
              currentUri,
              headers: currentHeaders,
              bodyBytes: currentBody,
              timeout: remainingTimeout,
              cancelSignal: cancelSignal,
            );
      final location = response.header(HttpHeaders.locationHeader);
      if (!_isRedirect(response.statusCode) || location == null) {
        return response;
      }
      if (redirectCount == 5) {
        throw const HttpException('Too many HTTP redirects');
      }
      final nextUri = currentUri.resolve(location);
      if (currentUri.scheme == 'https' && nextUri.scheme != 'https') {
        throw HttpException(
          'Refusing HTTPS redirect to ${nextUri.scheme}',
          uri: nextUri,
        );
      }
      currentHeaders = _headersForRedirect(currentUri, nextUri, currentHeaders);
      if (currentMethod == 'POST' &&
          (response.statusCode == HttpStatus.movedPermanently ||
              response.statusCode == HttpStatus.found ||
              response.statusCode == HttpStatus.seeOther)) {
        currentMethod = 'GET';
        currentBody = const [];
      }
      currentUri = nextUri;
    }
    throw const HttpException('Too many HTTP redirects');
  }

  _DirectRequestOperation<NetworkHttpResponse> _requestDirect(
    String method,
    Uri uri, {
    required Map<String, String> headers,
    required List<int> bodyBytes,
    required Duration? timeout,
    required Future<void>? cancelSignal,
  }) {
    HttpClientRequest? activeRequest;
    StreamSubscription<List<int>>? responseSubscription;
    Completer<Uint8List>? responseBody;
    Object? terminationError;
    Future<void> abort(Object error) async {
      try {
        activeRequest?.abort(error);
      } catch (_) {
        // Continue cleanup and preserve the original public failure.
      }
      try {
        await responseSubscription?.cancel();
      } catch (_) {
        // Continue cleanup and preserve the original public failure.
      }
      final body = responseBody;
      if (body != null && !body.isCompleted) body.completeError(error);
    }

    final request = () async {
      final request = await _directClient.openUrl(method, uri);
      activeRequest = request;
      final pendingError = terminationError;
      if (pendingError != null) {
        final error = pendingError;
        request.abort(error);
        throw error;
      }
      headers.forEach(request.headers.set);
      if (bodyBytes.isNotEmpty) request.add(bodyBytes);
      final response = await request.close();
      final body = responseBody = Completer<Uint8List>();
      final bytes = BytesBuilder();
      responseSubscription = response.listen(
        bytes.add,
        onError: (Object error, StackTrace stackTrace) {
          if (!body.isCompleted) body.completeError(error, stackTrace);
        },
        onDone: () {
          if (!body.isCompleted) body.complete(bytes.takeBytes());
        },
        cancelOnError: true,
      );
      final responseHeaders = <String, List<String>>{};
      response.headers.forEach((name, values) {
        responseHeaders[name.toLowerCase()] = List.unmodifiable(values);
      });
      return NetworkHttpResponse(
        statusCode: response.statusCode,
        bodyBytes: await body.future,
        headers: Map.unmodifiable(responseHeaders),
      );
    }();
    final signal = cancelSignal;
    final cancellation = signal == null
        ? null
        : Completer<NetworkHttpResponse>();
    if (cancellation != null) {
      unawaited(
        signal!.then((_) async {
          final error = terminationError ??=
              const NetworkHttpRequestCancelledException();
          await abort(error);
          if (!cancellation.isCompleted) {
            cancellation.completeError(error);
          }
        }, onError: (_, _) {}),
      );
    }
    final cancellableRequest = cancellation == null
        ? request
        : Future.any([request, cancellation.future]);
    final result = timeout == null
        ? cancellableRequest
        : cancellableRequest.timeout(
            timeout,
            onTimeout: () async {
              final error = terminationError ??= _timeoutException(timeout);
              await abort(error);
              throw error;
            },
          );
    return _DirectRequestOperation(result: result, source: request);
  }

  Future<NetworkHttpResponse> _downloadDirect(
    Uri uri,
    File destination, {
    required Map<String, String> headers,
  }) async {
    final request = await _directClient.getUrl(uri);
    headers.forEach(request.headers.set);
    final response = await request.close();
    await response.pipe(destination.openWrite());
    final responseHeaders = <String, List<String>>{};
    response.headers.forEach((name, values) {
      responseHeaders[name.toLowerCase()] = List.unmodifiable(values);
    });
    return NetworkHttpResponse(
      statusCode: response.statusCode,
      bodyBytes: Uint8List(0),
      headers: Map.unmodifiable(responseHeaders),
    );
  }

  static Duration? _remainingTimeout(Duration? timeout, Stopwatch stopwatch) {
    if (timeout == null) return null;
    final remaining = timeout - stopwatch.elapsed;
    if (remaining <= Duration.zero) throw _timeoutException(timeout);
    return remaining;
  }

  static void _requirePositiveTimeout(Duration? timeout) {
    if (timeout != null && timeout <= Duration.zero) {
      throw ArgumentError.value(timeout, 'timeout', 'must be positive');
    }
  }

  static TimeoutException _timeoutException(Duration timeout) =>
      TimeoutException('Network HTTP request timed out', timeout);

  static Map<String, String> _headersForRedirect(
    Uri from,
    Uri to,
    Map<String, String> headers,
  ) {
    if (_sameOrigin(from, to)) return headers;
    const sensitive = {
      HttpHeaders.authorizationHeader,
      HttpHeaders.cookieHeader,
      HttpHeaders.proxyAuthorizationHeader,
    };
    return {
      for (final entry in headers.entries)
        if (!sensitive.contains(entry.key.toLowerCase()))
          entry.key: entry.value,
    };
  }

  static bool _sameOrigin(Uri left, Uri right) =>
      left.scheme.toLowerCase() == right.scheme.toLowerCase() &&
      left.host.toLowerCase() == right.host.toLowerCase() &&
      left.port == right.port;

  static bool _isRedirect(int statusCode) =>
      statusCode == HttpStatus.movedPermanently ||
      statusCode == HttpStatus.found ||
      statusCode == HttpStatus.seeOther ||
      statusCode == HttpStatus.temporaryRedirect ||
      statusCode == HttpStatus.permanentRedirect;
}
