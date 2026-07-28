import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/ironwood_migration_privacy_lock_config.dart';
import '../../../core/layout/app_form_factor.dart';
import '../../../providers/app_security_provider.dart';
import '../models/ironwood_migration_phases.dart';
import 'ironwood_migration_coordinator_provider.dart';

const kIronwoodMigrationPrivacyIdleTimeout = Duration(minutes: 1);

final ironwoodMigrationPrivacyLockFeatureEnabledProvider = Provider<bool>((_) {
  return kIronwoodMigrationPrivacyLockEnabled;
});

final ironwoodMigrationPrivacyLockEligibleProvider = Provider<bool>((ref) {
  if (kAppFormFactor != AppFormFactor.desktop ||
      !ref.watch(ironwoodMigrationPrivacyLockFeatureEnabledProvider) ||
      ref.watch(appSecurityProvider).requiresUnlock) {
    return false;
  }

  final statuses = ref.watch(
    ironwoodMigrationCoordinatorProvider.select((state) => state.statuses),
  );
  return statuses.values.any(
    (status) =>
        status.activeRunId != null ||
        isIronwoodMigrationInProgressPhase(status.phase),
  );
});

class IronwoodMigrationPrivacyLockState {
  const IronwoodMigrationPrivacyLockState({
    required this.isLocked,
    this.lockedAt,
  });

  const IronwoodMigrationPrivacyLockState.unlocked()
    : isLocked = false,
      lockedAt = null;

  final bool isLocked;
  final DateTime? lockedAt;
}

class IronwoodMigrationPrivacyLockNotifier
    extends Notifier<IronwoodMigrationPrivacyLockState> {
  @override
  IronwoodMigrationPrivacyLockState build() {
    return const IronwoodMigrationPrivacyLockState.unlocked();
  }

  void lock({DateTime? at}) {
    if (state.isLocked) return;
    state = IronwoodMigrationPrivacyLockState(
      isLocked: true,
      lockedAt: at ?? DateTime.now(),
    );
  }

  void unlock() {
    if (!state.isLocked) return;
    state = const IronwoodMigrationPrivacyLockState.unlocked();
  }

  void clear() => unlock();
}

final ironwoodMigrationPrivacyLockProvider =
    NotifierProvider<
      IronwoodMigrationPrivacyLockNotifier,
      IronwoodMigrationPrivacyLockState
    >(IronwoodMigrationPrivacyLockNotifier.new);
