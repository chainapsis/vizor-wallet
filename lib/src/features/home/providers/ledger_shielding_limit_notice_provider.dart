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

/// Explains a Ledger account's missing shield action when the only blocker is
/// the device's transparent-input limit. Null whenever shielding is allowed,
/// the active account is not a Ledger, or the block has another cause.
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
      sync.canShield ||
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
