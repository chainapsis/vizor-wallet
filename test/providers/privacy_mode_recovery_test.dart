import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/app_bootstrap.dart';
import 'package:zcash_wallet/src/core/storage/app_secure_store.dart';
import 'package:zcash_wallet/src/core/storage/privacy_mode_persistence.dart';
import 'package:zcash_wallet/src/providers/privacy_mode_provider.dart';

import '../fakes/controlled_privacy_store.dart';

const _prepare = 'write:$kPrivacyModeRevealPendingKey=true';
const _reveal = 'write:$kPrivacyModeEnabledKey=false';
const _hide = 'write:$kPrivacyModeEnabledKey=true';
const _cleanup = 'delete:$kPrivacyModeRevealPendingKey';

ProviderContainer _container(
  ControlledPrivacyStore store, {
  bool hidden = true,
}) {
  final base = AppBootstrapState.empty;
  return ProviderContainer(
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
}

Future<void> _expectRestart(Map<String, String> persisted, bool hidden) async {
  // Only durable bytes cross this boundary. No provider, intent or session is
  // reused, and startup recovery operates on a separate store instance.
  final store = ControlledPrivacyStore()..values.addAll(persisted);
  final initial = await PrivacyModePersistence(store).readAndRecover();
  final container = _container(store, hidden: initial);
  try {
    expect(container.read(privacyModeProvider), hidden);
    expect(
      container.read(privacyModeProvider.notifier).requestedHidden,
      hidden,
    );
  } finally {
    container.dispose();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late ControlledPrivacyStore store;
  late ProviderContainer container;
  late PrivacyModeNotifier privacy;
  var disposed = false;
  setUp(() {
    store = ControlledPrivacyStore()..values[kPrivacyModeEnabledKey] = 'true';
    container = _container(store);
    disposed = false;
    addTearDown(() {
      if (!disposed) container.dispose();
    });
    privacy = container.read(privacyModeProvider.notifier);
  });

  test(
    'cancelled reveal plus failed rollback is hidden after restart',
    () async {
      var active = true;
      store.afterOperation = (operation) {
        if (operation == _reveal) active = false;
      };
      store.beforeOperation = (operation) async {
        if (operation == _hide) throw StateError('rollback failed');
      };
      await expectLater(
        privacy.setFromFlip(false, isActive: () => active).completed,
        throwsStateError,
      );
      expect(container.read(privacyModeProvider), isTrue);
      expect(store.values[kPrivacyModeEnabledKey], 'false');
      expect(store.values[kPrivacyModeRevealPendingKey], 'true');
      await _expectRestart(Map.of(store.values), true);
    },
  );

  for (final stage in [_prepare, _reveal, _hide, _cleanup]) {
    for (final afterCommit in [false, true]) {
      test(
        'failure at $stage afterCommit=$afterCommit survives restart',
        () async {
          var active = true;
          void fail(String operation) {
            if (operation == stage) throw StateError('injected save failure');
          }

          store.beforeOperation = (operation) async {
            if (!afterCommit) fail(operation);
          };
          store.afterOperation = (operation) {
            if (stage == _hide && operation == _reveal) active = false;
            if (afterCommit) fail(operation);
          };
          final result = privacy.setFromFlip(false, isActive: () => active);
          if (stage == _cleanup) {
            expect(await result.completed, isTrue);
            expect(container.read(privacyModeProvider), isFalse);
            await _expectRestart(Map.of(store.values), !afterCommit);
          } else {
            await expectLater(result.completed, throwsStateError);
            if (stage == _prepare) {
              expect(store.operations, isNot(contains(_reveal)));
            }
            expect(container.read(privacyModeProvider), isTrue);
            expect(privacy.requestedHidden, isTrue);
            await _expectRestart(Map.of(store.values), true);
          }
        },
      );
    }
  }

  test(
    'crash snapshots recover at every reveal persistence boundary',
    () async {
      final snapshots = <Map<String, String>>[Map.of(store.values)];
      store.beforeOperation = (operation) async {
        if (operation == _cleanup) {
          expect(container.read(privacyModeProvider), isFalse);
          snapshots.add(Map.of(store.values));
        }
      };
      store.afterOperation = (operation) => snapshots.add(Map.of(store.values));
      expect(
        await privacy.setFromFlip(false, isActive: () => true).completed,
        isTrue,
      );
      expect(snapshots, hasLength(5));
      for (var i = 0; i < snapshots.length; i++) {
        await _expectRestart(snapshots[i], i < 4);
      }
    },
  );

  for (final stage in [_prepare, _reveal]) {
    test('session cancellation after $stage keeps the durable mask', () async {
      var active = true;
      store.afterOperation = (operation) {
        if (operation == stage) active = false;
      };
      expect(
        await privacy.setFromFlip(false, isActive: () => active).completed,
        isFalse,
      );
      expect(container.read(privacyModeProvider), isTrue);
      await _expectRestart(Map.of(store.values), true);
    });
  }

  test(
    'session ending after the synchronous reveal commit only silences feedback',
    () async {
      var active = true;
      store.beforeOperation = (operation) async {
        if (operation == _cleanup) {
          expect(container.read(privacyModeProvider), isFalse);
          active = false;
        }
      };
      expect(
        await privacy.setFromFlip(false, isActive: () => active).completed,
        isTrue,
      );
      expect(container.read(privacyModeProvider), isFalse);
      await _expectRestart(Map.of(store.values), false);
    },
  );

  for (final automatic in [false, true]) {
    test(
      'superseding ${automatic ? 'unlock' : 'manual'} hide failure retains reveal protection',
      () async {
        final entered = Completer<void>();
        final release = Completer<void>();
        store.beforeOperation = (operation) async {
          if (operation == _reveal) {
            entered.complete();
            await release.future;
          }
          if (operation == _hide) throw StateError('hide failed');
        };
        final reveal = privacy
            .setFromFlip(false, isActive: () => true)
            .completed;
        await entered.future;
        final hiding = automatic ? privacy.hideForUnlock() : privacy.set(true);
        final handled = automatic
            ? hiding
            : expectLater(hiding, throwsStateError);
        release.complete();
        expect(await reveal, isFalse);
        await handled;
        expect(container.read(privacyModeProvider), isTrue);
        expect(store.values[kPrivacyModeRevealPendingKey], 'true');
        await _expectRestart(Map.of(store.values), true);
      },
    );
  }

  test('a reentrant newer hide keeps the marker if its save fails', () async {
    Future<void>? handled;
    final listener = container.listen(privacyModeProvider, (_, hidden) {
      if (!hidden) {
        handled = expectLater(
          privacy.setFromFlip(true, isActive: () => true).completed,
          throwsStateError,
        );
      }
    });
    addTearDown(listener.close);
    store.beforeOperation = (operation) async {
      if (operation == _hide) throw StateError('hide failed');
    };
    expect(
      await privacy.setFromFlip(false, isActive: () => true).completed,
      isFalse,
    );
    await handled;
    expect(container.read(privacyModeProvider), isTrue);
    expect(store.values[kPrivacyModeRevealPendingKey], 'true');
    await _expectRestart(Map.of(store.values), true);
  });

  test(
    'an explicit later reveal can replace a failed cancellation recovery',
    () async {
      var active = true;
      store.afterOperation = (operation) {
        if (operation == _reveal) active = false;
      };
      store.beforeOperation = (operation) async {
        if (operation == _hide) throw StateError('rollback failed');
      };
      await expectLater(
        privacy.setFromFlip(false, isActive: () => active).completed,
        throwsStateError,
      );
      store.beforeOperation = null;
      store.afterOperation = null;
      await privacy.set(false);
      expect(container.read(privacyModeProvider), isFalse);
      await _expectRestart(Map.of(store.values), false);
    },
  );

  test(
    'provider disposal during the visible write preserves restart protection',
    () async {
      final entered = Completer<void>();
      final release = Completer<void>();
      store.beforeOperation = (operation) async {
        if (operation == _reveal) {
          entered.complete();
          await release.future;
        }
      };
      final reveal = privacy.setFromFlip(false, isActive: () => true).completed;
      await entered.future;
      container.dispose();
      disposed = true;
      release.complete();
      expect(await reveal, isFalse);
      expect(store.values[kPrivacyModeRevealPendingKey], 'true');
      await _expectRestart(Map.of(store.values), true);
    },
  );

  for (final stage in [_prepare, _reveal, _cleanup]) {
    test('reset drains $stage and removes all recovery records', () async {
      final entered = Completer<void>();
      final release = Completer<void>();
      store.beforeOperation = (operation) async {
        if (operation == stage) {
          entered.complete();
          await release.future;
        }
      };
      final reveal = privacy.setFromFlip(false, isActive: () => true).completed;
      await entered.future;
      var cleared = false;
      final reset = privacy.clearForWalletReset(() async {
        cleared = true;
        store.values.clear();
      });
      await expectLater(privacy.set(false), throwsStateError);
      expect(cleared, isFalse);
      release.complete();
      expect(await reveal, isFalse);
      await reset;
      await Future<void>.delayed(Duration.zero);
      expect(store.values, isEmpty);
      await _expectRestart(Map.of(store.values), false);
    });
  }
}
