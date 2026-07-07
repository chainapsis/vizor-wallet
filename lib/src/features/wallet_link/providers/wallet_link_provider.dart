import 'dart:async';
import 'dart:convert';
import 'dart:io' show IOException;
import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../main.dart' show log;
import '../../../core/storage/wallet_paths.dart';
import '../../../providers/account_provider.dart';
import '../../../providers/rpc_endpoint_provider.dart';
import '../../../rust/api/sync.dart' as rust_sync;
import '../../../rust/api/wallet.dart' as rust_wallet;
import '../../address_book/providers/address_book_provider.dart';
import '../models/wallet_link_models.dart';
import '../services/wallet_link_api_client.dart';
import '../services/wallet_link_completion_crypto.dart';

final walletLinkLocalLifetimeProvider = Provider<Duration>((ref) {
  return const Duration(minutes: 1);
});

final walletLinkApiClientProvider = Provider<WalletLinkApiClient>((ref) {
  final client = WalletLinkApiClient();
  ref.onDispose(() => client.close(force: true));
  return client;
});

final walletLinkControllerProvider =
    NotifierProvider.autoDispose<WalletLinkController, WalletLinkState>(
      WalletLinkController.new,
    );

class WalletLinkController extends Notifier<WalletLinkState> {
  final _random = Random.secure();
  WalletLinkApiClient? _apiClient;
  Timer? _timer;
  int _epoch = 0;
  int? _statusPollEpoch;
  String? _lastStatusPollErrorLogKey;
  String? _remotePackageId;
  Uint8List? _activeKeyBytes;

  @override
  WalletLinkState build() {
    _apiClient = ref.watch(walletLinkApiClientProvider);
    ref.onDispose(_dispose);
    return const WalletLinkState.initial();
  }

  Future<void> start() async {
    final epoch = ++_epoch;
    _timer?.cancel();
    final previousPackageId = _remotePackageId;
    _remotePackageId = null;
    _activeKeyBytes = null;
    if (previousPackageId != null) {
      unawaited(_deletePackage(previousPackageId));
    }

    state = const WalletLinkState(phase: WalletLinkPhase.preparing);

    try {
      final upload = await _createUpload();
      if (epoch != _epoch) return;

      final lifetime = walletLinkDisplayLifetime(
        localLifetime: ref.read(walletLinkLocalLifetimeProvider),
        relayTtlSeconds: upload.relayTtlSeconds,
      );
      if (lifetime <= Duration.zero) {
        throw StateError('The mobile link expired before it could be shown.');
      }
      final expiresAt = DateTime.now().add(lifetime);
      _remotePackageId = upload.packageId;
      _activeKeyBytes = upload.keyBytes;
      state = WalletLinkState(
        phase: WalletLinkPhase.ready,
        qrPayload: upload.qrPayload,
        packageId: upload.packageId,
        expiresAt: expiresAt,
        remaining: lifetime,
        accountCount: upload.accountCount,
        contactCount: upload.contactCount,
      );
      _startReadyLoop(epoch, upload.packageId, expiresAt);
    } catch (error, stackTrace) {
      if (epoch != _epoch) return;
      log('WalletLinkController.start: ERROR: $error\n$stackTrace');
      state = WalletLinkState(
        phase: WalletLinkPhase.error,
        errorMessage: _friendlyError(error),
      );
    }
  }

  Future<void> regenerate() => start();

  void expire() {
    _expire(deleteRemote: false);
  }

  void markLinkedForPreview({required int accounts, required int contacts}) {
    _timer?.cancel();
    _epoch++;
    state = WalletLinkState(
      phase: WalletLinkPhase.linked,
      accountCount: accounts,
      contactCount: contacts,
      actualImportCounts: true,
    );
  }

  Future<WalletLinkPackageUpload> _createUpload() async {
    final id = _newUuidV4();
    final keyBytes = _randomBytes(32);
    final completionToken = _base64UrlNoPadding(_randomBytes(32));
    final payload = await _buildTransferPayload();
    final envelope = await _encryptPayload(payload, keyBytes: keyBytes);
    final completionTokenHash = await _sha256Base64UrlNoPadding(
      completionToken,
    );
    final createResponse = await _client.createPackage(
      WalletLinkCreatePackageRequest(
        id: id,
        envelope: envelope,
        completionTokenHash: completionTokenHash,
      ),
    );
    if (createResponse.id != id) {
      throw const FormatException('Wallet link package response id mismatch.');
    }

    final qrPayload = Uri(
      scheme: 'vizor',
      host: 'wallet-link',
      path: '/v1',
      queryParameters: {
        'id': id,
        'key': _base64UrlNoPadding(keyBytes),
        'completion': completionToken,
      },
    ).toString();

    final accountCount = (payload['accounts'] as List<Object?>).length;
    final contactCount = (payload['contacts'] as List<Object?>).length;
    return WalletLinkPackageUpload(
      packageId: id,
      qrPayload: qrPayload,
      keyBytes: keyBytes,
      relayTtlSeconds: createResponse.ttlSeconds,
      accountCount: accountCount,
      contactCount: contactCount,
    );
  }

