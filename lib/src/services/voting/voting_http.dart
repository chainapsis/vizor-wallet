import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

/// Small HTTP abstraction for voting services.
///
/// The voting clients are mostly protocol mappers; keeping transport injectable
/// lets tests assert URLs and JSON bodies without opening sockets.
abstract interface class VotingHttpClient {
  Future<VotingHttpResponse> get(Uri uri, {Duration? timeout});

  Future<VotingHttpResponse> postJson(
    Uri uri,
    Map<String, dynamic> body, {
    Duration? timeout,
  });
}

/// Raw HTTP response used by voting clients.
///
/// Config loading verifies checksums over [bodyBytes], while API clients usually
/// decode [bodyText] as JSON.
class VotingHttpResponse {
  final int statusCode;
  final Uint8List bodyBytes;
  final Map<String, List<String>> headers;

  const VotingHttpResponse({
    required this.statusCode,
    required this.bodyBytes,
    this.headers = const {},
  });

  String get bodyText => utf8.decode(bodyBytes);

  Map<String, dynamic> decodeJsonObject() {
    final decoded = jsonDecode(bodyText);
    if (decoded is Map<String, dynamic>) {
      return decoded;
    }
    if (decoded is Map) {
      return decoded.map((key, value) => MapEntry(key.toString(), value));
    }
    throw const FormatException('Expected JSON object');
  }
}

/// `dart:io` implementation used by app platforms that support [HttpClient].
class DartIoVotingHttpClient implements VotingHttpClient {
  DartIoVotingHttpClient({HttpClient? client})
    : _client = client ?? HttpClient();

  final HttpClient _client;

  @override
  Future<VotingHttpResponse> get(Uri uri, {Duration? timeout}) {
    return _send('GET', uri, timeout: timeout);
  }

  @override
  Future<VotingHttpResponse> postJson(
    Uri uri,
    Map<String, dynamic> body, {
    Duration? timeout,
  }) {
    return _send(
      'POST',
      uri,
      bodyBytes: utf8.encode(jsonEncode(body)),
      contentType: ContentType.json,
      timeout: timeout,
    );
  }

  void close({bool force = false}) {
    _client.close(force: force);
  }

  Future<VotingHttpResponse> _send(
    String method,
    Uri uri, {
    List<int>? bodyBytes,
    ContentType? contentType,
    Duration? timeout,
  }) async {
    Future<VotingHttpResponse> run() async {
      final request = await _client.openUrl(method, uri);
      if (contentType != null) {
        request.headers.contentType = contentType;
      }
      if (bodyBytes != null) {
        request.add(bodyBytes);
      }
      final response = await request.close();
      final bytes = await response.fold<List<int>>(
        <int>[],
        (buffer, chunk) => buffer..addAll(chunk),
      );
      return VotingHttpResponse(
        statusCode: response.statusCode,
        bodyBytes: Uint8List.fromList(bytes),
        headers: _headersToMap(response.headers),
      );
    }

    final future = run();
    return timeout == null ? future : future.timeout(timeout);
  }

  static Map<String, List<String>> _headersToMap(HttpHeaders headers) {
    final result = <String, List<String>>{};
    headers.forEach((name, values) {
      result[name] = List.unmodifiable(values);
    });
    return Map.unmodifiable(result);
  }
}
