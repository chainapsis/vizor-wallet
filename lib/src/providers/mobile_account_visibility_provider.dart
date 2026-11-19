import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app_bootstrap.dart';
import '../core/layout/app_form_factor.dart';
import '../core/storage/account_visibility_store.dart';
import '../core/storage/app_secure_store.dart';
import '../core/storage/linux_keyring_coordinator.dart';
import 'account_provider.dart';
import 'app_security_provider.dart';

final mobileAccountVisibilityStoreProvider =
    Provider<MobileAccountVisibilityStore>(
      (_) => MobileAccountVisibilityStore(AppSecureStore.instance),
    );

final mobileAccountVisibilityProvider =
    NotifierProvider<
      MobileAccountVisibilityNotifier,
      MobileAccountVisibilityConfig
    >(MobileAccountVisibilityNotifier.new);

class MobileAccountVisibilityNotifier
    extends Notifier<MobileAccountVisibilityConfig> {
  @override
  MobileAccountVisibilityConfig build() {
    final configuration = ref
        .watch(appBootstrapProvider)
        .mobileAccountVisibility;
    ref.listen(appSecurityProvider, (previous, next) {
      if (previous?.isPasswordConfigured == true &&
          !next.isPasswordConfigured) {
        state = const MobileAccountVisibilityConfig();
      }
    });
    return configuration;
  }

  Future<MobileAccountVisibilityRule?> change({
    required bool Function() isCurrent,
    required String? ruleId,
    Set<String>? accountIds,
    String? newPasscode,
    bool remove = false,
  }) => ref.read(linuxKeyringCoordinatorProvider).runMutation(() async {
    final security = ref.read(appSecurityProvider);
    if (!security.isUnlocked || !isCurrent()) {
      throw const SecureStorageSessionChangedException();
    }
    final current = state;
    final existing = current.rule(ruleId);
    if (ruleId != null && existing == null) {
      throw const SecureStorageSessionChangedException();
    }
    final accounts = ref.read(accountProvider).requireValue.accounts;
    final otherRules = current.rules
        .where((rule) => rule.id != ruleId)
        .toList();
    final otherIds = {for (final rule in otherRules) ...rule.accountIds};
    final ids = accountIds ?? existing?.accountIds ?? const <String>{};
    final validIds = accounts.map((account) => account.uuid).toSet();
    if (!remove &&
        (ids.isEmpty ||
            !validIds.containsAll(ids) ||
            ids.any(otherIds.contains))) {
      throw const MobileAccountVisibilityEditException(
        MobileAccountVisibilityEditFailure.selectAccounts,
      );
    }
    if (!remove &&
        validIds.every((id) => ids.contains(id) || otherIds.contains(id))) {
      throw const MobileAccountVisibilityEditException(
        MobileAccountVisibilityEditFailure.keepOrdinary,
      );
    }
    final salt = current.salt ?? MobileAccountVisibilityStore.randomToken(32);
    String? verifier = existing?.verifier;
    if (newPasscode != null && !remove) {
      if (!MobileAccountVisibilityStore.validCode(newPasscode)) {
        throw const MobileAccountVisibilityEditException(
          MobileAccountVisibilityEditFailure.differentPasscode,
        );
      }
      final matchesWallet = await ref
          .read(appSecurityProvider.notifier)
          .confirmPassword(newPasscode);
      verifier = await ref
          .read(mobileAccountVisibilityStoreProvider)
          .verifier(newPasscode, salt);
      if (matchesWallet ||
          otherRules.any((rule) => rule.verifier == verifier)) {
        throw const MobileAccountVisibilityEditException(
          MobileAccountVisibilityEditFailure.differentPasscode,
        );
      }
    }
    final rule = remove
        ? null
        : MobileAccountVisibilityRule(
            id: ruleId ?? MobileAccountVisibilityStore.randomToken(16),
            verifier: verifier!,
            accountIds: Set<String>.unmodifiable(ids),
          );
    final next = MobileAccountVisibilityConfig(
      salt: salt,
      rules: List.unmodifiable([...otherRules, ?rule]),
    );
    if (!isCurrent() || !identical(security, ref.read(appSecurityProvider))) {
      throw const SecureStorageSessionChangedException();
    }
    await ref.read(mobileAccountVisibilityStoreProvider).write(next);
    if (!ref.mounted) return rule;
    state = next;
    if (ref.read(appSecurityProvider).isUnlocked) {
      final scope = ref.read(mobileAccountScopeProvider.notifier);
      final selected = remove && ref.read(mobileAccountScopeProvider) == ruleId
          ? null
          : ref.read(mobileAccountScopeProvider);
      scope.select(selected);
      ref
          .read(accountProvider.notifier)
          .selectMobileAccountBeforeUnlock(selected, force: true);
    }
    return rule;
  });

  Future<void> forgetAccount(String uuid) async {
    final current = state;
    if (!current.assignedIds.contains(uuid)) return;
    final next = MobileAccountVisibilityConfig(
      salt: current.salt,
      rules: List.unmodifiable([
        for (final rule in current.rules)
          if (!(rule.accountIds.length == 1 && rule.accountIds.contains(uuid)))
            MobileAccountVisibilityRule(
              id: rule.id,
              verifier: rule.verifier,
              accountIds: Set.unmodifiable(
                rule.accountIds.where((id) => id != uuid),
              ),
            ),
      ]),
    );
    await ref.read(mobileAccountVisibilityStoreProvider).write(next);
    if (ref.mounted) state = next;
  }
}

