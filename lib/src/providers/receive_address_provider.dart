import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../main.dart' show log;
import '../app_bootstrap.dart';
import '../core/storage/wallet_paths.dart';
import '../rust/api/sync.dart' as rust_sync;
import '../rust/api/wallet.dart' as rust_wallet;
import 'account_provider.dart';

final receiveAddressServiceProvider = Provider<ReceiveAddressService>((ref) {
  return ReceiveAddressService(ref);
});

class ReceiveAddresses {
  const ReceiveAddresses({
    required this.shieldedAddress,
    required this.transparentAddress,
  });

  final String shieldedAddress;
  final String transparentAddress;
}

class ReceiveAddressBusyException implements Exception {
  const ReceiveAddressBusyException(this.cause);

  final Object cause;

  @override
  String toString() {
    return 'Wallet database is busy. Please try again in a moment.';
  }
}

class ReceiveAddressService {
  ReceiveAddressService(this._ref);

  static const _databaseLockRetryDelays = [
    Duration(milliseconds: 300),
    Duration(seconds: 1),
    Duration(seconds: 2),
  ];

  final Ref _ref;

  Future<ReceiveAddresses> loadAddresses({
    required String accountUuid,
    String? currentShieldedAddress,
  }) async {
    final dbPath = await getWalletDbPath();
    final network = _network;

    final String shieldedAddress;
    if (currentShieldedAddress != null) {
      shieldedAddress = currentShieldedAddress;
    } else {
      shieldedAddress = await _withDatabaseLockRetry(
        operationName: 'load shielded receive address',
        operation: () => rust_wallet.getUnifiedAddress(
          dbPath: dbPath,
          network: network,
          accountUuid: accountUuid,
        ),
      );
    }
    final transparentAddress = await _withDatabaseLockRetry(
      operationName: 'load transparent receive address',
      operation: () => rust_wallet.getTransparentAddress(
        dbPath: dbPath,
        network: network,
        accountUuid: accountUuid,
      ),
    );

    return ReceiveAddresses(
      shieldedAddress: shieldedAddress,
      transparentAddress: transparentAddress,
    );
  }

  Future<String> renewShieldedAddress({required String accountUuid}) async {
    final dbPath = await getWalletDbPath();
    final network = _network;

    final address = await _withDatabaseLockRetry(
      operationName: 'renew shielded receive address',
      operation: () => rust_sync.getNextAvailableAddress(
        dbPath: dbPath,
        network: network,
        accountUuid: accountUuid,
      ),
    );

    _ref
        .read(accountProvider.notifier)
        .updateActiveAddressForAccount(accountUuid, address);
    return address;
  }

  String get _network {
    final network = _ref.read(appBootstrapProvider).network;
    return network.isEmpty ? 'main' : network;
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
