import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/ironwood_migration_privacy_lock_config.dart';
import '../../../core/layout/app_form_factor.dart';
import '../../../providers/account_provider.dart';
import '../../../providers/app_security_provider.dart';
import '../models/ironwood_migration_phases.dart';
import 'ironwood_migration_coordinator_provider.dart';

const kIronwoodMigrationPrivacyIdleTimeout = Duration(minutes: 1);

final ironwoodMigrationPrivacyLockFeatureEnabledProvider = Provider<bool>((_) {
  return kIronwoodMigrationPrivacyLockEnabled;
});

class IronwoodMigrationPrivacyLockSuppression {
  const IronwoodMigrationPrivacyLockSuppression({required this.token});

  final int token;
}

class IronwoodMigrationPrivacyLockSuppressionNotifier
    extends Notifier<IronwoodMigrationPrivacyLockSuppression?> {
  int _nextToken = 0;

  @override
  IronwoodMigrationPrivacyLockSuppression? build() => null;

  IronwoodMigrationPrivacyLockSuppression acquire() {
    final suppression = IronwoodMigrationPrivacyLockSuppression(
      token: _nextToken++,
    );
    state = suppression;
    return suppression;
  }

  void release(IronwoodMigrationPrivacyLockSuppression suppression) {
    if (state?.token != suppression.token) return;
    state = null;
  }
}

final ironwoodMigrationPrivacyLockSuppressionProvider =
    NotifierProvider<
      IronwoodMigrationPrivacyLockSuppressionNotifier,
      IronwoodMigrationPrivacyLockSuppression?
    >(IronwoodMigrationPrivacyLockSuppressionNotifier.new);

final ironwoodMigrationPrivacyLockRequiredProvider = Provider<bool>((ref) {
  if (kAppFormFactor != AppFormFactor.desktop ||
      !ref.watch(ironwoodMigrationPrivacyLockFeatureEnabledProvider) ||
      !(ref.watch(accountProvider).value?.accounts.isNotEmpty ?? false) ||
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

final ironwoodMigrationPrivacyLockEligibleProvider = Provider<bool>((ref) {
  return ref.watch(ironwoodMigrationPrivacyLockRequiredProvider) &&
      ref.watch(ironwoodMigrationPrivacyLockSuppressionProvider) == null;
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