enum MobileAccountVisibilityEditFailure {
  differentPasscode,
  keepOrdinary,
  selectAccounts,
}

class MobileAccountVisibilityEditException implements Exception {
  const MobileAccountVisibilityEditException(this.failure);

  final MobileAccountVisibilityEditFailure failure;
}

final mobileAccountScopeProvider =
    NotifierProvider<MobileAccountScope, String?>(MobileAccountScope.new);

class MobileAccountScope extends Notifier<String?> {
  @override
  String? build() {
    ref.listen(appSecurityProvider, (previous, next) {
      if (!next.isUnlocked && previous?.isUnlocked == true) state = null;
    });
    return null;
  }

  void select(String? ruleId) => state = ruleId;
}

/// UI projection only. Sync, recovery and whole-wallet reset use accountProvider.
final visibleAccountsProvider = Provider<List<AccountInfo>>((ref) {
  final accounts =
      ref.watch(accountProvider.select((state) => state.value?.accounts)) ??
      const <AccountInfo>[];
  if (kAppFormFactor != AppFormFactor.mobile) return accounts;
  final configuration = ref.watch(mobileAccountVisibilityProvider);
  final scope = ref.watch(mobileAccountScopeProvider);
  if (scope == null && configuration.rules.isEmpty) return accounts;
  return [
    for (final account in accounts)
      if (configuration.allows(account.uuid, scope)) account,
  ];
});

/// Used by mobile secret screens to invalidate an open reveal if either the
/// target UUID or its visibility changes.
final visibleAccountTargetProvider = Provider.autoDispose
    .family<AccountInfo?, String?>((ref, requestedUuid) {
      final uuid =
          requestedUuid ??
          ref.watch(
            accountProvider.select((state) => state.value?.activeAccountUuid),
          );
      return ref
          .watch(visibleAccountsProvider)
          .where((account) => account.uuid == uuid)
          .firstOrNull;
    });

/// A settings route showing authenticated assignments also needs to lock when
/// backgrounded, even if the wallet underneath is in its ordinary scope.
final mobileAccountManagementOpenProvider =
    NotifierProvider<MobileAccountManagementSession, bool>(
      MobileAccountManagementSession.new,
    );

class MobileAccountManagementSession extends Notifier<bool> {
  Object? _owner;

  @override
  bool build() {
    ref.listen(appSecurityProvider, (previous, next) {
      if (!next.isUnlocked && previous?.isUnlocked == true) {
        _owner = null;
        state = false;
      }
    });
    return false;
  }

  void setOpen(Object owner, bool open) {
    if (!ref.mounted) return;
    if (open) {
      _owner = owner;
      state = true;
    } else if (identical(_owner, owner)) {
      _owner = null;
      state = false;
    }
  }
}

/// Requests a full lock when the sync idle screen would otherwise hold a
/// privileged account view underneath its overlay.
final mobileAccountRelockProvider = NotifierProvider<MobileAccountRelock, int>(
  MobileAccountRelock.new,
);

class MobileAccountRelock extends Notifier<int> {
  @override
  int build() => 0;

  void request() => state++;
}
