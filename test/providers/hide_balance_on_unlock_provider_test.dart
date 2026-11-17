import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/app_bootstrap.dart';
import 'package:zcash_wallet/src/core/storage/app_secure_store.dart';
import 'package:zcash_wallet/src/providers/app_security_provider.dart';
import 'package:zcash_wallet/src/providers/hide_balance_on_unlock_provider.dart';
import 'package:zcash_wallet/src/providers/privacy_mode_provider.dart';
import '../fakes/controlled_privacy_store.dart';

class _Store extends ControlledPrivacyStore {
  @override
  Future<bool> verifyPassword(String password) {
    final valid = password == 'Password1!';
    if (valid) setSessionPassword(password);
    return Future.value(valid);
  }

  @override
  Future<bool> verifyPasswordOnly(String password) =>
      Future.value(password == 'Password1!');
}

AppBootstrapState _bootstrap({
  bool enabled = true,
  bool hidden = false,
  bool unlocked = false,
}) {
  final base = AppBootstrapState.empty;
  return AppBootstrapState(
    initialLocation: '/unlock',
    initialAccountState: base.initialAccountState,
    initialSyncSnapshot: base.initialSyncSnapshot,
    network: base.network,
    rpcEndpointConfig: base.rpcEndpointConfig,
    themeMode: base.themeMode,
    privacyModeEnabled: hidden,
    hideBalanceOnUnlockEnabled: enabled,
    isPasswordConfigured: true,
    isUnlocked: unlocked,
    passwordRotationRecoveryFailed: false,
  );
}

