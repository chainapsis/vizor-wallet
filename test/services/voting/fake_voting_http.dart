import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:zcash_wallet/src/services/voting/voting_http.dart';

class FakeVotingHttpClient implements VotingHttpClient {
  final Map<String, Object> responses;
  final requests = <FakeVotingHttpRequest>[];

  FakeVotingHttpClient({this.responses = const {}});

  @override
  Future<VotingHttpResponse> get(Uri uri, {Duration? timeout}) async {
    requests.add(FakeVotingHttpRequest('GET', uri, timeout: timeout));
    return _responseFor(uri);
  }

  @override
  Future<VotingHttpResponse> postJson(
    Uri uri,
    Map<String, dynamic> body, {
    Duration? timeout,
  }) async {
    requests.add(
      FakeVotingHttpRequest('POST', uri, body: body, timeout: timeout),
    );
    return _responseFor(uri);
  }

  VotingHttpResponse _responseFor(Uri uri) {
    final configured = responses[uri.toString()] ?? responses[uri.path];
    final response = configured is SequentialVotingHttpResponses
        ? configured.next()
        : configured;
    if (response == null) {
      throw StateError('No fake voting HTTP response configured for $uri');
    }
    if (response is Exception) {
      throw response;
    }
    if (response is Error) {
      throw response;
    }
    if (response is VotingHttpResponse) {
      return response;
    }
    if (response is Map<String, dynamic>) {
      return jsonResponse(response);
    }
    if (response is List) {
      return jsonResponse(response);
    }
    if (response is String) {
      return textResponse(response);
    }
    throw StateError('Unsupported fake response: $response');
  }
}

class FakeVotingHttpRequest {
  final String method;
  final Uri uri;
  final Map<String, dynamic>? body;
  final Duration? timeout;

  const FakeVotingHttpRequest(this.method, this.uri, {this.body, this.timeout});
}

class SequentialVotingHttpResponses {
  SequentialVotingHttpResponses(this._responses);

  final List<Object> _responses;
  int _index = 0;

  Object next() {
    if (_responses.isEmpty) {
      throw StateError('SequentialVotingHttpResponses cannot be empty');
    }
    final index = _index < _responses.length ? _index : _responses.length - 1;
    _index += 1;
    return _responses[index];
  }
}

VotingHttpResponse jsonResponse(Object body, {int statusCode = 200}) {
  return VotingHttpResponse(
    statusCode: statusCode,
    bodyBytes: Uint8List.fromList(utf8.encode(jsonEncode(body))),
  );
}

VotingHttpResponse textResponse(String body, {int statusCode = 200}) {
  return VotingHttpResponse(
    statusCode: statusCode,
    bodyBytes: Uint8List.fromList(utf8.encode(body)),
  );
}

TimeoutException timeoutResponse() => TimeoutException('timed out');