  Future<Map<String, Object?>> _buildTransferPayload() async {
    final accountState = await ref.read(accountProvider.future);
    if (accountState.accounts.isEmpty) {
      throw StateError('No wallet accounts are available to link.');
    }

    final dbPath = await getWalletDbPath();
    final endpoint = ref.read(rpcEndpointProvider);
    final network = endpoint.networkName;
    final accountNotifier = ref.read(accountProvider.notifier);
    final accounts = <Map<String, Object?>>[];
    for (final account in accountState.accounts) {
      final birthdayHeight = await rust_sync.getExportBirthdayHeight(
        dbPath: dbPath,
        network: network,
        accountUuid: account.uuid,
      );
      final exportMetadata = await rust_wallet.getAccountExportMetadata(
        dbPath: dbPath,
        network: network,
        accountUuid: account.uuid,
      );
      final zip32AccountIndex = exportMetadata.zip32AccountIndex;
      final hardwareUfvk = exportMetadata.hardwareUfvk;
      final seedFingerprint = exportMetadata.seedFingerprint;
      final mnemonic = account.isHardware
          ? null
          : await accountNotifier.getMnemonicForAccount(account.uuid);
      if (!account.isHardware && (mnemonic == null || mnemonic.isEmpty)) {
        throw StateError('Unlock this wallet before linking mobile.');
      }
      if (!account.isHardware && zip32AccountIndex == null) {
        throw StateError(
          'Wallet account derivation metadata is not available.',
        );
      }
      if (account.isHardware &&
          (zip32AccountIndex == null ||
              hardwareUfvk == null ||
              seedFingerprint == null)) {
        throw StateError('Hardware wallet metadata is not available.');
      }
      accounts.add({
        'uuid': account.uuid,
        'name': account.name,
        'order': account.order,
        'isHardware': account.isHardware,
        'isSeedAnchor': account.isSeedAnchor,
        'hardwareKind': account.isHardware
            ? kWalletLinkHardwareKindKeystone
            : null,
        'profilePictureId': account.profilePictureId,
        'birthdayHeight': birthdayHeight.toInt(),
        'zip32AccountIndex': zip32AccountIndex,
        'ufvk': account.isHardware ? hardwareUfvk : null,
        'seedFingerprint': account.isHardware
            ? seedFingerprint!.toList()
            : null,
        'mnemonic': mnemonic,
      });
    }

    final contacts = await ref.read(addressBookProvider.future);
    return {
      'version': 1,
      'exportedAt': DateTime.now().toUtc().toIso8601String(),
      'network': network,
      'activeAccountUuid': accountState.activeAccountUuid,
      'accounts': accounts,
      'contacts': [for (final contact in contacts.contacts) contact.toJson()],
    };
  }

  Future<WalletLinkEnvelope> _encryptPayload(
    Map<String, Object?> payload, {
    required Uint8List keyBytes,
  }) async {
    final nonce = _randomBytes(12);
    final algorithm = AesGcm.with256bits();
    final secretBox = await algorithm.encrypt(
      utf8.encode(jsonEncode(payload)),
      secretKey: SecretKey(keyBytes),
      nonce: nonce,
    );
    return WalletLinkEnvelope(
      algorithm: 'aes-256-gcm',
      nonce: _base64UrlNoPadding(nonce),
      ciphertext: _base64UrlNoPadding(Uint8List.fromList(secretBox.cipherText)),
      tag: _base64UrlNoPadding(Uint8List.fromList(secretBox.mac.bytes)),
    );
  }

