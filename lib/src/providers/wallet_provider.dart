import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path_provider/path_provider.dart';

import '../rust/api/wallet.dart' as rust_wallet;

const _mnemonicKey = 'zcash_wallet_mnemonic';
const _networkKey = 'zcash_wallet_network';

class WalletState {
  final bool hasWallet;
  final String? unifiedAddress;
  final String? network;

  const WalletState({
    this.hasWallet = false,
    this.unifiedAddress,
    this.network,
  });

  WalletState copyWith({
    bool? hasWallet,
    String? unifiedAddress,
    String? network,
  }) =>
      WalletState(
        hasWallet: hasWallet ?? this.hasWallet,
        unifiedAddress: unifiedAddress ?? this.unifiedAddress,
        network: network ?? this.network,
      );
}

class WalletNotifier extends AsyncNotifier<WalletState> {
  static const _storage = FlutterSecureStorage();

  @override
  Future<WalletState> build() async {
    final dbPath = await _getDbPath();
    final exists = rust_wallet.walletExists(dbPath: dbPath);
    if (!exists) {
      return const WalletState();
    }

    final network = await _storage.read(key: _networkKey) ?? 'main';
    try {
      final address = await rust_wallet.getUnifiedAddress(
        dbPath: dbPath,
        network: network,
      );
      return WalletState(
        hasWallet: true,
        unifiedAddress: address,
        network: network,
      );
    } catch (_) {
      return const WalletState();
    }
  }

  /// Create a new wallet. Returns the mnemonic that must be shown to the user.
  Future<String> createWallet({String network = 'main'}) async {
    final dbPath = await _getDbPath();
    final result = await rust_wallet.createWallet(
      network: network,
      dbPath: dbPath,
    );

    // Store mnemonic securely
    await _storage.write(key: _mnemonicKey, value: result.mnemonic);
    await _storage.write(key: _networkKey, value: network);

    state = AsyncData(WalletState(
      hasWallet: true,
      unifiedAddress: result.unifiedAddress,
      network: network,
    ));

    return result.mnemonic;
  }

  /// Import a wallet from an existing mnemonic.
  Future<void> importWallet({
    required String mnemonic,
    int? birthdayHeight,
    String network = 'main',
  }) async {
    final dbPath = await _getDbPath();
    final result = await rust_wallet.importWallet(
      mnemonic: mnemonic,
      birthdayHeight:
          birthdayHeight != null ? BigInt.from(birthdayHeight) : null,
      network: network,
      dbPath: dbPath,
    );

    await _storage.write(key: _mnemonicKey, value: mnemonic);
    await _storage.write(key: _networkKey, value: network);

    state = AsyncData(WalletState(
      hasWallet: true,
      unifiedAddress: result.unifiedAddress,
      network: network,
    ));
  }

  Future<String> _getDbPath() async {
    final dir = await getApplicationDocumentsDirectory();
    return '${dir.path}${Platform.pathSeparator}zcash_wallet.db';
  }
}

final walletProvider =
    AsyncNotifierProvider<WalletNotifier, WalletState>(WalletNotifier.new);
