import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../models/wallet_link_models.dart';
import '../wallet_link_config.dart';

class WalletLinkApiException implements Exception {
  const WalletLinkApiException(this.statusCode, this.message);

  final int statusCode;
  final String message;

  @override
  String toString() => 'Wallet link API error $statusCode: $message';
}

class WalletLinkApiClient {
  WalletLinkApiClient({
    HttpClient? client,
    Uri? baseUri,
    this.timeout = const Duration(seconds: 12),
  }) : _client = client ?? HttpClient(),
       _baseUri = baseUri ?? walletLinkBackendBaseUri();

  final HttpClient _client;
  final Uri _baseUri;
  final Duration timeout;

  Future<WalletLinkCreatePackageResponse> createPackage(
    WalletLinkCreatePackageRequest input,
  ) async {
    final request = await _client
        .postUrl(walletLinkPackagesUri(_baseUri))
        .timeout(timeout);
    request.headers.contentType = ContentType.json;
    request.headers.set(HttpHeaders.acceptHeader, 'application/json');
    request.write(jsonEncode(input.toJson()));

    final response = await request.close().timeout(timeout);
    final body = await utf8.decoder.bind(response).join().timeout(timeout);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw WalletLinkApiException(response.statusCode, body.trim());
    }
    final decoded = jsonDecode(body);
    if (decoded is! Map<String, Object?>) {
      throw const FormatException('Wallet link response must be an object.');
    }
    return WalletLinkCreatePackageResponse.fromJson(decoded);
  }

  Future<void> deletePackage(String packageId) async {
    final request = await _client
        .deleteUrl(walletLinkPackagesUri(_baseUri, packageId: packageId))
        .timeout(timeout);
    request.headers.set(HttpHeaders.acceptHeader, 'application/json');

    final response = await request.close().timeout(timeout);
    await response.drain<void>().timeout(timeout);
    if (response.statusCode == 404 || response.statusCode == 410) return;
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw WalletLinkApiException(
        response.statusCode,
        'Failed to delete wallet link package.',
      );
    }
  }

  void close({bool force = false}) {
    _client.close(force: force);
  }
}
