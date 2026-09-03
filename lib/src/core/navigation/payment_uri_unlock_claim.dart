/// The post-unlock claim of a `zcash:` link parked while the wallet was locked.
///
/// `decidePaymentUriDrain` deliberately answers `wait` on `/unlock`, so the
/// unlock screens — not `_IncomingLinkHost` — own the handoff. This is
/// the provider-reading half of that: the two unlock screens (desktop and
/// mobile) call it so they cannot drift into two different claims.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app_bootstrap.dart';
import '../../features/send/models/send_prefill_args.dart';
import '../../providers/migration_send_gate_provider.dart'
    show migrationSendGateProvider;
import '../../providers/payment_uri_prefill_provider.dart';
import '../../providers/wallet_provider.dart';
import 'payment_uri_drain_policy.dart';

/// What the unlock screen should do once it has navigated to `/home`.
class PaymentUriUnlockClaim {
  const PaymentUriUnlockClaim({this.prefill, this.notice});

  /// Present this as a payment-request card. Null when nothing was parked, or
  /// when the link cannot be shown.
  final SendPrefillArgs? prefill;

  /// Say this instead — the link was claimed but is not being delivered.
  /// Null when there is nothing to say (nothing was parked).
  final String? notice;
}

/// Claims the parked payment-URI prefill after a successful unlock.
///
/// Call it *after* the post-unlock work (`restoreAfterUnlock`,
/// `refreshAfterUnlock`, `startSyncAnyway`) and before the `go('/home')`:
/// claiming earlier would clear the prefill with no way to recover it if any
/// of those threw, and the returned decision reads state those calls settle.
///
/// The claim is more than the TTL. `decidePaymentUriDrain` is the one place
/// that says whether a link can be shown at all, and its answer can change
/// across the unlock itself: `migrationSendGateProvider` reads an Ironwood
/// presentation that is still unresolved while locked, so a link that parked
/// under a false gate can land on a wallet whose Send the product has since
/// taken away. Running the same table here keeps the unlock claim and the
/// app-level drain on one decision rather than two.
PaymentUriUnlockClaim claimParkedPaymentUriAfterUnlock(WidgetRef ref) {
  final claimed = ref.read(paymentUriPrefillProvider.notifier).takeIfFresh();
  final prefill = claimed.prefill;
  if (prefill == null) {
    // `takeIfFresh` already applied the park TTL; `expired` is the only
    // no-prefill outcome the user needs told about.
    return PaymentUriUnlockClaim(
      notice: claimed.expired ? kPaymentUriExpiredMessage : null,
    );
  }

  final bootstrap = ref.read(appBootstrapProvider);
  final walletAsync = ref.read(walletProvider);
  final decision = decidePaymentUriDrain(
    hasParkedPrefill: true,
    // The age row already ran, inside the `takeIfFresh` above. Passing null
    // keeps one clock rather than two that can disagree.
    parkedFor: null,
    hasBlockingFailure: bootstrap.hasBlockingFailure,
    walletIsLoading: walletAsync.isLoading && walletAsync.value == null,
    walletHasError: walletAsync.hasError,
    hasWallet: walletAsync.value?.hasWallet ?? bootstrap.hasWallet,
    // Only reached from a successful unlock.
    isUnlocked: true,
    // The card is presented over `/home`, which is where the unlock is
    // heading. Asking about `/unlock` — still the current location here —
    // would answer "wait" for the handoff this very function is performing.
    matchedLocation: '/home',
    sendGatedByMigration: ref.read(migrationSendGateProvider),
  );

  return switch (decision.action) {
    // Whatever the policy would drop, drop here too, with its own sentence.
    PaymentUriDrainAction.dropWithMessage ||
    PaymentUriDrainAction.routeToWelcome => PaymentUriUnlockClaim(
      notice: decision.message,
    ),
    // `wait` and `routeToUnlock` cannot be reached from a successful unlock
    // landing on `/home`. If the table ever grows a row that can, presenting
    // is the answer that does not silently swallow a payment the user
    // deliberately opened — the prefill is already claimed either way.
    _ => PaymentUriUnlockClaim(prefill: prefill),
  };
}
