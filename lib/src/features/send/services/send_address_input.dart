import '../../../core/config/network_config.dart';
import '../../../rust/api/sync.dart' as rust_sync;
import '../../address_book/models/address_book_contact.dart';
import '../../address_scan/domain/address_input_policy.dart';
import 'send_flow.dart' show kWrongNetworkAddressMessage;

/// Send accepts only Zcash input, without modifying the current composer.
Future<AddressInputResult> resolveSendAddressInput(
  String raw, {
  required String networkName,
  Future<rust_sync.AddressValidationResult> Function({
    required String address,
    required String network,
  })?
  validateAddress,
}) => resolveAddressInput(
  raw,
  policy: AddressInputPolicy(
    context: AddressInputContext.send,
    network: AddressBookNetwork.zcash,
    zcashNetwork: ZcashNetwork.values.firstWhere(
      (value) => value.name == networkName,
    ),
  ),
  validateZcashAddress: (address, network) async {
    final result = await (validateAddress ?? rust_sync.validateAddress)(
      address: address,
      network: network.name,
    );
    if (result.isValid) return null;
    if (result.wrongNetwork) return '$kWrongNetworkAddressMessage.';
    return 'Only Zcash addresses and payment requests can be scanned here.';
  },
  parseCrossChainRequest: (_) =>
      throw StateError('Send rejects cross-chain requests before parsing.'),
);
