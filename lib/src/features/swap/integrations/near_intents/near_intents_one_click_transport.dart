part of 'near_intents_one_click_swap_adapter.dart';

class OneClickApiException implements Exception {
  const OneClickApiException(
    this.message, {
    this.operation,
    this.statusCode,
    this.providerMessage,
    this.responseBody,
  });

  final String message;
  final String? operation;
  final int? statusCode;
  final String? providerMessage;
  final String? responseBody;

  @override
  String toString() => 'OneClickApiException: $message';
}

class OneClickHttpResponse {
  const OneClickHttpResponse({required this.statusCode, required this.body});

  final int statusCode;
  final String body;

  Object? get decodedJson => jsonDecode(body);

  Map<String, dynamic> get jsonObject {
    final decoded = decodedJson;
    if (decoded is Map<String, dynamic>) {
      return decoded;
    }
    throw const OneClickApiException('Expected a JSON object response');
  }

  List<dynamic> get jsonList {
    final decoded = decodedJson;
    if (decoded is List<dynamic>) {
      return decoded;
    }
    throw const OneClickApiException('Expected a JSON list response');
  }
}

abstract interface class OneClickApiTransport {
  Future<OneClickHttpResponse> get(
    Uri uri, {
    Map<String, String> headers = const {},
  });

  Future<OneClickHttpResponse> post(
    Uri uri, {
    Map<String, String> headers = const {},
    Map<String, Object?>? body,
  });
}

class HttpClientOneClickApiTransport implements OneClickApiTransport {
  HttpClientOneClickApiTransport({
    HttpClient? client,
    this.timeout = const Duration(seconds: 20),
  }) : _client = client ?? HttpClient();

  final HttpClient _client;
  final Duration timeout;

  @override
  Future<OneClickHttpResponse> get(
    Uri uri, {
    Map<String, String> headers = const {},
  }) {
    return _send('GET', uri, headers: headers);
  }

  @override
  Future<OneClickHttpResponse> post(
    Uri uri, {
    Map<String, String> headers = const {},
    Map<String, Object?>? body,
  }) {
    return _send('POST', uri, headers: headers, body: body);
  }

  Future<OneClickHttpResponse> _send(
    String method,
    Uri uri, {
    Map<String, String> headers = const {},
    Map<String, Object?>? body,
  }) async {
    final request = await _client.openUrl(method, uri).timeout(timeout);
    request.headers.set(HttpHeaders.acceptHeader, 'application/json');
    for (final entry in headers.entries) {
      request.headers.set(entry.key, entry.value);
    }
    if (body != null) {
      request.headers.contentType = ContentType.json;
      request.write(jsonEncode(_withoutNulls(body)));
    }

    final response = await request.close().timeout(timeout);
    final responseBody = await utf8.decoder.bind(response).join();
    return OneClickHttpResponse(
      statusCode: response.statusCode,
      body: responseBody,
    );
  }
}

void _expectSuccess(OneClickHttpResponse response, String operation) {
  if (response.statusCode >= 200 && response.statusCode < 300) {
    return;
  }
  throw OneClickApiException(
    'NEAR Intents $operation failed '
    '(${response.statusCode}): ${response.body}',
    operation: operation,
    statusCode: response.statusCode,
    providerMessage: _providerMessageFromResponse(response.body),
    responseBody: response.body,
  );
}

String? _providerMessageFromResponse(String body) {
  try {
    final decoded = jsonDecode(body);
    if (decoded is Map<String, dynamic>) {
      final message = decoded['message'];
      if (message is String && message.trim().isNotEmpty) {
        return message.trim();
      }
    }
  } catch (_) {
    return null;
  }
  return null;
}

Map<String, Object?> _withoutNulls(Map<String, Object?> value) {
  return {
    for (final entry in value.entries)
      if (entry.value != null) entry.key: entry.value,
  };
}