ProviderContainer _container(
  _Store store, {
  bool enabled = true,
  bool hidden = false,
  bool unlocked = false,
}) {
  return ProviderContainer(
    overrides: [
      appBootstrapProvider.overrideWithValue(
        _bootstrap(enabled: enabled, hidden: hidden, unlocked: unlocked),
      ),
      appSecurityProvider.overrideWith(
        () => AppSecurityNotifier.testing(store: store),
      ),
      privacyModeProvider.overrideWith(
        () => PrivacyModeNotifier.testing(store: store),
      ),
      hideBalanceOnUnlockProvider.overrideWith(
        () => HideBalanceOnUnlockNotifier.testing(store: store),
      ),
    ],
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('new installs default to opt-out', () {
    expect(AppBootstrapState.empty.hideBalanceOnUnlockEnabled, isFalse);
  });

  test('preference persists without changing the current eye state', () async {
    final store = _Store();
    final container = _container(store, enabled: false);
    addTearDown(container.dispose);
    final notifier = container.read(hideBalanceOnUnlockProvider.notifier);
    await notifier.set(true);
    expect(store.values[kHideBalanceOnUnlockKey], 'true');
    expect(container.read(hideBalanceOnUnlockProvider), isTrue);
    expect(container.read(privacyModeProvider), isFalse);
    await container.read(privacyModeProvider.notifier).set(true);
    await notifier.set(false);
    expect(container.read(privacyModeProvider), isTrue);
    await notifier.clearForWalletReset(() async => store.values.clear());
    expect(container.read(hideBalanceOnUnlockProvider), isFalse);
  });

  test(
    'reset drains preference and eye writes and rejects new changes',
    () async {
      final store = _Store()..blocked = Completer<void>();
      final container = _container(store, enabled: false);
      addTearDown(container.dispose);
      final preference = container.read(hideBalanceOnUnlockProvider.notifier);
      final privacy = container.read(privacyModeProvider.notifier);
      final saving = preference.set(true);
      final hiding = privacy.hideForUnlock();
      var wiped = false;
      final reset = preference.clearForWalletReset(() async {
        wiped = true;
        store.values.clear();
      });
      await expectLater(preference.set(false), throwsStateError);
      await Future<void>.delayed(Duration.zero);
      expect(wiped, isFalse);
      store.blocked!.complete();
      await Future.wait([saving, hiding, reset]);
      expect(wiped, isTrue);
      expect(store.values, isEmpty);
      expect(container.read(hideBalanceOnUnlockProvider), isFalse);
      // The old wallet can remain mounted while later native cleanup awaits.
      expect(container.read(privacyModeProvider), isTrue);
      await preference.set(true);
      expect(container.read(hideBalanceOnUnlockProvider), isTrue);
    },
  );

  test(
    'failed reset preserves preferences and allows another settings save',
    () async {
      final store = _Store();
      final container = _container(store, hidden: true);
      addTearDown(container.dispose);
      final preference = container.read(hideBalanceOnUnlockProvider.notifier);
      await expectLater(
        preference.clearForWalletReset(() async {
          throw StateError('wipe failed');
        }),
        throwsStateError,
      );
      expect(container.read(hideBalanceOnUnlockProvider), isTrue);
      expect(container.read(privacyModeProvider), isTrue);
      await preference.set(false);
      expect(container.read(hideBalanceOnUnlockProvider), isFalse);
    },
  );

  test('failed preference save preserves the saved choice', () async {
    final store = _Store()..failWrites = true;
    final container = _container(store, enabled: false);
    addTearDown(container.dispose);
    await expectLater(
      container.read(hideBalanceOnUnlockProvider.notifier).set(true),
      throwsStateError,
    );
    expect(container.read(hideBalanceOnUnlockProvider), isFalse);
  });

  test('mask is set before the unlocked state is published', () async {
    final store = _Store();
    final container = _container(store);
    addTearDown(container.dispose);
    container.listen(appSecurityProvider, (_, next) {
      if (next.isUnlocked) expect(container.read(privacyModeProvider), isTrue);
    });
    expect(
      await container.read(appSecurityProvider.notifier).unlock('Password1!'),
      isTrue,
    );
    expect(store.values[kPrivacyModeEnabledKey], 'true');
    await container.read(privacyModeProvider.notifier).toggle();
    expect(container.read(privacyModeProvider), isFalse);
    container.read(appSecurityProvider.notifier).lock();
    await container.read(appSecurityProvider.notifier).unlock('Password1!');
    expect(container.read(privacyModeProvider), isTrue);
  });

  for (final hidden in [false, true]) {
    test('opt-out preserves existing eye state ($hidden)', () async {
      final store = _Store();
      final container = _container(store, enabled: false, hidden: hidden);
      addTearDown(container.dispose);
      await container.read(appSecurityProvider.notifier).unlock('Password1!');
      expect(container.read(privacyModeProvider), hidden);
      expect(store.writes, isEmpty);
    });
  }

  test('invalid authentication and confirmation do not hide amounts', () async {
    final store = _Store();
    final container = _container(store);
    addTearDown(container.dispose);
    final auth = container.read(appSecurityProvider.notifier);
    expect(await auth.unlock('wrong'), isFalse);
    expect(await auth.confirmPassword('Password1!'), isTrue);
    expect(container.read(privacyModeProvider), isFalse);
    expect(container.read(appSecurityProvider).isUnlocked, isFalse);
    expect(store.writes, isEmpty);
  });

  test('failed automatic persistence still hides and allows unlock', () async {
    final store = _Store()..failWrites = true;
    final container = _container(store);
    addTearDown(container.dispose);
    expect(
      await container.read(appSecurityProvider.notifier).unlock('Password1!'),
      isTrue,
    );
    expect(container.read(privacyModeProvider), isTrue);
    expect(container.read(appSecurityProvider).isUnlocked, isTrue);
  });

  test('a lock during the automatic write cannot reopen the wallet', () async {
    final store = _Store()..blocked = Completer<void>();
    final container = _container(store);
    addTearDown(container.dispose);
    final auth = container.read(appSecurityProvider.notifier);
    final unlock = auth.unlock('Password1!');
    final error = expectLater(
      unlock,
      throwsA(isA<SecureStorageSessionChangedException>()),
    );
    await Future<void>.delayed(Duration.zero);
    expect(container.read(privacyModeProvider), isTrue);
    expect(container.read(appSecurityProvider).isUnlocked, isFalse);
    auth.lock();
    store.blocked!.complete();
    await error;
    expect(container.read(appSecurityProvider).isUnlocked, isFalse);
  });

  test('an older manual reveal cannot overwrite automatic hiding', () async {
    final store = _Store()..blocked = Completer<void>();
    final container = _container(store, hidden: true);
    addTearDown(container.dispose);
    final privacy = container.read(privacyModeProvider.notifier);
    final reveal = privacy.set(false);
    final hide = privacy.hideForUnlock();
    expect(container.read(privacyModeProvider), isTrue);
    await Future<void>.delayed(Duration.zero);
    expect(store.writes.length, 1);
    store.blocked!.complete();
    await Future.wait([reveal, hide]);
    expect(container.read(privacyModeProvider), isTrue);
    expect(store.values[kPrivacyModeEnabledKey], 'true');
    await privacy.set(false);
    expect(container.read(privacyModeProvider), isFalse);
    expect(store.values[kPrivacyModeEnabledKey], 'false');
  });

  test('an already-unlocked bootstrap is masked from its initial state', () {
    final container = _container(_Store(), unlocked: true);
    addTearDown(container.dispose);
    expect(container.read(privacyModeProvider), isTrue);
  });

  testWidgets('first unlocked frame and semantics contain only the mask', (
    tester,
  ) async {
    final store = _Store()..blocked = Completer<void>();
    final container = _container(store);
    addTearDown(container.dispose);
    final semantics = tester.ensureSemantics();

    final unlockedFrames = <String>[];
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          home: Consumer(
            builder: (_, ref, _) {
              final unlocked = ref.watch(appSecurityProvider).isUnlocked;
              final hidden = ref.watch(privacyModeProvider);
              final text = !unlocked
                  ? 'Locked'
                  : hidden
                  ? '•••••• ZEC'
                  : '123.45 ZEC';
              if (unlocked) unlockedFrames.add(text);
              return Text(text);
            },
          ),
        ),
      ),
    );
    final unlock = container
        .read(appSecurityProvider.notifier)
        .unlock('Password1!');
    await tester.pump();
    expect(find.text('Locked'), findsOneWidget);
    store.blocked!.complete();
    await tester.pump();
    await unlock;
    await tester.pump();
    expect(unlockedFrames, isNotEmpty);
    expect(unlockedFrames.every((text) => text == '•••••• ZEC'), isTrue);
    expect(find.text('123.45 ZEC'), findsNothing);
    expect(find.bySemanticsLabel('123.45 ZEC'), findsNothing);
    semantics.dispose();
  });
}
