import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../main.dart' show log;
import '../app_bootstrap.dart';
import '../core/config/network_config.dart';
import '../core/storage/wallet_paths.dart';
import '../rust/api/sync.dart' as rust_sync;
import '../rust/api/wallet.dart' as rust_wallet;
import 'account_provider.dart';

final receiveAddressServiceProvider = Provider<ReceiveAddressService>((ref) {
  return ReceiveAddressService(ref);
});

class ReceiveAddressBusyException implements Exception {
  const ReceiveAddressBusyException(this.cause);

  final Object cause;

  @override
  String toString() {
    return 'Wallet is busy. Try again in a moment.';
  }
}

enum ReceiveAddressRequest {
  shielded('shielded'),
  orchard('orchard');

  const ReceiveAddressRequest(this.wireName);

  final String wireName;
}

class ReceiveAddressService {
  ReceiveAddressService(this._ref);

  static const _databaseLockRetryDelays = [
    Duration(milliseconds: 300),
    Duration(seconds: 1),
    Duration(seconds: 2),
  ];

  final Ref _ref;
  final Map<String, String> _transparentAddressCache = {};

  Future<String> loadShieldedAddress({
    required String accountUuid,
    String? currentShieldedAddress,
  }) async {
    if (currentShieldedAddress != null && currentShieldedAddress.isNotEmpty) {
      return currentShieldedAddress;
    }

    final dbPath = await getWalletDbPath();
    final network = _network;

    return _withDatabaseLockRetry(
      operationName: 'load shielded receive address',
      operation: () => rust_wallet.getUnifiedAddress(
        dbPath: dbPath,
        network: network,
        accountUuid: accountUuid,
      ),
    );
  }

  String? getCachedTransparentAddress(String accountUuid) {
    return _transparentAddressCache[accountUuid];
  }

  Future<String> loadTransparentAddress({required String accountUuid}) async {
    final cached = _transparentAddressCache[accountUuid];
    if (cached != null) return cached;

    final dbPath = await getWalletDbPath();
    final network = _network;

    final transparentAddress = await _withDatabaseLockRetry(
      operationName: 'load transparent address',
      operation: () => rust_wallet.getTransparentAddress(
        dbPath: dbPath,
        network: network,
        accountUuid: accountUuid,
      ),
    );

    _transparentAddressCache[accountUuid] = transparentAddress;
    return transparentAddress;
  }

  Future<String> loadTransparentReceiveAddress({
    required String accountUuid,
  }) async {
    final dbPath = await getWalletDbPath();
    final network = _network;

    final transparentAddress = await _withDatabaseLockRetry(
      operationName: 'load transparent receive address',
      operation: () => rust_wallet.getTransparentReceiveAddress(
        dbPath: dbPath,
        network: network,
        accountUuid: accountUuid,
      ),
    );

    _transparentAddressCache[accountUuid] = transparentAddress;
    return transparentAddress;
  }

  Future<String> renewShieldedAddress({required String accountUuid}) async {
    final dbPath = await getWalletDbPath();
    final network = _network;
    final accountNotifier = _ref.read(accountProvider.notifier);
    final addressRequest = accountNotifier.isHardwareAccount(accountUuid)
        ? ReceiveAddressRequest.orchard
        : ReceiveAddressRequest.shielded;

    final address = await _withDatabaseLockRetry(
      operationName: 'renew shielded receive address',
      operation: () => rust_sync.getNextAvailableAddress(
        dbPath: dbPath,
        network: network,
        accountUuid: accountUuid,
        addressRequest: addressRequest.wireName,
      ),
    );

    accountNotifier.updateActiveAddressForAccount(accountUuid, address);
    return address;
  }

  String get _network {
    final network = _ref.read(appBootstrapProvider).network;
    return network.isEmpty ? kZcashDefaultNetworkName : network;
  }

  Future<T> _withDatabaseLockRetry<T>({
    required String operationName,
    required Future<T> Function() operation,
  }) async {
    for (var attempt = 0; ; attempt++) {
      try {
        return await operation();
      } catch (e) {
        if (!_isDatabaseLockedError(e)) rethrow;

        if (attempt >= _databaseLockRetryDelays.length) {
          log(
            'ReceiveAddressService: $operationName failed after '
            '${attempt + 1} attempts: $e',
          );
          throw ReceiveAddressBusyException(e);
        }

        final delay = _databaseLockRetryDelays[attempt];
        log(
          'ReceiveAddressService: $operationName hit locked DB; retrying in '
          '${delay.inMilliseconds}ms (attempt ${attempt + 1}/'
          '${_databaseLockRetryDelays.length + 1})',
        );
        await Future<void>.delayed(delay);
      }
    }
  }

  bool _isDatabaseLockedError(Object error) {
    final message = error.toString().toLowerCase();
    return message.contains('database is locked') ||
        message.contains('database table is locked') ||
        message.contains('database is busy') ||
        message.contains('database busy') ||
        message.contains('databasebusy') ||
        message.contains('databaselocked') ||
        message.contains('sqlite_busy') ||
        message.contains('sqlite_locked');
  }
}
