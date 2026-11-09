import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../providers/rpc_endpoint_provider.dart';
import '../../../rust/api/sync.dart' as rust_sync;

/// Checks an address a Zcash name resolved to before a contact form lets
/// the user save it.
///
/// A typed contact address gets only the address book's quick format check.
/// A resolved address comes from a third-party server, so it goes through
/// the same Rust validator the send flow uses, for the wallet's network.
/// Overridable in tests.
final contactResolvedAddressValidatorProvider =
    Provider<Future<bool> Function(String address)>((ref) {
      final network = ref.watch(rpcEndpointProvider).networkName;
      return (address) async {
        final result = await rust_sync.validateAddress(
          address: address,
          network: network,
        );
        return result.isValid && !result.wrongNetwork;
      };
    });
