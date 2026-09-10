import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../providers/account_provider.dart';
import '../../../providers/rpc_endpoint_provider.dart';
import '../../../providers/sync_provider.dart';
import '../../../rust/api/sync.dart' as rust_sync;
import '../../ledger/ledger_error_messages.dart';
import '../../ledger/services/ledger_signing_service.dart'
    show ledgerWalletDbPathProvider;

typedef LedgerShieldStatusReader =
    Future<rust_sync.ShieldTransparentStatus> Function({
      required String dbPath,
      required String network,
      required String accountUuid,
    });

final ledgerShieldStatusReaderProvider = Provider<LedgerShieldStatusReader>(
  (_) => rust_sync.getShieldTransparentStatus,
);

/// Tells a Ledger account that one shielding round cannot take every
/// transparent input: the device limit leaves the rest for another round.
/// Null when the active account is not a Ledger, cannot shield right now,
/// holds no transparent balance, or fits within the limit.
final ledgerShieldingLimitNoticeProvider = FutureProvider.autoDispose<String?>((
  ref,
) async {
  final accounts = ref.watch(accountProvider).value;
  final activeUuid = accounts?.activeAccountUuid;
  if (accounts == null || activeUuid == null) return null;
  final isLedger = accounts.accounts.any(
    (account) =>
        account.uuid == activeUuid &&
        account.hardwareSignerKind == HardwareSignerKind.ledger,
  );
  if (!isLedger) return null;
  final sync = ref.watch(
    syncProvider.select(
      (state) => (
        accountUuid: state.value?.accountUuid,
        transparent: state.value?.transparentBalance ?? BigInt.zero,
        canShield: state.value?.canShieldTransparentBalance ?? false,
        completedAt: state.value?.lastSyncCompletedAt,
      ),
    ),
  );
  if (sync.accountUuid != activeUuid ||
      !sync.canShield ||
      sync.transparent <= BigInt.zero) {
    return null;
  }
  final dbPath = await ref.watch(ledgerWalletDbPathProvider)();
  final network = ref.watch(rpcEndpointProvider).networkName;
  final status = await ref.watch(ledgerShieldStatusReaderProvider)(
    dbPath: dbPath,
    network: network,
    accountUuid: activeUuid,
  );
  final limit = status.ledgerInputLimit;
  if (limit == null || status.transparentInputCount <= limit) return null;
  return ledgerShieldingInputLimitMessage(
    inputCount: status.transparentInputCount,
    limit: limit,
  );
});
