import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/storage/wallet_paths.dart';
import '../../../providers/rpc_endpoint_provider.dart';
import '../../../rust/api/ledger.dart' as rust_ledger;
import '../ledger_capability.dart';
import 'ledger_connection_service.dart';
import 'ledger_mobile_ble_service.dart';

typedef LedgerPcztSigner =
    Future<List<int>> Function(String accountUuid, List<int> pcztBytes);
typedef LedgerVotingPcztSigner =
    Future<List<LedgerVotingSignature>> Function(
      String accountUuid,
      List<int> pcztBytes,
    );
typedef LedgerOperationCanceller = Future<void> Function();
typedef LedgerWalletDbPathLoader = Future<String> Function();

final ledgerWalletDbPathProvider = Provider<LedgerWalletDbPathLoader>((_) {
  return getWalletDbPath;
});

final ledgerRustOperationCancellerProvider = Provider<LedgerOperationCanceller>(
  (_) => rust_ledger.ledgerCancelOperation,
);

class LedgerVotingSignature {
  const LedgerVotingSignature({
    required this.pool,
    required this.actionIndex,
    required this.signature,
  });

  final int pool;
  final int actionIndex;
  final List<int> signature;
}

LedgerVotingSignature requireMatchingLedgerVotingSignature({
  required List<LedgerVotingSignature> signatures,
  required int actionIndex,
}) {
  if (signatures.length != 1) {
    throw StateError(
      'Ledger returned a different number of voting signatures than requested.',
    );
  }
  final signature = signatures.single;
  if (signature.pool != 1 ||
      signature.actionIndex != actionIndex ||
      signature.signature.length != 64) {
    throw StateError(
      'Ledger returned a voting signature that does not match this bundle.',
    );
  }
  return signature;
}

final ledgerOperationCancellerProvider = Provider<LedgerOperationCanceller>((
  ref,
) {
  return () async {
    await ref.read(ledgerRustOperationCancellerProvider)();
    try {
      await ref.read(ledgerMobileBleServiceProvider).cancelSigning();
    } catch (_) {
      // Only one transport can own the active operation. Cancelling the idle
      // transport is best-effort and must not hide the real cancellation.
    }
  };
});

final ledgerPcztSignerProvider = Provider<LedgerPcztSigner>((ref) {
  final capability = ref.watch(ledgerStaticCapabilityProvider);
  final loadWalletDbPath = ref.watch(ledgerWalletDbPathProvider);
  final networkName = ref.watch(
    rpcEndpointProvider.select((endpoint) => endpoint.networkName),
  );
  return (accountUuid, pcztBytes) async {
    capability.requireSupported();
    final dbPath = await loadWalletDbPath();
    return ref
        .read(ledgerConnectionServiceProvider)
        .run(
          accountUuid: accountUuid,
          usb: () => rust_ledger.ledgerSignPcztFull(
            dbPath: dbPath,
            accountUuid: accountUuid,
            pcztBytes: pcztBytes,
            network: networkName,
          ),
          bluetooth: (mobile) async {
            final plan = await rust_ledger.ledgerBuildPcztFullSigningApduPlan(
              dbPath: dbPath,
              accountUuid: accountUuid,
              pcztBytes: pcztBytes,
              network: networkName,
            );
            final responses = await mobile.exchangeApdus(plan.commands);
            return rust_ledger.ledgerFinalizeMobilePcztFullSigning(
              dbPath: dbPath,
              accountUuid: accountUuid,
              pcztBytes: pcztBytes,
              network: networkName,
              responses: responses,
            );
          },
        );
  };
});

/// Compact signing boundary used by voting delegation bundles.
///
/// Voting deliberately consumes only action signatures, not a transaction-like
/// signed PCZT. The host memo associated with the request is not asserted to be
/// clear-sign metadata displayed by the current Ledger Zcash app.
final ledgerVotingPcztSignerProvider = Provider<LedgerVotingPcztSigner>((ref) {
  final capability = ref.watch(ledgerStaticCapabilityProvider);
  final loadWalletDbPath = ref.watch(ledgerWalletDbPathProvider);
  final networkName = ref.watch(
    rpcEndpointProvider.select((endpoint) => endpoint.networkName),
  );
  return (accountUuid, pcztBytes) async {
    capability.requireSupported();
    final dbPath = await loadWalletDbPath();
    final signatures = await ref
        .read(ledgerConnectionServiceProvider)
        .run(
          accountUuid: accountUuid,
          usb: () => rust_ledger.ledgerSignPczt(
            dbPath: dbPath,
            accountUuid: accountUuid,
            pcztBytes: pcztBytes,
            network: networkName,
          ),
          bluetooth: (mobile) => _signMobileVotingPczt(
            mobile: mobile,
            dbPath: dbPath,
            accountUuid: accountUuid,
            pcztBytes: pcztBytes,
            networkName: networkName,
          ),
        );
    return [
      for (final signature in signatures)
        LedgerVotingSignature(
          pool: signature.pool,
          actionIndex: signature.actionIndex,
          signature: signature.sig,
        ),
    ];
  };
});

Future<List<rust_ledger.LedgerActionSig>> _signMobileVotingPczt({
  required LedgerMobileBleService mobile,
  required String dbPath,
  required String accountUuid,
  required List<int> pcztBytes,
  required String networkName,
}) async {
  final plan = await rust_ledger.ledgerBuildPcztSigningApduPlan(
    dbPath: dbPath,
    accountUuid: accountUuid,
    pcztBytes: pcztBytes,
    network: networkName,
  );
  final responses = await mobile.exchangeApdus(plan.commands);
  return rust_ledger.ledgerFinalizeMobilePcztSigning(
    dbPath: dbPath,
    accountUuid: accountUuid,
    pcztBytes: pcztBytes,
    network: networkName,
    responses: responses,
  );
}
