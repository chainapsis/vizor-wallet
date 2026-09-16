import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../providers/account_provider.dart';
import '../../../providers/rpc_endpoint_provider.dart';
import '../../../providers/sync_provider.dart';
import '../../../rust/api/sync.dart' as rust_sync;
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

class LedgerShieldingCapacity {
  const LedgerShieldingCapacity({
    required this.inputCount,
    required this.inputLimit,
  });

  final int inputCount;
  final int inputLimit;

  int get approvalCount => (inputCount + inputLimit - 1) ~/ inputLimit;
}

/// Reports when the active Ledger needs more than one device approval to
/// shield its transparent inputs. Presentation layers own the displayed copy.
final ledgerShieldingCapacityProvider =
    FutureProvider.autoDispose<LedgerShieldingCapacity?>((ref) async {
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
      final status = await ref.watch(ledgerShieldStatusReaderProvider)(
        dbPath: await ref.watch(ledgerWalletDbPathProvider)(),
        network: ref.watch(rpcEndpointProvider).networkName,
        accountUuid: activeUuid,
      );
      final limit = status.ledgerInputLimit;
      if (limit == null || status.transparentInputCount <= limit) return null;
      return LedgerShieldingCapacity(
        inputCount: status.transparentInputCount,
        inputLimit: limit,
      );
    });
