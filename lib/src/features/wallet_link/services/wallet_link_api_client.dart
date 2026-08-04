import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../../../core/network/network_http_client.dart';
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
    NetworkHttpClient? networkClient,
    Uri? baseUri,
    this.timeout = const Duration(seconds: 12),
  }) : _client = networkClient ?? NetworkHttpClient(directClient: client),
       _baseUri = baseUri ?? walletLinkBackendBaseUri();

  final NetworkHttpClient _client;
  final Uri _baseUri;
  final Duration timeout;

  Future<WalletLinkCreatePackageResponse> createPackage(
    WalletLinkCreatePackageRequest input,
  ) async {
    final response = await _jsonRequest(
      'POST',
      walletLinkPackagesUri(_baseUri),
      body: input.toJson(),
    );
    final body = utf8.decode(response.bodyBytes);
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
    final response = await _client.request(
      'DELETE',
      walletLinkPackagesUri(_baseUri, packageId: packageId),
      headers: const {HttpHeaders.acceptHeader: 'application/json'},
      timeout: timeout,
    );
    if (response.statusCode == 404 || response.statusCode == 410) return;
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw WalletLinkApiException(
        response.statusCode,
        'Failed to delete wallet link package.',
      );
    }
  }

  Future<WalletLinkPackageStatus> getPackageStatus(String packageId) async {
    final response = await _jsonRequest(
      'GET',
      walletLinkPackageStatusUri(_baseUri, packageId: packageId),
    );
    final body = utf8.decode(response.bodyBytes);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw WalletLinkApiException(response.statusCode, body.trim());
    }
    final decoded = jsonDecode(body);
    if (decoded is! Map<String, Object?>) {
      throw const FormatException('Wallet link response must be an object.');
    }
    return WalletLinkPackageStatus.fromJson(decoded);
  }

  Future<WalletLinkPackageStatus> completePackage({
    required String packageId,
    required String completionToken,
    WalletLinkEnvelope? completionEnvelope,
  }) async {
    final response = await _jsonRequest(
      'POST',
      walletLinkPackageCompleteUri(_baseUri, packageId: packageId),
      body: {
        'completionToken': completionToken,
        if (completionEnvelope != null)
          'completionEnvelope': completionEnvelope.toJson(),
      },
    );
    final body = utf8.decode(response.bodyBytes);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw WalletLinkApiException(response.statusCode, body.trim());
    }
    final decoded = jsonDecode(body);
    if (decoded is! Map<String, Object?>) {
      throw const FormatException('Wallet link response must be an object.');
    }
    return WalletLinkPackageStatus.fromJson(decoded);
  }

  Future<WalletLinkPackageDownload> getPackage(String packageId) async {
    final response = await _jsonRequest(
      'GET',
      walletLinkPackagesUri(_baseUri, packageId: packageId),
    );
    final body = utf8.decode(response.bodyBytes);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw WalletLinkApiException(response.statusCode, body.trim());
    }
    final decoded = jsonDecode(body);
    if (decoded is! Map<String, Object?>) {
      throw const FormatException('Wallet link response must be an object.');
    }
    return WalletLinkPackageDownload.fromJson(decoded);
  }

  void close({bool force = false}) {
    _client.close(force: force);
  }

  Future<NetworkHttpResponse> _jsonRequest(
    String method,
    Uri uri, {
    Map<String, Object?>? body,
  }) {
    return _client.request(
      method,
      uri,
      headers: {
        HttpHeaders.acceptHeader: 'application/json',
        if (body != null)
          HttpHeaders.contentTypeHeader: ContentType.json.mimeType,
      },
      bodyBytes: body == null ? const [] : utf8.encode(jsonEncode(body)),
      timeout: timeout,
    );
  }
}
