import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../main.dart' show log;
import '../../../core/storage/wallet_paths.dart';
import '../../../providers/account_provider.dart';
import '../../../providers/rpc_endpoint_provider.dart';
import '../../../rust/api/wallet.dart' as rust_wallet;

/// Current unified and transparent address of every local account, keyed by the
/// trimmed address. Used by send review surfaces to recognize a recipient as
/// one of the user's own accounts without persisting addresses in [AccountInfo].
///
/// Address rotation caveat: only each account's CURRENT addresses are matched;
/// an older rotated address of the same account is not recognized.
final ownAccountAddressesProvider = FutureProvider<Map<String, AccountInfo>>((
  ref,
) async {
  final accounts = ref.watch(
    accountProvider.select((state) => state.value?.accounts ?? const []),
  );
  if (accounts.isEmpty) return const <String, AccountInfo>{};

  final network = ref.watch(rpcEndpointProvider).networkName;
  final dbPath = await getWalletDbPath();
  final byAddress = <String, AccountInfo>{};
  for (final account in accounts) {
    await _addOwnAccountAddress(
      byAddress: byAddress,
      account: account,
      loadAddress: () => rust_wallet.getUnifiedAddress(
        dbPath: dbPath,
        network: network,
        accountUuid: account.uuid,
      ),
      addressKind: 'unified',
    );
    await _addOwnAccountAddress(
      byAddress: byAddress,
      account: account,
      loadAddress: () => rust_wallet.getTransparentAddress(
        dbPath: dbPath,
        network: network,
        accountUuid: account.uuid,
      ),
      addressKind: 'transparent',
    );
  }
  return byAddress;
});

Future<void> _addOwnAccountAddress({
  required Map<String, AccountInfo> byAddress,
  required AccountInfo account,
  required Future<String> Function() loadAddress,
  required String addressKind,
}) async {
  try {
    final address = (await loadAddress()).trim();
    if (address.isNotEmpty) byAddress[address] = account;
  } catch (e) {
    // Best-effort: an account whose address fails to load simply is not
    // recognized as a self-transfer target for that address kind.
    log(
      'ownAccountAddresses: $addressKind address load failed for '
      '${account.uuid}: $e',
    );
  }
}
