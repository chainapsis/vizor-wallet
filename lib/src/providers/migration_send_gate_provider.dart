import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/layout/app_form_factor.dart';
import '../features/migration/providers/ironwood_migration_announcement_provider.dart';
import 'account_provider.dart';
import 'sync_provider.dart';

/// Whether the product currently refuses to start a send because a Private
/// (Ironwood) migration holds the account's entire spendable balance.
///
/// A migration in the `resume` state has moved the funds out of Orchard and
/// not yet into a spendable Ironwood note, so `ironwoodBalance` is zero and
/// there is nothing to spend. Mobile Home disables its Send button on exactly
/// this predicate; the payment-URI drain reads the same provider so a `zcash:`
/// link cannot walk in through the side door and land the user on a send form
/// the Home screen would not have opened.
///
/// **Deliberately mobile-only.** This is the product's send gate, not a raw
/// balance predicate, and desktop has no such gate to mirror: the desktop Home
/// pane's `onSend` is an unconditional `context.push('/send')`, and
/// `AppMainSidebar` gates Pay (`payNavigationLocked`) and voting during a
/// migration but never Send. Widening the payment-URI drop to desktop would
/// therefore be a new desktop behaviour rather than an alignment, so the gate
/// is scoped to the form factor that actually has it. Flip the guard here —
/// not at the call sites — if desktop Home ever starts disabling Send.
final migrationSendGateProvider = Provider<bool>((ref) {
  if (kAppFormFactor != AppFormFactor.mobile) return false;

  final migrationCta = ref.watch(ironwoodHomeMigrationPresentationProvider);
  if (migrationCta.mode != IronwoodHomeMigrationCtaMode.resume) return false;

  final activeAccountUuid = ref.watch(
    accountProvider.select((value) => value.value?.activeAccountUuid),
  );
  final ironwoodBalance = ref.watch(
    syncProvider.select(
      (value) => (value.value ?? SyncState())
          .scopedToAccount(activeAccountUuid)
          .ironwoodBalance,
    ),
  );
  return ironwoodBalance <= BigInt.zero;
});
