import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/network_config.dart';
import '../../../providers/account_provider.dart';
import '../../../providers/rpc_endpoint_provider.dart';
import '../../../rust/api/sync.dart' as rust_sync;
import '../../address_book/models/address_book_contact.dart';
import '../../pay/providers/cross_chain_payment_request_provider.dart';
import '../../swap/providers/swap_state_provider.dart';
import 'address_input_policy.dart';

/// Context identity excludes quote polling, balances and other unrelated state.
Object addressInputContextKey(WidgetRef ref, {bool includeSwap = false}) {
  final wallet = (
    ref.read(accountProvider).value?.activeAccountUuid,
    ref.read(rpcEndpointProvider).networkName,
  );
  if (!includeSwap) return wallet;
  final swap = ref.read(swapStateProvider);
  return (wallet, swap.externalAsset, swap.direction, swap.payMode);
}

Future<AddressInputResult> resolveWalletAddressInput(
  WidgetRef ref,
  String raw, {
  required AddressInputContext context,
  AddressBookNetwork? network,
}) {
  final walletNetwork = zcashNetworkFromName(
    ref.read(rpcEndpointProvider).networkName,
  );
  final usesSwap =
      context != AddressInputContext.send &&
      context != AddressInputContext.contact;
  final swap = usesSwap ? ref.read(swapStateProvider) : null;
  final selectedNetwork =
      network ??
      (context == AddressInputContext.send
          ? AddressBookNetwork.zcash
          : AddressBookNetwork.tryFromChainTicker(
              swap?.externalAsset.chainTicker ?? '',
            ));
  if (selectedNetwork == null) {
    return Future.value(
      const AddressInputResult.rejected(
        'This network is not supported for address input.',
      ),
    );
  }
  final parser = ref.read(crossChainPaymentParserProvider);
  return resolveAddressInput(
    raw,
    policy: AddressInputPolicy(
      context: context,
      network: selectedNetwork,
      zcashNetwork: walletNetwork,
      assets: swap?.supportedExternalAssets ?? const [],
    ),
    validateZcashAddress: (address, network) async {
      final result = await rust_sync.validateAddress(
        address: address,
        network: network.name,
      );
      if (result.isValid) return null;
      return result.wrongNetwork
          ? 'This address or request uses a different network.'
          : 'Enter a valid Zcash address.';
    },
    parseCrossChainRequest: parser,
  );
}
