// l10n-ignore-file: protocol values
import 'dart:convert';
import 'dart:io';

import '../../../../core/network/network_http_client.dart';
import '../../domain/near_intents_service_status.dart';

abstract interface class NearIntentsServiceStatusSource {
  Future<NearIntentsServiceFeed> loadIncidents({Future<void>? cancelSignal});
  Future<NearIntentsServiceFeed> loadMaintenance({Future<void>? cancelSignal});
}

class NearIntentsServiceStatusClient implements NearIntentsServiceStatusSource {
  NearIntentsServiceStatusClient({NetworkHttpClient? client})
    : _client = client ?? NetworkHttpClient();

  final NetworkHttpClient _client;

  @override
  Future<NearIntentsServiceFeed> loadIncidents({Future<void>? cancelSignal}) =>
      _get(
        'https://functions.vizor.cash/api/near-intents/shield/status',
        cancelSignal,
        parseNearIntentsIncidents,
      );

  @override
  Future<NearIntentsServiceFeed> loadMaintenance({
    Future<void>? cancelSignal,
  }) => _get(
    'https://functions.vizor.cash/api/near-intents/shield/maintenance-modes',
    cancelSignal,
    parseNearIntentsMaintenance,
  );

  Future<NearIntentsServiceFeed> _get(
    String url,
    Future<void>? cancelSignal,
    List<NearIntentsServiceIssue> Function(Object?) parse,
  ) async {
    final response = await _client.request(
      'GET',
      Uri.parse(url),
      headers: const {HttpHeaders.acceptHeader: 'application/json'},
      timeout: const Duration(seconds: 15),
      maxBodyBytes: 256 * 1024,
      cancelSignal: cancelSignal,
    );
    if (response.statusCode != 200) {
      throw HttpException('Service status returned ${response.statusCode}');
    }
    final values = response.headers['x-vizor-server-time'];
    if (values == null || values.length != 1) {
      throw const FormatException('Expected one Vizor server time header');
    }
    final serverTime = parseNearIntentsServerTime(values.single);
    return NearIntentsServiceFeed(
      issues: parse(jsonDecode(utf8.decode(response.bodyBytes))),
      serverTime: serverTime,
    );
  }

  void close() => _client.close(force: true);
}
