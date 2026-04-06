import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../main.dart' show log;
import 'account_provider.dart';

class WalletState {
  final bool hasWallet;
  final String? unifiedAddress;
  final String? network;
  final String? activeAccountUuid;

  const WalletState({
    this.hasWallet = false,
    this.unifiedAddress,
    this.network,
    this.activeAccountUuid,
  });
}

class WalletNotifier extends AsyncNotifier<WalletState> {
  @override
  Future<WalletState> build() async {
    final accountState = ref.watch(accountProvider);

    return accountState.when(
      data: (state) {
        if (!state.hasAccounts) return const WalletState();
        return WalletState(
          hasWallet: true,
          unifiedAddress: state.activeAddress,
          activeAccountUuid: state.activeAccountUuid,
        );
      },
      loading: () => const WalletState(),
      error: (e, st) {
        log('WalletNotifier: error from accountProvider: $e');
        Error.throwWithStackTrace(e, st);
      },
    );
  }
}

final walletProvider =
    AsyncNotifierProvider<WalletNotifier, WalletState>(WalletNotifier.new);
