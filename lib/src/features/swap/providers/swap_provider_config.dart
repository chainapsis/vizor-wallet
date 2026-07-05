import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/storage/app_secure_store.dart';
import '../../../providers/account_provider.dart';
import '../../../providers/receive_address_provider.dart';
import '../../../providers/zec_price_change_provider.dart';
import '../../../rust/api/swap_zwap.dart' as zwap;
import '../integrations/near_intents/near_intents_one_click_swap_adapter.dart';
import '../integrations/zwap/zwap_intent_store.dart';
import '../integrations/zwap/zwap_swap_adapter.dart';
import '../integrations/zwap/zwap_swap_config.dart';
import '../models/swap_models.dart';

final _oneClickBaseUri = Uri.parse(
  'https://functions.vizor.cash/api/near-intents/1click',
);

/// The active swap backend. Build-time switch (`VIZOR_SWAP_BACKEND=zwap`):
/// `near` → custodial NEAR Intents aggregator; `zwap` → the non-custodial
/// BTC↔ZEC atomic-swap engine.
final swapIntentProvider = Provider<SwapProvider>((ref) {
  switch (kSwapBackend) {
    case SwapBackend.zwap:
      // Keep the (autoDispose) ZEC/USD price source alive for the life of the
      // swap provider without rebuilding the adapter on price ticks: `listen`
      // subscribes (preventing auto-dispose) but does not recompute this
      // provider. The adapter reads the latest value lazily below.
      ref.listen(zecHomeUsdUnitPriceProvider, (previous, next) {});
      return ZwapSwapAdapter(
        client: ref.read(zwapSwapClientProvider),
        seedHex: () => _activeZwapSeedHex(ref),
        newReceiveRawAddress: () => _freshReceiveRawHex(ref),
        // Reuse the wallet's ZEC/USD spot price (same source as the home
        // balance) so swap fiat "$" values render instead of `$--`. zwap has no
        // price oracle of its own. Read lazily so a price tick refreshes the
        // fiat basis without rebuilding the adapter (which would wipe in-flight
        // swaps from its in-memory `_intents`).
        zecUsdUnitPrice: () => ref.read(zecHomeUsdUnitPriceProvider),
        // Persist in-flight swap recovery material so a swap survives an app
        // restart. Scoped to (and resolved at call time for) the active account.
        store: AppSecureStoreZwapIntentStore(
          storage: AppSecureStore.instance,
          activeAccountUuid: () =>
              ref.read(accountProvider).value?.activeAccountUuid,
        ),
      );
    case SwapBackend.near:
      return NearIntentsOneClickSwapAdapter(
        baseUri: _oneClickBaseUri,
        referral: 'vizor',
      );
  }
});

/// Stable 32-byte zwap identity seed (hex) for the active account, derived from
/// its mnemonic. Domain-separated so it is distinct from the Zcash wallet seed.
/// Returns the wallet's own secret material only while unlocked.
Future<String> _activeZwapSeedHex(Ref ref) async {
  final mnemonic = await ref.read(accountProvider.notifier).getActiveMnemonic();
  if (mnemonic == null || mnemonic.isEmpty) {
    throw StateError(
      'zwap swap needs an unlocked software account seed '
      '(hardware/locked accounts are unsupported for atomic swaps)',
    );
  }
  final digest = sha256.convert(utf8.encode('zwap-identity-v1:$mnemonic'));
  return _toHex(digest.bytes);
}

/// Generate a FRESH Orchard receiver (43-byte raw hex) for the active account —
/// the joint-note sweep destination, committed to the order at creation. Uses
/// the wallet's own diversified-address generator (`renewShieldedAddress`), so
/// each swap sweeps to a new address (no reuse across swaps).
Future<String> _freshReceiveRawHex(Ref ref) async {
  final accountUuid =
      ref.read(accountProvider).value?.activeAccountUuid;
  if (accountUuid == null || accountUuid.isEmpty) {
    throw StateError('zwap swap: no active account to receive ZEC');
  }
  final ua = await ref
      .read(receiveAddressServiceProvider)
      .renewShieldedAddress(accountUuid: accountUuid);
  return zwap.zwapUnifiedToOrchardRawHex(unifiedAddress: ua);
}

String _toHex(List<int> bytes) =>
    bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();

/// Manual recovery entry point for an orphaned zwap b2z (BTC→ZEC) swap whose
/// full recovery record was lost (created before persistence existed).
///
/// Rebuilds the `_Settle` from the minimal `(seed, obSwapId, deriveId)` record
/// by re-deriving the joint ZEC material, drops it into the adapter's in-memory
/// map, persists it, and drives one status pass — which sweeps the joint note to
/// a fresh receiver in the active account. The wallet must be UNLOCKED (needs
/// the account seed) and the zwap backend must be active.
///
/// Invoke from a temporary debug trigger, e.g.:
///
/// ```dart
/// await recoverOrphanedZwapB2z(
///   ref,
///   obSwapId: 'c8e7feea-5d61-42f5-9921-7ed6ec26e28d',
///   deriveId: 'b2z-1782985727585764~9',
/// );
/// ```
Future<void> recoverOrphanedZwapB2z(
  Ref ref, {
  required String obSwapId,
  required String deriveId,
}) async {
  final provider = ref.read(swapIntentProvider);
  if (provider is! ZwapSwapAdapter) {
    throw StateError(
      'recoverOrphanedZwapB2z: active swap backend is not zwap',
    );
  }
  await provider.recoverOrphanedB2z(obSwapId: obSwapId, deriveId: deriveId);
}

final swapStatusPollIntervalProvider = Provider<Duration>((ref) {
  return const Duration(seconds: 20);
});

final swapPriceRefreshIntervalProvider = Provider<Duration>((ref) {
  return const Duration(seconds: 30);
});