  void _startReadyLoop(int epoch, String packageId, DateTime expiresAt) {
    _timer?.cancel();
    unawaited(_pollForCompletion(epoch, packageId));
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (epoch != _epoch) return;
      final remaining = expiresAt.difference(DateTime.now());
      if (remaining <= Duration.zero) {
        _expire(deleteRemote: false);
        return;
      }
      state = state.copyWith(remaining: remaining);
      unawaited(_pollForCompletion(epoch, packageId));
    });
  }

  Future<void> _pollForCompletion(int epoch, String packageId) async {
    if (_statusPollEpoch == epoch) return;
    _statusPollEpoch = epoch;
    try {
      final status = await _client.getPackageStatus(packageId);
      if (epoch != _epoch ||
          state.phase != WalletLinkPhase.ready ||
          !status.isCompleted) {
        return;
      }
      final importSummary = await _decryptCompletionSummary(status);
      if (epoch != _epoch || state.phase != WalletLinkPhase.ready) {
        return;
      }
      _timer?.cancel();
      _remotePackageId = null;
      _activeKeyBytes = null;
      _lastStatusPollErrorLogKey = null;
      state = WalletLinkState(
        phase: WalletLinkPhase.linked,
        accountCount: importSummary?.importedAccountCount ?? state.accountCount,
        contactCount: importSummary?.importedContactCount ?? state.contactCount,
        actualImportCounts: importSummary != null,
      );
    } on WalletLinkApiException catch (error) {
      if (epoch != _epoch) return;
      if (error.statusCode == 404 || error.statusCode == 410) {
        _expire(deleteRemote: false);
      } else {
        _logStatusPollError(error);
      }
    } catch (error, stackTrace) {
      _logStatusPollError(error, stackTrace);
    } finally {
      if (_statusPollEpoch == epoch) {
        _statusPollEpoch = null;
      }
    }
  }

  void _expire({required bool deleteRemote}) {
    _timer?.cancel();
    _epoch++;
    _statusPollEpoch = null;
    _lastStatusPollErrorLogKey = null;
    final packageId = _remotePackageId;
    _remotePackageId = null;
    _activeKeyBytes = null;
    if (deleteRemote && packageId != null) {
      unawaited(_deletePackage(packageId));
    }
    state = WalletLinkState(
      phase: WalletLinkPhase.expired,
      accountCount: state.accountCount,
      contactCount: state.contactCount,
    );
  }

  Future<void> _deletePackage(String packageId) async {
    try {
      await ref.read(walletLinkApiClientProvider).deletePackage(packageId);
    } catch (error, stackTrace) {
      log('WalletLinkController.deletePackage: ERROR: $error\n$stackTrace');
      // Explicit replacement is best-effort. Backend TTL remains the fallback
      // if this cleanup cannot reach Lambda/DynamoDB.
    }
  }

  void _dispose() {
    _timer?.cancel();
    _epoch++;
    _statusPollEpoch = null;
    _lastStatusPollErrorLogKey = null;
    _remotePackageId = null;
    _activeKeyBytes = null;
  }

  Uint8List _randomBytes(int length) {
    return Uint8List.fromList([
      for (var i = 0; i < length; i++) _random.nextInt(256),
    ]);
  }

  String _newUuidV4() {
    final bytes = _randomBytes(16);
    bytes[6] = (bytes[6] & 0x0f) | 0x40;
    bytes[8] = (bytes[8] & 0x3f) | 0x80;
    final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-'
        '${hex.substring(12, 16)}-${hex.substring(16, 20)}-'
        '${hex.substring(20)}';
  }

  static String _base64UrlNoPadding(Uint8List bytes) {
    return base64UrlEncode(bytes).replaceAll('=', '');
  }

  static Future<String> _sha256Base64UrlNoPadding(String value) async {
    final digest = await Sha256().hash(utf8.encode(value));
    return base64UrlEncode(digest.bytes).replaceAll('=', '');
  }

  void _logStatusPollError(Object error, [StackTrace? stackTrace]) {
    final key = error.toString();
    if (_lastStatusPollErrorLogKey == key) return;
    _lastStatusPollErrorLogKey = key;
    final suffix = stackTrace == null ? '' : '\n$stackTrace';
    log('WalletLinkController.statusPoll: ERROR: $error$suffix');
  }

  Future<WalletLinkImportSummary?> _decryptCompletionSummary(
    WalletLinkPackageStatus status,
  ) async {
    final envelope = status.completionEnvelope;
    final keyBytes = _activeKeyBytes;
    if (envelope == null || keyBytes == null) {
      return null;
    }
    try {
      return await decryptWalletLinkImportSummary(
        envelope: envelope,
        keyBytes: keyBytes,
      );
    } catch (error, stackTrace) {
      log(
        'WalletLinkController.completionSummary: ERROR: '
        '$error\n$stackTrace',
      );
      return null;
    }
  }

  static String _friendlyError(Object error) {
    if (error is StateError) return error.message;
    if (error is WalletLinkApiException ||
        error is IOException ||
        error is TimeoutException) {
      return 'Could not reach the linking server. Try again.';
    }
    return 'Could not prepare the mobile link. Try again.';
  }

  WalletLinkApiClient get _client {
    final client = _apiClient;
    if (client != null) return client;
    return ref.read(walletLinkApiClientProvider);
  }
}
