import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/storage/wallet_paths.dart';
import '../../../providers/account_provider.dart';
import '../../../providers/rpc_endpoint_provider.dart';
import '../../../rust/api/sync.dart' as rust_sync;
import '../../../rust/api/wallet.dart' as rust_wallet;
import '../../address_book/providers/address_book_provider.dart';
import '../models/wallet_link_models.dart';
import '../services/wallet_link_api_client.dart';
import '../wallet_link_config.dart';

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
  String? _remotePackageId;

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
    if (previousPackageId != null) {
      unawaited(_deletePackage(previousPackageId));
    }

    state = const WalletLinkState(phase: WalletLinkPhase.preparing);

    try {
      final upload = await _createUpload();
      if (epoch != _epoch) return;

      final lifetime = ref.read(walletLinkLocalLifetimeProvider);
      final expiresAt = DateTime.now().add(lifetime);
      _remotePackageId = upload.packageId;
      state = WalletLinkState(
        phase: WalletLinkPhase.ready,
        qrPayload: upload.qrPayload,
        packageId: upload.packageId,
        expiresAt: expiresAt,
        remaining: lifetime,
        accountCount: upload.accountCount,
        contactCount: upload.contactCount,
      );
      _startCountdown(epoch, expiresAt);
    } catch (error) {
      if (epoch != _epoch) return;
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
    );
  }

  Future<WalletLinkPackageUpload> _createUpload() async {
    final id = _newUuidV4();
    final keyBytes = _randomBytes(32);
    final payload = await _buildTransferPayload();
    final envelope = await _encryptPayload(payload, keyBytes: keyBytes);
    await _client.createPackage(
      WalletLinkCreatePackageRequest(id: id, envelope: envelope),
    );

    final endpoint = walletLinkBackendBaseUri().toString();
    final qrPayload = Uri(
      scheme: 'vizor',
      host: 'wallet-link',
      path: '/v1',
      queryParameters: {
        'id': id,
        'key': _base64UrlNoPadding(keyBytes),
        'endpoint': endpoint,
      },
    ).toString();

    final accountCount = (payload['accounts'] as List<Object?>).length;
    final contactCount = (payload['contacts'] as List<Object?>).length;
    return WalletLinkPackageUpload(
      packageId: id,
      qrPayload: qrPayload,
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

  void _startCountdown(int epoch, DateTime expiresAt) {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (epoch != _epoch) return;
      final remaining = expiresAt.difference(DateTime.now());
      if (remaining <= Duration.zero) {
        _expire(deleteRemote: false);
        return;
      }
      state = state.copyWith(remaining: remaining);
    });
  }

  void _expire({required bool deleteRemote}) {
    _timer?.cancel();
    _epoch++;
    final packageId = _remotePackageId;
    _remotePackageId = null;
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
    } catch (_) {
      // Explicit replacement is best-effort. Backend TTL remains the fallback
      // if this cleanup cannot reach Lambda/DynamoDB.
    }
  }

  void _dispose() {
    _timer?.cancel();
    _epoch++;
    _remotePackageId = null;
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

  static String _friendlyError(Object error) {
    if (error is StateError) return error.message;
    if (error is WalletLinkApiException) {
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
