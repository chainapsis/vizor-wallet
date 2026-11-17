import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/core/storage/app_secure_store.dart';
import 'package:zcash_wallet/src/core/storage/privacy_mode_persistence.dart';

import '../../fakes/controlled_privacy_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  for (final legacy in [null, 'false', 'true']) {
    test('no marker preserves legacy privacy value $legacy', () async {
      final store = ControlledPrivacyStore();
      if (legacy != null) store.values[kPrivacyModeEnabledKey] = legacy;
      expect(
        await PrivacyModePersistence(store).readAndRecover(),
        legacy == 'true',
      );
      expect(store.writes, isEmpty);
    });
  }

  for (final marker in ['true', 'false', '', 'unknown-version']) {
    test('any existing marker ($marker) overrides a saved reveal', () async {
      final store = ControlledPrivacyStore()
        ..values.addAll({
          kPrivacyModeEnabledKey: 'false',
          kPrivacyModeRevealPendingKey: marker,
        });
      expect(await PrivacyModePersistence(store).readAndRecover(), isTrue);
      expect(store.values[kPrivacyModeEnabledKey], 'true');
      expect(store.values, isNot(contains(kPrivacyModeRevealPendingKey)));
      expect(store.operations, [
        'read:$kPrivacyModeRevealPendingKey',
        'write:$kPrivacyModeEnabledKey=true',
        'delete:$kPrivacyModeRevealPendingKey',
      ]);
    });
  }

  for (final key in [kPrivacyModeRevealPendingKey, kPrivacyModeEnabledKey]) {
    test('unknown read of $key keeps privacy on', () async {
      final store = ControlledPrivacyStore();
      store.beforeOperation = (operation) async {
        if (operation == 'read:$key') throw StateError('read failed');
      };
      expect(await PrivacyModePersistence(store).readAndRecover(), isTrue);
      expect(store.writes, isEmpty);
    });
    test('unavailable read of $key retains blocking startup policy', () async {
      final store = ControlledPrivacyStore();
      store.beforeOperation = (operation) async {
        if (operation == 'read:$key') {
          throw const SecureStorageUnavailableException(
            operation: 'privacy read',
            cause: 'unavailable',
          );
        }
      };
      await expectLater(
        PrivacyModePersistence(store).readAndRecover(),
        throwsA(isA<SecureStorageUnavailableException>()),
      );
    });
  }

  for (final afterCommit in [false, true]) {
    for (final stage in [
      'write:$kPrivacyModeEnabledKey=true',
      'delete:$kPrivacyModeRevealPendingKey',
    ]) {
      test(
        'startup recovery failure at $stage afterCommit=$afterCommit',
        () async {
          final store = ControlledPrivacyStore()
            ..values.addAll({
              kPrivacyModeEnabledKey: 'false',
              kPrivacyModeRevealPendingKey: 'true',
            });
          void fail(String operation) {
            if (operation == stage) throw StateError('recovery failure');
          }

          if (afterCommit) {
            store.afterOperation = fail;
          } else {
            store.beforeOperation = (operation) async => fail(operation);
          }
          expect(await PrivacyModePersistence(store).readAndRecover(), isTrue);
          if (stage.startsWith('write:')) {
            expect(store.values[kPrivacyModeRevealPendingKey], 'true');
          }
          store.beforeOperation = null;
          store.afterOperation = null;
          expect(await PrivacyModePersistence(store).readAndRecover(), isTrue);
          expect(store.values[kPrivacyModeEnabledKey], 'true');
          expect(store.values, isNot(contains(kPrivacyModeRevealPendingKey)));
        },
      );
    }
  }
}
