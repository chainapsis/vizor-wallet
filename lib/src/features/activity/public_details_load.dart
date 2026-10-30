import 'package:flutter_riverpod/misc.dart' show ProviderListenable;

import '../../core/storage/wallet_paths.dart';
import '../../providers/app_security_provider.dart';
import '../../providers/public_details_loads_provider.dart';
import '../../providers/rpc_endpoint_failover_provider.dart';
import '../../providers/sync_provider.dart';
import '../../rust/api/sync.dart' as rust_sync;

/// Reads a provider, as `WidgetRef.read` and `ProviderContainer.read` do.
typedef ProviderRead = T Function<T>(ProviderListenable<T> provider);

/// The native public load; injectable for tests.
typedef PublicTransactionEnhancer =
    Future<void> Function({
      required String dbPath,
      required String network,
      required String lightwalletdUrl,
      required String accountUuid,
      required String txidHex,
      required BigInt cancelEpoch,
    });

/// Loads [txidHex]'s full details for [accountUuid] from the server, after the
/// user confirmed it. Throws when the load did not store them.
///
/// It goes to the endpoint sync currently uses, which may be a failover. It
/// runs under [publicDetailsLoadsProvider], so a lock or a wallet change
/// stops it before anything is sent, even one that lands before the load
/// reaches Rust, and wallet deletion waits for it. A stored result notifies
/// [syncFollowupProvider], so open receipts and Activity feeds reload the rows
/// it changed.
Future<void> loadTransactionDetailsPublicly(
  ProviderRead read, {
  required String? accountUuid,
  required String txidHex,
  Future<String?> Function() existingWalletDbPath = getExistingWalletDbPath,
  PublicTransactionEnhancer enhance = rust_sync.enhanceTransactionPublicly,
}) async {
  final endpoint = read(rpcEndpointFailoverProvider).current;
  if (read(appSecurityProvider).requiresUnlock) {
    throw StateError('The wallet is locked.');
  }
  final followups = read(syncFollowupProvider.notifier);
  final ran = await read(publicDetailsLoadsProvider).run((ticket) async {
    // Never create a wallet database name for a load.
    final dbPath = await existingWalletDbPath();
    // A lock while the path was read leaves nothing to send.
    ticket.ensureNotCancelled();
    if (dbPath == null) throw StateError('The wallet is unavailable.');
    if (accountUuid == null) throw StateError('No account is active.');
    await enhance(
      dbPath: dbPath,
      network: endpoint.networkName,
      lightwalletdUrl: endpoint.normalizedLightwalletdUrl,
      accountUuid: accountUuid,
      txidHex: txidHex,
      cancelEpoch: ticket.cancelEpoch,
    );
  });
  if (!ran) throw StateError('The wallet is changing.');
  followups.updated();
}
