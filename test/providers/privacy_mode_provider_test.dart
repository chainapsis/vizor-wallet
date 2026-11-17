import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/app_bootstrap.dart';
import 'package:zcash_wallet/src/core/storage/app_secure_store.dart';
import 'package:zcash_wallet/src/providers/privacy_mode_provider.dart';

import '../fakes/controlled_privacy_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late ControlledPrivacyStore store;
  late ProviderContainer container;
  late PrivacyModeNotifier privacy;

  void setup({bool hidden = false}) {
    store = ControlledPrivacyStore();
    final base = AppBootstrapState.empty;
    container = ProviderContainer(
      overrides: [
        appBootstrapProvider.overrideWithValue(
          AppBootstrapState(
            initialLocation: base.initialLocation,
            initialAccountState: base.initialAccountState,
            initialSyncSnapshot: base.initialSyncSnapshot,
            network: base.network,
            rpcEndpointConfig: base.rpcEndpointConfig,
            themeMode: base.themeMode,
            privacyModeEnabled: hidden,
            isPasswordConfigured: true,
            isUnlocked: true,
            passwordRotationRecoveryFailed: false,
          ),
        ),
        privacyModeProvider.overrideWith(
          () => PrivacyModeNotifier.testing(store: store),
        ),
      ],
    );
    addTearDown(container.dispose);
    privacy = container.read(privacyModeProvider.notifier);
  }

  test(
    'flip hides before persistence and reports completion after saving',
    () async {
      setup();
      store.blocked = Completer<void>();
      var completed = false;
      final change = privacy
          .setFromFlip(true, isActive: () => true)
          .completed
          .then((result) {
            completed = true;
            return result;
          });
      expect(container.read(privacyModeProvider), isTrue);
      await Future<void>.delayed(Duration.zero);
      expect(completed, isFalse);
      store.blocked!.complete();
      expect(await change, isTrue);
      expect(store.values[kPrivacyModeEnabledKey], 'true');
    },
  );

  test('failed hide preserves the mask and later changes still work', () async {
    setup();
    store.failWrites = true;
    await expectLater(
      privacy.setFromFlip(true, isActive: () => true).completed,
      throwsStateError,
    );
    expect(container.read(privacyModeProvider), isTrue);
    expect(privacy.requestedHidden, isTrue);
    store.failWrites = false;
    expect(
      await privacy.setFromFlip(false, isActive: () => true).completed,
      isTrue,
    );
    expect(container.read(privacyModeProvider), isFalse);
  });

  test('reveal waits for persistence', () async {
    setup(hidden: true);
    store.blocked = Completer<void>();
    final change = privacy.setFromFlip(false, isActive: () => true).completed;
    expect(privacy.requestedHidden, isFalse);
    expect(container.read(privacyModeProvider), isTrue);
    store.blocked!.complete();
    expect(await change, isTrue);
    expect(container.read(privacyModeProvider), isFalse);
  });

  test('failed reveal leaves the mask and clears the pending intent', () async {
    setup(hidden: true);
    store.failWrites = true;
    await expectLater(
      privacy.setFromFlip(false, isActive: () => true).completed,
      throwsStateError,
    );
    expect(container.read(privacyModeProvider), isTrue);
    expect(privacy.requestedHidden, isTrue);
  });

  test(
    'rapid hide reveal hide keeps only the latest state and completion',
    () async {
      setup();
      store.blocked = Completer<void>();
      final hide = privacy.setFromFlip(true, isActive: () => true).completed;
      final reveal = privacy.setFromFlip(false, isActive: () => true).completed;
      final lastHide = privacy
          .setFromFlip(true, isActive: () => true)
          .completed;
      expect(container.read(privacyModeProvider), isTrue);
      store.blocked!.complete();
      expect(await Future.wait([hide, reveal, lastHide]), [false, false, true]);
      expect(container.read(privacyModeProvider), isTrue);
      expect(store.values[kPrivacyModeEnabledKey], 'true');
    },
  );

  test(
    'eye toggle reverses a pending reveal rather than the old mask',
    () async {
      setup(hidden: true);
      store.blocked = Completer<void>();
      final reveal = privacy.setFromFlip(false, isActive: () => true).completed;
      final eye = privacy.toggle();
      expect(privacy.requestedHidden, isTrue);
      store.blocked!.complete();
      expect(await reveal, isFalse);
      await eye;
      expect(container.read(privacyModeProvider), isTrue);
      expect(store.values[kPrivacyModeEnabledKey], 'true');
    },
  );

  test('unlock hide supersedes a flip reveal', () async {
    setup(hidden: true);
    store.blocked = Completer<void>();
    final reveal = privacy.setFromFlip(false, isActive: () => true).completed;
    final hide = privacy.hideForUnlock();
    store.blocked!.complete();
    expect(await reveal, isFalse);
    await hide;
    expect(container.read(privacyModeProvider), isTrue);
    expect(store.values[kPrivacyModeEnabledKey], 'true');
  });

  test('inactive reveal is not written', () async {
    setup(hidden: true);
    expect(
      await privacy.setFromFlip(false, isActive: () => false).completed,
      isFalse,
    );
    expect(store.writes, isEmpty);
    expect(container.read(privacyModeProvider), isTrue);
    expect(privacy.requestedHidden, isTrue);
  });

  test('session ending during a reveal restores the saved mask', () async {
    setup(hidden: true);
    final gate = Completer<void>();
    store.beforeOperation = (operation) async {
      if (operation == 'write:$kPrivacyModeEnabledKey=false') await gate.future;
    };
    var active = true;
    final reveal = privacy.setFromFlip(false, isActive: () => active).completed;
    await Future<void>.delayed(Duration.zero);
    active = false;
    gate.complete();
    expect(await reveal, isFalse);
    expect(store.writes, [
      '$kPrivacyModeRevealPendingKey=true',
      '$kPrivacyModeEnabledKey=false',
      '$kPrivacyModeEnabledKey=true',
    ]);
    expect(store.values[kPrivacyModeEnabledKey], 'true');
    expect(container.read(privacyModeProvider), isTrue);
  });

  test(
    'a new session can reveal after a cancelled reveal is restored',
    () async {
      setup(hidden: true);
      store.blocked = Completer<void>();
      var active = true;
      final cancelled = privacy
          .setFromFlip(false, isActive: () => active)
          .completed;
      await Future<void>.delayed(Duration.zero);
      active = false;
      store.blocked!.complete();
      expect(await cancelled, isFalse);
      expect(
        await privacy.setFromFlip(false, isActive: () => true).completed,
        isTrue,
      );
      expect(container.read(privacyModeProvider), isFalse);
      expect(store.values[kPrivacyModeEnabledKey], 'false');
    },
  );

  test('reset drains accepted changes and rejects new flips', () async {
    setup(hidden: true);
    store.blocked = Completer<void>();
    final reveal = privacy.setFromFlip(false, isActive: () => true).completed;
    await Future<void>.delayed(Duration.zero);
    var cleared = false;
    final reset = privacy.clearForWalletReset(() async {
      store.values.clear();
      cleared = true;
    });
    await expectLater(
      privacy.setFromFlip(true, isActive: () => true).completed,
      throwsStateError,
    );
    expect(cleared, isFalse);
    store.blocked!.complete();
    expect(await reveal, isFalse);
    await reset;
    expect(cleared, isTrue);
    expect(store.values, isEmpty);
    expect(container.read(privacyModeProvider), isTrue);
  });
  test(
    'reentrant reveal persists after the immediate hide notification',
    () async {
      setup();
      Future<bool>? reveal;
      final listener = container.listen(privacyModeProvider, (_, hidden) {
        if (hidden) {
          reveal = privacy.setFromFlip(false, isActive: () => true).completed;
        }
      });
      addTearDown(listener.close);
      final hide = privacy.setFromFlip(true, isActive: () => true);
      expect(hide.isCurrent, isFalse);
      expect(await hide.completed, isFalse);
      expect(await reveal!, isTrue);
      expect(container.read(privacyModeProvider), isFalse);
      expect(store.values[kPrivacyModeEnabledKey], 'false');
    },
  );
}
