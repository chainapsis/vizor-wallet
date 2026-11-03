import 'dart:convert';
import 'dart:io';

import '../../../../core/network/network_http_client.dart';
import '../../domain/near_intents_service_status.dart';

abstract interface class NearIntentsServiceStatusSource {
  Future<List<NearIntentsServiceIssue>> loadIncidents({
    Future<void>? cancelSignal,
  });
  Future<List<NearIntentsServiceIssue>> loadMaintenance({
    Future<void>? cancelSignal,
  });
}

class NearIntentsServiceStatusClient implements NearIntentsServiceStatusSource {
  NearIntentsServiceStatusClient({NetworkHttpClient? client})
    : _client = client ?? NetworkHttpClient();

  final NetworkHttpClient _client;

  @override
  Future<List<NearIntentsServiceIssue>> loadIncidents({
    Future<void>? cancelSignal,
  }) async => parseNearIntentsIncidents(
    await _get(
      'https://functions.vizor.cash/api/near-intents/shield/status',
      cancelSignal,
    ),
  );

  @override
  Future<List<NearIntentsServiceIssue>> loadMaintenance({
    Future<void>? cancelSignal,
  }) async => parseNearIntentsMaintenance(
    await _get(
      'https://functions.vizor.cash/api/near-intents/shield/maintenance-modes',
      cancelSignal,
    ),
  );

  Future<Object?> _get(String url, Future<void>? cancelSignal) async {
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
    return jsonDecode(utf8.decode(response.bodyBytes));
  }

  void close() => _client.close(force: true);
}
