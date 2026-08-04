import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import '../../core/network/network_http_client.dart';

/// Small HTTP abstraction for voting services.
///
/// The voting clients are mostly protocol mappers; keeping transport injectable
/// lets tests assert URLs and JSON bodies without opening sockets.
abstract interface class VotingHttpClient {
  Future<VotingHttpResponse> get(
    Uri uri, {
    Map<String, String>? headers,
    Duration? timeout,
  });

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
  DartIoVotingHttpClient({HttpClient? client, NetworkHttpClient? networkClient})
    : _client = networkClient ?? NetworkHttpClient(directClient: client);

  final NetworkHttpClient _client;

  @override
  Future<VotingHttpResponse> get(
    Uri uri, {
    Map<String, String>? headers,
    Duration? timeout,
  }) {
    return _send('GET', uri, headers: headers, timeout: timeout);
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
    Map<String, String>? headers,
    Duration? timeout,
  }) async {
    final requestHeaders = <String, String>{
      if (contentType != null)
        HttpHeaders.contentTypeHeader: contentType.mimeType,
      ...?headers,
    };
    final response = await _client.request(
      method,
      uri,
      headers: requestHeaders,
      bodyBytes: bodyBytes ?? const [],
      timeout: timeout,
    );
    return VotingHttpResponse(
      statusCode: response.statusCode,
      bodyBytes: response.bodyBytes,
      headers: response.headers,
    );
  }
}
